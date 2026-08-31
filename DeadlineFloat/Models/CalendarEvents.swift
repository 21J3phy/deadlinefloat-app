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
