import XCTest
@testable import DeadlineFloat

final class DeadlineBuilderTests: XCTestCase {
    private let entry = Fixture.calendarEntry(id: "cs@example.com", name: "CS 18000", background: "#5484ed")

    // MARK: - Timed events

    func testTimedDeadlineUsesItsStartAsTheDueMoment() {
        let start = Fixture.date(2026, 9, 2, 23, 59)
        let event = Fixture.timedEvent(title: "DUE: Project 3", start: start, durationMinutes: 60)
        let deadline = Fixture.builder().build(event: event, calendarEntry: entry)

        XCTAssertEqual(deadline?.sortInstant, start)
        XCTAssertEqual(deadline?.overdueInstant, start, "a deadline is late the moment it passes, not when the block ends")
        XCTAssertEqual(deadline?.displayInstant, start)
        XCTAssertEqual(deadline?.dayStart, Fixture.date(2026, 9, 2))
        XCTAssertFalse(deadline!.isAllDay)
    }

    func testMidnightDeadlineIsFiledOnTheDayItFallsOn() {
        let midnight = Fixture.date(2026, 9, 3, 0, 0, 0)
        let event = Fixture.timedEvent(title: "DUE at midnight", start: midnight)
        let deadline = Fixture.builder().build(event: event, calendarEntry: entry)

        XCTAssertEqual(deadline?.dayStart, Fixture.date(2026, 9, 3))
        XCTAssertEqual(deadline?.sortInstant, midnight)
    }

    func testNoonIsNotConfusedWithMidnight() {
        let noon = Fixture.date(2026, 9, 3, 12, 0, 0)
        let midnight = Fixture.date(2026, 9, 3, 0, 0, 0)
        let builder = Fixture.builder()
        let noonDeadline = builder.build(event: Fixture.timedEvent(id: "n", title: "DUE noon", start: noon), calendarEntry: entry)!
        let midnightDeadline = builder.build(event: Fixture.timedEvent(id: "m", title: "DUE midnight", start: midnight), calendarEntry: entry)!

        XCTAssertEqual(noonDeadline.sortInstant.timeIntervalSince(midnightDeadline.sortInstant), 12 * 3600)
        XCTAssertEqual(noonDeadline.dayStart, midnightDeadline.dayStart)

        let formatter = DeadlineFormatter(calendar: Fixture.calendar(), locale: Fixture.locale)
        XCTAssertEqual(Fixture.plain(formatter.timeText(for: noonDeadline)), "12:00 PM")
        XCTAssertEqual(Fixture.plain(formatter.timeText(for: midnightDeadline)), "12:00 AM")
    }

    func testEndTimeUnspecifiedLeavesNoEnd() {
        var event = Fixture.timedEvent(start: Fixture.date(2026, 9, 2, 9))
        event.endTimeUnspecified = true
        let deadline = Fixture.builder().build(event: event, calendarEntry: entry)
        if case .timed(_, let end) = deadline!.timing {
            XCTAssertNil(end)
        } else {
            XCTFail("expected a timed deadline")
        }
    }

    // MARK: - All-day events

    func testAllDayDeadlineHasNoInventedTime() {
        let event = Fixture.allDayEvent(startDay: "2026-09-03", endDayExclusive: "2026-09-04")
        let deadline = Fixture.builder().build(event: event, calendarEntry: entry)!

        XCTAssertTrue(deadline.isAllDay)
        XCTAssertNil(deadline.displayInstant)
        XCTAssertEqual(deadline.sortInstant, Fixture.date(2026, 9, 3))
        XCTAssertEqual(deadline.overdueInstant, Fixture.date(2026, 9, 4), "an all-day item is late only once its day ends")
        XCTAssertEqual(deadline.allDaySpanDays, 1)

        let formatter = DeadlineFormatter(calendar: Fixture.calendar(), locale: Fixture.locale)
        XCTAssertEqual(formatter.timeText(for: deadline), "All day")
    }

    func testAllDayIsNotOverdueDuringItsOwnDay() {
        let event = Fixture.allDayEvent(startDay: "2026-09-03", endDayExclusive: "2026-09-04")
        let deadline = Fixture.builder().build(event: event, calendarEntry: entry)!

        XCTAssertFalse(deadline.isOverdue(now: Fixture.date(2026, 9, 3, 0, 1)))
        XCTAssertFalse(deadline.isOverdue(now: Fixture.date(2026, 9, 3, 23, 59)))
        XCTAssertTrue(deadline.isOverdue(now: Fixture.date(2026, 9, 4, 0, 0)))
    }

    func testMultiDayAllDayKeepsGooglesExclusiveEnd() {
        let event = Fixture.allDayEvent(startDay: "2026-09-03", endDayExclusive: "2026-09-06")
        let deadline = Fixture.builder().build(event: event, calendarEntry: entry)!

        XCTAssertEqual(deadline.allDaySpanDays, 3, "Sep 3–5 inclusive is three days")
        XCTAssertEqual(deadline.overdueInstant, Fixture.date(2026, 9, 6))

        let formatter = DeadlineFormatter(calendar: Fixture.calendar(), locale: Fixture.locale)
        XCTAssertEqual(formatter.spanText(for: deadline), "through Sep 5")
    }

    func testAllDayWithMissingEndDefaultsToOneDay() {
        var event = Fixture.allDayEvent(startDay: "2026-09-03", endDayExclusive: "2026-09-04")
        event.end = nil
        let deadline = Fixture.builder().build(event: event, calendarEntry: entry)!
        XCTAssertEqual(deadline.overdueInstant, Fixture.date(2026, 9, 4))
    }

