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
    static let pin = "pin"
    static let pinned = "pin.fill"

    // Urgency
    static let overdue = "exclamationmark.triangle.fill"
    static let imminent = "clock.badge.exclamationmark.fill"
    static let later = "calendar"

    // Row metadata and actions
    static let location = "mappin.and.ellipse"
    static let video = "video.fill"
    static let recurring = "arrow.triangle.2.circlepath"
    static let duplicate = "square.on.square"
    static let openExternally = "arrow.up.forward"
    static let copy = "doc.on.doc"
    static let done = "checkmark.circle.fill"
    static let restore = "arrow.uturn.backward.circle"

    // Status
    static let offline = "wifi.slash"
    static let rateLimited = "hourglass"
    static let expiredAuth = "key.slash"
    static let notSignedIn = "person.crop.circle.badge.questionmark"
    static let serverProblem = "exclamationmark.circle"
    static let allClear = "checkmark.circle"
    static let empty = "checkmark"
    static let stale = "clock.arrow.circlepath"

    // Settings
    static let general = "slider.horizontal.3"
    static let appearance = "paintbrush.fill"
    static let calendars = "calendar"
    static let keywords = "text.magnifyingglass"
    static let account = "person.crop.circle.fill"
    static let about = "info.circle.fill"
    static let add = "plus"
    static let remove = "minus"
    static let reset = "arrow.uturn.backward"
    static let textSize = "textformat.size"
    static let barWidth = "arrow.left.and.right"
    static let opacity = "circle.lefthalf.filled"
    static let launchAtLogin = "power"
    static let link = "link"
    static let spotlight = "sparkles"
    static let menuBar = "menubar.rectangle"
    static let chevronDown = "chevron.down"
    static let chevronRight = "chevron.right"
    static let safari = "safari"
    static let lock = "lock.fill"
    static let undo = "arrow.uturn.backward"
    static let editing = "hand.draw"

    static let all: [String] = [
        appMark, refresh, settings, hide, pin, pinned,
        overdue, imminent, later,
        location, video, recurring, duplicate, openExternally, copy, done, restore,
        offline, rateLimited, expiredAuth, notSignedIn, serverProblem, allClear, empty, stale,
        general, appearance, calendars, keywords, account, about,
        add, remove, reset, textSize, opacity, launchAtLogin, link,
        spotlight, menuBar, chevronDown, chevronRight, safari, lock, undo, editing
    ]
}
