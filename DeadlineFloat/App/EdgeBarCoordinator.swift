import AppKit

/// Keeps one edge bar per display, and rebuilds the set when displays come
/// and go.
@MainActor
final class EdgeBarCoordinator {
    private let preferences: Preferences
    private let viewModel: DeadlineListViewModel
    private let onOpenSettings: () -> Void

    private var controllers: [CGDirectDisplayID: EdgeBarController] = [:]
    private var observers: [any NSObjectProtocol] = []
    private(set) var isVisible = false

    init(preferences: Preferences, viewModel: DeadlineListViewModel, onOpenSettings: @escaping () -> Void) {
        self.preferences = preferences
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcileDisplays() }
        })
        observers.append(center.addObserver(forName: .windowPreferencesChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        })
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controllers.values.forEach { $0.isMenuTracking = true } }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controllers.values.forEach { $0.isMenuTracking = false } }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        })
    }

    func invalidate() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        controllers.values.forEach { $0.invalidate() }
        controllers.removeAll()
    }

    // MARK: - Visibility

    func show() {
        isVisible = true
        reconcileDisplays()
        controllers.values.forEach { $0.show() }
    }

    func hide() {
        isVisible = false
        controllers.values.forEach { $0.hide() }
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    /// Whether any display's bar is currently slid open.
    var isAnyExpanded: Bool {
        controllers.values.contains { $0.state.isExpanded }
    }

    /// Whether any display's bar is held open.
    var isAnyPinned: Bool {
        controllers.values.contains { $0.state.isExpanded && $0.state.isPinned }
    }

    /// Slides the bar open and pins it on the display the pointer is on (or
    /// the main display). A bar that is already open on hover is pinned
    /// rather than closed; only a pinned bar is closed by the toggle.
    func toggleOpen() {
        Log.trace("Toggle bar: \(controllers.count) bar(s), any expanded: \(isAnyExpanded), any pinned: \(isAnyPinned)")
        if isAnyPinned {
            controllers.values.forEach { $0.collapse() }
            return
        }
        if let open = controllers.values.first(where: { $0.state.isExpanded }) {
            open.expand(pinned: true)
            return
        }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen, let id = Self.displayID(of: screen), let controller = controllers[id] else {
            Log.trace("No bar to open")
            return
        }
        controller.expand(pinned: true)
    }

    func applyPreferences() {
        let policy: NSApplication.ActivationPolicy = preferences.showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        controllers.values.forEach { $0.applyPreferences() }
    }

    // MARK: - Displays

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func reconcileDisplays() {
        let current = Set(NSScreen.screens.compactMap(Self.displayID))

        for (id, controller) in controllers where !current.contains(id) {
            controller.invalidate()
            controllers.removeValue(forKey: id)
        }
        for id in current where controllers[id] == nil {
            let controller = EdgeBarController(
                displayID: id,
                preferences: preferences,
                viewModel: viewModel,
                onOpenSettings: onOpenSettings
            )
            controller.applyPreferences()
            controllers[id] = controller
            if isVisible { controller.show() }
        }
        controllers.values.forEach { $0.screenParametersChanged() }
    }
}
