import Foundation

/// Google Calendar's built-in palettes.
///
/// The app always prefers the live `GET /colors` response; this table only
/// covers the first launch while offline, or an id the cached palette has never
/// seen. Values match Google Calendar's published colour ids.
enum GooglePalette {
    /// Event colour ids 1–11 ("Lavender" … "Tomato").
    static let eventBackgrounds: [String: String] = [
        "1": "#a4bdfc",  // Lavender
        "2": "#7ae7bf",  // Sage
        "3": "#dbadff",  // Grape
        "4": "#ff887c",  // Flamingo
        "5": "#fbd75b",  // Banana
        "6": "#ffb878",  // Tangerine
        "7": "#46d6db",  // Peacock
        "8": "#e1e1e1",  // Graphite
        "9": "#5484ed",  // Blueberry
        "10": "#51b749", // Basil
        "11": "#dc2127"  // Tomato
    ]

    /// Calendar colour ids 1–24.
    static let calendarBackgrounds: [String: String] = [
        "1": "#ac725e", "2": "#d06b64", "3": "#f83a22", "4": "#fa573c",
        "5": "#ff7537", "6": "#ffad46", "7": "#42d692", "8": "#16a765",
        "9": "#7bd148", "10": "#b3dc6c", "11": "#fbe983", "12": "#fad165",
        "13": "#92e1c0", "14": "#9fe1e7", "15": "#9fc6e7", "16": "#4986e7",
        "17": "#9a9cff", "18": "#b99aff", "19": "#c2c2c2", "20": "#cabdbf",
        "21": "#cca6ac", "22": "#f691b2", "23": "#cd74e6", "24": "#a47ae2"
    ]

    /// Used only when nothing else is known.
    static let fallback = RGBColor(hex: "#4986e7") ?? RGBColor(red: 0.28, green: 0.53, blue: 0.91)

    static func eventColor(id: String) -> RGBColor? {
        eventBackgrounds[id].flatMap(RGBColor.init(hex:))
    }

    static func calendarColor(id: String) -> RGBColor? {
        calendarBackgrounds[id].flatMap(RGBColor.init(hex:))
    }
}
