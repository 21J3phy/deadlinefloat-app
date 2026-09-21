import XCTest
@testable import DeadlineFloat

final class RulerSpanTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let entry = Fixture.calendarEntry()

    func testTheRulerRunsMidnightToMidnight() {
        let ruler = RulerSpan(day: Fixture.date(2026, 9, 2, 15), calendar: calendar)
        XCTAssertEqual(ruler.start, Fixture.date(2026, 9, 2))
        XCTAssertEqual(ruler.end, Fixture.date(2026, 9, 3))
        XCTAssertEqual(ruler.hours, 24, accuracy: 0.0001)
        XCTAssertEqual(ruler.hourMarks(calendar: calendar).count, 24)
    }

    func testDaylightSavingChangesTheLength() {
        XCTAssertEqual(RulerSpan(day: Fixture.date(2026, 3, 8), calendar: calendar).hours, 23, accuracy: 0.0001, "spring forward at 2 AM")
        XCTAssertEqual(RulerSpan(day: Fixture.date(2026, 3, 7), calendar: calendar).hours, 24, accuracy: 0.0001)
        XCTAssertEqual(RulerSpan(day: Fixture.date(2026, 11, 1), calendar: calendar).hours, 25, accuracy: 0.0001, "fall back at 2 AM")
        XCTAssertEqual(RulerSpan(day: Fixture.date(2026, 3, 8), calendar: calendar).hourMarks(calendar: calendar).count, 23)
    }

    func testTheCurrentRulerIsTodays() {
        XCTAssertEqual(RulerSpan.current(now: Fixture.date(2026, 9, 2, 14), calendar: calendar).day, Fixture.date(2026, 9, 2))
        XCTAssertEqual(RulerSpan.current(now: Fixture.date(2026, 9, 3, 0, 30), calendar: calendar).day, Fixture.date(2026, 9, 3), "the small hours belong to the new day")
        XCTAssertEqual(RulerSpan.current(now: Fixture.date(2026, 9, 3, 23, 59), calendar: calendar).day, Fixture.date(2026, 9, 3))
    }

    func testFractionsRunTopToBottomAndClamp() {
        let ruler = RulerSpan(day: Fixture.date(2026, 9, 2), calendar: calendar)
        XCTAssertEqual(ruler.fraction(of: Fixture.date(2026, 9, 2, 0)), 0, accuracy: 0.0001)
        XCTAssertEqual(ruler.fraction(of: Fixture.date(2026, 9, 2, 12)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ruler.fraction(of: Fixture.date(2026, 9, 2, 23, 59)), 23.9833 / 24, accuracy: 0.001)
        XCTAssertEqual(ruler.fraction(of: Fixture.date(2026, 9, 1, 22)), 0, "the day before pins to the top")
        XCTAssertEqual(ruler.fraction(of: Fixture.date(2026, 9, 3, 2)), 1, "the day after pins to the bottom")
    }

    func testCoversTimedInstantsInTheDayAndAllDayItemsOnIt() {
        let ruler = RulerSpan(day: Fixture.date(2026, 9, 2), calendar: calendar)
        let builder = Fixture.builder()
        let afternoon = builder.build(event: Fixture.timedEvent(id: "a", start: Fixture.date(2026, 9, 2, 16)), calendarEntry: entry)!
        let smallHours = builder.build(event: Fixture.timedEvent(id: "s", start: Fixture.date(2026, 9, 3, 0, 30)), calendarEntry: entry)!
        let dawn = builder.build(event: Fixture.timedEvent(id: "d", start: Fixture.date(2026, 9, 2, 6)), calendarEntry: entry)!
        let lastMinute = builder.build(event: Fixture.timedEvent(id: "l", start: Fixture.date(2026, 9, 2, 23, 59)), calendarEntry: entry)!
        let allDay = builder.build(event: Fixture.allDayEvent(id: "x", startDay: "2026-09-02", endDayExclusive: "2026-09-03"), calendarEntry: entry)!
        let tomorrowAllDay = builder.build(event: Fixture.allDayEvent(id: "y", startDay: "2026-09-03", endDayExclusive: "2026-09-04"), calendarEntry: entry)!

        XCTAssertTrue(ruler.covers(afternoon))
        XCTAssertFalse(ruler.covers(smallHours), "half past midnight is the next day's")
        XCTAssertTrue(ruler.covers(dawn))
        XCTAssertTrue(ruler.covers(lastMinute))
        XCTAssertTrue(ruler.covers(allDay))
        XCTAssertFalse(ruler.covers(tomorrowAllDay))
    }

    func testShortEventsGetAMinimumSpan() {
        let ruler = RulerSpan(day: Fixture.date(2026, 9, 2), calendar: calendar)
        let quarter = Fixture.builder().build(
            event: Fixture.timedEvent(start: Fixture.date(2026, 9, 2, 12), durationMinutes: 15),
            calendarEntry: entry
        )!
        let span = ruler.span(of: quarter, minimumFraction: 0.05)!
        XCTAssertEqual(span.start, 0.5, accuracy: 0.0001)
        XCTAssertEqual(span.end, 0.55, accuracy: 0.0001)
    }
}

final class RulerFormattingTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private lazy var formatter = DeadlineFormatter(calendar: calendar, locale: Fixture.locale)

    func testHourLabels() {
        XCTAssertEqual(Fixture.plain(formatter.hourLabel(Fixture.date(2026, 9, 2, 9))), "9 AM")
        XCTAssertEqual(Fixture.plain(formatter.hourLabel(Fixture.date(2026, 9, 2, 12))), "12 PM")
        XCTAssertEqual(Fixture.plain(formatter.hourLabel(Fixture.date(2026, 9, 3, 0))), "12 AM")
    }
}
