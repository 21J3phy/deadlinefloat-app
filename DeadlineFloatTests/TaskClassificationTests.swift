import XCTest
@testable import DeadlineFloat

final class TaskClassificationTests: XCTestCase {
    func testOnlyConfirmedUnfinishedTasksEnterActiveListEvenWithShowAllEnabled() {
        let calendar = Fixture.calendarEntry()
        let now = Fixture.date(2026, 9, 21, 9)
        let events = [
            Fixture.timedEvent(id: "task", title: "Write report", start: now),
            Fixture.timedEvent(id: "meeting", title: "Discuss homework due dates", start: now),
            Fixture.timedEvent(id: "unknown", title: "DUE: Unclassified", start: now),
            Fixture.timedEvent(id: "done", title: "Submit essay", start: now),
            Fixture.timedEvent(id: "excluded", title: "DONE: Submit lab", start: now)
        ]
        let snapshot = Fixture.snapshot(calendars: [calendar], events: [(calendar, events)])
        var configuration = FilterConfiguration.default
        configuration.showAllEvents = true
        var assembler = DeadlineAssembler(calendar: Fixture.calendar(), configuration: configuration)
        let id: (String) -> String = { "\(calendar.id)|\($0)" }
        assembler.taskClassifications = [id("task"): true, id("meeting"): false, id("done"): true, id("excluded"): true]
        let window = DateWindow(now: now, days: 3, calendar: Fixture.calendar())
        let partition = assembler.partition(from: snapshot, selectedCalendarIDs: nil,
                                            completed: [id("done"): now], window: window, now: now)
        XCTAssertEqual(partition.sections.flatMap(\.deadlines).map(\.eventID), ["task"])
        XCTAssertEqual(partition.completed.map(\.eventID), ["done"])
        let agenda = assembler.agenda(from: snapshot, selectedCalendarIDs: nil, window: window)
        XCTAssertEqual(Set(agenda.map(\.eventID)), Set(["task", "meeting", "unknown", "done"]))
        XCTAssertFalse(agenda.first { $0.eventID == "meeting" }!.isDeadline)
        XCTAssertFalse(agenda.first { $0.eventID == "unknown" }!.isDeadline)
        XCTAssertTrue(agenda.first { $0.eventID == "task" }!.isDeadline)
    }

    func testClassificationCacheChangesForNotesButNotRescheduling() {
        var event = Fixture.timedEvent(title: "Finish report", start: Fixture.date(2026, 9, 21))
        let original = TaskClassificationInput(event: event, calendarName: "Personal")
        event.start = GoogleEventDateTime(dateTime: "2026-09-22T09:00:00-04:00")
        XCTAssertEqual(original, TaskClassificationInput(event: event, calendarName: "Personal"))
        event.description = "Already submitted"
        XCTAssertNotEqual(original, TaskClassificationInput(event: event, calendarName: "Personal"))
        XCTAssertNotEqual(original, TaskClassificationInput(event: event, calendarName: "Team"))
    }
}
