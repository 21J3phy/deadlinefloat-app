import AppKit
import SwiftUI

/// Owns the floating panel: creation, placement, persistence and visibility.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private let viewModel: DeadlineListViewModel
    private let onOpenSettings: () -> Void

    private var panel: FloatingPanel?
    private var saveFrameTask: Task<Void, Never>?
    private var preferenceObserver: (any NSObjectProtocol)?

    init(
        preferences: Preferences,
        viewModel: DeadlineListViewModel,
        onOpenSettings: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings
        super.init()

        preferenceObserver = NotificationCenter.default.addObserver(
            forName: .windowPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        }
    }

    /// Called at termination. The controller otherwise lives for the whole
    /// session, so there is nothing to unwind in `deinit`.
    func invalidate() {
        saveFrameTask?.cancel()
        if let preferenceObserver {
            NotificationCenter.default.removeObserver(preferenceObserver)
            self.preferenceObserver = nil
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Presentation

    func show() {
        let panel = makePanelIfNeeded()
        applyPreferences()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    /// Puts the window back in the middle of the active screen — the escape
    /// hatch when a saved frame lands on a display that no longer exists.
    func resetPosition() {
        let panel = makePanelIfNeeded()
        panel.setFrame(Self.defaultFrame(), display: true)
        persistFrame()
        panel.orderFrontRegardless()
    }

    // MARK: - Construction

    @discardableResult
    private func makePanelIfNeeded() -> FloatingPanel {
        if let panel { return panel }

        let frame = restoredFrame() ?? Self.defaultFrame()
        let panel = FloatingPanel(contentRect: frame)
        panel.delegate = self
        panel.identifier = NSUserInterfaceItemIdentifier("DeadlineFloatPanel")

        let root = RootView(
            viewModel: viewModel,
            onHide: { [weak self] in self?.hide() },
            onOpenSettings: onOpenSettings
        )
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        // Let the desktop show through the glass rather than a solid backing.
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        panel.contentView = PanelBackdrop.makeContentView(hosting: hosting)
        panel.setFrame(frame, display: false)

        self.panel = panel
        return panel
    }

    // MARK: - Preferences

    func applyPreferences() {
        guard let panel else { return }
        panel.alphaValue = preferences.windowOpacity
        panel.level = preferences.floatAboveFullScreen ? .floating : .normal
        panel.collectionBehavior = preferences.floatAboveFullScreen
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .participatesInCycle]
            : [.canJoinAllSpaces, .participatesInCycle]

        let policy: NSApplication.ActivationPolicy = preferences.showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    // MARK: - Frame persistence

    /// Frames are written back a moment after the drag or resize settles, so a
    /// long drag does not hammer `UserDefaults`.
    private func scheduleFrameSave() {
        saveFrameTask?.cancel()
        saveFrameTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.persistFrame()
        }
    }

    private func persistFrame() {
        guard let panel else { return }
        preferences.windowFrameDescription = NSStringFromRect(panel.frame)
    }

    /// Restores the saved frame, but only if it still lands on a screen that
    /// exists — displays get unplugged.
    private func restoredFrame() -> NSRect? {
        guard let description = preferences.windowFrameDescription else { return nil }
        let frame = NSRectFromString(description)
        guard frame.width >= Metrics.minimumWindowSize.width,
              frame.height >= Metrics.minimumWindowSize.height
        else { return nil }
        return Self.clampToVisibleScreens(frame)
    }

    /// Pulls a frame back onto a visible screen, keeping its size.
    static func clampToVisibleScreens(_ frame: NSRect, screens: [NSScreen] = NSScreen.screens) -> NSRect? {
        guard !screens.isEmpty else { return nil }

        let intersects = screens.contains { screen in
            let visible = screen.visibleFrame
            return visible.intersects(frame) && visible.intersection(frame).width >= 40 && visible.intersection(frame).height >= 40
        }
        if intersects { return frame }

        guard let target = screens.first else { return nil }
        var moved = frame
        moved.origin.x = target.visibleFrame.midX - frame.width / 2
        moved.origin.y = target.visibleFrame.midY - frame.height / 2
        return moved
    }

    static func defaultFrame() -> NSRect {
        let size = Metrics.defaultWindowSize
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: size)
        }
        let visible = screen.visibleFrame
        // Top-right, a comfortable margin in from the corner.
        return NSRect(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) { scheduleFrameSave() }
    func windowDidResize(_ notification: Notification) { scheduleFrameSave() }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let panel, let corrected = Self.clampToVisibleScreens(panel.frame) else { return }
        if corrected != panel.frame { panel.setFrame(corrected, display: true) }
        scheduleFrameSave()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
