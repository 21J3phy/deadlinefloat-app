import Foundation

/// Fabricated deadlines used by `--demo` and by the screenshot renderer.
///
/// Nothing here touches the network, the keychain or a Google account, so the
/// interface can be exercised — and captured for the README — on a machine with
/// no credentials configured.
enum DemoData {
    static func snapshot(now: Date, calendar: Calendar) -> CalendarSnapshot {
        let courses = GoogleCalendarListEntry(
            id: "cs18000@group.calendar.google.com",
            summary: "CS 18000",
            colorId: "16",
            backgroundColor: "#4986e7",
            selected: true,
            accessRole: "reader"
        )
        let math = GoogleCalendarListEntry(
            id: "math26500@group.calendar.google.com",
            summary: "MATH 26500",
            colorId: "3",
            backgroundColor: "#f83a22",
            selected: true,
            accessRole: "reader"
        )
        let engineering = GoogleCalendarListEntry(
            id: "engr133@group.calendar.google.com",
            summary: "ENGR 133",
            colorId: "8",
            backgroundColor: "#16a765",
            selected: true,
            accessRole: "reader"
        )
        let personal = GoogleCalendarListEntry(
            id: "demo@deadlinefloat.app",
            summary: "Personal",
            colorId: "24",
            backgroundColor: "#a47ae2",
            selected: true,
            primary: true,
            accessRole: "owner"
        )

        func timed(
            _ id: String,
            _ title: String,
            offset: TimeInterval,
            duration: TimeInterval = 1_800,
            location: String? = nil,
            colorId: String? = nil,
            recurringID: String? = nil
        ) -> GoogleEvent {
            let start = now.addingTimeInterval(offset)
            return GoogleEvent(
                id: id,
                status: "confirmed",
                htmlLink: "https://calendar.google.com/calendar/event?eid=\(id)",
                summary: title,
                location: location,
                colorId: colorId,
                start: GoogleEventDateTime(dateTime: GoogleDate.rfc3339String(from: start)),
                end: GoogleEventDateTime(dateTime: GoogleDate.rfc3339String(from: start.addingTimeInterval(duration))),
                recurringEventId: recurringID,
                iCalUID: "\(id)@demo"
            )
        }

        func allDay(_ id: String, _ title: String, dayOffset: Int, spanDays: Int = 1) -> GoogleEvent {
            let day = calendar.startOfDay(for: now).adding(days: dayOffset, calendar: calendar)
            let end = day.adding(days: spanDays, calendar: calendar)
            return GoogleEvent(
                id: id,
                status: "confirmed",
                htmlLink: "https://calendar.google.com/calendar/event?eid=\(id)",
                summary: title,
                start: GoogleEventDateTime(date: dayString(day, calendar: calendar)),
                end: GoogleEventDateTime(date: dayString(end, calendar: calendar)),
                iCalUID: "\(id)@demo"
            )
        }

        /// At a wall-clock time on a given day — a lecture, or the classic
        /// 11:59 PM submission. Deadlines are a quarter of an hour; classes
        /// and meetings say how long they run.
        func tonight(_ id: String, _ title: String, hour: Int, minute: Int, dayOffset: Int, minutes: Int = 15, location: String? = nil, colorId: String? = nil) -> GoogleEvent {
            let day = calendar.startOfDay(for: now).adding(days: dayOffset, calendar: calendar)
            let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            return GoogleEvent(
                id: id,
                status: "confirmed",
                htmlLink: "https://calendar.google.com/calendar/event?eid=\(id)",
                summary: title,
                location: location,
                colorId: colorId,
                start: GoogleEventDateTime(dateTime: GoogleDate.rfc3339String(from: start)),
                end: GoogleEventDateTime(dateTime: GoogleDate.rfc3339String(from: start.addingTimeInterval(TimeInterval(minutes * 60)))),
                iCalUID: "\(id)@demo"
            )
        }

        let mathEvents = [
            timed("m1", "DUE: Homework 7 — Eigenvalues", offset: -2 * 3600 - 14 * 60),
            tonight("m0", "MATH 26500 lecture", hour: 9, minute: 30, dayOffset: 0, minutes: 50, location: "WALC 1055"),
            tonight("m3", "MATH 26500 lecture", hour: 9, minute: 30, dayOffset: 1, minutes: 50, location: "WALC 1055"),
            tonight("m2", "MATH 26500 quiz due", hour: 23, minute: 59, dayOffset: 1)
        ]

        let csEvents = [
            tonight("c0", "CS 18000 lab", hour: 11, minute: 30, dayOffset: 0, minutes: 110, location: "LWSN B146"),
            tonight("c4", "CS 18000 lecture", hour: 14, minute: 30, dayOffset: 1, minutes: 50, location: "LILY 1105"),
            timed("c1", "SUBMIT Project 3 — Recursion", offset: 2 * 3600 + 14 * 60, location: "Vocareum", colorId: "11"),
            timed("c2", "Lab 09 deadline", offset: 5 * 3600 + 40 * 60, location: "Zoom"),
            timed("c3", "Weekly reading due", offset: 26 * 3600, recurringID: "weekly-reading")
        ]

        let engineeringEvents = [
            tonight("e0", "ENGR 133 studio", hour: 13, minute: 30, dayOffset: 0, minutes: 110, location: "ARMS B071"),
            tonight("e1", "ENGR 133 report due", hour: 17, minute: 0, dayOffset: 0, location: "Brightspace"),
            allDay("e2", "DUE Team charter", dayOffset: 2)
        ]

        let personalEvents = [
            tonight("p0", "Team meeting", hour: 18, minute: 0, dayOffset: 0, minutes: 60, location: "Zoom"),
            timed("p1", "Scholarship application deadline", offset: 7 * 3600 + 5 * 60, colorId: "6"),
            allDay("p2", "Submit passport renewal", dayOffset: 1, spanDays: 2),
            timed("p3", "DONE Renew library books", offset: 3 * 3600),
            tonight("p4", "Gym", hour: 20, minute: 30, dayOffset: 0, minutes: 75),
            tonight("p5", "Dinner", hour: 19, minute: 0, dayOffset: 1, minutes: 90)
        ]

        return CalendarSnapshot(
            calendars: [personal, courses, math, engineering],
            perCalendarEvents: [
                CalendarEvents(calendar: math, events: mathEvents),
                CalendarEvents(calendar: courses, events: csEvents),
                CalendarEvents(calendar: engineering, events: engineeringEvents),
                CalendarEvents(calendar: personal, events: personalEvents)
            ],
            palette: palette,
            paletteFetchedAt: now,
            fetchedAt: now
        )
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    /// What `GET /colors` really returns, so demo colours go through the same
    /// translation the live app applies.
    static let palette = GoogleColorsResponse(
        updated: "2026-01-01T00:00:00.000Z",
        calendar: GooglePalette.apiCalendarBackgrounds.mapValues { GoogleColorDefinition(background: $0, foreground: "#1d1d1d") },
        event: GooglePalette.apiEventBackgrounds.mapValues { GoogleColorDefinition(background: $0, foreground: "#1d1d1d") }
    )
}
