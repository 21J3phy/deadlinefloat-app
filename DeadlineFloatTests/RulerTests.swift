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

/// Shortening the day changes what is drawn, never what is counted.
final class DaySpanTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let entry = Fixture.calendarEntry()
    private let waking = DaySpan(startHour: 7, endHour: 1)
    private let working = DaySpan(startHour: 9, endHour: 18)

    private func deadline(_ instant: Date, minutes: Int = 30) -> Deadline {
        Fixture.builder().build(
            event: Fixture.timedEvent(start: instant, durationMinutes: minutes),
            calendarEntry: entry
        )!
    }

    // MARK: - The value

    func testTheWholeDayIsMidnightToMidnight() {
        XCTAssertEqual(DaySpan.wholeDay.hours, 24)
        XCTAssertTrue(DaySpan.wholeDay.wraps, "its end is the next midnight")
        XCTAssertTrue(DaySpan.wholeDay.isWholeDay)
    }

    func testASpanKnowsWhetherItRunsPastMidnight() {
        XCTAssertTrue(waking.wraps)
        XCTAssertEqual(waking.hours, 18)
        XCTAssertFalse(working.wraps)
        XCTAssertEqual(working.hours, 9)
    }

    func testADayIsNeverShorterThanSixHours() {
        XCTAssertEqual(DaySpan(startHour: 9, endHour: 11).hours, DaySpan.minimumHours, "the end is pushed out, not the choice refused")
        XCTAssertEqual(DaySpan(startHour: 9, endHour: 11).endHour, 15)
        XCTAssertEqual(DaySpan(startHour: 22, endHour: 1).endHour, 4, "and it may push past midnight to get there")
    }

    func testOutOfRangeHoursAreBroughtBackOntoTheClock() {
        XCTAssertEqual(DaySpan(startHour: 25, endHour: -3).startHour, 1)
        XCTAssertEqual(DaySpan(startHour: 7, endHour: 99).endHour, 3, "99 o'clock is 3 AM")
        XCTAssertEqual(DaySpan(startHour: 7, endHour: 99).hours, 20)
    }

    // MARK: - The ruler it makes

    func testAWakingDayStartsAndEndsWhereItSays() {
        let ruler = RulerSpan(day: Fixture.date(2026, 9, 2), calendar: calendar, span: waking)
        XCTAssertEqual(ruler.start, Fixture.date(2026, 9, 2, 7))
        XCTAssertEqual(ruler.end, Fixture.date(2026, 9, 3, 1))
        XCTAssertEqual(ruler.hours, 18, accuracy: 0.0001)
        XCTAssertEqual(ruler.hourMarks(calendar: calendar).count, 18)
    }

    func testADayInsideOneDateDoesNotRunIntoTomorrow() {
        let ruler = RulerSpan(day: Fixture.date(2026, 9, 2), calendar: calendar, span: working)
        XCTAssertEqual(ruler.start, Fixture.date(2026, 9, 2, 9))
        XCTAssertEqual(ruler.end, Fixture.date(2026, 9, 2, 18))
        XCTAssertEqual(ruler.hours, 9, accuracy: 0.0001)
    }

    func testTheSmallHoursBelongToTheDayBeforeOnlyWhileItIsStillGoing() {
        func day(at now: Date) -> Date {
            RulerSpan.current(now: now, calendar: calendar, span: waking).day
        }
        XCTAssertEqual(day(at: Fixture.date(2026, 9, 3, 0, 30)), Fixture.date(2026, 9, 2), "half past midnight is still Wednesday night")
        XCTAssertEqual(day(at: Fixture.date(2026, 9, 3, 3)), Fixture.date(2026, 9, 3), "three in the morning is its own day again")
        XCTAssertEqual(day(at: Fixture.date(2026, 9, 3, 14)), Fixture.date(2026, 9, 3))
    }

    func testADayThatDoesNotWrapIsAlwaysTodays() {
        XCTAssertEqual(
            RulerSpan.current(now: Fixture.date(2026, 9, 3, 2), calendar: calendar, span: working).day,
            Fixture.date(2026, 9, 3)
        )
    }

    // MARK: - Nothing is hidden

    func testAnEventOutsideTheHoursShownIsStillOnItsDay() {
        let ruler = RulerSpan(day: Fixture.date(2026, 9, 2), calendar: calendar, span: waking)
        let earlyRun = deadline(Fixture.date(2026, 9, 2, 5))

        XCTAssertFalse(ruler.contains(Fixture.date(2026, 9, 2, 5)), "5 AM is off the ruler")
        XCTAssertTrue(ruler.covers(earlyRun), "but it is still drawn on that day")
        XCTAssertEqual(ruler.fraction(of: Fixture.date(2026, 9, 2, 5)), 0, "pinned to the top")
        XCTAssertNotNil(ruler.span(of: earlyRun, minimumFraction: 0.01), "and it still gets a block")
    }

    func testAnEventAfterTheHoursShownPinsToTheBottom() {
        let ruler = RulerSpan(day: Fixture.date(2026, 9, 2), calendar: calendar, span: working)
        let evening = deadline(Fixture.date(2026, 9, 2, 22))
        XCTAssertTrue(ruler.covers(evening))
        XCTAssertEqual(ruler.fraction(of: Fixture.date(2026, 9, 2, 22)), 1, "pinned to the bottom")
    }

    func testEveryInstantBelongsToExactlyOneDay() {
        let days = (1...4).map { Fixture.date(2026, 9, $0) }
        for span in [DaySpan.wholeDay, waking, working, DaySpan(startHour: 22, endHour: 6)] {
            let rulers = days.map { RulerSpan(day: $0, calendar: calendar, span: span) }
            // Every half hour of the second and third days.
            for step in 0..<96 {
                let instant = Fixture.date(2026, 9, 2).addingTimeInterval(Double(step) * 1_800)
                let owners = rulers.filter { $0.claims(instant) }
                XCTAssertEqual(
                    owners.count, 1,
                    "\(instant) is claimed by \(owners.count) days with \(span.startHour)–\(span.endHour)"
                )
            }
        }
    }

    func testAllDayItemsIgnoreTheHoursShown() {
        let ruler = RulerSpan(day: Fixture.date(2026, 9, 2), calendar: calendar, span: working)
        let allDay = Fixture.builder().build(
            event: Fixture.allDayEvent(startDay: "2026-09-02", endDayExclusive: "2026-09-03"),
            calendarEntry: entry
        )!
        XCTAssertTrue(ruler.covers(allDay))
    }

    // MARK: - Labels

    func testTheLabelReadsLikeSomebodyWroteIt() {
        let formatter = DeadlineFormatter(calendar: calendar, locale: Fixture.locale)
        XCTAssertEqual(formatter.spanLabel(.wholeDay), "The whole day")
        XCTAssertEqual(Fixture.plain(formatter.spanLabel(waking)), "7 AM to 1 AM")
        XCTAssertEqual(Fixture.plain(formatter.spanLabel(DaySpan(startHour: 8, endHour: 0))), "8 AM to midnight")
        XCTAssertEqual(Fixture.plain(formatter.spanLabel(DaySpan(startHour: 6, endHour: 12))), "6 AM to noon")
        XCTAssertEqual(formatter.hourLabel(hour: 0), "Midnight")
        XCTAssertEqual(formatter.hourLabel(hour: 12), "Noon")
        XCTAssertEqual(Fixture.plain(formatter.hourLabel(hour: 18)), "6 PM")
    }
}