    func testAllDayAcrossSpringForwardIsStillOneCalendarDay() {
        let event = Fixture.allDayEvent(startDay: "2026-03-08", endDayExclusive: "2026-03-09")
        let deadline = Fixture.builder().build(event: event, calendarEntry: entry)!
        XCTAssertEqual(deadline.overdueInstant.timeIntervalSince(deadline.sortInstant), 23 * 3600)
        XCTAssertEqual(deadline.allDaySpanDays, 1, "a 23-hour day is still one day")
    }

    // MARK: - Filtering during construction

    func testCancelledEventsAreDropped() {
        let event = Fixture.timedEvent(start: Fixture.date(2026, 9, 2, 9), status: "cancelled")
        XCTAssertNil(Fixture.builder().build(event: event, calendarEntry: entry))
    }

    func testDeclinedEventsAreDroppedByDefault() {
        let declined = GoogleEventAttendee(email: "me@example.com", responseStatus: "declined", this: true)
        let event = Fixture.timedEvent(start: Fixture.date(2026, 9, 2, 9), attendees: [declined])
        XCTAssertNil(Fixture.builder().build(event: event, calendarEntry: entry))

        var configuration = FilterConfiguration.default
        configuration.hideDeclinedEvents = false
        XCTAssertNotNil(Fixture.builder(configuration: configuration).build(event: event, calendarEntry: entry))
    }

    func testSomeoneElseDecliningDoesNotHideTheEvent() {
        let other = GoogleEventAttendee(email: "them@example.com", responseStatus: "declined", this: false)
        let event = Fixture.timedEvent(start: Fixture.date(2026, 9, 2, 9), attendees: [other])
        XCTAssertNotNil(Fixture.builder().build(event: event, calendarEntry: entry))
    }

    func testNonDeadlineTitlesAreDropped() {
        let event = Fixture.timedEvent(title: "Lecture", start: Fixture.date(2026, 9, 2, 9))
        XCTAssertNil(Fixture.builder().build(event: event, calendarEntry: entry))
    }

    func testUntitledEventsGetAPlaceholderAndOnlyShowInAllEventsMode() {
        var event = Fixture.timedEvent(start: Fixture.date(2026, 9, 2, 9))
        event.summary = nil
        XCTAssertNil(Fixture.builder().build(event: event, calendarEntry: entry))

        var configuration = FilterConfiguration.default
        configuration.showAllEvents = true
        let deadline = Fixture.builder(configuration: configuration).build(event: event, calendarEntry: entry)
        XCTAssertEqual(deadline?.title, "(No title)")
    }

    func testEventsWithoutAStartAreDropped() {
        var event = Fixture.timedEvent(start: Fixture.date(2026, 9, 2, 9))
        event.start = nil
        XCTAssertNil(Fixture.builder().build(event: event, calendarEntry: entry))
    }

    // MARK: - Metadata

    func testCalendarNameLocationAndLinkAreCarriedThrough() {
        let event = Fixture.timedEvent(
            title: "DUE: Lab 09",
            start: Fixture.date(2026, 9, 2, 17),
            location: "WALC 1055"
        )
        let deadline = Fixture.builder().build(event: event, calendarEntry: entry)!
        XCTAssertEqual(deadline.calendarName, "CS 18000")
        XCTAssertEqual(deadline.calendarID, "cs@example.com")
        XCTAssertEqual(deadline.location, "WALC 1055")
        XCTAssertEqual(deadline.link?.absoluteString, "https://calendar.google.com/calendar/event?eid=e1")
        XCTAssertEqual(deadline.id, "cs@example.com|e1")
    }

    func testBlankLocationBecomesNil() {
        var event = Fixture.timedEvent(start: Fixture.date(2026, 9, 2, 17))
        event.location = "   "
        XCTAssertNil(Fixture.builder().build(event: event, calendarEntry: entry)?.location)
    }

    func testConferencePlatformIsDetected() {
        var event = Fixture.timedEvent(start: Fixture.date(2026, 9, 2, 17))
        event.hangoutLink = "https://meet.google.com/abc-defg-hij"
        XCTAssertEqual(Fixture.builder().build(event: event, calendarEntry: entry)?.platform, "Google Meet")

        var zoom = Fixture.timedEvent(id: "z", start: Fixture.date(2026, 9, 2, 17))
        zoom.conferenceData = GoogleConferenceData(
            entryPoints: [GoogleConferenceEntryPoint(entryPointType: "video", uri: "https://purdue.zoom.us/j/123")]
        )
        XCTAssertEqual(Fixture.builder().build(event: zoom, calendarEntry: entry)?.platform, "Zoom")
    }

    func testUrgencyBucketing() {
        let now = Fixture.date(2026, 9, 2, 12, 0)
        let builder = Fixture.builder()

        let overdue = builder.build(event: Fixture.timedEvent(id: "a", start: now.addingTimeInterval(-60)), calendarEntry: entry)!
        let soon = builder.build(event: Fixture.timedEvent(id: "b", start: now.addingTimeInterval(3 * 3600)), calendarEntry: entry)!
        let edge = builder.build(event: Fixture.timedEvent(id: "c", start: now.addingTimeInterval(6 * 3600)), calendarEntry: entry)!
        let later = builder.build(event: Fixture.timedEvent(id: "d", start: now.addingTimeInterval(6 * 3600 + 1)), calendarEntry: entry)!

        XCTAssertEqual(overdue.urgency(now: now), .overdue)
        XCTAssertEqual(soon.urgency(now: now), .imminent)
        XCTAssertEqual(edge.urgency(now: now), .imminent, "exactly six hours away is still imminent")
        XCTAssertEqual(later.urgency(now: now), .later)
    }
}
