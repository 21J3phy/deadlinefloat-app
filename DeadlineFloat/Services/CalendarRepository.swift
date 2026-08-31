import Foundation

/// Fetches one refresh worth of calendar data and keeps the offline copy current.
///
/// Failure handling is deliberate rather than incidental:
///
/// * an expired or revoked sign-in propagates immediately so the UI can ask for
///   reconnection instead of spinning;
/// * a single calendar that fails does not sink the refresh — its previously
///   cached events are reused and the rest of the list stays fresh;
/// * if every calendar fails, the error is surfaced and the cached snapshot is
///   left untouched, so the window keeps showing the last good data.
actor CalendarRepository {
    /// How long a colour palette is trusted before it is fetched again.
    static let paletteMaxAge: TimeInterval = 24 * 60 * 60
    /// Calendars fetched at once. Small enough to stay well inside Google's
    /// per-user quota, large enough that a dozen calendars refresh promptly.
    static let concurrentCalendarFetches = 5

    private let client: GoogleCalendarClient
    private let cache: SnapshotCache
    private let clock: @Sendable () -> Date
    private var snapshot: CalendarSnapshot

    init(
        client: GoogleCalendarClient,
        cache: SnapshotCache = SnapshotCache(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.cache = cache
        self.clock = clock
        self.snapshot = cache.load() ?? .empty
    }

    func cachedSnapshot() -> CalendarSnapshot { snapshot }

    func clearCache() {
        snapshot = .empty
        cache.clear()
    }

    /// Pulls calendars, colours and events for `window`.
    ///
    /// - Parameter selectedCalendarIDs: `nil` means "the user has not chosen
    ///   yet", in which case the calendars Google itself has ticked are used.
    func refresh(window: DateWindow, selectedCalendarIDs: Set<String>?) async throws -> CalendarSnapshot {
        let calendars = try await client.calendarList()
        let targets = Self.targetCalendars(from: calendars, selection: selectedCalendarIDs)

        var palette = snapshot.palette
        var paletteFetchedAt = snapshot.paletteFetchedAt
        if shouldRefreshPalette(fetchedAt: paletteFetchedAt, palette: palette) {
            if let fetched = try? await client.colors() {
                palette = fetched
                paletteFetchedAt = clock()
            }
        }

        let results = await fetchEvents(for: targets, window: window)

        var failures: [Error] = []
        var perCalendar: [CalendarEvents] = []
        for target in targets {
            switch results[target.id] {
            case .success(let events):
                perCalendar.append(CalendarEvents(calendar: target, events: events))
            case .failure(let error):
                failures.append(error)
                // Keep whatever we last knew about this calendar rather than
                // making it silently vanish from the list.
                if let cached = snapshot.events(forCalendar: target.id) {
                    perCalendar.append(CalendarEvents(calendar: target, events: cached))
                }
            case .none:
                continue
            }
        }

        if let authFailure = failures.first(where: { Self.isAuthFailure($0) }) {
            throw authFailure
        }
        if !targets.isEmpty, perCalendar.isEmpty, let first = failures.first {
            throw first
        }

        // A colour id we have never seen means Google's palette moved on. Fetch
        // it once more so the row is drawn in the right colour straight away.
        let resolver = EventColorResolver(palette: palette)
        let events = perCalendar.flatMap(\.events)
        if resolver.needsPaletteRefresh(events: events, calendars: calendars),
           let refreshed = try? await client.colors() {
            palette = refreshed
            paletteFetchedAt = clock()
        }

        let updated = CalendarSnapshot(
            calendars: calendars,
            perCalendarEvents: perCalendar,
            palette: palette,
            paletteFetchedAt: paletteFetchedAt,
            fetchedAt: clock()
        )
        snapshot = updated
        cache.save(updated)

        if !failures.isEmpty {
            Log.sync.notice("Refreshed with \(failures.count, privacy: .public) calendar(s) served from cache")
        }
        return updated
    }

    // MARK: - Private

    private func fetchEvents(
        for calendars: [GoogleCalendarListEntry],
        window: DateWindow
    ) async -> [String: Result<[GoogleEvent], Error>] {
        var results: [String: Result<[GoogleEvent], Error>] = [:]
        var index = 0

        await withTaskGroup(of: (String, Result<[GoogleEvent], Error>).self) { group in
            func addTask(_ calendar: GoogleCalendarListEntry) {
                group.addTask { [client] in
                    do {
                        let events = try await client.events(calendarID: calendar.id, window: window)
                        return (calendar.id, .success(events))
                    } catch {
                        return (calendar.id, .failure(error))
                    }
                }
            }

            while index < calendars.count && index < Self.concurrentCalendarFetches {
                addTask(calendars[index])
                index += 1
            }

            while let (id, result) = await group.next() {
                results[id] = result
                if index < calendars.count {
                    addTask(calendars[index])
                    index += 1
                }
            }
        }
        return results
    }

    private func shouldRefreshPalette(fetchedAt: Date?, palette: GoogleColorsResponse?) -> Bool {
        guard palette != nil, let fetchedAt else { return true }
        return clock().timeIntervalSince(fetchedAt) > Self.paletteMaxAge
    }

    static func isAuthFailure(_ error: Error) -> Bool {
        if case APIError.unauthorized = error { return true }
        if case APIError.notSignedIn = error { return true }
        if case APIError.notConfigured = error { return true }
        return false
    }

    /// Which calendars to read. An explicit selection wins; otherwise fall back
    /// to the calendars ticked in Google Calendar itself, and finally to all of
    /// them so a first run is never empty.
    static func targetCalendars(
        from calendars: [GoogleCalendarListEntry],
        selection: Set<String>?
    ) -> [GoogleCalendarListEntry] {
        let usable = calendars.filter(\.isVisibleCandidate)
        if let selection {
            let chosen = usable.filter { selection.contains($0.id) }
            return chosen
        }
        let googleSelected = usable.filter { $0.selected == true }
        return googleSelected.isEmpty ? usable : googleSelected
    }
}
