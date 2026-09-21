import Foundation

/// Sorts deadlines chronologically and files them into sections:
/// **Overdue**, **Today**, **Tomorrow**, then one section per remaining day
/// titled with the full weekday and date.
struct DeadlineGrouper: Sendable {
    let calendar: Calendar
    let formatter: DeadlineFormatter

    func sections(from deadlines: [Deadline], now: Date, window: DateWindow) -> [DeadlineSection] {
        let visible = visible(deadlines, window: window, now: now)

        var overdue: [Deadline] = []
        var upcoming: [Deadline] = []
        for deadline in visible {
            if deadline.isOverdue(now: now) {
                overdue.append(deadline)
            } else {
                upcoming.append(deadline)
            }
        }

        var sections: [DeadlineSection] = []
        if !overdue.isEmpty {
            sections.append(
                DeadlineSection(kind: .overdue, title: formatter.sectionTitle(for: .overdue), deadlines: sort(overdue))
            )
        }

        let today = calendar.startOfDay(for: now)
        let tomorrow = today.adding(days: 1, calendar: calendar)

        let byDay = Dictionary(grouping: upcoming, by: \.dayStart)
        for day in byDay.keys.sorted() {
            guard let items = byDay[day] else { continue }
            let kind: DeadlineSection.Kind
            if calendar.isDate(day, inSameDayAs: today) {
                kind = .today
            } else if calendar.isDate(day, inSameDayAs: tomorrow) {
                kind = .tomorrow
            } else {
                kind = .day(day)
            }
            sections.append(
                DeadlineSection(kind: kind, title: formatter.sectionTitle(for: kind), deadlines: sort(items))
            )
        }
        return sections
    }

    /// Chronological, with stable tie-breaking so the list never reshuffles
    /// between refreshes when two deadlines share a moment.
    func sort(_ deadlines: [Deadline]) -> [Deadline] {
        deadlines.sorted { lhs, rhs in
            if lhs.sortInstant != rhs.sortInstant { return lhs.sortInstant < rhs.sortInstant }
            // All-day items sit above timed items that share the same instant.
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    /// The deadlines that fall inside the window, in their original order.
    func visible(_ deadlines: [Deadline], window: DateWindow, now: Date) -> [Deadline] {
        deadlines.compactMap { clampToWindow($0, window: window, now: now) }
    }

    // MARK: - Private

    /// Drops deadlines outside the window and pulls an in-progress multi-day
    /// all-day event forward so it is filed under today rather than a day that
    /// has already scrolled out of range.
    private func clampToWindow(_ deadline: Deadline, window: DateWindow, now: Date) -> Deadline? {
        var deadline = deadline
        switch deadline.timing {
        case .timed:
            guard window.contains(deadline.sortInstant) else { return nil }
        case .allDay(let start, let endExclusive):
            guard window.overlaps(from: start, to: endExclusive) else { return nil }
            if deadline.dayStart < window.start && !deadline.isOverdue(now: now) {
                deadline.dayStart = window.start
            }
        }
        return deadline
    }
}
