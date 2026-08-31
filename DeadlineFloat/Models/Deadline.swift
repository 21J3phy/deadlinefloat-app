import Foundation

/// Where a deadline's colour came from, so the UI can explain itself and the
/// resolver can be tested.
enum ColorSource: String, Hashable, Sendable, Codable {
    /// The event carried its own `colorId`.
    case event
    /// Inherited from the parent calendar.
    case calendar
    /// Neither was available (offline first run, unknown id).
    case fallback
}

/// How urgent a deadline is *right now*.
///
/// Urgency is communicated with icons, text and an extra border — never by
/// replacing the Google colour.
enum Urgency: Int, Hashable, Sendable, Comparable {
    case overdue = 0
    case imminent = 1   // due within `Urgency.imminentWindow`
    case later = 2

    static let imminentWindow: TimeInterval = 6 * 60 * 60

    static func < (lhs: Urgency, rhs: Urgency) -> Bool { lhs.rawValue < rhs.rawValue }

    var symbolName: String {
        switch self {
        case .overdue: return "exclamationmark.triangle.fill"
        case .imminent: return "clock.badge.exclamationmark.fill"
        case .later: return "calendar"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .overdue: return "Overdue"
        case .imminent: return "Due within six hours"
        case .later: return "Upcoming"
        }
    }
}

/// A deadline ready to display: everything the row needs, already resolved in
/// the user's local time zone.
struct Deadline: Identifiable, Hashable, Sendable {
    enum Timing: Hashable, Sendable {
        /// `start` and `endExclusive` are local midnights. Google's all-day end
        /// date is exclusive and is kept that way here.
        case allDay(start: Date, endExclusive: Date)
        case timed(start: Date, end: Date?)
    }

    /// Stable across refreshes: calendar + instance identity.
    var id: String
    var eventID: String
    var calendarID: String
    var calendarName: String
    var title: String
    var location: String?
    var platform: String?
    var link: URL?
    var timing: Timing
    var color: RGBColor
    var colorSource: ColorSource
    var isRecurringInstance: Bool
    var recurringEventID: String?
    var iCalUID: String?
    var updatedAt: Date?

    /// The instant used for chronological ordering. All-day deadlines sort to
    /// the top of their day.
    var sortInstant: Date

    /// `now >= overdueInstant` means the deadline has passed. For all-day items
    /// this is the end of the day, not its start — an all-day task is not late
    /// at 00:01.
    var overdueInstant: Date

    /// Local midnight of the day the deadline is filed under.
    var dayStart: Date

    /// Other calendars carrying the very same event, when duplicates were merged.
    var additionalCalendarNames: [String] = []

    var isAllDay: Bool {
        if case .allDay = timing { return true }
        return false
    }

    /// The moment shown to the user, or `nil` for all-day deadlines.
    var displayInstant: Date? {
        switch timing {
        case .allDay: return nil
        case .timed(let start, _): return start
        }
    }

    /// Multi-day all-day deadlines (`Aug 30 – Sep 1`) span more than one day.
    var allDaySpanDays: Int? {
        guard case .allDay(let start, let endExclusive) = timing else { return nil }
        let seconds = endExclusive.timeIntervalSince(start)
        return max(1, Int((seconds / 86_400).rounded()))
    }

    func urgency(now: Date) -> Urgency {
        if now >= overdueInstant { return .overdue }
        let reference = isAllDay ? overdueInstant : sortInstant
        if reference.timeIntervalSince(now) <= Urgency.imminentWindow { return .imminent }
        return .later
    }

    func isOverdue(now: Date) -> Bool { now >= overdueInstant }
}
