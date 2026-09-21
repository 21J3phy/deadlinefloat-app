import XCTest
@testable import DeadlineFloat

final class DrawerDetentsTests: XCTestCase {
    // A 120-point drawer above a 450-point viewport: the drawer fits, so it
    // rests at 0 and the default view rests at 120.
    private let detents = DrawerDetents(activeTop: 120, viewportHeight: 450)

    func testScrollingInsideTheListIsFree() {
        XCTAssertEqual(detents.restingOffset(for: 300, from: .active), 300)
        XCTAssertEqual(detents.restingOffset(for: 120, from: .active), 120)
    }

    func testAShortPullUpSnapsBackToTheDefaultView() {
        XCTAssertEqual(detents.restingOffset(for: 90, from: .active), 120)
        XCTAssertEqual(detents.side(at: 90, current: .active), .active)
    }

    func testPullingPastTheBarrierLandsOnTheDrawer() {
        XCTAssertEqual(detents.barrier(leaving: .active), 60, "half the drawer, since it is shorter than twice the depth")
        XCTAssertEqual(detents.restingOffset(for: 40, from: .active), 0)
        XCTAssertEqual(detents.side(at: 40, current: .active), .completed)
    }

    func testAShortPushDownFromTheDrawerSnapsBack() {
        XCTAssertEqual(detents.restingOffset(for: 50, from: .completed), 0)
        XCTAssertEqual(detents.side(at: 50, current: .completed), .completed)
    }

    func testPushingPastTheBarrierCatchesOnTheDefaultView() {
        XCTAssertEqual(detents.barrier(leaving: .completed), 72)
        XCTAssertEqual(detents.restingOffset(for: 100, from: .completed), 120)
        XCTAssertEqual(detents.restingOffset(for: 400, from: .completed), 120, "one flick lands on the default view, not deep in the list")
        XCTAssertEqual(detents.side(at: 100, current: .completed), .active)
    }

    func testATallDrawerRestsShowingItsBottom() {
        let tall = DrawerDetents(activeTop: 900, viewportHeight: 450)
        XCTAssertEqual(tall.completedRest, 450)
        XCTAssertEqual(tall.restingOffset(for: 820, from: .active), 450)
        XCTAssertEqual(tall.restingOffset(for: 200, from: .completed), 200, "scrolling further up inside the drawer is free")
        XCTAssertEqual(tall.barrier(leaving: .completed), 522)
        XCTAssertEqual(tall.restingOffset(for: 600, from: .completed), 900)
    }

    func testHysteresisMeansTheTwoBarriersDiffer() {
        XCTAssertLessThan(detents.barrier(leaving: .active), detents.barrier(leaving: .completed))
    }
}

final class SwipeRecognizerTests: XCTestCase {
    func testSmallMovementsAreUndecided() {
        var recognizer = SwipeRecognizer()
        recognizer.begin(directions: [.left])
        XCTAssertFalse(recognizer.move(dx: -3, dy: 1))
        XCTAssertEqual(recognizer.phase, .undecided)
        XCTAssertEqual(recognizer.displayedTranslation, 0)
    }

    func testMostlyHorizontalMovementLocksHorizontal() {
        var recognizer = SwipeRecognizer()
        recognizer.begin(directions: [.left])
        XCTAssertTrue(recognizer.move(dx: -10, dy: -2))
        XCTAssertEqual(recognizer.phase, .horizontal)
        XCTAssertEqual(recognizer.displayedTranslation, -10)
    }

    func testMostlyVerticalMovementLocksVerticalAndStaysThere() {
        var recognizer = SwipeRecognizer()
        recognizer.begin(directions: [.left])
        XCTAssertFalse(recognizer.move(dx: 2, dy: 10))
        XCTAssertEqual(recognizer.phase, .vertical)
        XCTAssertFalse(recognizer.move(dx: -60, dy: 0), "once vertical, later sideways drift never hijacks the scroll")
        XCTAssertNil(recognizer.end())
    }

    func testCommitsOnlyPastTheCommitDistance() {
        var recognizer = SwipeRecognizer()
        recognizer.begin(directions: [.left])
        _ = recognizer.move(dx: -60, dy: 0)
        XCTAssertFalse(recognizer.isPastCommit)
        XCTAssertNil(recognizer.end())

        recognizer.begin(directions: [.left])
        _ = recognizer.move(dx: -SwipeRecognizer.commitDistance, dy: 0)
        XCTAssertTrue(recognizer.isPastCommit)
        XCTAssertEqual(recognizer.end(), .left)
        XCTAssertEqual(recognizer.phase, .idle)
    }

