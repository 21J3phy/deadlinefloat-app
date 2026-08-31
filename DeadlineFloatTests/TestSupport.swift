import Foundation
@testable import DeadlineFloat

/// Shared fixtures. Everything is pinned to `America/Indiana/Indianapolis` and an
/// explicit `en_US` locale so results never depend on the machine running them.
enum Fixture {
    static let indianapolis = TimeZone(identifier: "America/Indiana/Indianapolis")!
    static let locale = Locale(identifier: "en_US")

    static func calendar(_ timeZone: TimeZone = indianapolis) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }

    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        in timeZone: TimeZone = indianapolis
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar(timeZone).date(from: components)!
    }

    /// Replaces the narrow no-break space ICU puts before AM/PM (and any other
    /// non-breaking space) with an ordinary one, so expectations stay readable.
    static func plain(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// `2026-09-01` style string for an all-day `EventDateTime`.
    static func dayString(_ year: Int, _ month: Int, _ day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func calendarEntry(
        id: String = "primary@example.com",
        name: String = "Personal",
        background: String? = "#5484ed",
        colorId: String? = nil,
        primary: Bool = false,
        selected: Bool = true
    ) -> GoogleCalendarListEntry {
        GoogleCalendarListEntry(
            id: id,
            summary: name,
            colorId: colorId,
            backgroundColor: background,
            selected: selected,
            primary: primary,
            accessRole: "owner"
        )
    }

    /// A timed event whose start is expressed in Indianapolis local time.
    static func timedEvent(
        id: String = "e1",
        title: String = "DUE: Homework",
        start: Date,
        durationMinutes: Int = 30,
        colorId: String? = nil,
        location: String? = nil,
        recurringEventId: String? = nil,
        iCalUID: String? = nil,
        attendees: [GoogleEventAttendee]? = nil,
        status: String = "confirmed"
    ) -> GoogleEvent {
        GoogleEvent(
            id: id,
            status: status,
            htmlLink: "https://calendar.google.com/calendar/event?eid=\(id)",
            summary: title,
            location: location,
            colorId: colorId,
            start: GoogleEventDateTime(dateTime: GoogleDate.rfc3339String(from: start)),
            end: GoogleEventDateTime(dateTime: GoogleDate.rfc3339String(from: start.addingTimeInterval(TimeInterval(durationMinutes * 60)))),
            recurringEventId: recurringEventId,
            iCalUID: iCalUID,
            attendees: attendees
        )
    }

    static func allDayEvent(
        id: String = "a1",
        title: String = "DUE Reading",
        startDay: String,
        endDayExclusive: String,
        colorId: String? = nil,
        iCalUID: String? = nil
    ) -> GoogleEvent {
        GoogleEvent(
            id: id,
            status: "confirmed",
            htmlLink: "https://calendar.google.com/calendar/event?eid=\(id)",
            summary: title,
            colorId: colorId,
            start: GoogleEventDateTime(date: startDay),
            end: GoogleEventDateTime(date: endDayExclusive),
            iCalUID: iCalUID
        )
    }

    static func snapshot(
        calendars: [GoogleCalendarListEntry],
        events: [(GoogleCalendarListEntry, [GoogleEvent])],
        palette: GoogleColorsResponse? = DemoData.palette,
        fetchedAt: Date = Date()
    ) -> CalendarSnapshot {
        CalendarSnapshot(
            calendars: calendars,
            perCalendarEvents: events.map { CalendarEvents(calendar: $0.0, events: $0.1) },
            palette: palette,
            paletteFetchedAt: fetchedAt,
            fetchedAt: fetchedAt
        )
    }

    static func builder(
        configuration: FilterConfiguration = .default,
        palette: GoogleColorsResponse? = DemoData.palette,
        timeZone: TimeZone = indianapolis
    ) -> DeadlineBuilder {
        DeadlineBuilder(
            calendar: calendar(timeZone),
            detector: DeadlineDetector(configuration: configuration),
            colorResolver: EventColorResolver(palette: palette)
        )
    }
}

/// Scriptable stand-in for `URLSession`.
final class FakeTransport: HTTPPerforming, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest, Int) throws -> (Data, HTTPURLResponse)

    private let handler: Handler
    private let lock = NSLock()
    private var _requests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    var callCount: Int { requests.count }

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Always answers with the same status and body.
    convenience init(status: Int, json: String, headers: [String: String] = [:]) {
        self.init { request, _ in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            return (Data(json.utf8), response)
        }
    }

    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let index = record(request)
        let (data, response) = try handler(request, index)
        return (data, response)
    }

    /// Kept out of the async method so the lock is never taken across a suspension.
    private func record(_ request: URLRequest) -> Int {
        lock.lock(); defer { lock.unlock() }
        _requests.append(request)
        return _requests.count - 1
    }
}

extension HTTPClient {
    /// A client that never really sleeps and has no jitter, so backoff is
    /// deterministic in tests.
    static func testing(
        transport: HTTPPerforming,
        retryPolicy: RetryPolicy = RetryPolicy(),
        recordedSleeps: SleepRecorder? = nil
    ) -> HTTPClient {
        HTTPClient(
            transport: transport,
            retryPolicy: retryPolicy,
            sleeper: { seconds in recordedSleeps?.record(seconds) },
            jitterProvider: { 0.5 }
        )
    }
}

final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [TimeInterval] = []

    var values: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return _values
    }

    func record(_ value: TimeInterval) {
        lock.lock(); _values.append(value); lock.unlock()
    }
}
