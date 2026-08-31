import XCTest
@testable import DeadlineFloat

final class DuplicateReducerTests: XCTestCase {
    private let personal = Fixture.calendarEntry(id: "me@example.com", name: "Personal", primary: true)
    private let shared = Fixture.calendarEntry(id: "team@example.com", name: "Team")

    private func deadline(on entry: GoogleCalendarListEntry, uid: String?, start: Date, id: String = "e1") -> Deadline {
        Fixture.builder().build(
            event: Fixture.timedEvent(id: id, title: "DUE: Grant report", start: start, iCalUID: uid),
            calendarEntry: entry
        )!
    }

    func testSameEventOnTwoCalendarsCollapsesToOneRow() {
        let start = Fixture.date(2026, 9, 3, 17)
        let reducer = DuplicateReducer(priorityOrder: [personal.id, shared.id])
        let merged = reducer.reduce([
            deadline(on: shared, uid: "grant@google.com", start: start),
            deadline(on: personal, uid: "grant@google.com", start: start)
        ])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].calendarName, "Personal", "the highest-priority calendar survives")
        XCTAssertEqual(merged[0].additionalCalendarNames, ["Team"])
    }

    func testMergeIsStableRegardlessOfInputOrder() {
        let start = Fixture.date(2026, 9, 3, 17)
        let reducer = DuplicateReducer(priorityOrder: [personal.id, shared.id])
        let a = reducer.reduce([deadline(on: shared, uid: "u", start: start), deadline(on: personal, uid: "u", start: start)])
        let b = reducer.reduce([deadline(on: personal, uid: "u", start: start), deadline(on: shared, uid: "u", start: start)])
        XCTAssertEqual(a.map(\.id), b.map(\.id))
    }

    func testDifferentStartsAreNotDuplicates() {
        let reducer = DuplicateReducer(priorityOrder: [personal.id, shared.id])
        let merged = reducer.reduce([
            deadline(on: personal, uid: "u", start: Fixture.date(2026, 9, 3, 17)),
            deadline(on: shared, uid: "u", start: Fixture.date(2026, 9, 4, 17))
        ])
        XCTAssertEqual(merged.count, 2)
    }

    func testDifferentUIDsAreKeptEvenWhenTheyLookIdentical() {
        let start = Fixture.date(2026, 9, 3, 17)
        let merged = DuplicateReducer().reduce([
            deadline(on: personal, uid: "one@google.com", start: start),
            deadline(on: shared, uid: "two@google.com", start: start)
        ])
        XCTAssertEqual(merged.count, 2, "look-alike events from different sources are still two real events")
        XCTAssertEqual(Set(merged.map(\.calendarName)), ["Personal", "Team"])
    }

    func testEventsWithoutUIDsArePassedThroughUntouched() {
        let start = Fixture.date(2026, 9, 3, 17)
        let merged = DuplicateReducer().reduce([
            deadline(on: personal, uid: nil, start: start),
            deadline(on: shared, uid: nil, start: start)
        ])
        XCTAssertEqual(merged.count, 2)
    }

    func testUnknownCalendarsSortAfterKnownOnes() {
        let start = Fixture.date(2026, 9, 3, 17)
        let stranger = Fixture.calendarEntry(id: "zzz@example.com", name: "Aardvark")
        let reducer = DuplicateReducer(priorityOrder: [personal.id])
        let merged = reducer.reduce([
            deadline(on: stranger, uid: "u", start: start),
            deadline(on: personal, uid: "u", start: start)
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].calendarName, "Personal")
    }
}

final class DeadlineAssemblerTests: XCTestCase {
    private let calendar = Fixture.calendar()

    private func snapshot() -> CalendarSnapshot {
        let personal = Fixture.calendarEntry(id: "me@example.com", name: "Personal", background: "#a47ae2", primary: true)
        let course = Fixture.calendarEntry(id: "cs@example.com", name: "CS 18000", background: "#5484ed")

        return Fixture.snapshot(
            calendars: [personal, course],
            events: [
                (personal, [
                    Fixture.timedEvent(id: "p1", title: "DUE: Passport form", start: Fixture.date(2026, 9, 2, 9), iCalUID: "shared@g"),
                    Fixture.timedEvent(id: "p2", title: "Lunch with Sam", start: Fixture.date(2026, 9, 2, 12)),
                    Fixture.timedEvent(id: "p3", title: "DONE: Renew books", start: Fixture.date(2026, 9, 2, 15))
                ]),
                (course, [
                    Fixture.timedEvent(id: "c1", title: "SUBMIT Project 3", start: Fixture.date(2026, 9, 2, 23, 59)),
                    Fixture.timedEvent(id: "c2", title: "DUE: Passport form", start: Fixture.date(2026, 9, 2, 9), iCalUID: "shared@g"),
                    Fixture.allDayEvent(id: "c3", title: "DUE Team charter", startDay: "2026-09-04", endDayExclusive: "2026-09-05")
                ])
            ]
        )
    }

