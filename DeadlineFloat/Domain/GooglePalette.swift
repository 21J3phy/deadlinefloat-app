import Foundation

/// Google Calendar's palettes.
///
/// The Calendar API still reports its original 2010 palette — Tomato as
/// `#dc2127`, Basil as `#16a765` — and so does `GET /colors`. Google Calendar
/// itself has drawn the newer Material palette since 2018: Tomato is
/// `#D50000`, Basil `#0B8043`. To look the same as the calendar the user is
/// looking at, every preset colour is mapped to the colour Google Calendar
/// shows, by id when one is given and by hex otherwise. A colour that is not
/// a preset — one the user picked themselves — is used exactly as reported.
enum GooglePalette {
    // MARK: - What Google Calendar shows

    /// Event colour ids 1–11 ("Lavender" … "Tomato"), as Google Calendar draws them.
    static let eventBackgrounds: [String: String] = [
        "1": "#7986cb",  // Lavender
        "2": "#33b679",  // Sage
        "3": "#8e24aa",  // Grape
        "4": "#e67c73",  // Flamingo
        "5": "#f6bf26",  // Banana
        "6": "#f4511e",  // Tangerine
        "7": "#039be5",  // Peacock
        "8": "#616161",  // Graphite
        "9": "#3f51b5",  // Blueberry
        "10": "#0b8043", // Basil
        "11": "#d50000"  // Tomato
    ]

    /// Calendar colour ids 1–24, as Google Calendar draws them.
    static let calendarBackgrounds: [String: String] = [
        "1": "#795548",  // Cocoa
        "2": "#e67c73",  // Flamingo
        "3": "#d50000",  // Tomato
        "4": "#f4511e",  // Tangerine
        "5": "#ef6c00",  // Pumpkin
        "6": "#f09300",  // Mango
        "7": "#009688",  // Eucalyptus
        "8": "#0b8043",  // Basil
        "9": "#7cb342",  // Pistachio
        "10": "#c0ca33", // Avocado
        "11": "#e4c441", // Citron
        "12": "#f6bf26", // Banana
        "13": "#33b679", // Sage
        "14": "#039be5", // Peacock
        "15": "#4285f4", // Cobalt
        "16": "#3f51b5", // Blueberry
        "17": "#7986cb", // Lavender
        "18": "#b39ddb", // Wisteria
        "19": "#616161", // Graphite
        "20": "#a79b8e", // Birch
        "21": "#ad1457", // Radicchio
        "22": "#d81b60", // Cherry Blossom
        "23": "#8e24aa", // Grape
        "24": "#9e69af"  // Amethyst
    ]

    // MARK: - What the API reports

    /// The API's event palette, by id — the values `GET /colors` returns.
    static let apiEventBackgrounds: [String: String] = [
        "1": "#a4bdfc", "2": "#7ae7bf", "3": "#dbadff", "4": "#ff887c",
        "5": "#fbd75b", "6": "#ffb878", "7": "#46d6db", "8": "#e1e1e1",
        "9": "#5484ed", "10": "#51b749", "11": "#dc2127"
    ]

    /// The API's calendar palette, by id.
    static let apiCalendarBackgrounds: [String: String] = [
        "1": "#ac725e", "2": "#d06b64", "3": "#f83a22", "4": "#fa573c",
        "5": "#ff7537", "6": "#ffad46", "7": "#42d692", "8": "#16a765",
        "9": "#7bd148", "10": "#b3dc6c", "11": "#fbe983", "12": "#fad165",
        "13": "#92e1c0", "14": "#9fe1e7", "15": "#9fc6e7", "16": "#4986e7",
        "17": "#9a9cff", "18": "#b99aff", "19": "#c2c2c2", "20": "#cabdbf",
        "21": "#cca6ac", "22": "#f691b2", "23": "#cd74e6", "24": "#a47ae2"
    ]

    /// API hex (lowercased, with `#`) → the colour Google Calendar shows.
    static let displayColorByAPIHex: [String: String] = {
        var map: [String: String] = [:]
        for (id, hex) in apiCalendarBackgrounds {
            if let shown = calendarBackgrounds[id] { map[hex.lowercased()] = shown }
        }
        for (id, hex) in apiEventBackgrounds {
            if let shown = eventBackgrounds[id] { map[hex.lowercased()] = shown }
        }
        return map
    }()

    /// Used only when nothing else is known.
    static let fallback = RGBColor(hex: "#4285f4") ?? RGBColor(red: 0.26, green: 0.52, blue: 0.96)

    static func eventColor(id: String) -> RGBColor? {
        eventBackgrounds[id].flatMap(RGBColor.init(hex:))
    }

    static func calendarColor(id: String) -> RGBColor? {
        calendarBackgrounds[id].flatMap(RGBColor.init(hex:))
    }

    /// The colour to draw for a hex the API reported: the preset's Google
    /// Calendar colour if it is one, otherwise the hex itself.
    static func displayColor(forAPIHex hex: String) -> RGBColor? {
        let key = hex.hasPrefix("#") ? hex.lowercased() : "#" + hex.lowercased()
        if let shown = displayColorByAPIHex[key] { return RGBColor(hex: shown) }
        return RGBColor(hex: hex)
    }
}
