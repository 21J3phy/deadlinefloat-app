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
    private(set) var taskDetectionMessage: String?

    var taskFocus: ScheduleFocus? {
        ScheduleFocus.select(from: agenda.filter { $0.isDeadline && !completedIDs.contains($0.id) }, now: now)
    }

    /// Ids of everything marked done, for the schedule and the strip.
    private(set) var completedIDs: Set<String> = []

    /// Google has granted the scope that lets an event be moved. Until it
    /// has, blocks are drawn but cannot be dragged.
    private(set) var hasEditingGrant = false

    /// The last event this app moved, so it can be put back.
    private(set) var lastMove: UndoableMove?

    private(set) var calendars: [GoogleCalendarListEntry] = []
    private(set) var syncState = SyncState.initial
    private(set) var isSignedIn = false
    private(set) var accountLabel: String?
    private(set) var now = Date()

    /// Non-fatal message shown in the sign-in card, e.g. a failed sign-in attempt.
    var transientMessage: String?

    /// Whether clicking that message should offer a reconnection — a sign-in
    /// that failed — or merely dismiss it, as a move that could not be written
    /// while offline should.
    private(set) var transientMessageIsReconnect = true

    /// True while the browser has the sign-in and the loopback listener is open.
    private(set) var isSigningIn = false

    let preferences: Preferences

    // MARK: Collaborators

    @ObservationIgnored private let auth: GoogleAuthService
    @ObservationIgnored private let repository: CalendarRepository
    @ObservationIgnored private let cache: SnapshotCache
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let isDemo: Bool

    @ObservationIgnored private let taskClassifier = EventTaskClassifier()
    @ObservationIgnored private var classificationTask: Task<Void, Never>?
    @ObservationIgnored private var classificationInputs: [String: TaskClassificationInput] = [:]
    @ObservationIgnored private var taskDecisions: [String: Bool] = [:]
    @ObservationIgnored private var classificationGeneration = 0
    @ObservationIgnored private var classificationRetryAfter = Date.distantPast
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
    /// Moves that have been drawn but not yet confirmed by Google, by deadline
    /// id. They are laid over the snapshot on every rebuild, so a refresh that
    /// lands mid-flight cannot drag a block back to where it was.
    @ObservationIgnored private var pendingMoves: [String: EventMove] = [:]
    /// Bumped per event on every drop, so a slow answer to an earlier drag
    /// cannot overwrite a later one.
    @ObservationIgnored private var moveGeneration: [String: Int] = [:]

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
        classificationTask?.cancel()
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
        classificationTask?.cancel()
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

    /// Changing the hours the ruler draws can move which day the bar is on,
    /// and a waking day that starts yesterday needs yesterday fetched.
    func daySpanChanged() {
        rebuild()
        if effectiveLookbackDays > fetchedLookbackDays { refresh() }
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
    var ruler: RulerSpan { RulerSpan.current(now: now, calendar: calendar, span: preferences.daySpan) }


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
            try await auth.signIn(allowsEditing: preferences.allowsEventEditing)
            isSignedIn = true
            syncState.problem = nil
            hasEditingGrant = GoogleEndpoints.grants(editing: await auth.grantedScope())
            refresh()
        } catch is CancellationError {
            // The user closed the browser tab or pressed Cancel; nothing to report.
        } catch {
            transientMessageIsReconnect = true
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
        classificationGeneration += 1
        classificationTask?.cancel()
        classificationTask = nil
        classificationInputs = [:]
        taskDecisions = [:]
        await auth.signOut()
        await repository.clearCache()
        snapshot = .empty
        calendars = []
        completed = []
        agenda = []
        focus = nil
        accountLabel = nil
        isSignedIn = false
        hasEditingGrant = false
        lastMove = nil
        pendingMoves.removeAll()
        moveGeneration.removeAll()
        fetchedRangeDays = 0
        fetchedLookbackDays = 0
        syncState = SyncState(isRefreshing: false, lastSuccessfulRefresh: nil, problem: .notSignedIn)
        rebuild()
    }

    func open(_ deadline: Deadline) {
        guard let link = deadline.link else { return }
        NSWorkspace.shared.open(link)
    }

    // MARK: Editing

    /// One move already made, kept so it can be put back.
    struct UndoableMove: Equatable, Sendable {
        var deadlineID: String
        var title: String
        /// Where the event was before the drag.
        var previous: EventMove
    }

    /// Whether blocks on the calendar can be dragged right now: the setting is
    /// on, somebody is signed in, and Google granted the scope that allows it.
    ///
    /// A demo run needs no grant and keeps the change to itself — there is no
    /// account behind it to write to.
    var canEditEvents: Bool {
        guard preferences.allowsEventEditing else { return false }
        return isDemo || (isSignedIn && hasEditingGrant)
    }

    /// Editing is wanted but not yet permitted — the sign-in predates it, or
    /// consent was refused. Settings offers a reconnection when this is true.
    var needsEditingPermission: Bool {
        preferences.allowsEventEditing && isSignedIn && !hasEditingGrant && !isDemo
    }

    /// The snapshot with any moves still in flight laid over it. Everything
    /// the panel shows is derived from this rather than the raw snapshot, so a
    /// dropped block stays where it was dropped even if a scheduled refresh
    /// lands before Google has confirmed the change.
    private var effectiveSnapshot: CalendarSnapshot {
        guard !pendingMoves.isEmpty else { return snapshot }
        return snapshot.applying(Array(pendingMoves.values), timeZone: calendar.timeZone)
    }

    /// Moves an event, or changes how long it lasts.
    ///
    /// The new time is drawn immediately and written to Google behind it. If
    /// Google refuses — a read-only calendar, an event somebody else owns, no
    /// network — the block goes back where it came from and the footer says
    /// why, so a failure is never silent and never leaves the two out of step.
    func reschedule(_ deadline: Deadline, start: Date, end: Date) {
        guard canEditEvents, let move = EventEdit.move(for: deadline, proposal: .init(start: start, end: end)) else { return }
        guard let previous = EventEdit.reverse(of: deadline) else { return }

        let id = move.deadlineID
        let generation = (moveGeneration[id] ?? 0) + 1
        moveGeneration[id] = generation
        pendingMoves[id] = move
        lastMove = UndoableMove(deadlineID: id, title: deadline.title, previous: previous)
        transientMessage = nil
        rebuild()

        // A demo has nowhere to send it; the drawing is the whole of it.
        guard !isDemo else {
            snapshot = snapshot.applying([move], timeZone: calendar.timeZone)
            pendingMoves.removeValue(forKey: id)
            rebuild()
            return
        }

        let timeZone = calendar.timeZone
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await repository.reschedule(move, timeZone: timeZone)
                guard self.moveGeneration[id] == generation else { return }
                self.snapshot = updated
                self.pendingMoves.removeValue(forKey: id)
                self.rebuild()
            } catch {
                guard self.moveGeneration[id] == generation else { return }
                self.pendingMoves.removeValue(forKey: id)
                if self.lastMove?.deadlineID == id { self.lastMove = nil }
                let needsReconnect = Self.isAuthFailure(error)
                self.transientMessageIsReconnect = needsReconnect
                self.show(message: Self.moveFailureMessage(for: error))
                if needsReconnect { self.hasEditingGrant = false }
                Log.sync.error("Could not move event: \(error.localizedDescription, privacy: .public)")
                self.rebuild()
            }
        }
    }

    /// Whether this block is the one that could be put back.
    func canUndoMove(of deadline: Deadline) -> Bool {
        canEditEvents && lastMove?.deadlineID == deadline.id
    }

    /// Puts the last moved event back where it was.
    func undoLastMove() {
        guard canEditEvents, let undo = lastMove,
              let deadline = agenda.first(where: { $0.id == undo.deadlineID })
        else { return }
        lastMove = nil
        reschedule(deadline, start: undo.previous.start, end: undo.previous.end)
        // Putting an event back is not itself something to undo.
        lastMove = nil
    }

    /// Puts a message in the footer and takes it away again, so an explanation
    /// of one failed drag does not sit there for the rest of the day.
    private func show(message: String, seconds: TimeInterval = 8) {
        transientMessage = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.transientMessage == message else { return }
            self.transientMessage = nil
        }
    }

    nonisolated static func isAuthFailure(_ error: Error) -> Bool {
        if case APIError.unauthorized = error { return true }
        if case APIError.notSignedIn = error { return true }
        return false
    }

    nonisolated static func moveFailureMessage(for error: Error) -> String {
        switch error {
        case APIError.unauthorized:
            return "Reconnect to move events"
        case APIError.offline:
            return "Offline — the event did not move"
        case APIError.server(let status, let message) where status == 403:
            return message.isEmpty ? "That calendar is read-only" : message
        default:
            return "Could not move that event"
        }
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
        let scope = await auth.grantedScope()
        hasEditingGrant = signedIn && GoogleEndpoints.grants(editing: scope)
        if !signedIn { syncState.problem = .notSignedIn }
    }

    /// Re-derives the visible list from the in-memory snapshot. Cheap, pure, and
    /// the only place `sections` is assigned.
    func rebuild() {
        updateTaskClassification()
        var assembler = DeadlineAssembler(
            calendar: calendar,
            configuration: preferences.filter,
            mergeDuplicates: preferences.mergeDuplicates
        )
        assembler.taskClassifications = taskDecisions
        let source = effectiveSnapshot
        let partition = assembler.partition(
            from: source,
            selectedCalendarIDs: preferences.selectedCalendarIDs,
            completed: preferences.completedDeadlines,
            window: window,
            now: now
        )
        let updated = partition.sections
        if updated != sections { sections = updated }
        if partition.completed != completed { completed = partition.completed }

        let schedule = assembler.agenda(from: source, selectedCalendarIDs: preferences.selectedCalendarIDs, window: fetchWindow)
        if schedule != agenda { agenda = schedule }
        let done = Set(preferences.completedDeadlines.keys)
        if done != completedIDs { completedIDs = done }
        let focused = ScheduleFocus.select(from: schedule, now: now)
        if focused != focus { focus = focused }

        scheduleTick()
    }

    /// Run inference outside the rendering/drag path, and reject answers for
    /// a replaced snapshot. Unknown and failed entries never become task rows.
    private func updateTaskClassification() {
        var inputs: [String: TaskClassificationInput] = [:]
        let detector = DeadlineDetector(configuration: preferences.filter)
        for entry in snapshot.perCalendarEvents {
            if let selected = preferences.selectedCalendarIDs, !selected.contains(entry.calendar.id) { continue }
            for event in entry.events where !event.isCancelled {
                if preferences.filter.hideDeclinedEvents && event.isDeclinedBySelf { continue }
                if detector.isExcluded(title: event.summary ?? "") { continue }
                inputs["\(entry.calendar.id)|\(event.id)"] = TaskClassificationInput(event: event, calendarName: entry.calendar.displayName)
            }
        }
        if inputs != classificationInputs {
            classificationGeneration += 1
            classificationTask?.cancel()
            classificationTask = nil
            taskDecisions = taskDecisions.filter { inputs[$0.key] == classificationInputs[$0.key] }
            classificationInputs = inputs
            classificationRetryAfter = .distantPast
        }
        guard !inputs.isEmpty else { taskDetectionMessage = nil; return }
        if let message = EventTaskClassifier.unavailableMessage {
            taskDetectionMessage = message
            return
        }
        guard classificationTask == nil, clock() >= classificationRetryAfter else { return }
        let pending = inputs.filter { taskDecisions[$0.key] == nil }
        guard !pending.isEmpty else { taskDetectionMessage = nil; return }
        let generation = classificationGeneration
        taskDetectionMessage = "Finding unfinished tasks with Apple Intelligence…"
        classificationTask = Task { [weak self, taskClassifier] in
            var failed = false
            for (id, input) in pending.sorted(by: { $0.key < $1.key }) {
                guard !Task.isCancelled else { return }
                do {
                    let decision = try await taskClassifier.classify(input)
                    guard let self, !Task.isCancelled, self.classificationGeneration == generation else { return }
                    self.taskDecisions[id] = decision
                    self.rebuild()
                } catch {
                    guard !Task.isCancelled else { return }
                    failed = true
                }
            }
            guard let self, self.classificationGeneration == generation else { return }
            self.classificationTask = nil
            self.classificationRetryAfter = self.clock().addingTimeInterval(failed ? 60 : 0)
            self.taskDetectionMessage = failed ? "Some events could not be classified. Task detection will retry." : nil
            self.rebuild()
        }
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
