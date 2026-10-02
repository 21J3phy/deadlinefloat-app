import XCTest
@testable import DeadlineFloat

/// The arithmetic behind dragging a block, the narrow hole in the network
/// layer that lets the result be written, and the optimistic rewrite that
/// draws it before Google has answered.
final class EventEditTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let entry = Fixture.calendarEntry()

    private func day(_ year: Int, _ month: Int, _ d: Int) -> RulerSpan {
        RulerSpan(day: Fixture.date(year, month, d), calendar: calendar)
    }

    // MARK: - Snapping

    func testTimesSnapToTheFiveMinuteGrid() {
        let snapped = EventEdit.snap(Fixture.date(2026, 9, 21, 14, 37), minutes: 5, calendar: calendar)
        XCTAssertEqual(snapped, Fixture.date(2026, 9, 21, 14, 35))

        let up = EventEdit.snap(Fixture.date(2026, 9, 21, 14, 38), minutes: 5, calendar: calendar)
        XCTAssertEqual(up, Fixture.date(2026, 9, 21, 14, 40))
    }

    func testFineSnappingKeepsTheMinute() {
        let snapped = EventEdit.snap(Fixture.date(2026, 9, 21, 14, 37, 20), minutes: 1, calendar: calendar)
        XCTAssertEqual(snapped, Fixture.date(2026, 9, 21, 14, 37))
    }

    // MARK: - Moving

    func testAMoveKeepsTheLengthAndSnapsTheStart() {
        let start = Fixture.date(2026, 9, 21, 9)
        let proposal = EventEdit.propose(
            mode: .move,
            start: start,
            end: start.addingTimeInterval(90 * 60),
            seconds: 63 * 60,
            days: 0,
            day: day(2026, 9, 21),
            fine: false,
            calendar: calendar
        )
        XCTAssertEqual(proposal.start, Fixture.date(2026, 9, 21, 10, 5))
        XCTAssertEqual(proposal.duration, 90 * 60, "the event is as long as it was")
    }

    func testDraggingSidewaysChangesTheDay() {
        let start = Fixture.date(2026, 9, 21, 9)
        let proposal = EventEdit.propose(
            mode: .move,
            start: start,
            end: start.addingTimeInterval(60 * 60),
            seconds: 0,
            days: 2,
            day: day(2026, 9, 23),
            fine: false,
            calendar: calendar
        )
        XCTAssertEqual(proposal.start, Fixture.date(2026, 9, 23, 9))
        XCTAssertEqual(proposal.end, Fixture.date(2026, 9, 23, 10))
    }

    func testAMoveStaysInsideTheColumnItLandedOn() {
        let start = Fixture.date(2026, 9, 21, 9)
        let end = start.addingTimeInterval(60 * 60)

        let tooHigh = EventEdit.propose(
            mode: .move, start: start, end: end, seconds: -40 * 3_600,
            days: 0, day: day(2026, 9, 21), fine: false, calendar: calendar
        )
        XCTAssertEqual(tooHigh.start, Fixture.date(2026, 9, 21), "pinned to the top of the day")

        let tooLow = EventEdit.propose(
            mode: .move, start: start, end: end, seconds: 40 * 3_600,
            days: 0, day: day(2026, 9, 21), fine: false, calendar: calendar
        )
        XCTAssertEqual(tooLow.start, Fixture.date(2026, 9, 21, 23, 55), "still a sliver of it showing")
    }

    func testAMoveAcrossSpringForwardKeepsTheWallClockTime() {
        // 2 AM does not exist on 8 March 2026; adding a day, not 86,400
        // seconds, is what keeps a 9 AM event at 9 AM.
        let start = Fixture.date(2026, 3, 7, 9)
        let proposal = EventEdit.propose(
            mode: .move,
            start: start,
            end: start.addingTimeInterval(60 * 60),
            seconds: 0,
            days: 1,
            day: day(2026, 3, 8),
            fine: false,
            calendar: calendar
        )
        XCTAssertEqual(proposal.start, Fixture.date(2026, 3, 8, 9))
    }

    // MARK: - Resizing

    func testDraggingTheBottomEdgeMovesOnlyTheEnd() {
        let start = Fixture.date(2026, 9, 21, 9)
        let proposal = EventEdit.propose(
            mode: .resizeEnd,
            start: start,
            end: Fixture.date(2026, 9, 21, 10),
            seconds: 32 * 60,
            days: 0,
            day: day(2026, 9, 21),
            fine: false,
            calendar: calendar
        )
        XCTAssertEqual(proposal.start, start)
        XCTAssertEqual(proposal.end, Fixture.date(2026, 9, 21, 10, 30))
    }

    func testDraggingTheTopEdgeMovesOnlyTheStart() {
        let end = Fixture.date(2026, 9, 21, 10)
        let proposal = EventEdit.propose(
            mode: .resizeStart,
            start: Fixture.date(2026, 9, 21, 9),
            end: end,
            seconds: 30 * 60,
            days: 0,
            day: day(2026, 9, 21),
            fine: false,
            calendar: calendar
        )
        XCTAssertEqual(proposal.start, Fixture.date(2026, 9, 21, 9, 30))
        XCTAssertEqual(proposal.end, end)
    }

    func testAnEventCannotBeDraggedShorterThanFiveMinutes() {
        let start = Fixture.date(2026, 9, 21, 9)
        let end = Fixture.date(2026, 9, 21, 10)

        let squashedFromBelow = EventEdit.propose(
            mode: .resizeEnd, start: start, end: end, seconds: -5 * 3_600,
            days: 0, day: day(2026, 9, 21), fine: false, calendar: calendar
        )
        XCTAssertEqual(squashedFromBelow.end, start.addingTimeInterval(EventEdit.minimumDuration))

        let squashedFromAbove = EventEdit.propose(
            mode: .resizeStart, start: start, end: end, seconds: 5 * 3_600,
            days: 0, day: day(2026, 9, 21), fine: false, calendar: calendar
        )
        XCTAssertEqual(squashedFromAbove.start, end.addingTimeInterval(-EventEdit.minimumDuration))
    }

    func testResizingIgnoresASidewaysDrag() {
        let start = Fixture.date(2026, 9, 21, 9)
        let proposal = EventEdit.propose(
            mode: .resizeEnd,
            start: start,
            end: Fixture.date(2026, 9, 21, 10),
            seconds: 0,
            days: 0,
            day: day(2026, 9, 21),
            fine: false,
            calendar: calendar
        )
        XCTAssertEqual(proposal.start, start)
        XCTAssertFalse(EventEdit.Mode.resizeEnd.changesDay)
        XCTAssertFalse(EventEdit.Mode.resizeStart.changesDay)
        XCTAssertTrue(EventEdit.Mode.move.changesDay)
    }

    // MARK: - What can be dragged

    func testOnlyTimedEventsWithAnEndCanBeDragged() {
        let timed = Fixture.builder().build(
            event: Fixture.timedEvent(start: Fixture.date(2026, 9, 21, 9)),
            calendarEntry: entry
        )
        XCTAssertTrue(EventEdit.isEditable(try XCTUnwrap(timed)))

        let allDay = Fixture.builder().build(
            event: Fixture.allDayEvent(startDay: "2026-09-21", endDayExclusive: "2026-09-22"),
            calendarEntry: entry
        )
        XCTAssertFalse(EventEdit.isEditable(try XCTUnwrap(allDay)), "an all-day item has no length on the grid")
    }

    func testADropWhereItStartedAsksForNothing() throws {
        let start = Fixture.date(2026, 9, 21, 9)
        let deadline = try XCTUnwrap(
            Fixture.builder().build(event: Fixture.timedEvent(start: start, durationMinutes: 60), calendarEntry: entry)
        )
        XCTAssertNil(EventEdit.move(for: deadline, proposal: .init(start: start, end: start.addingTimeInterval(3_600))))
        XCTAssertNotNil(EventEdit.move(for: deadline, proposal: .init(start: start.addingTimeInterval(300), end: start.addingTimeInterval(3_900))))
    }

    func testAMoveCarriesTheIdsNeededToWriteIt() throws {
        let deadline = try XCTUnwrap(
            Fixture.builder().build(event: Fixture.timedEvent(id: "abc", start: Fixture.date(2026, 9, 21, 9)), calendarEntry: entry)
        )
        let move = try XCTUnwrap(
            EventEdit.move(for: deadline, proposal: .init(start: Fixture.date(2026, 9, 21, 10), end: Fixture.date(2026, 9, 21, 11)))
        )
        XCTAssertEqual(move.eventID, "abc")
        XCTAssertEqual(move.calendarID, entry.id)
        XCTAssertEqual(move.deadlineID, deadline.id, "the id the block was drawn under")
    }

    // MARK: - Drawing it before Google has answered

    func testApplyingAMoveRewritesTheEventInTheSnapshot() throws {
        let event = Fixture.timedEvent(id: "e1", start: Fixture.date(2026, 9, 21, 9), durationMinutes: 60)
        let snapshot = Fixture.snapshot(calendars: [entry], events: [(entry, [event])])

        let moved = snapshot.applying(
            [EventMove(
                calendarID: entry.id,
                eventID: "e1",
                start: Fixture.date(2026, 9, 22, 14),
                end: Fixture.date(2026, 9, 22, 15)
            )],
            timeZone: Fixture.indianapolis
        )

        let deadline = try XCTUnwrap(
            Fixture.builder().build(event: try XCTUnwrap(moved.allEvents.first), calendarEntry: entry)
        )
        XCTAssertEqual(deadline.displayInstant, Fixture.date(2026, 9, 22, 14))
        XCTAssertEqual(deadline.dayStart, Fixture.date(2026, 9, 22), "it is filed under the day it was dropped on")
        guard case .timed(_, let end) = deadline.timing else { return XCTFail("still timed") }
        XCTAssertEqual(end, Fixture.date(2026, 9, 22, 15))
    }

    func testApplyingAMoveLeavesEveryOtherEventAlone() {
        let mine = Fixture.timedEvent(id: "e1", start: Fixture.date(2026, 9, 21, 9))
        let other = Fixture.timedEvent(id: "e2", start: Fixture.date(2026, 9, 21, 11))
        let snapshot = Fixture.snapshot(calendars: [entry], events: [(entry, [mine, other])])

        let moved = snapshot.applying(
            [EventMove(calendarID: entry.id, eventID: "e1", start: Fixture.date(2026, 9, 21, 15), end: Fixture.date(2026, 9, 21, 16))],
            timeZone: Fixture.indianapolis
        )
        XCTAssertEqual(moved.allEvents.first { $0.id == "e2" }, other)
        XCTAssertEqual(snapshot.allEvents.first { $0.id == "e1" }, mine, "the original is untouched")
    }

    func testARescheduledEventKeepsEverythingButItsTimes() throws {
        let event = Fixture.timedEvent(id: "e1", title: "DUE: Essay", start: Fixture.date(2026, 9, 21, 9), colorId: "5", location: "Library")
        let moved = event.rescheduled(
            start: Fixture.date(2026, 9, 21, 13),
            end: Fixture.date(2026, 9, 21, 14),
            timeZone: Fixture.indianapolis
        )
        XCTAssertEqual(moved.summary, event.summary)
        XCTAssertEqual(moved.colorId, "5")
        XCTAssertEqual(moved.location, "Library")
        XCTAssertEqual(moved.htmlLink, event.htmlLink)
        XCTAssertEqual(GoogleDate.timestamp(from: try XCTUnwrap(moved.start?.dateTime)), Fixture.date(2026, 9, 21, 13))
        XCTAssertNil(moved.start?.date, "a timed event does not acquire an all-day date")
    }

    func testReplacingFoldsGooglesAnswerBackIn() throws {
        let event = Fixture.timedEvent(id: "e1", start: Fixture.date(2026, 9, 21, 9))
        let snapshot = Fixture.snapshot(calendars: [entry], events: [(entry, [event])])
        var confirmed = event
        confirmed.summary = "DUE: Essay (final)"

        let updated = snapshot.replacing(confirmed, inCalendar: entry.id)
        XCTAssertEqual(updated.allEvents.first?.summary, "DUE: Essay (final)")
        XCTAssertEqual(updated.replacing(confirmed, inCalendar: "someone-else").allEvents.count, 1)
    }

    // MARK: - Writing the time out

    func testTheWrittenTimestampCarriesTheZonesOffset() {
        XCTAssertEqual(
            GoogleDate.rfc3339String(from: Fixture.date(2026, 9, 21, 14, 30), timeZone: Fixture.indianapolis),
            "2026-09-21T14:30:00-04:00"
        )
        XCTAssertEqual(
            GoogleDate.rfc3339String(from: Fixture.date(2026, 1, 15, 8), timeZone: Fixture.indianapolis),
            "2026-01-15T08:00:00-05:00",
            "the offset is the one in force that day, not the one in force today"
        )
        XCTAssertEqual(
            GoogleDate.rfc3339String(from: Fixture.date(2026, 9, 21, 14, 30), timeZone: TimeZone(identifier: "Asia/Kolkata")!),
            "2026-09-22T00:00:00+05:30"
        )
    }

    func testARoundTripThroughTheWriterAndTheParserIsExact() throws {
        let instant = Fixture.date(2026, 11, 1, 1, 30)
        let text = GoogleDate.rfc3339String(from: instant, timeZone: Fixture.indianapolis)
        XCTAssertEqual(GoogleDate.timestamp(from: text), instant)
    }
}

