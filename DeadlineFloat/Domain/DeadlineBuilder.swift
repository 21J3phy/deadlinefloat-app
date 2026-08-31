import Foundation

/// Turns Google events into display-ready `Deadline` values.
///
/// The builder is the only place that interprets Google's time model, so the
/// rules live here in one readable list:
///
/// * A **timed** event's due moment is its *start*. That is the time shown, the
///   time the countdown counts down to, and the moment after which it is overdue.
/// * An **all-day** event has no invented time. It sorts to the top of its day
///   and only becomes overdue once the day is over — Google's all-day `end.date`
///   is exclusive and is kept that way.
/// * A **recurring** event arrives already expanded (`singleEvents=true`), so
///   each instance carries its own start; `recurringEventId` is retained purely
///   for display and de-duplication.
struct DeadlineBuilder: Sendable {
    let calendar: Calendar
    let detector: DeadlineDetector
    let colorResolver: EventColorResolver

    func build(_ input: CalendarEvents) -> [Deadline] {
        input.events.compactMap { build(event: $0, calendarEntry: input.calendar) }
    }

    func build(events: [CalendarEvents]) -> [Deadline] {
        events.flatMap(build)
    }

    func build(event: GoogleEvent, calendarEntry: GoogleCalendarListEntry) -> Deadline? {
        guard !event.isCancelled else { return nil }
        if detector.configuration.hideDeclinedEvents && event.isDeclinedBySelf { return nil }

        let rawTitle = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = rawTitle.isEmpty ? "(No title)" : rawTitle
        guard detector.shouldDisplay(title: title) else { return nil }
        guard let timing = timing(for: event) else { return nil }

        let resolution = colorResolver.resolve(event: event, calendarEntry: calendarEntry)

        let sortInstant: Date
        let overdueInstant: Date
        let dayStart: Date

        switch timing {
        case .allDay(let start, let endExclusive):
            sortInstant = start
            overdueInstant = endExclusive
            dayStart = start
        case .timed(let start, _):
            sortInstant = start
            overdueInstant = start
            dayStart = calendar.startOfDay(for: start)
        }

        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)

        return Deadline(
            id: "\(calendarEntry.id)|\(event.id)",
            eventID: event.id,
            calendarID: calendarEntry.id,
            calendarName: calendarEntry.displayName,
            title: title,
            location: (location?.isEmpty ?? true) ? nil : location,
            platform: event.conferencePlatform,
            link: event.htmlLink.flatMap(URL.init(string:)),
            timing: timing,
            color: resolution.color,
            colorSource: resolution.source,
            isRecurringInstance: event.isRecurringInstance,
            recurringEventID: event.recurringEventId,
            iCalUID: event.iCalUID,
            updatedAt: event.updated.flatMap(GoogleDate.timestamp(from:)),
            sortInstant: sortInstant,
            overdueInstant: overdueInstant,
            dayStart: dayStart
        )
    }

    // MARK: - Timing

    private func timing(for event: GoogleEvent) -> Deadline.Timing? {
        guard let start = event.start else { return nil }

        if start.isAllDay {
            guard let startDate = start.date,
                  let startInstant = GoogleDate.allDayStart(from: startDate, calendar: calendar)
            else { return nil }

            let endInstant: Date
            if let endDate = event.end?.date,
               let parsed = GoogleDate.allDayStart(from: endDate, calendar: calendar),
               parsed > startInstant {
                endInstant = parsed
            } else {
                // A one-day all-day event ends at the next local midnight.
                endInstant = startInstant.adding(days: 1, calendar: calendar)
            }
            return .allDay(start: startInstant, endExclusive: endInstant)
        }

        guard let dateTime = start.dateTime,
              let startInstant = GoogleDate.timestamp(from: dateTime)
        else { return nil }

        var endInstant: Date?
        if event.endTimeUnspecified != true,
           let endString = event.end?.dateTime,
           let parsed = GoogleDate.timestamp(from: endString),
           parsed >= startInstant {
            endInstant = parsed
        }
        return .timed(start: startInstant, end: endInstant)
    }
}
