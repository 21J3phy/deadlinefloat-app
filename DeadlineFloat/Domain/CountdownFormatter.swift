import Foundation

/// Renders the human-readable countdown shown on every row, e.g. `2h 14m left`.
///
/// Timed deadlines count down to their exact due instant. All-day deadlines have
/// no instant to count to, so they are expressed in whole days (`Today`, `in 2d`,
/// `1d ago`) rather than inventing a time.
struct CountdownFormatter: Sendable {
    let calendar: Calendar

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    func string(for deadline: Deadline, now: Date) -> String {
        if deadline.isAllDay {
            return allDayString(dayStart: deadline.dayStart, now: now)
        }
        return string(target: deadline.sortInstant, now: now)
    }

    /// Countdown between two instants.
    ///
    /// Durations are truncated rather than rounded: with 119 seconds left the
    /// answer is "1m left", never "2m left". A countdown that overstates the
    /// time remaining is worse than one that understates it.
    func string(target: Date, now: Date) -> String {
        let seconds = Int(target.timeIntervalSince(now))
        if seconds >= 0 {
            return seconds < 60 ? "<1m left" : "\(components(seconds)) left"
        }
        let past = -seconds
        return past < 60 ? "just now" : "\(components(past)) ago"
    }

    /// Whole-day countdown for all-day deadlines.
    func allDayString(dayStart: Date, now: Date) -> String {
        let today = calendar.startOfDay(for: now)
        let delta = calendar.dateComponents([.day], from: today, to: dayStart).day ?? 0
        if delta == 0 { return "Today" }
        if delta > 0 { return "in \(delta)d" }
        return "\(-delta)d ago"
    }

    // MARK: - Private

    /// Formats a positive duration as `Xd Yh`, `Xh Ym` or `Xm`.
    private func components(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        let mins = minutes % 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}
