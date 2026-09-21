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

    /// Every deadline in the range, grouped by day.
    private(set) var sections: [DeadlineSection] = []

    /// Deadlines the user has marked done, most recently completed last.
    private(set) var completed: [Deadline] = []

    /// Every event in the fetch window — the schedule for the calendar
    /// columns, the sliver, and the now/next focus.
    private(set) var agenda: [Deadline] = []

    /// The event happening now, or the next one to start.
    private(set) var focus: ScheduleFocus?

    /// Ids of everything marked done, for the schedule and the strip.
    private(set) var completedIDs: Set<String> = []

    private(set) var calendars: [GoogleCalendarListEntry] = []
    private(set) var syncState = SyncState.initial
    private(set) var isSignedIn = false
    private(set) var accountLabel: String?
    private(set) var now = Date()

    /// Non-fatal message shown in the sign-in card, e.g. a failed sign-in attempt.
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
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    /// Set when a refresh was asked for while one was already running, so the
    /// request is honoured afterwards instead of dropped.
    @ObservationIgnored private var refreshRequestedWhileBusy = false
    /// The widest window already fetched, so narrowing the range never refetches.
    @ObservationIgnored private var fetchedRangeDays = 0
    @ObservationIgnored private var fetchedLookbackDays = 0

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
        tickTask?.cancel()
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
            return
        }

        // Paint the last known list immediately; the network refresh follows.
        snapshot = cache.load() ?? .empty
        calendars = snapshot.calendars
        accountLabel = Self.accountLabel(from: snapshot.calendars)
        rebuild()

        startRefreshLoop()
        installSystemObservers()

        Task { await refreshSignInState() }
        refresh()
    }

    func stop() {
        refreshLoop?.cancel()
        tickTask?.cancel()
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

    /// The days the panel shows: today plus the range.
    var window: DateWindow {
        DateWindow(
            now: now,
            days: preferences.range.days,
            calendar: calendar,
            overdueLookbackDays: preferences.overdueLookbackDays
        )
    }

    /// Always at least three days, so the next event and the pill beside the
    /// sliver are known even when the panel shows only today.
    static let minimumFetchDays = 3

    var fetchWindow: DateWindow {
        DateWindow(
            now: now,
            days: max(Self.minimumFetchDays, preferences.range.days),
            calendar: calendar,
            overdueLookbackDays: effectiveLookbackDays
        )
    }

    /// If the ruler's span ran past midnight, the small hours would still be
    /// yesterday's day, and the fetch would need to reach back to it. On the
    /// full-day span this is always today.
    private var effectiveLookbackDays: Int {
        let wakingDayIsYesterday = ruler.day < calendar.startOfDay(for: now)
        return max(preferences.overdueLookbackDays, wakingDayIsYesterday ? 1 : 0)
    }

    /// The local midnight of each day the calendar shows: first the day the
    /// sliver is on, so the two agree and the needle is where the sliver's
    /// is, then the rest of the range.
    var calendarDays: [Date] {
        let first = ruler.day
        return (0..<preferences.range.days).map { first.adding(days: $0, calendar: calendar) }
    }

    /// Today's events, for the sliver.
    var todayAgenda: [Deadline] {
        let ruler = ruler
        return agenda.filter { ruler.covers($0) }
    }

    /// The stretch of the day the edge ruler shows right now.
    var ruler: RulerSpan { RulerSpan.current(now: now, calendar: calendar) }


    var formatter: DeadlineFormatter { DeadlineFormatter(calendar: calendar) }
    var countdownFormatter: CountdownFormatter { CountdownFormatter(calendar: calendar) }

    var isEmpty: Bool { sections.isEmpty }

    var totalCount: Int { sections.reduce(0) { $0 + $1.deadlines.count } }

    var overdueCount: Int { sections.first(where: \.isOverdue)?.deadlines.count ?? 0 }

    /// What the menu bar shows beside the icon, or `nil` for a quiet menu bar:
    /// `42 min left` while something is on, `in 2 hr 14 min` before the next thing.
    var menuBarCountdownText: String? {
        guard preferences.menuBarShowsCountdown, let focus else { return nil }
        let text = countdownFormatter.string(target: focus.until, now: now)
        let figure = text.hasSuffix(" left") ? String(text.dropLast(5)) : text
        return focus.kind == .happeningNow ? "\(figure) left" : "in \(figure)"
    }

    /// Non-nil only when this build cannot sign in at all — an empty or
    /// malformed compiled-in client ID. Users of a released build never see it.
    var configurationProblem: String? { preferences.clientConfiguration.configurationProblem }

    // MARK: Actions

    func setRange(_ range: RangeOption) {
        guard preferences.range != range else { return }
        let needsWiderWindow = max(Self.minimumFetchDays, range.days) > fetchedRangeDays
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

    /// A longer look-back is a wider window, which the last fetch may not cover.
    func lookbackChanged() {
        rebuild()
        if preferences.overdueLookbackDays > fetchedLookbackDays { refresh() }
    }

    func calendarSelectionChanged() {
        rebuild()
        refresh()
    }

    /// Manual refresh, and the target of the timer. A request that arrives
    /// while a refresh is running is queued and honoured once it finishes.
    func refresh() {
        guard !isDemo else { return }
        guard refreshTask == nil else {
            refreshRequestedWhileBusy = true
            return
        }

        syncState.isRefreshing = true
        let window = self.fetchWindow
        let selection = preferences.selectedCalendarIDs
        let requestedDays = window.days
        let requestedLookback = effectiveLookbackDays

        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await repository.refresh(window: window, selectedCalendarIDs: selection)
                self.applySuccessfulRefresh(updated, requestedDays: requestedDays, requestedLookback: requestedLookback)
            } catch is CancellationError {
                self.syncState.isRefreshing = false
            } catch {
                self.applyFailedRefresh(error)
            }
            self.refreshTask = nil
            if self.refreshRequestedWhileBusy {
                self.refreshRequestedWhileBusy = false
                self.refresh()
            }
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
            // The user closed the browser tab or pressed Cancel; nothing to report.
        } catch {
            transientMessage = error.localizedDescription
            Log.auth.error("Sign-in failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stops waiting for the browser. The listener closes and the sign-in
    /// button returns to its resting state.
    func cancelSignIn() {
        guard isSigningIn else { return }
        Task { await auth.cancelSignIn() }
    }

    func signOut() async {
        await auth.signOut()
        await repository.clearCache()
        snapshot = .empty
        calendars = []
        completed = []
        agenda = []
        focus = nil
        accountLabel = nil
        isSignedIn = false
        fetchedRangeDays = 0
        fetchedLookbackDays = 0
        syncState = SyncState(isRefreshing: false, lastSuccessfulRefresh: nil, problem: .notSignedIn)
        rebuild()
    }

    func open(_ deadline: Deadline) {
        guard let link = deadline.link else { return }
        NSWorkspace.shared.open(link)
    }

    // MARK: Completion

    func complete(_ deadline: Deadline) {
        preferences.markCompleted(deadline.id, at: clock())
        rebuild()
    }

    func restore(_ deadline: Deadline) {
        preferences.markNotCompleted(deadline.id)
        rebuild()
    }

    func toggleCompleted(_ deadline: Deadline) {
        if preferences.isCompleted(deadline.id) { restore(deadline) } else { complete(deadline) }
    }

    /// A swipe on an active row completes it; a swipe on a completed row
    /// brings it back. Either direction works — the gesture is "toggle".
    func handleSwipe(_ key: SwipeRowKey, _ direction: SwipeDirection) {
        switch key.list {
        case .active:
            if let deadline = activeDeadline(withID: key.deadlineID) { complete(deadline) }
        case .completed:
            if let deadline = completed.first(where: { $0.id == key.deadlineID }) { restore(deadline) }
        }
    }

    private func activeDeadline(withID id: String) -> Deadline? {
        if let listed = sections.lazy.flatMap(\.deadlines).first(where: { $0.id == id }) { return listed }
        return agenda.first { $0.id == id && $0.isDeadline }
    }

    func copyLink(_ deadline: Deadline) {
        guard let link = deadline.link else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(link.absoluteString, forType: .string)
    }

    func copyTitle(_ deadline: Deadline) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(deadline.title, forType: .string)
    }

    // MARK: Refresh plumbing

    private func applySuccessfulRefresh(_ updated: CalendarSnapshot, requestedDays: Int, requestedLookback: Int) {
        snapshot = updated
        calendars = updated.calendars
        accountLabel = Self.accountLabel(from: updated.calendars) ?? accountLabel
        fetchedRangeDays = max(fetchedRangeDays, requestedDays)
        fetchedLookbackDays = max(fetchedLookbackDays, requestedLookback)
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
        let partition = assembler.partition(
            from: snapshot,
            selectedCalendarIDs: preferences.selectedCalendarIDs,
            completed: preferences.completedDeadlines,
            window: window,
            now: now
        )
        let updated = partition.sections
        if updated != sections { sections = updated }
        if partition.completed != completed { completed = partition.completed }

        let schedule = assembler.agenda(from: snapshot, selectedCalendarIDs: preferences.selectedCalendarIDs, window: fetchWindow)
        if schedule != agenda { agenda = schedule }
        let done = Set(preferences.completedDeadlines.keys)
        if done != completedIDs { completedIDs = done }
        let focused = ScheduleFocus.select(from: schedule, now: now)
        if focused != focus { focus = focused }

        scheduleTick()
    }

    // MARK: Clock

    /// The clock advances on the minute, so every `Xm left` flips exactly when
    /// it should, and additionally at the first moment a visible deadline
    /// changes state — passes its due time, or comes within the imminent
    /// window — so a row never lingers in the wrong section.
    private func scheduleTick() {
        tickTask?.cancel()
        let target = Self.nextTick(after: now, calendar: calendar, deadlines: sections.flatMap(\.deadlines) + agenda)
        let delay = max(0.2, target.timeIntervalSince(clock()))
        tickTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.now = self.clock()
            self.rebuild()
        }
    }

    nonisolated static func nextTick(after now: Date, calendar: Calendar, deadlines: [Deadline]) -> Date {
        let second = calendar.component(.second, from: now)
        let nanosecond = Double(calendar.component(.nanosecond, from: now)) / 1_000_000_000
        var next = now.addingTimeInterval(60 - Double(second) - nanosecond)

        for deadline in deadlines {
            var transitions = [
                deadline.overdueInstant,
                (deadline.isAllDay ? deadline.overdueInstant : deadline.sortInstant).addingTimeInterval(-Urgency.imminentWindow)
            ]
            if case .timed(let start, let end) = deadline.timing {
                transitions.append(start)
                transitions.append(end ?? start.addingTimeInterval(30 * 60))
            }
            for instant in transitions where instant > now && instant < next {
                next = instant
            }
        }
        // A hair after the boundary, so the comparison lands on the right side.
        return next.addingTimeInterval(0.05)
    }

    // MARK: Timers and system notifications

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
