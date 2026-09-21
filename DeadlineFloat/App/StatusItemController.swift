import AppKit

/// The menu-bar item: left-click drops the panel down, right-click opens a menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let onTogglePanel: () -> Void
    private let onRefresh: () -> Void
    private let onOpenSettings: () -> Void
    private let isPanelVisible: () -> Bool

    init(
        onTogglePanel: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        isPanelVisible: @escaping () -> Bool
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onTogglePanel = onTogglePanel
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        self.isPanelVisible = isPanelVisible
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
            button.toolTip = "DeadlineFloat — click for your deadlines"
        }
    }

    /// The icon's frame in screen coordinates, for anchoring the panel.
    var buttonScreenFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    var window: NSWindow? { statusItem.button?.window }

    /// Called when the app is shutting down. The status item otherwise lives for
    /// the whole session, so there is nothing to tear down in `deinit`.
    func removeFromMenuBar() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Shows the overdue count beside the icon when there is one, and — if the
    /// user asked for it — the countdown to the next deadline. With neither the
    /// menu bar stays quiet.
    func update(overdueCount: Int, countdown: String?) {
        guard let button = statusItem.button else { return }

        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let title = NSMutableAttributedString()
        if overdueCount > 0 {
            title.append(NSAttributedString(
                string: " \(overdueCount)",
                attributes: [.font: font, .foregroundColor: NSColor.systemRed]
            ))
        }
        if let countdown, !countdown.isEmpty {
            title.append(NSAttributedString(
                string: overdueCount > 0 ? " · \(countdown)" : " \(countdown)",
                attributes: [.font: font, .foregroundColor: NSColor.labelColor]
            ))
        }
        button.attributedTitle = title

        var tips: [String] = []
        if overdueCount > 0 { tips.append("\(overdueCount) overdue") }
        if let countdown, !countdown.isEmpty { tips.append("next deadline in \(countdown)") }
        button.toolTip = tips.isEmpty
            ? "DeadlineFloat — click for your deadlines"
            : "DeadlineFloat — " + tips.joined(separator: ", ")
    }

    // MARK: - Actions

    @objc private func handleClick() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true

        if isRightClick {
            presentMenu()
        } else {
            onTogglePanel()
        }
    }

    private func presentMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let toggle = NSMenuItem(
            title: isPanelVisible() ? "Close Deadlines" : "Open Deadlines",
            action: #selector(menuTogglePanel),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(menuRefresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

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

    @objc private func menuTogglePanel() { onTogglePanel() }
    @objc private func menuRefresh() { onRefresh() }
    @objc private func menuSettings() { onOpenSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func menuToggleLaunchAtLogin() {
        try? LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
    }
}
