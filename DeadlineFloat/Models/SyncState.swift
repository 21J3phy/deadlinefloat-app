import Foundation

/// Why the last refresh did not produce fresh data.
enum SyncProblem: Equatable, Sendable {
    case notSignedIn
    case authenticationExpired
    case offline
    case rateLimited(retryAfter: Date?)
    case server(String)

    var title: String {
        switch self {
        case .notSignedIn: return "Not connected"
        case .authenticationExpired: return "Google sign-in expired"
        case .offline: return "Offline"
        case .rateLimited: return "Google is rate limiting"
        case .server(let message): return message
        }
    }

    var symbolName: String {
        switch self {
        case .notSignedIn: return "person.crop.circle.badge.questionmark"
        case .authenticationExpired: return "key.slash"
        case .offline: return "wifi.slash"
        case .rateLimited: return "hourglass"
        case .server: return "exclamationmark.circle"
        }
    }

    /// Whether tapping refresh could plausibly fix it.
    var isRetryable: Bool {
        switch self {
        case .notSignedIn, .authenticationExpired: return false
        case .offline, .rateLimited, .server: return true
        }
    }

    /// Whether the user must re-authorise.
    var requiresReauthentication: Bool {
        switch self {
        case .notSignedIn, .authenticationExpired: return true
        default: return false
        }
    }
}

/// Snapshot of the refresh loop, surfaced in the footer.
struct SyncState: Equatable, Sendable {
    var isRefreshing: Bool = false
    var lastSuccessfulRefresh: Date?
    var problem: SyncProblem?

    /// True when the list is showing cached data because the last refresh failed.
    var isShowingStaleData: Bool { problem != nil && lastSuccessfulRefresh != nil }

    static let initial = SyncState()
}
