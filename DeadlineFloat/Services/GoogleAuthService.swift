import AppKit
import Foundation

enum AuthError: LocalizedError, Equatable {
    case notConfigured
    case stateMismatch
    case denied(String)
    case noAuthorizationCode
    case tokenExchangeFailed(String)
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "This build has no usable Google OAuth client ID. See Settings → Account → Advanced."
        case .stateMismatch:
            return "The sign-in response did not match this request and was rejected."
        case .denied(let reason):
            return reason == "access_denied"
                ? "Permission was not granted."
                : "Google reported: \(reason)"
        case .noAuthorizationCode:
            return "Google did not return an authorization code."
        case .tokenExchangeFailed(let detail):
            return "Could not complete sign-in: \(detail)"
        case .refreshFailed(let detail):
            return "Could not refresh Google access: \(detail)"
        }
    }
}

/// Owns the OAuth lifecycle: authorisation, refresh, revocation and storage.
///
/// Only one scope is ever requested — `calendar.readonly` — and tokens live in
/// the Keychain, never in `UserDefaults` or on disk.
actor GoogleAuthService {
    private let store: TokenStoring
    private let http: HTTPClient
    private let urlOpener: @Sendable (URL) -> Void
    private let clock: @Sendable () -> Date

    private var configuration: GoogleClientConfig
    private var cachedTokens: OAuthTokens?
    private var hasLoadedFromStore = false
    private var refreshTask: Task<OAuthTokens, Error>?
    private var activeServer: LoopbackRedirectServer?

    init(
        store: TokenStoring = KeychainTokenStore(),
        http: HTTPClient = HTTPClient(),
        configuration: GoogleClientConfig = .resolve(),
        urlOpener: @escaping @Sendable (URL) -> Void = { url in NSWorkspace.shared.open(url) },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.http = http
        self.configuration = configuration
        self.urlOpener = urlOpener
        self.clock = clock
    }

    // MARK: - State

    var isConfigured: Bool { configuration.isConfigured }

    func updateConfiguration(_ configuration: GoogleClientConfig) {
        self.configuration = configuration
    }

    func isSignedIn() -> Bool {
        (try? loadTokens()) != nil
    }

    func grantedScope() -> String? {
        (try? loadTokens())?.scope
    }

    private func loadTokens() throws -> OAuthTokens? {
        if !hasLoadedFromStore {
            cachedTokens = try store.load()
            hasLoadedFromStore = true
        }
        return cachedTokens
    }

    private func persist(_ tokens: OAuthTokens) throws {
        cachedTokens = tokens
        hasLoadedFromStore = true
        try store.save(tokens)
    }

    // MARK: - Sign in

    /// Runs the loopback authorisation-code flow with PKCE.
    func signIn() async throws {
        guard configuration.isConfigured, configuration.isWellFormed else {
            throw AuthError.notConfigured
        }

        let server = LoopbackRedirectServer()
        activeServer = server
        defer {
            server.stop()
            activeServer = nil
        }

        let port = try server.start()
        let redirectURI = "http://127.0.0.1:\(port)"
        let pkce = PKCE.generate()
        let state = PKCE.stateToken()

        guard let authorizationURL = Self.authorizationURL(
            clientID: configuration.trimmedClientID,
            redirectURI: redirectURI,
            pkce: pkce,
            state: state
        ) else { throw AuthError.notConfigured }

        Log.auth.info("Opening Google authorization page")
        urlOpener(authorizationURL)

        let callback = try await server.waitForCallback()

        if let error = callback.error { throw AuthError.denied(error) }
        guard callback.state == state else { throw AuthError.stateMismatch }
        guard let code = callback.code, !code.isEmpty else { throw AuthError.noAuthorizationCode }

        var fields = [
            "code": code,
            "client_id": configuration.trimmedClientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": pkce.verifier
        ]
        if let secret = configuration.clientSecret, !secret.isEmpty {
            fields["client_secret"] = secret
        }

        let response = try await http.postForm(GoogleEndpoints.token, fields: fields)
        let decoded = try JSONDecoder().decode(GoogleTokenResponse.self, from: response.data)

        if let error = decoded.error {
            let detail = decoded.error_description ?? error
            if detail.lowercased().contains("client_secret") {
                throw AuthError.tokenExchangeFailed(
                    "\(detail) This OAuth client requires its secret — add it alongside the client ID."
                )
            }
            throw AuthError.tokenExchangeFailed(detail)
        }
        guard let tokens = decoded.tokens(now: clock(), existingRefreshToken: nil) else {
            throw AuthError.tokenExchangeFailed("no access token in response")
        }
        try persist(tokens)
        Log.auth.info("Google sign-in complete")
    }

    func cancelSignIn() {
        activeServer?.stop()
        activeServer = nil
    }

    // MARK: - Sign out

    /// Revokes the refresh token with Google, then clears local storage.
    /// Local state is cleared even if the network call fails.
    func signOut() async {
        let tokens = try? loadTokens()
        if let token = tokens?.refreshToken ?? tokens?.accessToken {
            let url = GoogleEndpoints.revoke
            _ = try? await http.postForm(url, fields: ["token": token])
        }
        cachedTokens = nil
        hasLoadedFromStore = true
        refreshTask = nil
        try? store.clear()
        Log.auth.info("Signed out and cleared stored tokens")
    }

    // MARK: - Access tokens

    /// A valid access token, refreshing first when the stored one has expired.
    /// Concurrent callers share a single refresh.
    func accessToken() async throws -> String {
        guard configuration.isConfigured else { throw APIError.notConfigured }
        guard let tokens = try loadTokens() else { throw APIError.notSignedIn }

        if !tokens.isExpired(now: clock()) { return tokens.accessToken }
        guard tokens.canRefresh else { throw APIError.unauthorized }

        if let existing = refreshTask {
            return try await existing.value.accessToken
        }

        let task = Task<OAuthTokens, Error> { [configuration, http, clock] in
            var fields = [
                "client_id": configuration.trimmedClientID,
                "refresh_token": tokens.refreshToken ?? "",
                "grant_type": "refresh_token"
            ]
            if let secret = configuration.clientSecret, !secret.isEmpty {
                fields["client_secret"] = secret
            }

            let response = try await http.postForm(GoogleEndpoints.token, fields: fields)
            let decoded = try JSONDecoder().decode(GoogleTokenResponse.self, from: response.data)
            if let error = decoded.error {
                throw AuthError.refreshFailed(decoded.error_description ?? error)
            }
            guard let refreshed = decoded.tokens(now: clock(), existingRefreshToken: tokens.refreshToken) else {
                throw AuthError.refreshFailed("no access token in refresh response")
            }
            return refreshed
        }
        refreshTask = task

        do {
            let refreshed = try await task.value
            refreshTask = nil
            try persist(refreshed)
            return refreshed.accessToken
        } catch {
            refreshTask = nil
            // A revoked or expired refresh token is terminal: drop it so the UI
            // asks the user to reconnect instead of retrying forever.
            if Self.isTerminalRefreshFailure(error) {
                cachedTokens = nil
                try? store.clear()
                throw APIError.unauthorized
            }
            throw error
        }
    }

    static func isTerminalRefreshFailure(_ error: Error) -> Bool {
        if case APIError.unauthorized = error { return true }
        if case APIError.server(let status, _) = error, status == 400 || status == 401 { return true }
        if case AuthError.refreshFailed(let detail) = error {
            let lowered = detail.lowercased()
            return lowered.contains("invalid_grant")
                || lowered.contains("expired")
                || lowered.contains("revoked")
                || lowered.contains("token has been")
        }
        return false
    }

    // MARK: - URL construction

    /// Builds the authorisation URL. `access_type=offline` is what yields a
    /// refresh token; `prompt=consent` guarantees one is issued even if the user
    /// has authorised this client before.
    static func authorizationURL(
        clientID: String,
        redirectURI: String,
        pkce: PKCE,
        state: String
    ) -> URL? {
        guard !clientID.isEmpty else { return nil }
        var components = URLComponents(url: GoogleEndpoints.authorization, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleEndpoints.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components?.url
    }
}
