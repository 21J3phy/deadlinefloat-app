import AppKit
import Foundation
import Observation

/// The panel's view model: owns the refresh loop, the clock tick, and the
/// derived sections the list renders.
///
/// It deliberately keeps the last good `CalendarSnapshot` in memory. Changing the
/// range, editing keywords or toggling a calendar re-derives the list instantly
/// from that snapshot; only a genuinely wider window goes back to the network.
@MainActor
@Observable
final class DeadlineListViewModel {
    // MARK: Published state

    private(set) var sections: [DeadlineSection] = []
    private(set) var calendars: [GoogleCalendarListEntry] = []
    private(set) var syncState = SyncState.initial
    private(set) var isSignedIn = false
    private(set) var accountLabel: String?
    private(set) var now = Date()

    /// Non-fatal message shown under the header, e.g. a failed sign-in attempt.
    var transientMessage: String?

    /// True while the browser has the sign-in and the loopback listener is open.
    private(set) var isSigningIn = false

    let preferences: Preferences

    // MARK: Collaborators

    @ObservationIgnored private let auth: GoogleAuthService
    @ObservationIgnored private let repository: CalendarRepository
    @ObservationIgnored private let cache: SnapshotCache
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let isDemo: Bool

    @ObservationIgnored private var snapshot: CalendarSnapshot = .empty
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    @ObservationIgnored private var tickLoop: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    /// The widest range already fetched, so narrowing the range never refetches.
    @ObservationIgnored private var fetchedRangeDays = 0

    // MARK: Init

    init(
        preferences: Preferences,
        auth: GoogleAuthService,
        repository: CalendarRepository,
        cache: SnapshotCache = SnapshotCache(),
        clock: @escaping @Sendable () -> Date = { Date() },
        isDemo: Bool = AppInfo.isDemoMode
    ) {
        self.preferences = preferences
        self.auth = auth
        self.repository = repository
        self.cache = cache
        self.clock = clock
        self.isDemo = isDemo
        self.now = clock()
    }

    deinit {
        refreshLoop?.cancel()
        tickLoop?.cancel()
        refreshTask?.cancel()
    }

    // MARK: Lifecycle

    func start() {
        if isDemo {
            snapshot = DemoData.snapshot(now: clock(), calendar: calendar)
            calendars = snapshot.calendars
            isSignedIn = true
            accountLabel = "demo@deadlinefloat.app"
            syncState = SyncState(isRefreshing: false, lastSuccessfulRefresh: clock(), problem: nil)
            rebuild()
            startTicking()
            return
        }

        // Paint the last known list immediately; the network refresh follows.
        snapshot = cache.load() ?? .empty
        calendars = snapshot.calendars
        accountLabel = Self.accountLabel(from: snapshot.calendars)
        rebuild()

        startTicking()
        startRefreshLoop()
        installSystemObservers()

        Task { await refreshSignInState() }
        refresh()
    }

    func stop() {
        refreshLoop?.cancel()
        tickLoop?.cancel()
        refreshTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        observers.removeAll()
    }

    // MARK: Derived values

