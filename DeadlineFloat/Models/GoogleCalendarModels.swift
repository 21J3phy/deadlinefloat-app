import Foundation

// MARK: - calendarList

/// One entry from `GET /users/me/calendarList`.
struct GoogleCalendarListEntry: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var summary: String? = nil
    var summaryOverride: String? = nil
    var description: String? = nil
    var timeZone: String? = nil
    var colorId: String? = nil
    var backgroundColor: String? = nil
    var foregroundColor: String? = nil
    var selected: Bool? = nil
    var primary: Bool? = nil
    var accessRole: String? = nil
    var deleted: Bool? = nil
    var hidden: Bool? = nil

    /// What the user calls this calendar — their override wins, as it does in
    /// Google Calendar itself.
    var displayName: String {
        if let summaryOverride, !summaryOverride.isEmpty { return summaryOverride }
        if let summary, !summary.isEmpty { return summary }
        return id
    }

    var isVisibleCandidate: Bool {
        deleted != true && hidden != true
    }
}

struct GoogleCalendarListResponse: Codable, Sendable {
    var items: [GoogleCalendarListEntry]? = nil
    var nextPageToken: String? = nil
    var nextSyncToken: String? = nil
}

// MARK: - events

/// A Google `EventDateTime`: either an all-day `date` or a timestamped `dateTime`.
struct GoogleEventDateTime: Codable, Hashable, Sendable {
    var date: String? = nil
    var dateTime: String? = nil
    var timeZone: String? = nil

    var isAllDay: Bool { date != nil && dateTime == nil }
}

struct GoogleEventPerson: Codable, Hashable, Sendable {
    var email: String? = nil
    var displayName: String? = nil
    var this: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case email, displayName
        case this = "self"
    }
}

struct GoogleEventAttendee: Codable, Hashable, Sendable {
    var email: String? = nil
    var displayName: String? = nil
    var responseStatus: String? = nil
    var this: Bool? = nil
    var organizer: Bool? = nil
    var optional: Bool? = nil
    var resource: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case email, displayName, responseStatus, organizer, optional, resource
        case this = "self"
    }
}

struct GoogleConferenceEntryPoint: Codable, Hashable, Sendable {
    var entryPointType: String? = nil
    var uri: String? = nil
    var label: String? = nil
}

struct GoogleConferenceSolutionKey: Codable, Hashable, Sendable {
    var type: String? = nil
}

struct GoogleConferenceSolution: Codable, Hashable, Sendable {
    var name: String? = nil
    var key: GoogleConferenceSolutionKey? = nil
}

struct GoogleConferenceData: Codable, Hashable, Sendable {
    var conferenceId: String? = nil
    var conferenceSolution: GoogleConferenceSolution? = nil
    var entryPoints: [GoogleConferenceEntryPoint]? = nil
}

/// A single event *instance*.
///
/// The client always requests `singleEvents=true`, so recurring series arrive
/// already expanded: each instance carries its own `id` (`series_20260901T120000Z`),
/// `recurringEventId` and `originalStartTime`.
struct GoogleEvent: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var status: String? = nil
    var htmlLink: String? = nil
    var summary: String? = nil
    var description: String? = nil
    var location: String? = nil
    var colorId: String? = nil
    var start: GoogleEventDateTime? = nil
    var end: GoogleEventDateTime? = nil
    var endTimeUnspecified: Bool? = nil
    var recurringEventId: String? = nil
    var originalStartTime: GoogleEventDateTime? = nil
    var iCalUID: String? = nil
    var eventType: String? = nil
    var transparency: String? = nil
    var visibility: String? = nil
    var hangoutLink: String? = nil
    var conferenceData: GoogleConferenceData? = nil
    var attendees: [GoogleEventAttendee]? = nil
    var organizer: GoogleEventPerson? = nil
    var creator: GoogleEventPerson? = nil
    var updated: String? = nil
    var created: String? = nil

    var isCancelled: Bool { status?.lowercased() == "cancelled" }
    var isRecurringInstance: Bool { recurringEventId?.isEmpty == false }

    /// `true` when the signed-in user has declined this invitation.
    var isDeclinedBySelf: Bool {
        attendees?.contains { $0.this == true && $0.responseStatus?.lowercased() == "declined" } ?? false
    }

    /// A human-readable meeting platform derived from conference metadata.
    var conferencePlatform: String? {
        if let name = conferenceData?.conferenceSolution?.name, !name.isEmpty { return name }
        if hangoutLink?.isEmpty == false { return "Google Meet" }
        guard let uri = conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri,
              let host = URL(string: uri)?.host?.lowercased() else { return nil }
        if host.contains("zoom") { return "Zoom" }
        if host.contains("teams.microsoft") { return "Microsoft Teams" }
        if host.contains("meet.google") { return "Google Meet" }
        if host.contains("webex") { return "Webex" }
        return host
    }
}

struct GoogleEventsResponse: Codable, Sendable {
    var summary: String? = nil
    var timeZone: String? = nil
    var accessRole: String? = nil
    var items: [GoogleEvent]? = nil
    var nextPageToken: String? = nil
    var nextSyncToken: String? = nil
}

// MARK: - colors

struct GoogleColorDefinition: Codable, Hashable, Sendable {
    var background: String? = nil
    var foreground: String? = nil
}

/// Response of `GET /colors` — Google's authoritative palette.
struct GoogleColorsResponse: Codable, Hashable, Sendable {
    var updated: String? = nil
    var calendar: [String: GoogleColorDefinition]? = nil
    var event: [String: GoogleColorDefinition]? = nil
}

// MARK: - errors

/// Google's standard error envelope, used to distinguish rate limiting from
/// authentication failures.
struct GoogleAPIErrorEnvelope: Codable, Sendable {
    struct Detail: Codable, Sendable {
        var domain: String?
        var reason: String?
        var message: String?
    }

    struct Body: Codable, Sendable {
        var code: Int?
        var message: String?
        var errors: [Detail]?
        var status: String?
    }

    var error: Body? = nil

    var primaryReason: String? { error?.errors?.first?.reason ?? error?.status }
    var message: String? { error?.message }
}
