import Foundation

/// The stretch of the day the edge ruler covers: the whole calendar day,
/// midnight to midnight, so the needle is always on it and an 11:59 PM
/// deadline sits at the very bottom.
///
/// The span is expressed as a start hour and an end hour on the following
/// day, so a shorter "waking day" (say 7 AM to 1 AM) is a two-line change;
/// `current(now:)` then hands the small hours to the day before.
struct RulerSpan: Equatable, Sendable {
    static let startHour = 0
    static let endHour = 0

    /// The day's local midnight.
    let day: Date
    /// `startHour` on `day`.
    let start: Date
    /// `endHour` the following morning. Exclusive.
    let end: Date

    init(day: Date, calendar: Calendar) {
        let midnight = calendar.startOfDay(for: day)
        self.day = midnight
        self.start = calendar.date(bySettingHour: Self.startHour, minute: 0, second: 0, of: midnight) ?? midnight
        let next = midnight.adding(days: 1, calendar: calendar)
        self.end = calendar.date(bySettingHour: Self.endHour, minute: 0, second: 0, of: next) ?? next
    }

    /// The ruler that should be showing at `now`: today's, unless the span
    /// runs past midnight and yesterday's is still going.
    static func current(now: Date, calendar: Calendar) -> RulerSpan {
        let today = calendar.startOfDay(for: now)
        let lateCutoff = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: today) ?? today
        if now < lateCutoff {
            return RulerSpan(day: today.adding(days: -1, calendar: calendar), calendar: calendar)
        }
        return RulerSpan(day: today, calendar: calendar)
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Length in hours — 24 on an ordinary day, 23 or 25 across a DST change.
    var hours: Double { duration / 3_600 }

    func contains(_ instant: Date) -> Bool {
        instant >= start && instant < end
    }

    /// Where an instant falls along the ruler, 0 at the top and 1 at the
    /// bottom, clamped so a moment outside the span pins to the nearest end.
    func fraction(of instant: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, instant.timeIntervalSince(start) / duration))
    }

    /// The first instant of each hour on the ruler, for tick marks.
    func hourMarks(calendar: Calendar) -> [Date] {
        var marks: [Date] = []
        var cursor = start
        while cursor < end {
            marks.append(cursor)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return marks
    }

    /// Whether the deadline is drawn on this ruler: a timed one starts within
    /// the span; an all-day one covers the day.
    func covers(_ deadline: Deadline) -> Bool {
        switch deadline.timing {
        case .timed(let instant, _):
            return contains(instant)
        case .allDay(let from, let toExclusive):
            return from <= day && toExclusive > day
        }
    }

    /// The vertical span of a timed deadline as fractions of the ruler, with a
    /// minimum so a moment is still visible.
    func span(of deadline: Deadline, minimumFraction: Double) -> (start: Double, end: Double)? {
        guard case .timed(let from, let to) = deadline.timing, contains(from) else { return nil }
        let top = fraction(of: from)
        let bottom = max(top + minimumFraction, fraction(of: to ?? from))
        return (top, min(bottom, 1 + minimumFraction))
    }
}
