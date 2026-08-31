import AppKit

/// The menu-bar item: left-click toggles the window, right-click opens a menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let onToggleWindow: () -> Void
    private let onRefresh: () -> Void
    private let onOpenSettings: () -> Void
    private let onResetPosition: () -> Void
    private let isWindowVisible: () -> Bool

    init(
        onToggleWindow: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onResetPosition: @escaping () -> Void,
        isWindowVisible: @escaping () -> Bool
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onToggleWindow = onToggleWindow
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        self.onResetPosition = onResetPosition
        self.isWindowVisible = isWindowVisible
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: Symbols.appMark,
                accessibilityDescription: "DeadlineFloat"
            )
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "DeadlineFloat — click to show or hide the window"
        }
    }

    /// Called when the app is shutting down. The status item otherwise lives for
    /// the whole session, so there is nothing to tear down in `deinit`.
    func removeFromMenuBar() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Shows the overdue count beside the icon when there is one, and nothing
    /// otherwise — the menu bar stays quiet when you are on top of things.
    func update(overdueCount: Int) {
        guard let button = statusItem.button else { return }
        button.title = overdueCount > 0 ? " \(overdueCount)" : ""
        button.toolTip = overdueCount > 0
            ? "DeadlineFloat — \(overdueCount) overdue"
            : "DeadlineFloat — click to show or hide the window"
    }

    // MARK: - Actions

    @objc private func handleClick() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true

        if isRightClick {
            presentMenu()
        } else {
            onToggleWindow()
        }
    }

    private func presentMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let toggle = NSMenuItem(
            title: isWindowVisible() ? "Hide Window" : "Show Window",
            action: #selector(menuToggleWindow),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(menuRefresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let reset = NSMenuItem(title: "Reset Window Position", action: #selector(menuResetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        let settings = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let launch = NSMenuItem(title: "Launch at Login", action: #selector(menuToggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = LaunchAtLogin.isEnabled ? .on : .off
        launch.isEnabled = LaunchAtLogin.status != .notFound
        menu.addItem(launch)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit DeadlineFloat", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuToggleWindow() { onToggleWindow() }
    @objc private func menuRefresh() { onRefresh() }
    @objc private func menuSettings() { onOpenSettings() }
    @objc private func menuResetPosition() { onResetPosition() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func menuToggleLaunchAtLogin() {
        try? LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
    }
}
