import XCTest
@testable import DeadlineFloat

/// The window is "today plus N calendar days" in the Mac's local time zone.
/// These tests pin that definition, including across both daylight-saving
/// transitions in `America/Indiana/Indianapolis`.
final class DateWindowTests: XCTestCase {
    private let calendar = Fixture.calendar()

    func testDefaultRangeIsOneDay() {
        XCTAssertEqual(RangeOption.default, .oneDay)
        XCTAssertEqual(RangeOption.default.days, 1)
        XCTAssertEqual(RangeOption(days: 99), .oneDay, "unknown values fall back to the default")
        XCTAssertEqual(RangeOption.week.days, 7)
        XCTAssertEqual(RangeOption.week.shortLabel, "Week")
    }

    func testWindowStartsAtLocalMidnightToday() {
        let now = Fixture.date(2026, 9, 2, 14, 37, 12)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        XCTAssertEqual(window.start, Fixture.date(2026, 9, 2, 0, 0, 0))
    }

    func testTwoThreeAndFourDayEnds() {
        let now = Fixture.date(2026, 9, 2, 9, 0, 0)
        XCTAssertEqual(DateWindow(now: now, days: 2, calendar: calendar).end, Fixture.date(2026, 9, 4))
        XCTAssertEqual(DateWindow(now: now, days: 3, calendar: calendar).end, Fixture.date(2026, 9, 5))
        XCTAssertEqual(DateWindow(now: now, days: 4, calendar: calendar).end, Fixture.date(2026, 9, 6))
    }

    func testWindowIsExclusiveAtTheEnd() {
        let now = Fixture.date(2026, 9, 2, 9, 0, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        XCTAssertTrue(window.contains(Fixture.date(2026, 9, 4, 23, 59, 59)))
        XCTAssertFalse(window.contains(window.end), "midnight that begins day N+1 is outside the window")
    }

    func testEventExactlyAtMidnightTodayIsInsideTheWindow() {
        let now = Fixture.date(2026, 9, 2, 9, 0, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        XCTAssertTrue(window.contains(Fixture.date(2026, 9, 2, 0, 0, 0)))
    }

    func testNoonAndMidnightBothLandInsideTheSameWindow() {
        let now = Fixture.date(2026, 9, 2, 1, 0, 0)
        let window = DateWindow(now: now, days: 2, calendar: calendar)
        XCTAssertTrue(window.contains(Fixture.date(2026, 9, 2, 12, 0, 0)))
        XCTAssertTrue(window.contains(Fixture.date(2026, 9, 3, 0, 0, 0)))
        XCTAssertTrue(window.contains(Fixture.date(2026, 9, 3, 12, 0, 0)))
        XCTAssertFalse(window.contains(Fixture.date(2026, 9, 4, 0, 0, 0)))
    }

    // MARK: - Daylight saving

    func testSpringForwardDayIsTwentyThreeHoursLong() {
        // Clocks jump 02:00 → 03:00 on 8 March 2026.
        let now = Fixture.date(2026, 3, 8, 10, 0, 0)
        let window = DateWindow(now: now, days: 1, calendar: calendar)
        XCTAssertEqual(window.start, Fixture.date(2026, 3, 8, 0, 0, 0))
        XCTAssertEqual(window.end, Fixture.date(2026, 3, 9, 0, 0, 0))
        XCTAssertEqual(window.end.timeIntervalSince(window.start), 23 * 3600)
    }

    func testFallBackDayIsTwentyFiveHoursLong() {
        // Clocks fall back 02:00 → 01:00 on 1 November 2026.
        let now = Fixture.date(2026, 11, 1, 10, 0, 0)
        let window = DateWindow(now: now, days: 1, calendar: calendar)
        XCTAssertEqual(window.end.timeIntervalSince(window.start), 25 * 3600)
    }

    func testThreeDayWindowSpanningSpringForwardIsNotSeventyTwoHours() {
        let now = Fixture.date(2026, 3, 7, 12, 0, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        XCTAssertEqual(window.end, Fixture.date(2026, 3, 10, 0, 0, 0))
        XCTAssertEqual(
            window.end.timeIntervalSince(window.start),
            71 * 3600,
            "an hour disappears inside the range, so naive 24×3 arithmetic would be wrong"
        )
    }

    func testThreeDayWindowSpanningFallBackGainsAnHour() {
        let now = Fixture.date(2026, 10, 31, 12, 0, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        XCTAssertEqual(window.end, Fixture.date(2026, 11, 3, 0, 0, 0))
        XCTAssertEqual(window.end.timeIntervalSince(window.start), 73 * 3600)
    }

    func testWindowUsesTheSuppliedTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let now = Fixture.date(2026, 9, 2, 14, 0, 0)
        let indyWindow = DateWindow(now: now, days: 3, calendar: calendar)
        let tokyoWindow = DateWindow(now: now, days: 3, calendar: Fixture.calendar(tokyo))
        XCTAssertNotEqual(indyWindow.start, tokyoWindow.start)
        XCTAssertEqual(tokyoWindow.timeZone, tokyo)
    }

    // MARK: - Look-back

    func testLookbackIsOffByDefault() {
        let now = Fixture.date(2026, 9, 2, 14, 0, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        XCTAssertEqual(window.lookbackStart, window.start)
        XCTAssertFalse(window.contains(Fixture.date(2026, 9, 1, 23, 0, 0)))
    }

    func testLookbackExtendsBackwardsOnly() {
        let now = Fixture.date(2026, 9, 2, 14, 0, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar, overdueLookbackDays: 2)
        XCTAssertEqual(window.lookbackStart, Fixture.date(2026, 8, 31))
        XCTAssertEqual(window.end, Fixture.date(2026, 9, 5), "look-back must not move the end of the window")
        XCTAssertTrue(window.contains(Fixture.date(2026, 9, 1, 23, 0, 0)))
    }

    func testOverlapsHandlesMultiDaySpans() {
        let now = Fixture.date(2026, 9, 2, 14, 0, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        // Started two days ago, still running today.
        XCTAssertTrue(window.overlaps(from: Fixture.date(2026, 8, 31), to: Fixture.date(2026, 9, 3)))
        // Finished before the window opened.
        XCTAssertFalse(window.overlaps(from: Fixture.date(2026, 8, 30), to: Fixture.date(2026, 9, 2)))
        // Starts after the window closes.
        XCTAssertFalse(window.overlaps(from: Fixture.date(2026, 9, 5), to: Fixture.date(2026, 9, 6)))
    }

    func testDaysIsClampedToAtLeastOne() {
        let now = Fixture.date(2026, 9, 2, 14, 0, 0)
        let window = DateWindow(now: now, days: 0, calendar: calendar)
        XCTAssertEqual(window.days, 1)
        XCTAssertEqual(window.end, Fixture.date(2026, 9, 3))
    }
}
