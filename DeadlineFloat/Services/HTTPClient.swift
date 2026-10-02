import Foundation

/// Everything that can go wrong talking to Google, in the shapes the UI needs.
enum APIError: LocalizedError, Equatable {
    case notConfigured
    case notSignedIn
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case offline
    case server(status: Int, message: String)
    case invalidResponse
    /// The request was blocked before it left the process — see `HTTPClient`.
    case disallowedRequest(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add your Google OAuth client ID in Settings."
        case .notSignedIn: return "Connect a Google account to see your deadlines."
        case .unauthorized: return "Google sign-in expired. Reconnect to continue."
        case .rateLimited: return "Google is rate limiting requests. Retrying shortly."
        case .offline: return "No internet connection."
        case .server(let status, let message):
            return message.isEmpty ? "Google returned HTTP \(status)." : message
        case .invalidResponse: return "Google returned an unexpected response."
        case .disallowedRequest(let detail): return "Blocked an unexpected request: \(detail)."
        }
    }
}

struct HTTPResponse: Sendable {
    var status: Int
    var data: Data
    var headers: [String: String]

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// Seam for tests: a fake transport replaces `URLSession` without a network.
protocol HTTPPerforming: Sendable {
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPPerforming {
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// When and how long to wait before trying again.
struct RetryPolicy: Sendable, Equatable {
    var maxAttempts: Int = 4
    var baseDelay: TimeInterval = 0.8
    var maxDelay: TimeInterval = 30

    /// Google signals quota problems with `429`, and also with `403` carrying a
    /// rate-limit reason. Transient 5xx responses are worth another try.
    func isRetryable(status: Int, reason: String?) -> Bool {
        switch status {
        case 408, 429, 500, 502, 503, 504:
            return true
        case 403:
            guard let reason = reason?.lowercased() else { return false }
            return [
                "ratelimitexceeded",
                "userratelimitexceeded",
                "quotaexceeded",
                "backenderror"
            ].contains(reason)
        default:
            return false
        }
    }

    /// Exponential backoff with full jitter, capped, honouring `Retry-After`.
    /// `jitter` is supplied by the caller so the schedule is testable.
    func delay(attempt: Int, retryAfter: TimeInterval?, jitter: Double) -> TimeInterval {
        if let retryAfter, retryAfter > 0 { return min(retryAfter, maxDelay) }
        let exponent = max(0, attempt - 1)
        let exponential = baseDelay * pow(2, Double(exponent))
        let capped = min(exponential, maxDelay)
        let clampedJitter = min(1, max(0, jitter))
        return capped * (0.75 + 0.5 * clampedJitter)
    }
}

/// The only way the app reaches the network.
///
/// Two invariants are enforced here rather than trusted to call sites:
///
/// * **Host allowlist** — a request to anything other than Google's OAuth and
///   Calendar endpoints is refused, so calendar data cannot be sent anywhere
///   else, deliberately or otherwise. There is no analytics endpoint to remove
///   because none can be reached.
/// * **Almost read-only Calendar access** — a request to the Calendar API must
///   be a `GET`, with one exception: a `PATCH` to one event's own URL, which is
///   how a block dragged on the calendar is written back. Nothing else passes,
///   so the app remains structurally incapable of creating an event, deleting
///   one, or touching a calendar or its sharing.
struct HTTPClient: Sendable {
    var transport: HTTPPerforming
    var allowedHosts: Set<String>
    var retryPolicy: RetryPolicy
    /// Injected so tests do not actually sleep.
    var sleeper: @Sendable (TimeInterval) async throws -> Void
    /// Injected so backoff is deterministic under test.
    var jitterProvider: @Sendable () -> Double

    init(
        transport: HTTPPerforming = URLSession.shared,
        allowedHosts: Set<String> = GoogleEndpoints.allowedHosts,
        retryPolicy: RetryPolicy = RetryPolicy(),
        sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        },
        jitterProvider: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
    ) {
        self.transport = transport
        self.allowedHosts = allowedHosts
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
        self.jitterProvider = jitterProvider
    }

    /// Hosts on which writes are restricted to the one shape below.
    static let restrictedHosts: Set<String> = ["www.googleapis.com"]

    /// The only write the app can make: `PATCH /calendar/v3/calendars/{id}/events/{id}`.
    ///
    /// Checking the shape of the path, and not merely the verb, is what keeps
    /// the permission as narrow as the feature that needs it — a `PATCH` to a
    /// calendar, an ACL or the event list is refused just as a `DELETE` is.
    static func isPermitted(method: String, url: URL) -> Bool {
        switch method.uppercased() {
        case "GET":
            return true
        case "PATCH":
            let components = url.pathComponents
            guard components.count == 7 else { return false }
            return components[1] == "calendar"
                && components[2] == "v3"
                && components[3] == "calendars"
                && !components[4].isEmpty
                && components[5] == "events"
                && !components[6].isEmpty
        default:
            return false
        }
    }

    func get(_ url: URL, accessToken: String?) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        return try await send(request)
    }

