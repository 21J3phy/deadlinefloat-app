import XCTest
@testable import DeadlineFloat

final class GroupingSortingTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private lazy var formatter = DeadlineFormatter(calendar: calendar, locale: Fixture.locale)
    private lazy var grouper = DeadlineGrouper(calendar: calendar, formatter: formatter)
    private let entry = Fixture.calendarEntry()

    private func deadline(
        _ id: String,
        _ title: String,
        at date: Date,
        allDayEnd: Date? = nil
    ) -> Deadline {
        let builder = Fixture.builder()
        if let allDayEnd {
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            let e = calendar.dateComponents([.year, .month, .day], from: allDayEnd)
            let event = Fixture.allDayEvent(
                id: id,
                title: title,
                startDay: Fixture.dayString(c.year!, c.month!, c.day!),
                endDayExclusive: Fixture.dayString(e.year!, e.month!, e.day!)
            )
            return builder.build(event: event, calendarEntry: entry)!
        }
        return builder.build(event: Fixture.timedEvent(id: id, title: title, start: date), calendarEntry: entry)!
    }

    // MARK: - Section order and titles

    func testSectionsAreOverdueTodayTomorrowThenNamedDays() {
        let now = Fixture.date(2026, 9, 2, 14, 0)      // Wednesday
        let window = DateWindow(now: now, days: 3, calendar: calendar)

        let deadlines = [
            deadline("d4", "DUE Friday item", at: Fixture.date(2026, 9, 4, 9)),
            deadline("d1", "DUE overdue item", at: Fixture.date(2026, 9, 2, 9)),
            deadline("d3", "DUE tomorrow item", at: Fixture.date(2026, 9, 3, 9)),
            deadline("d2", "DUE later today", at: Fixture.date(2026, 9, 2, 18))
        ]

        let sections = grouper.sections(from: deadlines, now: now, window: window)
        XCTAssertEqual(sections.map(\.title), ["Overdue", "Due today", "Due tomorrow", "Friday, September 4"])
        XCTAssertEqual(sections.map(\.kind), [.overdue, .today, .tomorrow, .day(Fixture.date(2026, 9, 4))])
    }

    func testEmptySectionsAreOmitted() {
        let now = Fixture.date(2026, 9, 2, 14, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        let sections = grouper.sections(
            from: [deadline("d", "DUE tomorrow", at: Fixture.date(2026, 9, 3, 9))],
            now: now,
            window: window
        )
        XCTAssertEqual(sections.map(\.title), ["Due tomorrow"])
    }

    func testFullWeekdayAndDateFormatting() {
        XCTAssertEqual(formatter.dayHeadline(Fixture.date(2026, 9, 4)), "Friday, September 4")
        XCTAssertEqual(formatter.dayHeadline(Fixture.date(2026, 12, 25)), "Friday, December 25")
    }

    // MARK: - Ordering

    func testOverdueItemsComeFirstAndAreChronological() {
        let now = Fixture.date(2026, 9, 2, 14, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        let deadlines = [
            deadline("late2", "DUE late two", at: Fixture.date(2026, 9, 2, 11)),
            deadline("late1", "DUE late one", at: Fixture.date(2026, 9, 2, 8)),
            deadline("soon", "DUE soon", at: Fixture.date(2026, 9, 2, 20))
        ]
        let sections = grouper.sections(from: deadlines, now: now, window: window)

        XCTAssertEqual(sections[0].kind, .overdue)
        XCTAssertEqual(sections[0].deadlines.map(\.id), ["primary@example.com|late1", "primary@example.com|late2"])
        XCTAssertEqual(sections[1].deadlines.map(\.id), ["primary@example.com|soon"])
    }

    func testAllDayItemsSortAboveTimedItemsOnTheSameDay() {
        let now = Fixture.date(2026, 9, 2, 6, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        let deadlines = [
            deadline("timed", "DUE at eight", at: Fixture.date(2026, 9, 3, 8)),
            deadline("allday", "DUE all day", at: Fixture.date(2026, 9, 3), allDayEnd: Fixture.date(2026, 9, 4))
        ]
        let sections = grouper.sections(from: deadlines, now: now, window: window)
        XCTAssertEqual(sections[0].deadlines.map(\.eventID), ["allday", "timed"])
    }

    func testTiesBreakOnTitleThenIdentifierSoOrderIsStable() {
        let now = Fixture.date(2026, 9, 2, 6, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        let instant = Fixture.date(2026, 9, 2, 17)
        let deadlines = [
            deadline("z", "DUE zebra", at: instant),
            deadline("a", "DUE apple", at: instant),
            deadline("m", "DUE mango", at: instant)
        ]
        let first = grouper.sections(from: deadlines, now: now, window: window)[0].deadlines.map(\.eventID)
        let second = grouper.sections(from: deadlines.reversed(), now: now, window: window)[0].deadlines.map(\.eventID)
        XCTAssertEqual(first, ["a", "m", "z"])
        XCTAssertEqual(first, second, "sorting must not depend on input order")
    }

    // MARK: - Window clamping

    func testDeadlinesOutsideTheWindowAreDropped() {
        let now = Fixture.date(2026, 9, 2, 14, 0)
        let window = DateWindow(now: now, days: 2, calendar: calendar)   // through Sep 3
        let deadlines = [
            deadline("in", "DUE inside", at: Fixture.date(2026, 9, 3, 9)),
            deadline("out", "DUE outside", at: Fixture.date(2026, 9, 4, 9)),
            deadline("past", "DUE yesterday", at: Fixture.date(2026, 9, 1, 9))
        ]
        let ids = grouper.sections(from: deadlines, now: now, window: window).flatMap { $0.deadlines.map(\.eventID) }
        XCTAssertEqual(ids, ["in"])
    }

    func testLookbackKeepsYesterdaysOverdueItems() {
        let now = Fixture.date(2026, 9, 2, 14, 0)
        let window = DateWindow(now: now, days: 2, calendar: calendar, overdueLookbackDays: 1)
        let deadlines = [deadline("past", "DUE yesterday", at: Fixture.date(2026, 9, 1, 9))]
        let sections = grouper.sections(from: deadlines, now: now, window: window)
        XCTAssertEqual(sections.map(\.title), ["Overdue"])
        XCTAssertEqual(sections[0].deadlines.map(\.eventID), ["past"])
    }

    func testOngoingMultiDayAllDayItemIsFiledUnderToday() {
        let now = Fixture.date(2026, 9, 2, 14, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        // Started 31 August, runs through 3 September.
        let ongoing = deadline("span", "DUE conference week", at: Fixture.date(2026, 8, 31), allDayEnd: Fixture.date(2026, 9, 4))

        let sections = grouper.sections(from: [ongoing], now: now, window: window)
        XCTAssertEqual(sections.map(\.title), ["Due today"])
        XCTAssertEqual(sections[0].deadlines[0].dayStart, Fixture.date(2026, 9, 2))
    }

    func testMidnightDeadlineTodayIsKept() {
        let now = Fixture.date(2026, 9, 2, 14, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        let midnight = deadline("mid", "DUE midnight", at: Fixture.date(2026, 9, 2, 0, 0))
        let sections = grouper.sections(from: [midnight], now: now, window: window)
        XCTAssertEqual(sections.map(\.title), ["Overdue"], "midnight this morning has already passed")
        XCTAssertEqual(sections[0].deadlines.count, 1)
    }

    func testMidnightStartingTomorrowIsFiledUnderTomorrow() {
        let now = Fixture.date(2026, 9, 2, 22, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        let midnight = deadline("mid", "DUE midnight", at: Fixture.date(2026, 9, 3, 0, 0))
        let sections = grouper.sections(from: [midnight], now: now, window: window)
        XCTAssertEqual(sections.map(\.title), ["Due tomorrow"])
    }

    // MARK: - DST behaviour

    func testDeadlinesAcrossSpringForwardKeepTheirLocalWallClockDay() {
        let now = Fixture.date(2026, 3, 7, 12, 0)          // Saturday before the change
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        let deadlines = [
            deadline("before", "DUE before change", at: Fixture.date(2026, 3, 8, 1, 30)),
            deadline("after", "DUE after change", at: Fixture.date(2026, 3, 8, 4, 30)),
            deadline("monday", "DUE monday", at: Fixture.date(2026, 3, 9, 9, 0))
        ]
        let sections = grouper.sections(from: deadlines, now: now, window: window)
        XCTAssertEqual(sections.map(\.title), ["Due tomorrow", "Monday, March 9"])
        XCTAssertEqual(sections[0].deadlines.map(\.eventID), ["before", "after"])
    }

    func testDeadlinesAcrossFallBackStayOnTheirOwnDays() {
        let now = Fixture.date(2026, 10, 31, 12, 0)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        let deadlines = [
            deadline("sun", "DUE sunday", at: Fixture.date(2026, 11, 1, 13, 0)),
            deadline("mon", "DUE monday", at: Fixture.date(2026, 11, 2, 9, 0))
        ]
        let sections = grouper.sections(from: deadlines, now: now, window: window)
        XCTAssertEqual(sections.map(\.title), ["Due tomorrow", "Monday, November 2"])
    }

    // MARK: - Empty state text

    func testEmptyStateWording() {
        XCTAssertEqual(formatter.emptyStateText(range: .threeDays, showingAllEvents: false), "No deadlines in the next 3 days")
        XCTAssertEqual(formatter.emptyStateText(range: .twoDays, showingAllEvents: false), "No deadlines in the next 2 days")
        XCTAssertEqual(formatter.emptyStateText(range: .oneDay, showingAllEvents: false), "No deadlines today")
        XCTAssertEqual(formatter.emptyStateText(range: .week, showingAllEvents: true), "No events this week")
    }

    func testLastRefreshWording() {
        let now = Fixture.date(2026, 9, 2, 14, 30)
        XCTAssertEqual(formatter.lastRefreshText(nil, now: now), "Never updated")
        XCTAssertEqual(Fixture.plain(formatter.lastRefreshText(Fixture.date(2026, 9, 2, 14, 14), now: now)), "Updated 2:14 PM")
        XCTAssertEqual(Fixture.plain(formatter.lastRefreshText(Fixture.date(2026, 9, 1, 9, 5), now: now)), "Updated Sep 1 9:05 AM")
    }
}
