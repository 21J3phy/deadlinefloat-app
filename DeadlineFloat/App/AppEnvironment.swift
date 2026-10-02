import Foundation

/// Composition root. Everything the app needs is built once, here, and nothing
/// reaches for a singleton.
@MainActor
final class AppEnvironment {
    let preferences: Preferences
    let auth: GoogleAuthService
    let repository: CalendarRepository
    let cache: SnapshotCache
    let viewModel: DeadlineListViewModel

    init(
        isDemo: Bool = AppInfo.isDemoMode,
        defaults: UserDefaults = .standard,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        // A demo run must never disturb real settings, so it gets its own
        // defaults domain and starts from a clean slate.
        let resolvedDefaults: UserDefaults
        if isDemo, defaults == .standard {
            let suite = "\(AppInfo.bundleIdentifier).demo"
            let demoDefaults = UserDefaults(suiteName: suite) ?? .standard
            demoDefaults.removePersistentDomain(forName: suite)
            resolvedDefaults = demoDefaults
        } else {
            resolvedDefaults = defaults
        }

        let preferences = Preferences(defaults: resolvedDefaults)
        // A demo shows the whole app, dragging included; there is no account
        // behind it, so the moves go no further than the window.
        if isDemo { preferences.allowsEventEditing = true }
        self.preferences = preferences

        // Demo runs never touch the real keychain or the real cache file.
        let store: any TokenStoring = isDemo ? InMemoryTokenStore() : KeychainTokenStore()
        let cache = isDemo
            ? SnapshotCache(fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("deadlinefloat-demo.json"))
            : SnapshotCache()
        self.cache = cache

        let http = HTTPClient()
        let auth = GoogleAuthService(
            store: store,
            http: http,
            configuration: preferences.clientConfiguration
        )
        self.auth = auth

        let client = GoogleCalendarClient(
            http: http,
            accessTokenProvider: { try await auth.accessToken() }
        )
        let repository = CalendarRepository(client: client, cache: cache)
        self.repository = repository

        self.viewModel = DeadlineListViewModel(
            preferences: preferences,
            auth: auth,
            repository: repository,
            cache: cache,
            clock: clock,
            isDemo: isDemo
        )
    }
}