    var calendarForComputation: Calendar { calendar }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = .current
        return calendar
    }

    var window: DateWindow {
        DateWindow(
            now: now,
            days: preferences.range.days,
            calendar: calendar,
            overdueLookbackDays: preferences.overdueLookbackDays
        )
    }

    var formatter: DeadlineFormatter { DeadlineFormatter(calendar: calendar) }
    var countdownFormatter: CountdownFormatter { CountdownFormatter(calendar: calendar) }

    var isEmpty: Bool { sections.isEmpty }

    var totalCount: Int { sections.reduce(0) { $0 + $1.deadlines.count } }

    var overdueCount: Int { sections.first(where: \.isOverdue)?.deadlines.count ?? 0 }

    /// Non-nil only when this build cannot sign in at all — an empty or
    /// malformed compiled-in client ID. Users of a released build never see it.
    var configurationProblem: String? { preferences.clientConfiguration.configurationProblem }

    // MARK: Actions

    func setRange(_ range: RangeOption) {
        guard preferences.range != range else { return }
        let needsWiderWindow = range.days > fetchedRangeDays
        preferences.range = range
        rebuild()
        if needsWiderWindow { refresh() }
    }

    func setCompactMode(_ compact: Bool) {
        preferences.compactMode = compact
    }

    func filterChanged() {
        rebuild()
    }

    func calendarSelectionChanged() {
        rebuild()
        refresh()
    }

    /// Manual refresh, and the target of the 5-minute timer.
    func refresh() {
        guard !isDemo else { return }
        guard refreshTask == nil else { return }

        syncState.isRefreshing = true
        let window = self.window
        let selection = preferences.selectedCalendarIDs
        let requestedDays = preferences.range.days

        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await repository.refresh(window: window, selectedCalendarIDs: selection)
                self.applySuccessfulRefresh(updated, requestedDays: requestedDays)
            } catch is CancellationError {
                self.syncState.isRefreshing = false
            } catch {
                self.applyFailedRefresh(error)
            }
            self.refreshTask = nil
        }
    }

    func signIn() async {
        guard !isSigningIn else { return }
        transientMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }

        await auth.updateConfiguration(preferences.clientConfiguration)
        do {
            try await auth.signIn()
            isSignedIn = true
            syncState.problem = nil
            refresh()
        } catch is CancellationError {
            // The user closed the browser tab or cancelled; nothing to report.
        } catch {
            transientMessage = error.localizedDescription
            Log.auth.error("Sign-in failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func signOut() async {
        await auth.signOut()
        await repository.clearCache()
        snapshot = .empty
        calendars = []
        sections = []
        accountLabel = nil
        isSignedIn = false
        fetchedRangeDays = 0
        syncState = SyncState(isRefreshing: false, lastSuccessfulRefresh: nil, problem: .notSignedIn)
    }

    func open(_ deadline: Deadline) {
        guard let link = deadline.link else { return }
        NSWorkspace.shared.open(link)
    }

    // MARK: Refresh plumbing

    private func applySuccessfulRefresh(_ updated: CalendarSnapshot, requestedDays: Int) {
        snapshot = updated
        calendars = updated.calendars
        accountLabel = Self.accountLabel(from: updated.calendars) ?? accountLabel
        fetchedRangeDays = max(fetchedRangeDays, requestedDays)
        isSignedIn = true
        syncState = SyncState(isRefreshing: false, lastSuccessfulRefresh: updated.fetchedAt, problem: nil)
        rebuild()
    }

    private func applyFailedRefresh(_ error: Error) {
        let problem = Self.problem(for: error)
        if problem.requiresReauthentication { isSignedIn = false }
        syncState.isRefreshing = false
        syncState.problem = problem
        Log.sync.error("Refresh failed: \(String(describing: problem), privacy: .public)")
        // Cached deadlines stay on screen; the footer explains why they are stale.
        rebuild()
    }

    private func refreshSignInState() async {
        let signedIn = await auth.isSignedIn()
        isSignedIn = signedIn
        if !signedIn { syncState.problem = .notSignedIn }
    }

    /// Re-derives the visible list from the in-memory snapshot. Cheap, pure, and
    /// the only place `sections` is assigned.
    func rebuild() {
        let assembler = DeadlineAssembler(
            calendar: calendar,
            configuration: preferences.filter,
            mergeDuplicates: preferences.mergeDuplicates
        )
        let updated = assembler.sections(
            from: snapshot,
            selectedCalendarIDs: preferences.selectedCalendarIDs,
            window: window,
            now: now
        )
        if updated != sections { sections = updated }
    }

    // MARK: Timers and system notifications

    private func startTicking() {
        tickLoop?.cancel()
        tickLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, !Task.isCancelled else { return }
                self.now = self.clock()
                self.rebuild()
            }
        }
    }

    private func startRefreshLoop() {
        refreshLoop?.cancel()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.preferences.refreshInterval else { return }
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    /// Day rollover, time-zone moves, clock changes and waking from sleep all
    /// invalidate what "today" means, so each one re-derives and re-fetches.
    private func installSystemObservers() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSCalendarDayChanged,
            .NSSystemTimeZoneDidChange,
            .NSSystemClockDidChange
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.now = self.clock()
                    self.rebuild()
                    self.refresh()
                }
            }
            observers.append(token)
        }

        let workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = self.clock()
                self.rebuild()
                self.refresh()
            }
        }
        observers.append(workspaceToken)
    }

    // MARK: Helpers

    /// Google's primary calendar id is the account's address, so the app can
    /// label the connection without ever asking for the profile or email scope.
    nonisolated static func accountLabel(from calendars: [GoogleCalendarListEntry]) -> String? {
        calendars.first { $0.primary == true }?.id
    }

    nonisolated static func problem(for error: Error) -> SyncProblem {
        switch error {
        case let apiError as APIError:
            switch apiError {
            case .unauthorized: return .authenticationExpired
            case .notSignedIn, .notConfigured: return .notSignedIn
            case .offline: return .offline
            case .rateLimited(let retryAfter):
                return .rateLimited(retryAfter: retryAfter.map { Date().addingTimeInterval($0) })
            case .server(_, let message): return .server(message.isEmpty ? "Google request failed" : message)
            case .invalidResponse: return .server("Unexpected response from Google")
            case .disallowedRequest(let detail): return .server("Blocked request: \(detail)")
            }
        case let urlError as URLError where HTTPClient.isOffline(urlError):
            return .offline
        case is AuthError:
            return .authenticationExpired
        default:
            return .server(error.localizedDescription)
        }
    }
}
