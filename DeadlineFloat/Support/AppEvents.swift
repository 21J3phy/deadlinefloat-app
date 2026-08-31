import Foundation

extension Notification.Name {
    /// Posted when a preference that the AppKit layer owns changes — window
    /// opacity, floating level, Dock visibility — so the panel can apply it
    /// without the settings view knowing about `NSPanel`.
    static let windowPreferencesChanged = Notification.Name("DeadlineFloat.windowPreferencesChanged")
    /// Posted to bring the panel forward (menu bar item, keyboard shortcut).
    static let showFloatingPanel = Notification.Name("DeadlineFloat.showFloatingPanel")
}

enum AppEvents {
    static func windowPreferencesChanged() {
        NotificationCenter.default.post(name: .windowPreferencesChanged, object: nil)
    }
}
