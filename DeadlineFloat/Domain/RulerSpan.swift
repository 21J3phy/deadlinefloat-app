import Foundation

/// The stretch of the day the edge ruler covers.
///
/// Midnight to midnight by default, so the needle is always on it and an
/// 11:59 PM deadline sits at the very bottom. `DaySpan` shortens it to a
/// waking day — 7 AM to 1 AM, say — and then the span is expressed as a start
/// hour and an end hour on the following morning, and `current(now:)` hands
/// the small hours to the day before.
///
/// A shortened span changes what is *drawn*, never what is *counted*. Every
/// instant still belongs to exactly one day — see `claims` — so an event at
/// 3 AM on a day that starts at 7 is drawn pinned to the top of its own
/// column rather than disappearing.
struct RulerSpan: Equatable, Sendable {
    /// The day's local midnight.
    let day: Date
    /// The hour the ruler starts, on `day`.
    let start: Date
    /// The hour it ends, on `day` or the following morning. Exclusive.
    let end: Date
    /// The first and last instant filed under this day, which reaches past
    /// both ends of the ruler when the span is shorter than the day.
    let claimStart: Date
    let claimEnd: Date

    init(day: Date, calendar: Calendar, span: DaySpan = .wholeDay) {
        let midnight = calendar.startOfDay(for: day)
        self.day = midnight
        self.start = calendar.date(bySettingHour: span.startHour, minute: 0, second: 0, of: midnight) ?? midnight

        let next = midnight.adding(days: 1, calendar: calendar)
        if span.wraps {
            let end = calendar.date(bySettingHour: span.endHour, minute: 0, second: 0, of: next) ?? next
            self.end = end
            // A wrapping span already reaches into tomorrow, so the hours it
            // owns are exactly the hours between one day's end and the next's.
            self.claimStart = calendar.date(bySettingHour: span.endHour, minute: 0, second: 0, of: midnight) ?? midnight
            self.claimEnd = end
        } else {
            self.end = calendar.date(bySettingHour: span.endHour, minute: 0, second: 0, of: midnight) ?? next
            // A span inside one day owns that whole calendar day; the hours
            // before it and after it pin to its two ends.
            self.claimStart = midnight
            self.claimEnd = next
        }
    }

    /// The ruler that should be showing at `now`: today's, unless the span
    /// runs past midnight and yesterday's is still going.
    static func current(now: Date, calendar: Calendar, span: DaySpan = .wholeDay) -> RulerSpan {
        let today = calendar.startOfDay(for: now)
        guard span.wraps else { return RulerSpan(day: today, calendar: calendar, span: span) }
        let lateCutoff = calendar.date(bySettingHour: span.endHour, minute: 0, second: 0, of: today) ?? today
        if now < lateCutoff {
            return RulerSpan(day: today.adding(days: -1, calendar: calendar), calendar: calendar, span: span)
        }
        return RulerSpan(day: today, calendar: calendar, span: span)
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Length in hours — 24 on an ordinary whole day, 23 or 25 across a DST
    /// change, and whatever the span asks for otherwise.
    var hours: Double { duration / 3_600 }

    /// Whether the instant is on the drawn ruler. The needle asks this, so it
    /// appears only while now is somewhere the ruler can put it.
    func contains(_ instant: Date) -> Bool {
        instant >= start && instant < end
    }

    /// Whether this day is the one the instant is filed under. Every instant
    /// is claimed by exactly one day, whatever the span leaves off the ruler.
    func claims(_ instant: Date) -> Bool {
        instant >= claimStart && instant < claimEnd
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

    /// Whether the deadline is drawn on this ruler: a timed one is filed under
    /// this day; an all-day one covers it.
    func covers(_ deadline: Deadline) -> Bool {
        switch deadline.timing {
        case .timed(let instant, _):
            return claims(instant)
        case .allDay(let from, let toExclusive):
            return from <= day && toExclusive > day
        }
    }

    /// The vertical span of a timed deadline as fractions of the ruler, with a
    /// minimum so a moment is still visible.
    func span(of deadline: Deadline, minimumFraction: Double) -> (start: Double, end: Double)? {
        guard case .timed(let from, let to) = deadline.timing, claims(from) else { return nil }
        let top = fraction(of: from)
        let bottom = max(top + minimumFraction, fraction(of: to ?? from))
        return (top, min(bottom, 1 + minimumFraction))
    }
}
