import Foundation

/// The credential set held in the Keychain.
struct OAuthTokens: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String? = nil
    var expiresAt: Date
    var scope: String? = nil
    var tokenType: String

    init(accessToken: String, refreshToken: String?, expiresAt: Date, scope: String?, tokenType: String = "Bearer") {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
        self.tokenType = tokenType
    }

    /// Access tokens are refreshed a minute early so a request never races the
    /// expiry it was checked against.
    func isExpired(now: Date, leeway: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }

    var canRefresh: Bool { refreshToken?.isEmpty == false }

    var authorizationHeader: String { "\(tokenType) \(accessToken)" }
}

/// Google's token endpoint response.
struct GoogleTokenResponse: Codable, Sendable {
    var access_token: String? = nil
    var refresh_token: String? = nil
    var expires_in: Double? = nil
    var scope: String? = nil
    var token_type: String? = nil
    var error: String? = nil
    var error_description: String? = nil

    /// Merges a response into the stored tokens. A refresh response omits the
    /// refresh token, so the existing one is carried forward.
    func tokens(now: Date, existingRefreshToken: String?) -> OAuthTokens? {
        guard let accessToken = access_token, !accessToken.isEmpty else { return nil }
        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: refresh_token ?? existingRefreshToken,
            expiresAt: now.addingTimeInterval(expires_in ?? 3_600),
            scope: scope,
            tokenType: token_type ?? "Bearer"
        )
    }
}