    func testADirectionTheRowDoesNotAllowNeverCommits() {
        var recognizer = SwipeRecognizer()
        recognizer.begin(directions: [.left])
        _ = recognizer.move(dx: 200, dy: 0)
        XCTAssertFalse(recognizer.isPastCommit)
        XCTAssertLessThanOrEqual(recognizer.displayedTranslation, 10, "only a token give, so it reads as nothing there")
        XCTAssertNil(recognizer.end())
    }

    func testTravelBeyondTheCommitDistanceMeetsResistance() {
        var recognizer = SwipeRecognizer()
        recognizer.begin(directions: [.left])
        _ = recognizer.move(dx: -188, dy: 0)
        XCTAssertEqual(recognizer.displayedTranslation, -(88 + 30), accuracy: 0.001)
    }

    func testCancelDropsEverything() {
        var recognizer = SwipeRecognizer()
        recognizer.begin(directions: [.right])
        _ = recognizer.move(dx: 120, dy: 0)
        recognizer.cancel()
        XCTAssertEqual(recognizer.phase, .idle)
        XCTAssertEqual(recognizer.displayedTranslation, 0)
        XCTAssertFalse(recognizer.move(dx: 50, dy: 0), "movement without a begin is ignored")
    }
}

final class AgendaTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let now = Fixture.date(2026, 9, 2, 14, 0)
    private lazy var assembler = DeadlineAssembler(calendar: calendar, locale: Fixture.locale)
    private lazy var window = DateWindow(now: now, days: 1, calendar: calendar)

    private var snapshot: CalendarSnapshot {
        let entry = Fixture.calendarEntry()
        return Fixture.snapshot(calendars: [entry], events: [(entry, [
            Fixture.timedEvent(id: "lecture", title: "MA 265 lecture", start: Fixture.date(2026, 9, 2, 9, 30)),
            Fixture.timedEvent(id: "due", title: "DUE Homework 3", start: Fixture.date(2026, 9, 2, 16)),
            Fixture.timedEvent(id: "done", title: "DONE Laundry", start: Fixture.date(2026, 9, 2, 11)),
            Fixture.timedEvent(id: "tomorrow", title: "Tomorrow lecture", start: Fixture.date(2026, 9, 3, 9, 30)),
            Fixture.allDayEvent(id: "allday", title: "Career fair", startDay: "2026-09-02", endDayExclusive: "2026-09-03")
        ])])
    }

    func testTheAgendaHasEveryEventInTheWindowInTimeOrderAllDayFirst() {
        let agenda = assembler.agenda(from: snapshot, selectedCalendarIDs: nil, window: window)
        XCTAssertEqual(agenda.map(\.eventID), ["allday", "lecture", "due"])
    }

    func testTheAgendaMarksWhichItemsAreDeadlines() {
        let agenda = assembler.agenda(from: snapshot, selectedCalendarIDs: nil, window: window)
        XCTAssertEqual(agenda.first { $0.eventID == "due" }?.isDeadline, true)
        XCTAssertEqual(agenda.first { $0.eventID == "lecture" }?.isDeadline, false)
    }

    func testExclusionsStillApplyToTheAgenda() {
        let agenda = assembler.agenda(from: snapshot, selectedCalendarIDs: nil, window: window)
        XCTAssertFalse(agenda.contains { $0.eventID == "done" })
    }
}

