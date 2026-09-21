import XCTest
@testable import DeadlineFloat

final class CountdownFormatterTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private lazy var formatter = CountdownFormatter(calendar: calendar)
    private let now = Fixture.date(2026, 9, 2, 12, 0, 0)

    private func countdown(offsetSeconds: TimeInterval) -> String {
        formatter.string(target: now.addingTimeInterval(offsetSeconds), now: now)
    }

    func testTheHeadlineFormat() {
        XCTAssertEqual(countdown(offsetSeconds: 2 * 3600 + 14 * 60), "2 hr 14 min left")
    }

    func testMinutesOnly() {
        XCTAssertEqual(countdown(offsetSeconds: 14 * 60), "14 min left")
        XCTAssertEqual(countdown(offsetSeconds: 60), "1 min left")
        XCTAssertEqual(countdown(offsetSeconds: 59 * 60), "59 min left")
    }

    func testHoursAndMinutes() {
        XCTAssertEqual(countdown(offsetSeconds: 3600), "1 hr left")
        XCTAssertEqual(countdown(offsetSeconds: 5 * 3600 + 40 * 60), "5 hr 40 min left")
        XCTAssertEqual(countdown(offsetSeconds: 23 * 3600 + 59 * 60), "23 hr 59 min left")
    }

    func testDaysAndHours() {
        XCTAssertEqual(countdown(offsetSeconds: 24 * 3600), "1 day left")
        XCTAssertEqual(countdown(offsetSeconds: 3 * 24 * 3600 + 4 * 3600), "3 days 4 hr left")
    }

    func testUnderAMinute() {
        XCTAssertEqual(countdown(offsetSeconds: 0), "<1 min left")
        XCTAssertEqual(countdown(offsetSeconds: 30), "<1 min left")
        XCTAssertEqual(countdown(offsetSeconds: 59), "<1 min left")
    }

    func testJustPassed() {
        XCTAssertEqual(countdown(offsetSeconds: -1), "just now")
        XCTAssertEqual(countdown(offsetSeconds: -59), "just now")
    }

    func testPastDurations() {
        XCTAssertEqual(countdown(offsetSeconds: -60), "1 min ago")
        XCTAssertEqual(countdown(offsetSeconds: -(2 * 3600 + 14 * 60)), "2 hr 14 min ago")
        XCTAssertEqual(countdown(offsetSeconds: -(26 * 3600)), "1 day 2 hr ago")
    }

    func testDurationsAreTruncatedNeverRoundedUp() {
        // 119.6 seconds left is one minute and change — saying "2 min left"
        // would promise time the user does not have.
        XCTAssertEqual(formatter.string(target: now.addingTimeInterval(119.6), now: now), "1 min left")
        XCTAssertEqual(formatter.string(target: now.addingTimeInterval(-119.6), now: now), "1 min ago")
        XCTAssertEqual(formatter.string(target: now.addingTimeInterval(59.9), now: now), "<1 min left")
    }

    // MARK: - All-day

    func testAllDayUsesWholeDays() {
        XCTAssertEqual(formatter.allDayString(dayStart: Fixture.date(2026, 9, 2), now: now), "Today")
        XCTAssertEqual(formatter.allDayString(dayStart: Fixture.date(2026, 9, 3), now: now), "in 1 day")
        XCTAssertEqual(formatter.allDayString(dayStart: Fixture.date(2026, 9, 5), now: now), "in 3 days")
        XCTAssertEqual(formatter.allDayString(dayStart: Fixture.date(2026, 9, 1), now: now), "1 day ago")
    }

    func testAllDayDeadlineNeverProducesAnHourCountdown() {
        let event = Fixture.allDayEvent(startDay: "2026-09-03", endDayExclusive: "2026-09-04")
        let deadline = Fixture.builder().build(event: event, calendarEntry: Fixture.calendarEntry())!
        XCTAssertEqual(formatter.string(for: deadline, now: now), "in 1 day")
    }

    func testAllDayAcrossSpringForwardCountsCalendarDaysNotHours() {
        // 7 March 12:00 → 8 March is one calendar day even though it is 23 hours.
        let now = Fixture.date(2026, 3, 7, 12, 0)
        XCTAssertEqual(formatter.allDayString(dayStart: Fixture.date(2026, 3, 8), now: now), "in 1 day")
        XCTAssertEqual(formatter.allDayString(dayStart: Fixture.date(2026, 3, 9), now: now), "in 2 days")
    }

    func testTimedDeadlineAcrossSpringForwardLosesAnHour() {
        // 01:00 on 8 March to 09:00 the same morning is only 7 hours: 02:00 never happens.
        let start = Fixture.date(2026, 3, 8, 1, 0)
        let target = Fixture.date(2026, 3, 8, 9, 0)
        XCTAssertEqual(formatter.string(target: target, now: start), "7 hr left")
    }

    func testTimedDeadlineAcrossFallBackGainsAnHour() {
        let start = Fixture.date(2026, 11, 1, 0, 30)
        let target = Fixture.date(2026, 11, 1, 3, 30)
        XCTAssertEqual(formatter.string(target: target, now: start), "4 hr left")
    }
}
