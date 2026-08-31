import Foundation

/// Read-only access to the Calendar v3 API.
///
/// Every method here issues a `GET`; `HTTPClient` rejects anything else against
/// `www.googleapis.com`, so this type cannot be turned into a writer by accident.
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