final class ScheduleFocusTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let entry = Fixture.calendarEntry()

    private func event(_ id: String, _ title: String, at start: Date, minutes: Int = 60) -> Deadline {
        var item = Fixture.builder(configuration: {
            var c = FilterConfiguration.default; c.showAllEvents = true; return c
        }()).build(event: Fixture.timedEvent(id: id, title: title, start: start, durationMinutes: minutes), calendarEntry: entry)!
        item.isDeadline = DeadlineDetector(configuration: .default).isDeadline(title: title)
        return item
    }

    func testAnEventInProgressIsTheFocusWithItsEndAsTheTarget() {
        let now = Fixture.date(2026, 9, 2, 10, 0)
        let lecture = event("l", "Lecture", at: Fixture.date(2026, 9, 2, 9, 30), minutes: 50)
        let later = event("m", "Meeting", at: Fixture.date(2026, 9, 2, 11, 0))
        let focus = ScheduleFocus.select(from: [lecture, later], now: now)
        XCTAssertEqual(focus?.item.eventID, "l")
        XCTAssertEqual(focus?.kind, .happeningNow)
        XCTAssertEqual(focus?.until, Fixture.date(2026, 9, 2, 10, 20))
        XCTAssertEqual(focus?.label, "HAPPENING NOW")
    }

    func testWithNothingOnTheNextEventIsTheFocusWithItsStartAsTheTarget() {
        let now = Fixture.date(2026, 9, 2, 10, 30)
        let lecture = event("l", "Lecture", at: Fixture.date(2026, 9, 2, 9, 30), minutes: 50)
        let later = event("m", "Meeting", at: Fixture.date(2026, 9, 2, 11, 0))
        let focus = ScheduleFocus.select(from: [lecture, later], now: now)
        XCTAssertEqual(focus?.item.eventID, "m")
        XCTAssertEqual(focus?.kind, .upNext)
        XCTAssertEqual(focus?.until, Fixture.date(2026, 9, 2, 11, 0))
        XCTAssertEqual(focus?.label, "UP NEXT")
    }

    func testANextDeadlineSaysSo() {
        let now = Fixture.date(2026, 9, 2, 10, 30)
        let due = event("d", "DUE Homework", at: Fixture.date(2026, 9, 2, 16, 0), minutes: 15)
        let focus = ScheduleFocus.select(from: [due], now: now)
        XCTAssertEqual(focus?.label, "DUE NEXT")
        XCTAssertEqual(focus?.isDeadline, true)
    }

    func testOverlappingEventsFocusTheOneEndingSoonest() {
        let now = Fixture.date(2026, 9, 2, 10, 0)
        let long = event("a", "Long", at: Fixture.date(2026, 9, 2, 9, 0), minutes: 180)
        let short = event("b", "Short", at: Fixture.date(2026, 9, 2, 9, 45), minutes: 30)
        XCTAssertEqual(ScheduleFocus.select(from: [long, short], now: now)?.item.eventID, "b")
    }

    func testNothingLeftMeansNoFocus() {
        let now = Fixture.date(2026, 9, 2, 20, 0)
        let lecture = event("l", "Lecture", at: Fixture.date(2026, 9, 2, 9, 30), minutes: 50)
        XCTAssertNil(ScheduleFocus.select(from: [lecture], now: now))
    }
}

final class DeadlinePartitionTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let now = Fixture.date(2026, 9, 2, 14, 0)
    private lazy var assembler = DeadlineAssembler(calendar: calendar, locale: Fixture.locale)
    private lazy var window = DateWindow(now: now, days: 3, calendar: calendar)

    private var snapshot: CalendarSnapshot {
        let entry = Fixture.calendarEntry()
        return Fixture.snapshot(calendars: [entry], events: [(entry, [
            Fixture.timedEvent(id: "a", title: "DUE a", start: Fixture.date(2026, 9, 2, 16)),
            Fixture.timedEvent(id: "b", title: "DUE b", start: Fixture.date(2026, 9, 2, 18)),
            Fixture.timedEvent(id: "c", title: "DUE c", start: Fixture.date(2026, 9, 3, 9)),
            Fixture.timedEvent(id: "old", title: "DUE old", start: Fixture.date(2026, 8, 20, 9))
        ])])
    }

    func testCompletedDeadlinesLeaveTheSections() {
        let partition = assembler.partition(
            from: snapshot,
            selectedCalendarIDs: nil,
            completed: ["primary@example.com|b": now],
            window: window,
            now: now
        )
        XCTAssertEqual(partition.sections.flatMap(\.deadlines).map(\.eventID), ["a", "c"])
        XCTAssertEqual(partition.completed.map(\.eventID), ["b"])
    }

    func testCompletedItemsAreOrderedOldestFirstSoTheNewestSitsNearestTheList() {
        let partition = assembler.partition(
            from: snapshot,
            selectedCalendarIDs: nil,
            completed: [
                "primary@example.com|a": now.addingTimeInterval(-60),
                "primary@example.com|c": now.addingTimeInterval(-600)
            ],
            window: window,
            now: now
        )
        XCTAssertEqual(partition.completed.map(\.eventID), ["c", "a"])
    }

    func testCompletedItemsOutsideTheWindowAreNotShown() {
        let partition = assembler.partition(
            from: snapshot,
            selectedCalendarIDs: nil,
            completed: ["primary@example.com|old": now],
            window: window,
            now: now
        )
        XCTAssertTrue(partition.completed.isEmpty)
    }

}
