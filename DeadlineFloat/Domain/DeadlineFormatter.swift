import Foundation

/// Locale-aware text for rows, section headers and the status footer.
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
        Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
        .weekday(.wide)
        .month(.wide)
        .day()
    }

    private var shortDateStyle: Date.FormatStyle {
        Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
        .month(.abbreviated)
        .day()
    }

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

    /// `Wednesday, September 2`
    func dayHeadline(_ date: Date) -> String { date.formatted(weekdayDateStyle) }

    func sectionTitle(for kind: DeadlineSection.Kind) -> String {
        switch kind {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .day(let date): return dayHeadline(date)
        }
    }

    /// Footer text: `Updated 2:14 PM`, or with the day when it is not today.
    func lastRefreshText(_ date: Date?, now: Date) -> String {
        guard let date else { return "Never updated" }
        if calendar.isDate(date, inSameDayAs: now) {
            return "Updated \(time(date))"
        }
        return "Updated \(date.formatted(shortDateStyle)) \(time(date))"
    }

    /// `No deadlines in the next 3 days`
    func emptyStateText(range: RangeOption, showingAllEvents: Bool) -> String {
        showingAllEvents
            ? "No events in the next \(range.longLabel)"
            : "No deadlines in the next \(range.longLabel)"
    }
}