    func testWholePipeline() {
        let now = Fixture.date(2026, 9, 2, 14, 0)
        let assembler = DeadlineAssembler(calendar: calendar, locale: Fixture.locale)
        let sections = assembler.sections(
            from: snapshot(),
            selectedCalendarIDs: nil,
            window: DateWindow(now: now, days: 3, calendar: calendar),
            now: now
        )

        XCTAssertEqual(sections.map(\.title), ["Overdue", "Today", "Friday, September 4"])
        XCTAssertEqual(sections[0].deadlines.map(\.title), ["DUE: Passport form"])
        XCTAssertEqual(sections[0].deadlines[0].additionalCalendarNames, ["CS 18000"], "the duplicate was merged")
        XCTAssertEqual(sections[1].deadlines.map(\.title), ["SUBMIT Project 3"])
        XCTAssertEqual(sections[2].deadlines.map(\.title), ["DUE Team charter"])
    }

    func testCalendarSelectionIsHonoured() {
        let now = Fixture.date(2026, 9, 2, 14, 0)
        let assembler = DeadlineAssembler(calendar: calendar, locale: Fixture.locale)
        let sections = assembler.sections(
            from: snapshot(),
            selectedCalendarIDs: ["cs@example.com"],
            window: DateWindow(now: now, days: 3, calendar: calendar),
            now: now
        )
        let names = Set(sections.flatMap { $0.deadlines.map(\.calendarName) })
        XCTAssertEqual(names, ["CS 18000"])
    }

    func testShowAllEventsRevealsNonDeadlinesButNotExclusions() {
        let now = Fixture.date(2026, 9, 2, 14, 0)
        var configuration = FilterConfiguration.default
        configuration.showAllEvents = true
        let assembler = DeadlineAssembler(calendar: calendar, locale: Fixture.locale, configuration: configuration)
        let titles = assembler.sections(
            from: snapshot(),
            selectedCalendarIDs: nil,
            window: DateWindow(now: now, days: 3, calendar: calendar),
            now: now
        ).flatMap { $0.deadlines.map(\.title) }

        XCTAssertTrue(titles.contains("Lunch with Sam"))
        XCTAssertFalse(titles.contains("DONE: Renew books"))
    }

    func testDisablingMergeKeepsBothCopies() {
        let now = Fixture.date(2026, 9, 2, 14, 0)
        let assembler = DeadlineAssembler(calendar: calendar, locale: Fixture.locale, mergeDuplicates: false)
        let sections = assembler.sections(
            from: snapshot(),
            selectedCalendarIDs: nil,
            window: DateWindow(now: now, days: 3, calendar: calendar),
            now: now
        )
        XCTAssertEqual(sections[0].deadlines.count, 2)
    }

    func testNarrowingTheRangeDropsLaterSections() {
        let now = Fixture.date(2026, 9, 2, 14, 0)
        let assembler = DeadlineAssembler(calendar: calendar, locale: Fixture.locale)
        let twoDays = assembler.sections(
            from: snapshot(),
            selectedCalendarIDs: nil,
            window: DateWindow(now: now, days: 2, calendar: calendar),
            now: now
        )
        XCTAssertEqual(twoDays.map(\.title), ["Overdue", "Today"])
    }

    func testEmptySnapshotProducesNoSections() {
        let now = Fixture.date(2026, 9, 2, 14, 0)
        let assembler = DeadlineAssembler(calendar: calendar, locale: Fixture.locale)
        XCTAssertTrue(assembler.sections(
            from: .empty,
            selectedCalendarIDs: nil,
            window: DateWindow(now: now, days: 3, calendar: calendar),
            now: now
        ).isEmpty)
    }
}
