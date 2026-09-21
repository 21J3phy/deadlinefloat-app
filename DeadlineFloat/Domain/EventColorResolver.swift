import Foundation

/// Resolves the colour Google Calendar would show for an event.
///
/// Order, matching Google Calendar itself:
/// 1. the event's own `colorId`;
/// 2. the parent calendar's `colorId`, or its `backgroundColor`;
/// 3. a neutral blue.
///
/// Every preset is translated from the palette the API reports to the one
/// Google Calendar draws (see `GooglePalette`), so a Tomato event here is the
/// same Tomato as in the browser. A calendar with a custom colour keeps it.
/// The live `GET /colors` response is consulted only for an id neither table
/// knows, so a colour Google adds later still resolves to something.
///
/// Urgency never changes the answer — it is expressed with text, so the
/// Google colour survives intact.
struct EventColorResolver: Sendable {
    let palette: GoogleColorsResponse?

    init(palette: GoogleColorsResponse?) {
        self.palette = palette
    }

    struct Resolution: Hashable, Sendable {
        var color: RGBColor
        var source: ColorSource
    }

    func resolve(event: GoogleEvent, calendarEntry: GoogleCalendarListEntry?) -> Resolution {
        if let colorId = event.colorId, !colorId.isEmpty {
            if let color = GooglePalette.eventColor(id: colorId) {
                return Resolution(color: color, source: .event)
            }
            if let hex = palette?.event?[colorId]?.background, let color = GooglePalette.displayColor(forAPIHex: hex) {
                return Resolution(color: color, source: .event)
            }
        }

        if let calendarEntry, let color = calendarColorIfKnown(calendarEntry) {
            return Resolution(color: color, source: .calendar)
        }

        return Resolution(color: GooglePalette.fallback, source: .fallback)
    }

    /// The colour shown next to a calendar in Settings.
    func calendarColor(_ entry: GoogleCalendarListEntry) -> RGBColor {
        calendarColorIfKnown(entry) ?? GooglePalette.fallback
    }

    private func calendarColorIfKnown(_ entry: GoogleCalendarListEntry) -> RGBColor? {
        if let colorId = entry.colorId, !colorId.isEmpty {
            if let color = GooglePalette.calendarColor(id: colorId) { return color }
            if let hex = palette?.calendar?[colorId]?.background, let color = GooglePalette.displayColor(forAPIHex: hex) {
                return color
            }
        }
        if let hex = entry.backgroundColor, let color = GooglePalette.displayColor(forAPIHex: hex) { return color }
        return nil
    }

    /// True when the cached palette cannot explain a colour id neither built-in
    /// table knows, which is the app's cue to re-fetch `GET /colors`.
    func needsPaletteRefresh(events: [GoogleEvent], calendars: [GoogleCalendarListEntry]) -> Bool {
        for event in events {
            guard let colorId = event.colorId, !colorId.isEmpty, GooglePalette.eventColor(id: colorId) == nil else { continue }
            if palette?.event?[colorId] == nil { return true }
        }
        for entry in calendars {
            guard let colorId = entry.colorId, !colorId.isEmpty, GooglePalette.calendarColor(id: colorId) == nil else { continue }
            if palette?.calendar?[colorId] == nil { return true }
        }
        return false
    }
}
