import Foundation

/// Locale-aware text for rows, section headers, the spotlight and the status
/// footer.
///
/// Every formatter is built from an explicit locale, calendar and time zone so
/// the same input always produces the same output under test, and so the running
/// app follows the Mac's 12/24-hour setting.
struct DeadlineFormatter: Sendable {
    let calendar: Calendar
    let locale: Locale

    init(calendar: Calendar, locale: Locale = .autoupdatingCurrent) {
        self.calendar = calendar
        self.locale = locale
    }

    private var timeZone: TimeZone { calendar.timeZone }

    private var baseStyle: Date.FormatStyle {
        Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
    }

    private var timeStyle: Date.FormatStyle {
        Date.FormatStyle(
            date: .omitted,
            time: .shortened,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
    }

    private var weekdayDateStyle: Date.FormatStyle {
        baseStyle.weekday(.wide).month(.wide).day()
    }

    private var shortDateStyle: Date.FormatStyle {
        baseStyle.month(.abbreviated).day()
    }

    private var weekdayStyle: Date.FormatStyle {
        baseStyle.weekday(.wide)
    }

    // MARK: - Rows

    /// `11:59 PM`, or `All day` when there is no time to show.
    func timeText(for deadline: Deadline) -> String {
        guard let instant = deadline.displayInstant else { return "All day" }
        return instant.formatted(timeStyle)
    }

    /// Extra qualifier for multi-day all-day deadlines: `through Sep 1`.
    func spanText(for deadline: Deadline) -> String? {
        guard case .allDay(_, let endExclusive) = deadline.timing,
              let span = deadline.allDaySpanDays, span > 1,
              let lastDay = calendar.date(byAdding: .day, value: -1, to: endExclusive)
        else { return nil }
        return "through \(lastDay.formatted(shortDateStyle))"
    }

    func time(_ date: Date) -> String { date.formatted(timeStyle) }

    // MARK: - Sections

    /// `Wednesday, September 2`
    func dayHeadline(_ date: Date) -> String { date.formatted(weekdayDateStyle) }

    /// `Wednesday`
    func weekday(_ date: Date) -> String { date.formatted(weekdayStyle) }

    /// `Sep 2`
    func shortDate(_ date: Date) -> String { date.formatted(shortDateStyle) }

    func sectionTitle(for kind: DeadlineSection.Kind) -> String {
        switch kind {
        case .overdue: return "Overdue"
        case .today: return "Due today"
        case .tomorrow: return "Due tomorrow"
        case .day(let date): return dayHeadline(date)
        }
    }

    // MARK: - Ruler

    /// `9 AM`, `12 PM` — or `09`, `12` where the locale uses 24-hour time.
    func hourLabel(_ date: Date) -> String {
        date.formatted(baseStyle.hour(.defaultDigits(amPM: .abbreviated)))
    }

    // MARK: - Spotlight

    /// The day a deadline falls on, relative to now: `Today`, `Tomorrow`, a
    /// weekday name inside the coming week, otherwise `Sep 12`.
    func relativeDayLabel(_ day: Date, now: Date) -> String {
        let today = calendar.startOfDay(for: now)
        if calendar.isDate(day, inSameDayAs: today) { return "Today" }
        if calendar.isDate(day, inSameDayAs: today.adding(days: 1, calendar: calendar)) { return "Tomorrow" }
        if calendar.isDate(day, inSameDayAs: today.adding(days: -1, calendar: calendar)) { return "Yesterday" }
        let delta = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: day)).day ?? 0
        if delta > 1 && delta < 7 { return weekday(day) }
        return shortDate(day)
    }

    /// `Today at 4:21 PM`, `Tomorrow at 11:59 PM`, `Friday at 9:00 AM`, or
    /// `All day · Tomorrow` for a deadline with no time.
    func whenText(for deadline: Deadline, now: Date) -> String {
        let day = relativeDayLabel(deadline.dayStart, now: now)
        switch deadline.timing {
        case .allDay:
            if let span = spanText(for: deadline) { return "All day · \(day) \(span)" }
            return "All day · \(day)"
        case .timed(let start, _):
            return "\(day) at \(time(start))"
        }
    }

    // MARK: - Footer and empty state

    /// Footer text: `Updated 2:14 PM`, or with the day when it is not today.
    func lastRefreshText(_ date: Date?, now: Date) -> String {
        guard let date else { return "Never updated" }
        if calendar.isDate(date, inSameDayAs: now) {
            return "Updated \(time(date))"
        }
        return "Updated \(date.formatted(shortDateStyle)) \(time(date))"
    }

    /// `No deadlines today`, `No deadlines in the next 3 days`, `… this week`
    func emptyStateText(range: RangeOption, showingAllEvents: Bool) -> String {
        let noun = showingAllEvents ? "events" : "deadlines"
        switch range {
        case .oneDay: return "No \(noun) today"
        case .week: return "No \(noun) this week"
        default: return "No \(noun) in the next \(range.longLabel)"
        }
    }

    /// Footer summary: `9 deadlines`, `1 event`.
    func countText(_ count: Int, showingAllEvents: Bool) -> String {
        let noun = showingAllEvents ? "event" : "deadline"
        return "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}
