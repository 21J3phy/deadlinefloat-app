import Foundation

/// Resolves the exact Google Calendar colour for an event.
///
/// Order, matching Google Calendar itself:
/// 1. the event's own `colorId`, looked up in the live **event** palette;
/// 2. the parent calendar's `backgroundColor`, or its `colorId` in the live
///    **calendar** palette;
/// 3. Google's published default palettes;
/// 4. a neutral blue.
///
/// Urgency never changes the answer — it is expressed with icons, text and an
/// extra border so the Google colour survives intact.
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
            if let hex = palette?.event?[colorId]?.background, let color = RGBColor(hex: hex) {
                return Resolution(color: color, source: .event)
            }
            if let color = GooglePalette.eventColor(id: colorId) {
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
        if let hex = entry.backgroundColor, let color = RGBColor(hex: hex) { return color }
        if let colorId = entry.colorId, !colorId.isEmpty {
            if let hex = palette?.calendar?[colorId]?.background, let color = RGBColor(hex: hex) {
                return color
            }
            if let color = GooglePalette.calendarColor(id: colorId) { return color }
        }
        return nil
    }

    /// True when the cached palette cannot explain a colour id that just arrived,
    /// which is the app's cue to re-fetch `GET /colors`.
    func needsPaletteRefresh(events: [GoogleEvent], calendars: [GoogleCalendarListEntry]) -> Bool {
        guard let palette else { return true }

        for event in events {
            guard let colorId = event.colorId, !colorId.isEmpty else { continue }
            if palette.event?[colorId] == nil { return true }
        }
        for entry in calendars {
            guard entry.backgroundColor == nil,
                  let colorId = entry.colorId, !colorId.isEmpty else { continue }
            if palette.calendar?[colorId] == nil { return true }
        }
        return false
    }
}
