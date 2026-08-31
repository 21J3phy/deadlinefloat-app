import XCTest
@testable import DeadlineFloat

/// Recurring series arrive from Google already expanded (`singleEvents=true`),
/// so these tests cover what the app must do with those instances: keep each
/// one's own local time, preserve the series link, respect moved occurrences,
/// and never collapse a series into a single row.
final class RecurrenceTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let entry = Fixture.calendarEntry(id: "cs@example.com", name: "CS 18000")

    func testClientAsksForExpandedInstancesInStartOrder() throws {
        let transport = FakeTransport(status: 200, json: #"{"items":[]}"#)
        let client = GoogleCalendarClient(
            http: .testing(transport: transport),
            accessTokenProvider: { "token" }
        )
        let window = DateWindow(now: Fixture.date(2026, 9, 2, 12), days: 3, calendar: calendar)

        _ = try awaitValue { try await client.events(calendarID: "cs@example.com", window: window) }

        let url = try XCTUnwrap(transport.requests.first?.url)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(values["singleEvents"], "true")
        XCTAssertEqual(values["orderBy"], "startTime")
        XCTAssertEqual(values["showDeleted"], "false")
        XCTAssertEqual(values["timeZone"], Fixture.indianapolis.identifier)
        XCTAssertEqual(values["timeMin"], GoogleDate.rfc3339String(from: window.queryStart))
        XCTAssertEqual(values["timeMax"], GoogleDate.rfc3339String(from: window.queryEnd))
    }

    func testEachInstanceKeepsItsOwnDayAndSeriesLink() {
        let builder = Fixture.builder()
        let instances = (0..<3).map { offset in
            Fixture.timedEvent(
                id: "series_2026090\(2 + offset)T230000Z",
                title: "DUE: Weekly reading",
                start: Fixture.date(2026, 9, 2 + offset, 19, 0),
                recurringEventId: "series",
                iCalUID: "series@google.com"
            )
        }
        let deadlines = instances.compactMap { builder.build(event: $0, calendarEntry: entry) }

        XCTAssertEqual(deadlines.count, 3)
        XCTAssertEqual(Set(deadlines.map(\.recurringEventID)), ["series"])
        XCTAssertTrue(deadlines.allSatisfy(\.isRecurringInstance))
        XCTAssertEqual(
            deadlines.map(\.dayStart),
            [Fixture.date(2026, 9, 2), Fixture.date(2026, 9, 3), Fixture.date(2026, 9, 4)]
        )
    }

    func testRecurringInstancesKeepTheSameWallClockTimeAcrossSpringForward() {
        // A 9:00 AM daily deadline: Google sends each instance with the correct
        // offset, -05:00 before the change and -04:00 after it.
        let before = GoogleEvent(
            id: "s_20260307T140000Z",
            status: "confirmed",
            summary: "DUE: Daily standup report",
            start: GoogleEventDateTime(dateTime: "2026-03-07T09:00:00-05:00"),
            end: GoogleEventDateTime(dateTime: "2026-03-07T09:15:00-05:00"),
            recurringEventId: "s"
        )
        let after = GoogleEvent(
            id: "s_20260309T130000Z",
            status: "confirmed",
            summary: "DUE: Daily standup report",
            start: GoogleEventDateTime(dateTime: "2026-03-09T09:00:00-04:00"),
            end: GoogleEventDateTime(dateTime: "2026-03-09T09:15:00-04:00"),
            recurringEventId: "s"
        )

        let builder = Fixture.builder()
        let first = builder.build(event: before, calendarEntry: entry)!
        let second = builder.build(event: after, calendarEntry: entry)!

        let formatter = DeadlineFormatter(calendar: calendar, locale: Fixture.locale)
        XCTAssertEqual(Fixture.plain(formatter.timeText(for: first)), "9:00 AM")
        XCTAssertEqual(Fixture.plain(formatter.timeText(for: second)), "9:00 AM", "the wall-clock time must survive the DST change")
        XCTAssertEqual(
            second.sortInstant.timeIntervalSince(first.sortInstant),
            47 * 3600,
            "two calendar days that contain a spring-forward are 47 hours apart"
        )
    }

    func testAMovedOccurrenceIsFiledOnItsNewDay() {
        // Google reports the exception with its new start and the original in
        // `originalStartTime`; the app must follow the new start.
        var moved = Fixture.timedEvent(
            id: "series_20260903T130000Z",
            title: "DUE: Weekly reading",
            start: Fixture.date(2026, 9, 4, 15, 0),
            recurringEventId: "series"
        )
        moved.originalStartTime = GoogleEventDateTime(dateTime: GoogleDate.rfc3339String(from: Fixture.date(2026, 9, 3, 9, 0)))

        let deadline = Fixture.builder().build(event: moved, calendarEntry: entry)!
        XCTAssertEqual(deadline.dayStart, Fixture.date(2026, 9, 4))
    }

    func testCancelledOccurrenceIsRemovedFromTheSeries() {
        let builder = Fixture.builder()
        let live = Fixture.timedEvent(id: "s_1", title: "DUE: Weekly reading", start: Fixture.date(2026, 9, 2, 19), recurringEventId: "s")
        let cancelled = Fixture.timedEvent(id: "s_2", title: "DUE: Weekly reading", start: Fixture.date(2026, 9, 3, 19), recurringEventId: "s", status: "cancelled")

        XCTAssertNotNil(builder.build(event: live, calendarEntry: entry))
        XCTAssertNil(builder.build(event: cancelled, calendarEntry: entry))
    }

    func testAllInstancesSurviveGroupingAsSeparateRows() {
        let builder = Fixture.builder()
        let events = (0..<3).map { offset in
            Fixture.timedEvent(
                id: "s_\(offset)",
                title: "DUE: Weekly reading",
                start: Fixture.date(2026, 9, 2 + offset, 19, 0),
                recurringEventId: "s",
                iCalUID: "series@google.com"
            )
        }
        let deadlines = events.compactMap { builder.build(event: $0, calendarEntry: entry) }
        let now = Fixture.date(2026, 9, 2, 12)
        let window = DateWindow(now: now, days: 3, calendar: calendar)
        let sections = DeadlineGrouper(
            calendar: calendar,
            formatter: DeadlineFormatter(calendar: calendar, locale: Fixture.locale)
        ).sections(from: deadlines, now: now, window: window)

        XCTAssertEqual(sections.flatMap(\.deadlines).count, 3)
        XCTAssertEqual(sections.map(\.title), ["Today", "Tomorrow", "Friday, September 4"])
    }

    func testDuplicateReducerDoesNotMergeDifferentInstancesOfOneSeries() {
        let builder = Fixture.builder()
        let events = (0..<2).map { offset in
            Fixture.timedEvent(
                id: "s_\(offset)",
                title: "DUE: Weekly reading",
                start: Fixture.date(2026, 9, 2 + offset, 19, 0),
                recurringEventId: "s",
                iCalUID: "series@google.com"
            )
        }
        let deadlines = events.compactMap { builder.build(event: $0, calendarEntry: entry) }
        XCTAssertEqual(DuplicateReducer().reduce(deadlines).count, 2, "same uid, different start — not duplicates")
    }
}

/// Bridges an async call into a synchronous XCTest body.
func awaitValue<T: Sendable>(
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: @escaping @Sendable () async throws -> T
) throws -> T {
    let box = ResultBox<T>()
    let expectation = XCTestExpectation(description: "async value")
    Task {
        do { box.value = .success(try await operation()) }
        catch { box.value = .failure(error) }
        expectation.fulfill()
    }
    let waiter = XCTWaiter()
    guard waiter.wait(for: [expectation], timeout: timeout) == .completed else {
        XCTFail("async operation timed out", file: file, line: line)
        throw CancellationError()
    }
    switch box.value {
    case .success(let value): return value
    case .failure(let error): throw error
    case .none: throw CancellationError()
    }
}

final class ResultBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Result<T, Error>?

    var value: Result<T, Error>? {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}
