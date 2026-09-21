import AppKit
import Observation
import SwiftUI

/// The panel that drops down from the menu bar icon.
///
/// A borderless, non-activating window anchored under the hourglass on
/// whichever display the menu bar was clicked. It fades in from just above
/// its resting place, closes on a click anywhere outside it (unless pinned),
/// on `Esc`, or on another click of the icon, and never takes focus from what
/// you are working in.
@MainActor
final class MenuBarPanelController: NSObject, NSWindowDelegate {
    static let preferredHeight: CGFloat = 720

    private var width: CGFloat { Metrics.taskPaneWidth + Metrics.calendarWidth(for: preferences.range) }

    private let preferences: Preferences
    private let viewModel: DeadlineListViewModel
    private let state = EdgeBarState(isExpanded: true, isPinned: false, edge: .right)
    private let panel: EdgeBarPanel
    private let container = HoverContainerView()
    private let hosting: BarHostingView<EdgeBarView>
    private let swipeMonitor = SwipeGestureMonitor()

    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    /// The status item's window, so a click on the icon is never "outside".
    weak var statusWindow: NSWindow?

    private(set) var isVisible = false

    init(preferences: Preferences, viewModel: DeadlineListViewModel, onOpenSettings: @escaping () -> Void) {
        self.preferences = preferences
        self.viewModel = viewModel
        panel = EdgeBarPanel(frame: NSRect(x: 0, y: 0, width: Metrics.taskPaneWidth, height: Self.preferredHeight))
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let state = self.state
        hosting = BarHostingView(rootView: EdgeBarView(
            viewModel: viewModel, bar: state, isDocked: false,
            onOpenSettings: onOpenSettings, onTogglePin: {}, onExpand: {}, swipeMonitor: swipeMonitor
        ))
        super.init()

        hosting.rootView = EdgeBarView(
            viewModel: viewModel,
            bar: state,
            isDocked: false,
            onOpenSettings: onOpenSettings,
            onTogglePin: { [weak self] in self?.togglePin() },
            onExpand: {},
            swipeMonitor: swipeMonitor
        )
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        hosting.frame = container.bounds
        panel.contentView = container
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.hide() }
        swipeMonitor.onCommit = { [weak viewModel] key, direction in viewModel?.handleSwipe(key, direction) }
        swipeMonitor.install(window: panel, hosting: hosting)
        observeRange()
    }

    /// The panel widens and narrows with the number of days it shows.
    private func observeRange() {
        withObservationTracking {
            _ = preferences.range
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isVisible {
                    var frame = self.panel.frame
                    let width = self.width
                    frame.origin.x = frame.maxX - width
                    frame.size.width = width
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.2
                        self.panel.animator().setFrame(frame, display: true)
                    }
                }
                self.observeRange()
            }
        }
    }

    func invalidate() {
        removeClickMonitors()
        swipeMonitor.uninstall()
        panel.orderOut(nil)
    }

    // MARK: - Showing

    /// Shows the panel under `anchor` (the icon's frame in screen coordinates),
    /// or centred near the top of the main display when there is no anchor.
    func show(anchoredTo rawAnchor: NSRect?) {
        // Before the status item has been laid out its frame is empty; fall
        // back to the top of the main display rather than anchoring at (0, 0).
        let anchor = rawAnchor.flatMap { $0.isEmpty || $0.width < 1 ? nil : $0 }
        let screen = anchor.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame

        let width = self.width
        let height = min(Self.preferredHeight, visible.height - 16)
        var x = (anchor?.midX ?? (visible.maxX - 120)) - width / 2
        x = min(visible.maxX - width - 8, max(visible.minX + 8, x))
        let top = (anchor?.minY ?? visible.maxY) - 6
        let frame = NSRect(x: x, y: top - height, width: width, height: height)

        state.isPinned = false
        panel.alphaValue = preferences.windowOpacity
        panel.setFrame(frame.offsetBy(dx: 0, dy: 8), display: false)
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        installClickMonitors()
        Log.ui.info("Panel shown at \(frame.origin.x, privacy: .public),\(frame.origin.y, privacy: .public)")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        state.isPinned = false
        removeClickMonitors()
        Log.ui.info("Panel hidden")
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isVisible else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    func toggle(anchoredTo anchor: NSRect?) {
        if isVisible { hide() } else { show(anchoredTo: anchor) }
    }

    func togglePin() {
        state.isPinned.toggle()
    }

    func applyPreferences() {
        if isVisible { panel.alphaValue = preferences.windowOpacity }
    }

    // MARK: - Clicks outside

    private func installClickMonitors() {
        guard globalClickMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor [weak self] in self?.clickedOutside() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            let window = event.window
            let inside = window === self.panel || (window != nil && window === self.statusWindow)
            if !inside { MainActor.assumeIsolated { self.clickedOutside() } }
            return event
        }
    }

    private func removeClickMonitors() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        globalClickMonitor = nil
        localClickMonitor = nil
    }

    private func clickedOutside() {
        guard isVisible, !state.isPinned else { return }
        hide()
    }
}