/// The one request the app can make that changes something, and the consent
/// that has to be in hand before it is made.
final class EventWriteRequestTests: XCTestCase {
    private func client(_ transport: FakeTransport) -> GoogleCalendarClient {
        GoogleCalendarClient(http: .testing(transport: transport), accessTokenProvider: { "token-123" })
    }

    func testRescheduleSendsOnlyTheTwoTimesToOneEventsURL() async throws {
        let body = #"{"id":"e1","status":"confirmed","summary":"DUE: Essay"}"#
        let transport = FakeTransport(status: 200, json: body)

        let returned = try await client(transport).reschedule(
            calendarID: "primary@example.com",
            eventID: "e1",
            start: Fixture.date(2026, 9, 21, 14),
            end: Fixture.date(2026, 9, 21, 15),
            timeZone: Fixture.indianapolis
        )
        XCTAssertEqual(returned.id, "e1")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/calendar/v3/calendars/primary@example.com/events/e1")
        XCTAssertEqual(request.url?.query, "sendUpdates=none", "moving one's own event does not mail the guests")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")

        let sent = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
        XCTAssertEqual(Set(try XCTUnwrap(sent).keys), ["start", "end"], "nothing else is written")
        XCTAssertEqual((sent?["start"] as? [String: Any])?["dateTime"] as? String, "2026-09-21T14:00:00-04:00")
        XCTAssertEqual((sent?["end"] as? [String: Any])?["dateTime"] as? String, "2026-09-21T15:00:00-04:00")
        XCTAssertNil((sent?["start"] as? [String: Any])?["date"])
    }

