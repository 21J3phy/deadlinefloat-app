import XCTest
@testable import DeadlineFloat

final class GoogleDateTests: XCTestCase {
    func testParsesOffsetTimestamp() {
        let parsed = GoogleDate.timestamp(from: "2026-08-30T23:59:00-04:00")
        XCTAssertEqual(parsed, Fixture.date(2026, 8, 30, 23, 59, 0))
    }

    func testParsesZuluTimestamp() {
        let parsed = GoogleDate.timestamp(from: "2026-08-31T03:59:00Z")
        // 03:59 UTC is 23:59 the previous evening in Indianapolis during DST.
        XCTAssertEqual(parsed, Fixture.date(2026, 8, 30, 23, 59, 0))
    }

    func testParsesFractionalSeconds() {
        let withFraction = GoogleDate.timestamp(from: "2026-08-30T12:00:00.250Z")
        let withoutFraction = GoogleDate.timestamp(from: "2026-08-30T12:00:00Z")
        XCTAssertNotNil(withFraction)
        XCTAssertEqual(withFraction!.timeIntervalSince(withoutFraction!), 0.25, accuracy: 0.0001)
    }

    func testParsesCompactOffset() {
        XCTAssertEqual(
            GoogleDate.timestamp(from: "2026-08-30T23:59:00-0400"),
            GoogleDate.timestamp(from: "2026-08-30T23:59:00-04:00")
        )
    }

    func testParsesHalfHourOffset() {
        // Kolkata is +05:30 — a good check that minutes in the offset are used.
        let parsed = GoogleDate.timestamp(from: "2026-08-30T12:00:00+05:30")
        XCTAssertEqual(parsed, GoogleDate.timestamp(from: "2026-08-30T06:30:00Z"))
    }

    func testRejectsMalformedInput() {
        XCTAssertNil(GoogleDate.timestamp(from: ""))
        XCTAssertNil(GoogleDate.timestamp(from: "not a date"))
        XCTAssertNil(GoogleDate.timestamp(from: "2026-08-30"))
        XCTAssertNil(GoogleDate.timestamp(from: "2026/08/30T12:00:00Z"))
        XCTAssertNil(GoogleDate.timestamp(from: "2026-08-30T12:00:00%00:00"))
    }

    func testAllDayParsesToLocalMidnight() {
        let calendar = Fixture.calendar()
        let parsed = GoogleDate.allDayStart(from: "2026-08-30", calendar: calendar)
        XCTAssertEqual(parsed, Fixture.date(2026, 8, 30, 0, 0, 0))
    }

    func testAllDayFollowsTheCalendarTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let parsed = GoogleDate.allDayStart(from: "2026-08-30", calendar: Fixture.calendar(tokyo))
        XCTAssertEqual(parsed, Fixture.date(2026, 8, 30, 0, 0, 0, in: tokyo))
        XCTAssertNotEqual(parsed, Fixture.date(2026, 8, 30, 0, 0, 0))
    }

    func testAllDayRejectsMalformedInput() {
        XCTAssertNil(GoogleDate.allDayStart(from: "2026-08", calendar: Fixture.calendar()))
        XCTAssertNil(GoogleDate.allDayStart(from: "yyyy-mm-dd", calendar: Fixture.calendar()))
    }

    func testRFC3339StringIsUTCAndRoundTrips() {
        let date = Fixture.date(2026, 8, 30, 23, 59, 0)
        let text = GoogleDate.rfc3339String(from: date)
        XCTAssertTrue(text.hasSuffix("Z"), text)
        XCTAssertEqual(GoogleDate.timestamp(from: text), date)
    }

    func testMidnightAndNoonAreDistinct() {
        let midnight = GoogleDate.timestamp(from: "2026-08-30T00:00:00-04:00")!
        let noon = GoogleDate.timestamp(from: "2026-08-30T12:00:00-04:00")!
        XCTAssertEqual(noon.timeIntervalSince(midnight), 12 * 3600)
        XCTAssertEqual(midnight, Fixture.date(2026, 8, 30, 0, 0, 0))
        XCTAssertEqual(noon, Fixture.date(2026, 8, 30, 12, 0, 0))
    }

    func testInstantResolvesEitherShape() {
        let calendar = Fixture.calendar()
        XCTAssertEqual(
            GoogleDate.instant(from: GoogleEventDateTime(date: "2026-08-30"), calendar: calendar),
            Fixture.date(2026, 8, 30)
        )
        XCTAssertEqual(
            GoogleDate.instant(from: GoogleEventDateTime(dateTime: "2026-08-30T12:00:00-04:00"), calendar: calendar),
            Fixture.date(2026, 8, 30, 12)
        )
        XCTAssertNil(GoogleDate.instant(from: nil, calendar: calendar))
        XCTAssertNil(GoogleDate.instant(from: GoogleEventDateTime(), calendar: calendar))
    }
}
