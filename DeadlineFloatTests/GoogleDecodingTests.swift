import XCTest
@testable import DeadlineFloat

/// Decoding against payloads shaped exactly like Google's, including the fields
/// that need special handling (`self`, all-day `date`, conference data).
final class GoogleDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testDecodesCalendarList() throws {
        let json = """
        {
          "kind": "calendar#calendarList",
          "nextPageToken": "abc",
          "items": [
            {
              "id": "me@example.com",
              "summary": "me@example.com",
              "summaryOverride": "Personal",
              "timeZone": "America/Indiana/Indianapolis",
              "colorId": "16",
              "backgroundColor": "#4986e7",
              "foregroundColor": "#ffffff",
              "selected": true,
              "primary": true,
              "accessRole": "owner"
            },
            {
              "id": "cs18000@group.calendar.google.com",
              "summary": "CS 18000",
              "backgroundColor": "#5484ed",
              "accessRole": "reader",
              "deleted": false
            }
          ]
        }
        """
        let response = try decode(GoogleCalendarListResponse.self, json)
        XCTAssertEqual(response.nextPageToken, "abc")
        XCTAssertEqual(response.items?.count, 2)
        XCTAssertEqual(response.items?[0].displayName, "Personal", "summaryOverride wins")
        XCTAssertEqual(response.items?[1].displayName, "CS 18000")
        XCTAssertTrue(response.items!.allSatisfy(\.isVisibleCandidate))
    }

    func testHiddenAndDeletedCalendarsAreFlagged() throws {
        let json = """
        {"items":[{"id":"a","deleted":true},{"id":"b","hidden":true},{"id":"c"}]}
        """
        let items = try decode(GoogleCalendarListResponse.self, json).items!
        XCTAssertEqual(items.filter(\.isVisibleCandidate).map(\.id), ["c"])
    }

    func testDecodesTimedEventWithEverything() throws {
        let json = """
        {
          "id": "abc123_20260902T035900Z",
          "status": "confirmed",
          "htmlLink": "https://www.google.com/calendar/event?eid=abc",
          "summary": "SUBMIT Project 3",
          "description": "Upload to Vocareum",
          "location": "WALC 1055",
          "colorId": "11",
          "start": { "dateTime": "2026-09-02T23:59:00-04:00", "timeZone": "America/Indiana/Indianapolis" },
          "end":   { "dateTime": "2026-09-03T00:29:00-04:00", "timeZone": "America/Indiana/Indianapolis" },
          "recurringEventId": "abc123",
          "originalStartTime": { "dateTime": "2026-09-02T23:59:00-04:00" },
          "iCalUID": "abc123@google.com",
          "eventType": "default",
          "transparency": "opaque",
          "hangoutLink": "https://meet.google.com/xyz",
          "conferenceData": {
            "conferenceId": "xyz",
            "conferenceSolution": { "name": "Google Meet", "key": { "type": "hangoutsMeet" } },
            "entryPoints": [{ "entryPointType": "video", "uri": "https://meet.google.com/xyz", "label": "meet.google.com/xyz" }]
          },
          "attendees": [
            { "email": "me@example.com", "self": true, "responseStatus": "accepted" },
            { "email": "ta@example.com", "responseStatus": "declined" }
          ],
          "organizer": { "email": "prof@example.com", "displayName": "Prof" },
          "updated": "2026-08-30T10:11:12.345Z"
        }
        """
        let event = try decode(GoogleEvent.self, json)
        XCTAssertEqual(event.summary, "SUBMIT Project 3")
        XCTAssertEqual(event.colorId, "11")
        XCTAssertTrue(event.isRecurringInstance)
        XCTAssertFalse(event.isCancelled)
        XCTAssertFalse(event.isDeclinedBySelf, "only the signed-in user's own declination counts")
        XCTAssertEqual(event.attendees?[0].this, true)
        XCTAssertEqual(event.conferencePlatform, "Google Meet")
        XCTAssertEqual(GoogleDate.timestamp(from: event.start!.dateTime!), Fixture.date(2026, 9, 2, 23, 59))
    }

    func testDecodesDeclinedByUser() throws {
        let json = """
        {"id":"x","attendees":[{"email":"me@example.com","self":true,"responseStatus":"declined"}]}
        """
        XCTAssertTrue(try decode(GoogleEvent.self, json).isDeclinedBySelf)
    }

    func testDecodesAllDayEvent() throws {
        let json = """
        {
          "id": "allday1",
          "status": "confirmed",
          "summary": "DUE Team charter",
          "start": { "date": "2026-09-04" },
          "end":   { "date": "2026-09-05" }
        }
        """
        let event = try decode(GoogleEvent.self, json)
        XCTAssertTrue(event.start!.isAllDay)
        XCTAssertNil(event.end!.dateTime)
        let deadline = Fixture.builder().build(event: event, calendarEntry: Fixture.calendarEntry())!
        XCTAssertTrue(deadline.isAllDay)
    }

    func testDecodesCancelledInstanceOfARecurringSeries() throws {
        let json = """
        {"id":"abc_20260903T130000Z","status":"cancelled","recurringEventId":"abc",
         "originalStartTime":{"dateTime":"2026-09-03T09:00:00-04:00"}}
        """
        let event = try decode(GoogleEvent.self, json)
        XCTAssertTrue(event.isCancelled)
        XCTAssertNil(Fixture.builder().build(event: event, calendarEntry: Fixture.calendarEntry()))
    }

    func testDecodesColorsPayload() throws {
        let json = """
        {
          "kind": "calendar#colors",
          "updated": "2012-02-14T00:00:00.000Z",
          "calendar": { "1": { "background": "#ac725e", "foreground": "#1d1d1d" } },
          "event":    { "11": { "background": "#dc2127", "foreground": "#1d1d1d" } }
        }
        """
        let colors = try decode(GoogleColorsResponse.self, json)
        XCTAssertEqual(colors.calendar?["1"]?.background, "#ac725e")
        XCTAssertEqual(colors.event?["11"]?.background, "#dc2127")
    }

    func testDecodesErrorEnvelope() throws {
        let json = """
        {"error":{"code":403,"message":"Rate Limit Exceeded","status":"PERMISSION_DENIED",
          "errors":[{"domain":"usageLimits","reason":"rateLimitExceeded","message":"Rate Limit Exceeded"}]}}
        """
        let envelope = try decode(GoogleAPIErrorEnvelope.self, json)
        XCTAssertEqual(envelope.primaryReason, "rateLimitExceeded")
        XCTAssertEqual(envelope.message, "Rate Limit Exceeded")
    }

    func testUnknownFieldsAreIgnored() throws {
        let json = """
        {"id":"x","somethingBrandNew":{"nested":[1,2,3]},"summary":"DUE: thing"}
        """
        XCTAssertEqual(try decode(GoogleEvent.self, json).summary, "DUE: thing")
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let snapshot = DemoData.snapshot(now: Fixture.date(2026, 9, 2, 12), calendar: Fixture.calendar())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(CalendarSnapshot.self, from: encoder.encode(snapshot))
        XCTAssertEqual(restored.calendars.map(\.id), snapshot.calendars.map(\.id))
        XCTAssertEqual(restored.allEvents.count, snapshot.allEvents.count)
        XCTAssertEqual(restored.palette, snapshot.palette)
    }
}
