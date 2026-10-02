import Foundation

/// Events fetched from one calendar, kept together so the parent calendar's name
/// and colour stay attached to them.
struct CalendarEvents: Hashable, Sendable, Codable {
    var calendar: GoogleCalendarListEntry
    var events: [GoogleEvent]
}

/// Everything one refresh produced. Persisted verbatim so the window has content
/// the moment it opens and an offline launch still shows deadlines.
struct CalendarSnapshot: Hashable, Sendable, Codable {
    var calendars: [GoogleCalendarListEntry]
    var perCalendarEvents: [CalendarEvents]
    var palette: GoogleColorsResponse?
    var paletteFetchedAt: Date?
    var fetchedAt: Date

    init(
        calendars: [GoogleCalendarListEntry] = [],
        perCalendarEvents: [CalendarEvents] = [],
        palette: GoogleColorsResponse? = nil,
        paletteFetchedAt: Date? = nil,
        fetchedAt: Date = .distantPast
    ) {
        self.calendars = calendars
        self.perCalendarEvents = perCalendarEvents
        self.palette = palette
        self.paletteFetchedAt = paletteFetchedAt
        self.fetchedAt = fetchedAt
    }

    static let empty = CalendarSnapshot()

    var isEmpty: Bool { perCalendarEvents.allSatisfy(\.events.isEmpty) }

    var allEvents: [GoogleEvent] { perCalendarEvents.flatMap(\.events) }

    func events(forCalendar id: String) -> [GoogleEvent]? {
        perCalendarEvents.first { $0.calendar.id == id }?.events
    }
}

// MARK: - Editing

extension GoogleEvent {
    /// The same event at a new time.
    ///
    /// Only the two timestamps change. The event keeps the zone it was written
    /// in, so an event created in another time zone still displays there in
    /// Google Calendar after it has been nudged here; the instant is carried by
    /// the offset in `dateTime`, which is what every reader actually uses.
    func rescheduled(start: Date, end: Date, timeZone: TimeZone) -> GoogleEvent {
        var copy = self
        let zone = self.start?.timeZone ?? timeZone.identifier
        copy.start = GoogleEventDateTime(
            dateTime: GoogleDate.rfc3339String(from: start, timeZone: timeZone),
            timeZone: zone
        )
        copy.end = GoogleEventDateTime(
            dateTime: GoogleDate.rfc3339String(from: end, timeZone: timeZone),
            timeZone: self.end?.timeZone ?? zone
        )
        copy.endTimeUnspecified = false
        return copy
    }
}

extension CalendarSnapshot {
    /// The snapshot as it will be once `moves` have landed.
    ///
    /// This is what the panel draws the instant a block is dropped, before
    /// Google has answered. Rewriting the raw events rather than the finished
    /// `Deadline`s means the whole read path — grouping, sorting, which day an
    /// event is filed under, whether it is overdue — runs over the new time,
    /// so a block dragged to tomorrow really is on tomorrow's list.
    func applying(_ moves: [EventMove], timeZone: TimeZone) -> CalendarSnapshot {
        guard !moves.isEmpty else { return self }
        var byCalendar: [String: [String: EventMove]] = [:]
        for move in moves {
            byCalendar[move.calendarID, default: [:]][move.eventID] = move
        }

        var copy = self
        copy.perCalendarEvents = perCalendarEvents.map { entry in
            guard let wanted = byCalendar[entry.calendar.id] else { return entry }
            var entry = entry
            entry.events = entry.events.map { event in
                guard let move = wanted[event.id] else { return event }
                return event.rescheduled(start: move.start, end: move.end, timeZone: timeZone)
            }
            return entry
        }
        return copy
    }

    /// The snapshot with one event replaced by the copy Google returned.
    func replacing(_ event: GoogleEvent, inCalendar calendarID: String) -> CalendarSnapshot {
        var copy = self
        copy.perCalendarEvents = perCalendarEvents.map { entry in
            guard entry.calendar.id == calendarID else { return entry }
            var entry = entry
            if let index = entry.events.firstIndex(where: { $0.id == event.id }) {
                entry.events[index] = event
            }
            return entry
        }
        return copy
    }
}
