import AppKit
import SwiftUI

/// Hosts the settings window. Managed directly rather than through SwiftUI's
/// `Settings` scene so the app can stay a menu-bar accessory and still open
/// settings from the status menu, the keyboard and the panel header.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let viewModel: DeadlineListViewModel
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(viewModel: DeadlineListViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    /// - Parameter pane: which pane to land on. `nil` leaves whichever pane the
    ///   user was last looking at.
    func show(pane: SettingsView.Pane? = nil) {
        if let pane { navigation.pane = pane }
        let window = makeWindowIfNeeded()
        // Settings needs real focus, so this is the one place the app activates.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center(ifNeverPositioned: true)
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let window { return window }

        let hosting = NSHostingController(rootView: SettingsView(viewModel: viewModel, navigation: navigation))
        let window = NSWindow(contentViewController: hosting)
        window.title = "DeadlineFloat Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.setFrameAutosaveName("DeadlineFloatSettings")
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.fullScreenNone, .moveToActiveSpace]

        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Drop back to accessory behaviour when settings closes, unless the user
        // asked for a Dock icon.
        if !viewModel.preferences.showInDock, NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private extension NSWindow {
    /// Centres the window the first time it appears; later openings keep the
    /// position the user left it in.
    func center(ifNeverPositioned: Bool) {
        guard ifNeverPositioned, frame.origin == .zero else { return }
        center()
    }
}
