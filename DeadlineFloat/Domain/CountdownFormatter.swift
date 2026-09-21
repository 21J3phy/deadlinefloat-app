import Foundation

/// Renders the human-readable countdown shown on every row, e.g. `2 hr 14 min
/// left`, and the large figure on the now/next card, e.g. `1 hr 12 min`.
///
/// Everything is in whole minutes, in words: no seconds anywhere, and zero
/// trailing units are dropped (`1 hr`, not `1 hr 0 min`). Timed deadlines
/// count down to their exact due instant. All-day deadlines have no instant
/// to count to, so they are expressed in whole days (`Today`, `in 2 days`,
/// `1 day ago`) rather than inventing a time.
struct CountdownFormatter: Sendable {
    let calendar: Calendar

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    // MARK: - Rows

    func string(for deadline: Deadline, now: Date) -> String {
        if deadline.isAllDay {
            return allDayString(dayStart: deadline.dayStart, now: now)
        }
        return string(target: deadline.sortInstant, now: now)
    }

    /// Countdown between two instants.
    ///
    /// Durations are truncated rather than rounded: with 119 seconds left the
    /// answer is "1 min left", never "2 min left". A countdown that overstates
    /// the time remaining is worse than one that understates it.
    func string(target: Date, now: Date) -> String {
        let seconds = Int(target.timeIntervalSince(now))
        if seconds >= 0 {
            return seconds < 60 ? "<1 min left" : "\(components(seconds)) left"
        }
        let past = -seconds
        return past < 60 ? "just now" : "\(components(past)) ago"
    }

    /// Whole-day countdown for all-day deadlines.
    func allDayString(dayStart: Date, now: Date) -> String {
        let delta = dayDelta(to: dayStart, now: now)
        if delta == 0 { return "Today" }
        if delta > 0 { return "in \(days(delta))" }
        return "\(days(-delta)) ago"
    }

    // MARK: - The card and the pill

    /// The large figure for what is on or next: `1 hr 12 min`, `45 min`,
    /// `2 days 3 hr`. The view around it says whether that is time *left* or
    /// time *until*.
    func spotlightString(for deadline: Deadline, now: Date) -> String {
        if deadline.isAllDay {
            return allDaySpotlightString(dayStart: deadline.dayStart, now: now)
        }
        return spotlightString(target: deadline.sortInstant, now: now)
    }

    func spotlightString(target: Date, now: Date) -> String {
        let seconds = Int(target.timeIntervalSince(now))
        if seconds <= 0 { return "Now" }
        if seconds < 60 { return "<1 min" }
        return components(seconds)
    }

    func allDaySpotlightString(dayStart: Date, now: Date) -> String {
        let delta = dayDelta(to: dayStart, now: now)
        if delta == 0 { return "Today" }
        if delta == 1 { return "Tomorrow" }
        if delta > 1 { return "In \(delta) days" }
        return delta == -1 ? "Yesterday" : "\(-delta) days ago"
    }

    // MARK: - Private

    private func dayDelta(to dayStart: Date, now: Date) -> Int {
        let today = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: today, to: dayStart).day ?? 0
    }

    private func days(_ count: Int) -> String {
        "\(count) \(count == 1 ? "day" : "days")"
    }

    /// Formats a positive duration as `X days Y hr`, `X hr Y min` or `X min`,
    /// dropping a trailing zero unit.
    private func components(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let dayCount = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        let mins = minutes % 60

        if dayCount > 0 {
            return hours > 0 ? "\(days(dayCount)) \(hours) hr" : days(dayCount)
        }
        if hours > 0 {
            return mins > 0 ? "\(hours) hr \(mins) min" : "\(hours) hr"
        }
        return "\(mins) min"
    }
}
