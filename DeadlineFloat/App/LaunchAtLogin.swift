import Foundation
import ServiceManagement

/// "Launch at Login", backed by `SMAppService`.
///
/// The system owns the truth here — the login item can be turned off in System
/// Settings without the app being told — so the UI always reads `isEnabled`
/// rather than caching a preference of its own.
enum LaunchAtLogin {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    /// `true` when macOS has the login item but the user has disabled it in
    /// System Settings; the app should say so instead of silently failing.
    static var requiresApproval: Bool { status == .requiresApproval }

    static func set(_ enabled: Bool) throws {
        if enabled {
            guard !isEnabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard status != .notFound else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static var statusDescription: String {
        switch status {
        case .enabled: return "On"
        case .requiresApproval: return "Needs approval in System Settings"
        case .notRegistered: return "Off"
        case .notFound: return "Unavailable for this build"
        @unknown default: return "Unknown"
        }
    }
}
