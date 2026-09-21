import XCTest
@testable import DeadlineFloat

final class SpotlightCountdownTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private lazy var formatter = CountdownFormatter(calendar: calendar)
    private let now = Fixture.date(2026, 9, 2, 12, 0, 0)

    private func spotlight(_ offset: TimeInterval) -> String {
        formatter.spotlightString(target: now.addingTimeInterval(offset), now: now)
    }

    func testWholeMinutesInWordsNoSeconds() {
        XCTAssertEqual(spotlight(2 * 3600 + 14 * 60 + 7), "2 hr 14 min")
        XCTAssertEqual(spotlight(23 * 3600 + 59 * 60 + 59), "23 hr 59 min")
        XCTAssertEqual(spotlight(3600), "1 hr")
        XCTAssertEqual(spotlight(1 * 3600 + 12 * 60), "1 hr 12 min")
    }

    func testMinutesOnlyInsideTheLastHour() {
        XCTAssertEqual(spotlight(14 * 60 + 7), "14 min")
        XCTAssertEqual(spotlight(59), "<1 min")
        XCTAssertEqual(spotlight(1), "<1 min")
    }

    func testDaysBeyondADay() {
        XCTAssertEqual(spotlight(86_400), "1 day")
        XCTAssertEqual(spotlight(2 * 86_400 + 3 * 3600 + 59 * 60), "2 days 3 hr")
    }

    func testTruncatesRatherThanRoundsUp() {
        XCTAssertEqual(formatter.spotlightString(target: now.addingTimeInterval(119.9), now: now), "1 min")
    }

    func testAtOrPastTheInstantSaysNow() {
        XCTAssertEqual(spotlight(0), "Now")
        XCTAssertEqual(spotlight(-5), "Now")
    }

    func testAllDayIsNamedByDay() {
        XCTAssertEqual(formatter.allDaySpotlightString(dayStart: Fixture.date(2026, 9, 2), now: now), "Today")
        XCTAssertEqual(formatter.allDaySpotlightString(dayStart: Fixture.date(2026, 9, 3), now: now), "Tomorrow")
        XCTAssertEqual(formatter.allDaySpotlightString(dayStart: Fixture.date(2026, 9, 5), now: now), "In 3 days")
    }
}

final class WhenTextTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private lazy var formatter = DeadlineFormatter(calendar: calendar, locale: Fixture.locale)
    private let entry = Fixture.calendarEntry()
    private let now = Fixture.date(2026, 9, 2, 14, 0)   // Wednesday

    private func timed(_ date: Date) -> Deadline {
        Fixture.builder().build(event: Fixture.timedEvent(start: date), calendarEntry: entry)!
    }

    func testRelativeDayLabels() {
        XCTAssertEqual(formatter.relativeDayLabel(Fixture.date(2026, 9, 2), now: now), "Today")
        XCTAssertEqual(formatter.relativeDayLabel(Fixture.date(2026, 9, 3), now: now), "Tomorrow")
        XCTAssertEqual(formatter.relativeDayLabel(Fixture.date(2026, 9, 1), now: now), "Yesterday")
        XCTAssertEqual(formatter.relativeDayLabel(Fixture.date(2026, 9, 4), now: now), "Friday")
        XCTAssertEqual(formatter.relativeDayLabel(Fixture.date(2026, 9, 8), now: now), "Tuesday")
        XCTAssertEqual(formatter.relativeDayLabel(Fixture.date(2026, 9, 9), now: now), "Sep 9", "a week out the weekday alone would be ambiguous")
    }

    func testTimedDeadlines() {
        XCTAssertEqual(Fixture.plain(formatter.whenText(for: timed(Fixture.date(2026, 9, 2, 16, 21)), now: now)), "Today at 4:21 PM")
        XCTAssertEqual(Fixture.plain(formatter.whenText(for: timed(Fixture.date(2026, 9, 3, 23, 59)), now: now)), "Tomorrow at 11:59 PM")
        XCTAssertEqual(Fixture.plain(formatter.whenText(for: timed(Fixture.date(2026, 9, 4, 9, 0)), now: now)), "Friday at 9:00 AM")
    }

    func testAllDayDeadlines() {
        let single = Fixture.builder().build(
            event: Fixture.allDayEvent(startDay: "2026-09-03", endDayExclusive: "2026-09-04"),
            calendarEntry: entry
        )!
        XCTAssertEqual(formatter.whenText(for: single, now: now), "All day · Tomorrow")

        let multi = Fixture.builder().build(
            event: Fixture.allDayEvent(startDay: "2026-09-03", endDayExclusive: "2026-09-06"),
            calendarEntry: entry
        )!
        XCTAssertEqual(formatter.whenText(for: multi, now: now), "All day · Tomorrow through Sep 5")
    }

    func testSectionHeaderPieces() {
        XCTAssertEqual(formatter.weekday(Fixture.date(2026, 9, 4)), "Friday")
        XCTAssertEqual(formatter.shortDate(Fixture.date(2026, 9, 4)), "Sep 4")
    }

    func testFooterCounts() {
        XCTAssertEqual(formatter.countText(1, showingAllEvents: false), "1 deadline")
        XCTAssertEqual(formatter.countText(9, showingAllEvents: false), "9 deadlines")
        XCTAssertEqual(formatter.countText(2, showingAllEvents: true), "2 events")
    }
}

final class TickSchedulingTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let entry = Fixture.calendarEntry()

    private func timed(_ id: String, at date: Date) -> Deadline {
        Fixture.builder().build(event: Fixture.timedEvent(id: id, start: date), calendarEntry: entry)!
    }

    func testTicksLandJustAfterTheNextMinute() {
        let now = Fixture.date(2026, 9, 2, 14, 0, 20)
        let next = DeadlineListViewModel.nextTick(after: now, calendar: calendar, deadlines: [])
        XCTAssertEqual(next.timeIntervalSince(Fixture.date(2026, 9, 2, 14, 1, 0)), 0.05, accuracy: 0.001)
    }

    func testADeadlinePassingBeforeTheMinuteBringsTheTickForward() {
        let now = Fixture.date(2026, 9, 2, 14, 0, 20)
        let due = timed("d", at: Fixture.date(2026, 9, 2, 14, 0, 45))
        let next = DeadlineListViewModel.nextTick(after: now, calendar: calendar, deadlines: [due])
        XCTAssertEqual(next.timeIntervalSince(due.overdueInstant), 0.05, accuracy: 0.001)
    }

    func testCrossingIntoTheImminentWindowBringsTheTickForward() {
        let now = Fixture.date(2026, 9, 2, 14, 0, 20)
        // Due in six hours and ten seconds: it becomes imminent in ten seconds.
        let due = timed("d", at: now.addingTimeInterval(Urgency.imminentWindow + 10))
        let next = DeadlineListViewModel.nextTick(after: now, calendar: calendar, deadlines: [due])
        XCTAssertEqual(next.timeIntervalSince(now), 10.05, accuracy: 0.001)
    }

    func testTransitionsInThePastAreIgnored() {
        let now = Fixture.date(2026, 9, 2, 14, 0, 20)
        let late = timed("late", at: Fixture.date(2026, 9, 2, 9))
        let next = DeadlineListViewModel.nextTick(after: now, calendar: calendar, deadlines: [late])
        XCTAssertEqual(next.timeIntervalSince(Fixture.date(2026, 9, 2, 14, 1, 0)), 0.05, accuracy: 0.001)
    }
}