    func testARefusedWriteIsReportedRatherThanSwallowed() async {
        let transport = FakeTransport(status: 403, json: #"{"error":{"code":403,"errors":[{"reason":"forbiddenForNonOrganizer"}],"message":"Cannot change this event"}}"#)
        do {
            _ = try await client(transport).reschedule(
                calendarID: "c", eventID: "e", start: Date(), end: Date().addingTimeInterval(3_600),
                timeZone: Fixture.indianapolis
            )
            XCTFail("expected the refusal to propagate")
        } catch {
            XCTAssertEqual(DeadlineListViewModel.moveFailureMessage(for: error), "Cannot change this event")
        }
    }

    func testFailureMessagesSayWhatToDoAboutIt() {
        XCTAssertEqual(DeadlineListViewModel.moveFailureMessage(for: APIError.offline), "Offline — the event did not move")
        XCTAssertEqual(DeadlineListViewModel.moveFailureMessage(for: APIError.unauthorized), "Reconnect to move events")
        XCTAssertTrue(DeadlineListViewModel.isAuthFailure(APIError.unauthorized))
        XCTAssertFalse(DeadlineListViewModel.isAuthFailure(APIError.offline))
    }

    // MARK: - Consent

    func testEditingIsAskedForOnlyWhenItIsTurnedOn() {
        XCTAssertEqual(GoogleEndpoints.scopes(allowsEditing: false), GoogleEndpoints.scope)
        XCTAssertFalse(GoogleEndpoints.scopes(allowsEditing: false).contains(" "), "still exactly one scope")

        let both = GoogleEndpoints.scopes(allowsEditing: true).split(separator: " ").map(String.init)
        XCTAssertEqual(both, [GoogleEndpoints.scope, GoogleEndpoints.editingScope])
        XCTAssertFalse(both.contains { $0.contains("profile") || $0.contains("email") })
        XCTAssertFalse(both.contains("https://www.googleapis.com/auth/calendar"), "never the full-access scope")
    }

    func testTheAuthorizationURLCarriesWhicheverScopesWereAskedFor() throws {
        let url = try XCTUnwrap(GoogleAuthService.authorizationURL(
            clientID: "abc.apps.googleusercontent.com",
            redirectURI: "http://127.0.0.1:5000",
            pkce: .generate(),
            state: "s",
            scopes: GoogleEndpoints.scopes(allowsEditing: true)
        ))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "scope" }?.value, GoogleEndpoints.scopes(allowsEditing: true))
    }

    func testAGrantIsReadFromWhatGoogleActuallyIssued() {
        XCTAssertFalse(GoogleEndpoints.grants(editing: nil))
        XCTAssertFalse(GoogleEndpoints.grants(editing: GoogleEndpoints.scope))
        XCTAssertFalse(GoogleEndpoints.grants(editing: "https://www.googleapis.com/auth/calendar.events.readonly"))
        XCTAssertTrue(GoogleEndpoints.grants(editing: GoogleEndpoints.scopes(allowsEditing: true)))
        XCTAssertTrue(GoogleEndpoints.grants(editing: "https://www.googleapis.com/auth/calendar"))
    }

    func testARefreshThatOmitsTheScopeKeepsTheOneAlreadyGranted() throws {
        let response = GoogleTokenResponse(access_token: "new", expires_in: 3_600)
        let tokens = try XCTUnwrap(response.tokens(
            now: Fixture.date(2026, 9, 21, 9),
            existingRefreshToken: "r",
            existingScope: GoogleEndpoints.scopes(allowsEditing: true)
        ))
        XCTAssertTrue(GoogleEndpoints.grants(editing: tokens.scope))
        XCTAssertEqual(tokens.refreshToken, "r")
    }
}
