import Foundation

/// The whole read path in one place: raw Google payload in, sections out.
///
/// Keeping it a pure value type means the entire pipeline — filtering, colour
/// resolution, de-duplication, window clamping, grouping and sorting — is
/// testable without a network, a keychain or a window.
struct DeadlineAssembler: Sendable {
    var calendar: Calendar
    var locale: Locale
    var configuration: FilterConfiguration
    var mergeDuplicates: Bool
    /// When supplied, only positively classified tasks enter the task list.
    var taskClassifications: [String: Bool]? = nil

    init(
        calendar: Calendar,
        locale: Locale = .autoupdatingCurrent,
        configuration: FilterConfiguration = .default,
        mergeDuplicates: Bool = true
    ) {
        self.calendar = calendar
        self.locale = locale
        self.configuration = configuration
        self.mergeDuplicates = mergeDuplicates
    }

    var formatter: DeadlineFormatter { DeadlineFormatter(calendar: calendar, locale: locale) }

    func deadlines(from snapshot: CalendarSnapshot, selectedCalendarIDs: Set<String>?) -> [Deadline] {
        let resolver = EventColorResolver(palette: snapshot.palette)
        var taskFilter = configuration
        if taskClassifications != nil { taskFilter.showAllEvents = true }
        let detector = DeadlineDetector(configuration: taskFilter)
        let builder = DeadlineBuilder(calendar: calendar, detector: detector, colorResolver: resolver)

        let included = snapshot.perCalendarEvents.filter { entry in
            guard let selectedCalendarIDs else { return true }
            return selectedCalendarIDs.contains(entry.calendar.id)
        }

        var deadlines = builder.build(events: included)
        if let taskClassifications {
            deadlines = deadlines.filter { taskClassifications[$0.id] == true }
        }

        if mergeDuplicates {
            let priority = snapshot.calendars
                .sorted { lhs, rhs in
                    if (lhs.primary == true) != (rhs.primary == true) { return lhs.primary == true }
                    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                }
                .map(\.id)
            deadlines = DuplicateReducer(priorityOrder: priority).reduce(deadlines)
        }
        return deadlines
    }

    /// Everything on the calendar inside `window` — lectures, meetings and
    /// deadlines alike — in time order, with all-day items first. The include
    /// rules are ignored; exclusions and declined-event hiding still apply, so
    /// a `DONE …` event never appears. Each item says whether it is a deadline
    /// so the schedule can mark the ones that matter.
    func agenda(from snapshot: CalendarSnapshot, selectedCalendarIDs: Set<String>?, window: DateWindow) -> [Deadline] {
        var everything = configuration
        everything.showAllEvents = true
        let resolver = EventColorResolver(palette: snapshot.palette)
        let builder = DeadlineBuilder(calendar: calendar, detector: DeadlineDetector(configuration: everything), colorResolver: resolver)
        let detector = DeadlineDetector(configuration: configuration)

        let included = snapshot.perCalendarEvents.filter { entry in
            guard let selectedCalendarIDs else { return true }
            return selectedCalendarIDs.contains(entry.calendar.id)
        }

        var items = builder.build(events: included)
        if mergeDuplicates {
            let priority = snapshot.calendars
                .sorted { lhs, rhs in
                    if (lhs.primary == true) != (rhs.primary == true) { return lhs.primary == true }
                    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                }
                .map(\.id)
            items = DuplicateReducer(priorityOrder: priority).reduce(items)
        }

        return items
            .filter { item in
                switch item.timing {
                case .timed(let start, _): return window.contains(start)
                case .allDay(let start, let end): return window.overlaps(from: start, to: end)
                }
            }
            .map { item in
                var item = item
                item.isDeadline = taskClassifications.map { $0[item.id] == true }
                    ?? (configuration.showAllEvents || detector.isDeadline(title: item.title))
                return item
            }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                if lhs.sortInstant != rhs.sortInstant { return lhs.sortInstant < rhs.sortInstant }
                return lhs.id < rhs.id
            }
    }

    func sections(from snapshot: CalendarSnapshot, selectedCalendarIDs: Set<String>?, window: DateWindow, now: Date) -> [DeadlineSection] {
        let deadlines = deadlines(from: snapshot, selectedCalendarIDs: selectedCalendarIDs)
        return DeadlineGrouper(calendar: calendar, formatter: formatter)
            .sections(from: deadlines, now: now, window: window)
    }
}
