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
        let detector = DeadlineDetector(configuration: configuration)
        let builder = DeadlineBuilder(calendar: calendar, detector: detector, colorResolver: resolver)

        let included = snapshot.perCalendarEvents.filter { entry in
            guard let selectedCalendarIDs else { return true }
            return selectedCalendarIDs.contains(entry.calendar.id)
        }

        var deadlines = builder.build(events: included)

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

    func sections(from snapshot: CalendarSnapshot, selectedCalendarIDs: Set<String>?, window: DateWindow, now: Date) -> [DeadlineSection] {
        let deadlines = deadlines(from: snapshot, selectedCalendarIDs: selectedCalendarIDs)
        return DeadlineGrouper(calendar: calendar, formatter: formatter)
            .sections(from: deadlines, now: now, window: window)
    }
}
