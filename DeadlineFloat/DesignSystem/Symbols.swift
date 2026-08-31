import Foundation

/// Every SF Symbol the app draws, in one list.
///
/// `SymbolAvailabilityTests` walks `all` and fails if any name does not resolve
/// on the deployment target, so a typo or a symbol that is newer than macOS 14
/// is caught by the test suite rather than by an empty box in the window.
enum Symbols {
    // Header and chrome
    static let appMark = "hourglass"
    static let refresh = "arrow.clockwise"
    static let settings = "gearshape"
    static let hide = "xmark"
    static let compact = "rectangle.compress.vertical"
    static let expand = "rectangle.expand.vertical"

    // Urgency
    static let overdue = "exclamationmark.triangle.fill"
    static let imminent = "clock.badge.exclamationmark.fill"
    static let later = "calendar"

    // Row metadata
    static let location = "mappin.and.ellipse"
    static let video = "video.fill"
    static let recurring = "arrow.triangle.2.circlepath"
    static let duplicate = "square.on.square"
    static let openExternally = "arrow.up.forward.app"

    // Status
    static let offline = "wifi.slash"
    static let rateLimited = "hourglass"
    static let expiredAuth = "key.slash"
    static let notSignedIn = "person.crop.circle.badge.questionmark"
    static let serverProblem = "exclamationmark.circle"
    static let allClear = "checkmark.circle"
    static let empty = "checkmark.seal"

    // Settings
    static let general = "slider.horizontal.3"
    static let appearance = "paintbrush"
    static let calendars = "calendar.badge.clock"
    static let keywords = "text.magnifyingglass"
    static let account = "person.crop.circle"
    static let about = "info.circle"
    static let add = "plus"
    static let remove = "minus"
    static let reset = "arrow.uturn.backward"
    static let textSize = "textformat.size"
    static let opacity = "circle.lefthalf.filled"
    static let launchAtLogin = "power"
    static let link = "link"

    static let all: [String] = [
        appMark, refresh, settings, hide, compact, expand,
        overdue, imminent, later,
        location, video, recurring, duplicate, openExternally,
        offline, rateLimited, expiredAuth, notSignedIn, serverProblem, allClear, empty,
        general, appearance, calendars, keywords, account, about,
        add, remove, reset, textSize, opacity, launchAtLogin, link
    ]
}
