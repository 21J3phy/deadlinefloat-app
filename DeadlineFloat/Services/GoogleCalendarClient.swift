import Foundation

/// Access to the Calendar v3 API: everything read, and one thing written.
///
/// Every method but `reschedule` issues a `GET`, and `reschedule` issues the
/// only `PATCH` `HTTPClient` will let through — one event's own URL, carrying
/// nothing but its new start and end. Anything else against
/// `www.googleapis.com` is refused there, so this type cannot be turned into a
/// general writer by accident.
struct GoogleCalendarClient: Sendable {
    var http: HTTPClient
    var accessTokenProvider: @Sendable () async throws -> String

    // MARK: - calendarList

    func calendarList(pageLimit: Int = 10) async throws -> [GoogleCalendarListEntry] {
        var entries: [GoogleCalendarListEntry] = []
        var pageToken: String?
        var page = 0

        repeat {
            var items = [
                URLQueryItem(name: "maxResults", value: "250"),
                URLQueryItem(name: "showHidden", value: "true"),
                URLQueryItem(name: "minAccessRole", value: "reader")
            ]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }

            let url = try Self.url(pathComponents: ["users", "me", "calendarList"], query: items)
            let response = try await http.get(url, accessToken: try await accessTokenProvider())
            let decoded = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: response.data)
            entries.append(contentsOf: decoded.items ?? [])
            pageToken = decoded.nextPageToken
            page += 1
        } while pageToken != nil && page < pageLimit

        return entries.filter(\.isVisibleCandidate)
    }

    // MARK: - colors

    func colors() async throws -> GoogleColorsResponse {
        let url = try Self.url(pathComponents: ["colors"], query: [])
        let response = try await http.get(url, accessToken: try await accessTokenProvider())
        return try JSONDecoder().decode(GoogleColorsResponse.self, from: response.data)
    }

    // MARK: - events

    /// Instances of every event that overlaps `window`.
    ///
    /// `singleEvents=true` is what makes recurrence correct: Google expands each
    /// series into concrete instances in the requested range, applying exceptions
    /// and moved occurrences, and each instance carries the right local time
    /// across daylight-saving boundaries. `orderBy=startTime` is only valid with
    /// `singleEvents`, which is why both are always sent together.
    func events(
        calendarID: String,
        window: DateWindow,
        pageLimit: Int = 10
    ) async throws -> [GoogleEvent] {
        var collected: [GoogleEvent] = []
        var pageToken: String?
        var page = 0

        repeat {
            var items = [
                URLQueryItem(name: "timeMin", value: GoogleDate.rfc3339String(from: window.queryStart)),
                URLQueryItem(name: "timeMax", value: GoogleDate.rfc3339String(from: window.queryEnd)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "showDeleted", value: "false"),
                URLQueryItem(name: "maxResults", value: "250"),
                URLQueryItem(name: "timeZone", value: window.timeZone.identifier)
            ]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }

            let url = try Self.url(pathComponents: ["calendars", calendarID, "events"], query: items)
            let response = try await http.get(url, accessToken: try await accessTokenProvider())
            let decoded = try JSONDecoder().decode(GoogleEventsResponse.self, from: response.data)
            collected.append(contentsOf: decoded.items ?? [])
            pageToken = decoded.nextPageToken
            page += 1
        } while pageToken != nil && page < pageLimit

        return collected
    }

    // MARK: - Moving an event

    /// Writes an event's new start and end, and returns the event as Google
    /// now holds it.
    ///
    /// `PATCH` rather than `PUT`: only the two times are sent, so nothing else
    /// on the event — its guests, its description, its colour — can be lost by
    /// writing back a copy this app assembled. `sendUpdates=none` keeps a nudge
    /// on one's own calendar from mailing everybody invited; a change that
    /// guests should hear about is one to make in Google Calendar itself.
    ///
    /// A recurring event arrives here already expanded, so the id is one
    /// instance's and only that instance moves — the same thing Google
    /// Calendar does when you drag one occurrence of a series.
    @discardableResult
    func reschedule(
        calendarID: String,
        eventID: String,
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) async throws -> GoogleEvent {
        let url = try Self.url(
            pathComponents: ["calendars", calendarID, "events", eventID],
            query: [URLQueryItem(name: "sendUpdates", value: "none")]
        )
        let body = try JSONEncoder().encode(
            EventTimesPatch(
                start: GoogleEventDateTime(
                    dateTime: GoogleDate.rfc3339String(from: start, timeZone: timeZone),
                    timeZone: timeZone.identifier
                ),
                end: GoogleEventDateTime(
                    dateTime: GoogleDate.rfc3339String(from: end, timeZone: timeZone),
                    timeZone: timeZone.identifier
                )
            )
        )
        let response = try await http.patchJSON(url, accessToken: try await accessTokenProvider(), body: body)
        return try JSONDecoder().decode(GoogleEvent.self, from: response.data)
    }

    /// The whole body of the only write the app makes.
    private struct EventTimesPatch: Encodable {
        var start: GoogleEventDateTime
        var end: GoogleEventDateTime
    }

    // MARK: - URL building

    static func url(pathComponents: [String], query: [URLQueryItem]) throws -> URL {
        var url = GoogleEndpoints.apiBase
        for component in pathComponents {
            url.appendPathComponent(component)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let final = components.url else { throw APIError.invalidResponse }
        return final
    }
}
