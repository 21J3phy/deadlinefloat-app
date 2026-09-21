import AppKit

/// Builds the application menu.
///
/// An AppKit-lifecycle app has no menu unless it makes one, and without an Edit
/// menu the settings text fields would not support Cut, Copy, Paste or Select
/// All — so those are wired up explicitly.
@MainActor
enum MainMenuBuilder {
    static func install(target: AppDelegate) {
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(withTitle: "About DeadlineFloat", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settings.target = target
        appMenu.addItem(settings)

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(AppDelegate.refreshNow), keyEquivalent: "r")
        refresh.target = target
        appMenu.addItem(refresh)

        let toggle = NSMenuItem(title: "Show or Hide Deadlines", action: #selector(AppDelegate.togglePanel), keyEquivalent: "w")
        toggle.target = target
        appMenu.addItem(toggle)

        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide DeadlineFloat", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit DeadlineFloat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu — required for text field editing in Settings.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "W")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}