    /// JSON PATCH, used only to write one event's new start and end.
    func patchJSON(_ url: URL, accessToken: String, body: Data) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return try await send(request)
    }

    /// Form-encoded POST, used only for the OAuth token and revoke endpoints.
    func postForm(_ url: URL, fields: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.formEncode(fields).utf8)
        return try await send(request)
    }

    // MARK: - Core

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        try validate(request)

        var attempt = 1
        while true {
            do {
                let (data, response) = try await transport.perform(request)
                guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

                var headers: [String: String] = [:]
                for (key, value) in http.allHeaderFields {
                    if let key = key as? String, let value = value as? String { headers[key] = value }
                }
                let result = HTTPResponse(status: http.statusCode, data: data, headers: headers)

                if (200..<300).contains(http.statusCode) { return result }

                let envelope = try? JSONDecoder().decode(GoogleAPIErrorEnvelope.self, from: data)
                let reason = envelope?.primaryReason
                let message = envelope?.message ?? ""

                if http.statusCode == 401 { throw APIError.unauthorized }

                let retryAfter = result.header("Retry-After").flatMap(TimeInterval.init)

                if retryPolicy.isRetryable(status: http.statusCode, reason: reason), attempt < retryPolicy.maxAttempts {
                    let wait = retryPolicy.delay(attempt: attempt, retryAfter: retryAfter, jitter: jitterProvider())
                    Log.network.notice("HTTP \(http.statusCode, privacy: .public) — retrying in \(wait, format: .fixed(precision: 1))s")
                    try await sleeper(wait)
                    attempt += 1
                    continue
                }

                if http.statusCode == 429 || retryPolicy.isRetryable(status: http.statusCode, reason: reason) {
                    throw APIError.rateLimited(retryAfter: retryAfter)
                }
                throw APIError.server(status: http.statusCode, message: message)
            } catch let error as APIError {
                throw error
            } catch let error as URLError {
                if Self.isOffline(error) { throw APIError.offline }
                if error.code == .cancelled { throw CancellationError() }
                if attempt < retryPolicy.maxAttempts {
                    let wait = retryPolicy.delay(attempt: attempt, retryAfter: nil, jitter: jitterProvider())
                    try await sleeper(wait)
                    attempt += 1
                    continue
                }
                throw APIError.server(status: error.errorCode, message: error.localizedDescription)
            }
        }
    }

    func validate(_ request: URLRequest) throws {
        guard let url = request.url, let host = url.host?.lowercased() else {
            throw APIError.disallowedRequest("request has no host")
        }
        guard url.scheme?.lowercased() == "https" else {
            throw APIError.disallowedRequest("\(url.scheme ?? "no scheme") is not https")
        }
        guard allowedHosts.contains(host) else {
            throw APIError.disallowedRequest(host)
        }
        if Self.restrictedHosts.contains(host) {
            let method = (request.httpMethod ?? "GET").uppercased()
            guard Self.isPermitted(method: method, url: url) else {
                throw APIError.disallowedRequest("\(method) \(url.path) is not permitted on \(host)")
            }
        }
    }

    static func isOffline(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff,
             .dataNotAllowed, .secureConnectionFailed, .timedOut:
            return true
        default:
            return false
        }
    }

    static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}
