import Foundation

/// The span of time the app looks at: **today plus the selected number of
/// calendar days**, in the Mac's local time zone.
///
/// All arithmetic goes through `Calendar`, never `now + n * 86400`, so the
/// window stays correct across daylight-saving transitions: on the day the
/// clocks spring forward the window is 23 hours long, and 25 on the day they
/// fall back.
struct DateWindow: Equatable, Sendable {
    /// Local midnight at the start of today.
    let start: Date
    /// Local midnight `days` calendar days later. Exclusive.
    let end: Date
    /// How far before `start` overdue items are still shown (0 by default,
    /// matching "today plus N days" exactly).
    let lookbackStart: Date
    let days: Int
    let timeZone: TimeZone

    init(now: Date, days: Int, calendar: Calendar, overdueLookbackDays: Int = 0) {
        let days = max(1, days)
        let lookback = max(0, overdueLookbackDays)
        self.days = days
        self.timeZone = calendar.timeZone
        let midnight = calendar.startOfDay(for: now)
        self.start = midnight
        self.end = midnight.adding(days: days, calendar: calendar)
        self.lookbackStart = lookback == 0 ? midnight : midnight.adding(days: -lookback, calendar: calendar)
    }

    /// Lower bound sent to the API. Google filters `timeMin` against the event's
    /// *end*, so ongoing multi-day events are still returned.
    var queryStart: Date { lookbackStart }
    var queryEnd: Date { end }

    /// True when a half-open interval `[from, to)` overlaps the window at all.
    func overlaps(from: Date, to: Date) -> Bool {
        to > lookbackStart && from < end
    }

    func contains(_ instant: Date) -> Bool {
        instant >= lookbackStart && instant < end
    }
}
