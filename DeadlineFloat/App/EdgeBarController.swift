import AppKit
import Observation
import SwiftUI

/// One display's edge bar: the sliver, the callout pill beside it, and the
/// panel they expand into.
///
/// Two windows, both docked to the edge. The bar window is exactly the
/// sliver's width when collapsed, so the rest of the screen stays clickable;
/// the pill is its own small window beside the sliver. Pressing the pointer
/// against the screen's edge for a moment slides the bar out, as does a click
/// on the sliver or the pill; leaving it, unless pinned, slides it back after
/// a short grace.
@MainActor
final class EdgeBarController: NSObject, NSWindowDelegate {
    static let dwellDelay: Duration = .milliseconds(250)
    static let collapseGrace: Duration = .milliseconds(350)
    /// How close to the screen's outer edge the pointer must be to open the bar.
    static let edgeReach: CGFloat = 2

    let displayID: CGDirectDisplayID
    let state = EdgeBarState()

    private let preferences: Preferences
    private let viewModel: DeadlineListViewModel
    private let onOpenSettings: () -> Void

    private let panel: EdgeBarPanel
    private let callout: EdgeBarPanel
    private let container = HoverContainerView()
    private let calloutContainer = HoverContainerView()
    private let hosting: BarHostingView<EdgeBarView>
    private let calloutHosting: BarHostingView<CalloutRootView>
    private let swipeMonitor = SwipeGestureMonitor()

    private var dwellTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    /// True while the sheet shrinks back into the sliver, before the window
    /// narrows around it and the pill comes back.
    private var isSettling = false
    private var isPointerInside = false
    private var isVisible = false
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    /// Set by the coordinator while any menu is being tracked, so the bar does
    /// not collapse under a context menu.
    var isMenuTracking = false {
        didSet { if !isMenuTracking && !isPointerInside { scheduleCollapse() } }
    }

    init(
        displayID: CGDirectDisplayID,
        preferences: Preferences,
        viewModel: DeadlineListViewModel,
        onOpenSettings: @escaping () -> Void
    ) {
        self.displayID = displayID
        self.preferences = preferences
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings

        panel = EdgeBarPanel(frame: NSRect(x: 0, y: 0, width: Metrics.collapsedBarWidth(sliver: CGFloat(preferences.sliverWidth)), height: 600))
        callout = EdgeBarPanel(frame: NSRect(x: 0, y: 0, width: Metrics.calloutWidth, height: Metrics.calloutHeight))

        let state = self.state
        let barView = EdgeBarView(
            viewModel: viewModel,
            bar: state,
            onOpenSettings: onOpenSettings,
            onTogglePin: {},
            onExpand: {},
            swipeMonitor: swipeMonitor
        )
        hosting = BarHostingView(rootView: barView)
        calloutHosting = BarHostingView(rootView: CalloutRootView(viewModel: viewModel, edge: state.edge))
        super.init()

        hosting.rootView = EdgeBarView(
            viewModel: viewModel,
            bar: state,
            onOpenSettings: onOpenSettings,
            onTogglePin: { [weak self] in self?.togglePin() },
            onExpand: { [weak self] in self?.expand(pinned: true) },
            onSettled: { [weak self] in self?.panelSettled() },
            swipeMonitor: swipeMonitor
        )

        for (window, host, box) in [(panel, hosting as NSView, container), (callout, calloutHosting as NSView, calloutContainer)] {
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor.clear.cgColor
            host.translatesAutoresizingMaskIntoConstraints = true
            host.autoresizingMask = [.width, .height]
            box.addSubview(host)
            host.frame = box.bounds
            window.contentView = box
            window.delegate = self
        }

        container.onEnter = { [weak self] in self?.pointerEntered() }
        container.onExit = { [weak self] in self?.pointerExited() }
        container.onMove = { [weak self] in self?.pointerMoved() }
        container.onClick = { [weak self] in
            guard let self, !self.state.isExpanded else { return }
            self.expand(pinned: true)
        }
        calloutContainer.onEnter = { [weak self] in self?.pointerEntered() }
        calloutContainer.onExit = { [weak self] in self?.pointerExited() }
        calloutContainer.onClick = { [weak self] in self?.expand(pinned: true) }

        panel.onEscape = { [weak self] in self?.collapse() }
        swipeMonitor.onCommit = { [weak viewModel] key, direction in viewModel?.handleSwipe(key, direction) }
        swipeMonitor.install(window: panel, hosting: hosting)

        observeCallout()
        observeRange()
    }

    func invalidate() {
        cancelDwell()
        collapseTask?.cancel()
        removeClickMonitors()
        swipeMonitor.uninstall()
        panel.orderOut(nil)
        callout.orderOut(nil)
    }

    // MARK: - Screen

    private var screen: NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }
    }

    /// The preferred edge, unless the Dock already sits there on this display.
    private func resolvedEdge(on screen: NSScreen) -> ScreenEdge {
        let preferred = preferences.edge
        let dockOnRight = screen.visibleFrame.maxX < screen.frame.maxX - 1
        let dockOnLeft = screen.visibleFrame.minX > screen.frame.minX + 1
        if preferred == .right && dockOnRight { return .left }
        if preferred == .left && dockOnLeft { return .right }
        return preferred
    }

    // MARK: - Visibility

    func show() {
        isVisible = true
        layout(animated: false)
        panel.orderFrontRegardless()
        updateCallout()
    }

    func hide() {
        isVisible = false
        collapse(animated: false)
        panel.orderOut(nil)
        callout.orderOut(nil)
    }

    func applyPreferences() {
        let level: NSWindow.Level = preferences.floatAboveFullScreen ? .floating : .normal
        let behavior: NSWindow.CollectionBehavior = preferences.floatAboveFullScreen
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            : [.canJoinAllSpaces, .stationary, .ignoresCycle]
        for window in [panel, callout] {
            window.level = level
            window.collectionBehavior = behavior
            window.alphaValue = preferences.windowOpacity
        }
        layout(animated: false)
        updateCallout()
    }

    func screenParametersChanged() {
        layout(animated: false)
        updateCallout()
    }

    // MARK: - Expansion

    func expand(pinned: Bool) {
        cancelDwell()
        collapseTask?.cancel()
        settleTask?.cancel()
        isSettling = false
        state.isPinned = pinned || state.isPinned
        guard !state.isExpanded else { return }
        Log.trace("Bar expanding (pinned: \(pinned))")
        callout.orderOut(nil)
        // The window takes its full size at once — it is clear wherever the
        // sheet has not reached — and the sliver stretches out inside it.
        state.isExpanded = true
        layout(animated: false)
        panel.makeKeyAndOrderFront(nil)
        installClickMonitors()
    }

    func collapse(animated: Bool = true) {
        cancelDwell()
        collapseTask?.cancel()
        settleTask?.cancel()
        state.isPinned = false
        guard state.isExpanded else { return }
        Log.trace("Bar collapsing")
        removeClickMonitors()
        if panel.isKeyWindow { panel.resignKey() }
        state.isExpanded = false
        guard animated else {
            isSettling = false
            layout(animated: false)
            updateCallout()
            return
        }
        // The sheet shrinks back into the strip first; only once the sliver
        // is drawing again (`panelSettled`) does the window narrow around it
        // and the pill return. The timer is a fallback, should that never come.
        isSettling = true
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.finishSettling()
        }
    }

    /// The panel has shrunk all the way back and the sliver has taken over.
    /// The window narrows on a later turn, after that has been drawn into
    /// the wide window; narrowing in the same pass showed the old, wide
    /// panel squeezed into the sliver's width for a few frames.
    private func panelSettled() {
        guard isSettling else { return }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, !Task.isCancelled else { return }
            self.finishSettling()
        }
    }

    private func finishSettling() {
        guard isSettling, !state.isExpanded else { return }
        isSettling = false
        layout(animated: false)
        updateCallout()
    }

    func togglePin() {
        if state.isPinned {
            state.isPinned = false
            if !isPointerInside { scheduleCollapse() }
        } else {
            state.isPinned = true
        }
    }

    // MARK: - Hover

    private func pointerEntered() {
        isPointerInside = true
        collapseTask?.cancel()
        pointerMoved()
    }

    /// Hovering opens the bar only with the pointer pressed against the
    /// screen's edge. Anywhere else over the window does nothing — and while
    /// the sheet shrinks back the window is still panel-wide, so without this
    /// heading back across the screen caught the pointer and reopened it.
    private func pointerMoved() {
        guard !state.isExpanded, isPointerInside, isPointerAtEdge else {
            cancelDwell()
            return
        }
        guard dwellTask == nil else { return }
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: Self.dwellDelay)
            guard let self, !Task.isCancelled else { return }
            self.dwellTask = nil
            guard self.isPointerInside, self.isPointerAtEdge else { return }
            self.expand(pinned: false)
        }
    }

    private func pointerExited() {
        isPointerInside = false
        cancelDwell()
        scheduleCollapse()
    }

    private func cancelDwell() {
        dwellTask?.cancel()
        dwellTask = nil
    }

    private var isPointerAtEdge: Bool {
        guard let screen else { return false }
        let x = NSEvent.mouseLocation.x
        return state.edge == .right
            ? x >= screen.frame.maxX - Self.edgeReach
            : x <= screen.frame.minX + Self.edgeReach
    }

    private func scheduleCollapse() {
        guard state.isExpanded, !state.isPinned else { return }
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.collapseGrace)
            guard let self, !Task.isCancelled else { return }
            guard !self.isPointerInside, !self.isMenuTracking, !self.state.isPinned else { return }
            if let responder = self.panel.firstResponder, responder is NSTextView { return }
            self.collapse()
        }
    }

    // MARK: - Frames

    private func layout(animated: Bool) {
        guard let screen else { return }
        let edge = resolvedEdge(on: screen)
        if state.edge != edge {
            state.edge = edge
            calloutHosting.rootView = CalloutRootView(viewModel: viewModel, edge: edge)
        }

        let visible = screen.visibleFrame
        let width = state.isExpanded ? Metrics.expandedBarWidth(for: preferences.range) : Metrics.collapsedBarWidth(sliver: sliverWidth)
        let x = edge == .right ? screen.frame.maxX - width : screen.frame.minX
        let frame = NSRect(x: x, y: visible.minY, width: width, height: visible.height)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
            // Lay the content out at the new size now, in this same pass, so
            // the window is never shown with its old content stretched.
            hosting.needsLayout = true
            hosting.layoutSubtreeIfNeeded()
        }
    }

    private var sliverWidth: CGFloat { CGFloat(preferences.sliverWidth) }

    /// The bar widens and narrows with the number of days it shows, and the
    /// sliver with its width setting.
    private func observeRange() {
        withObservationTracking {
            _ = preferences.range
            _ = preferences.sliverWidth
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.state.isExpanded {
                    self.layout(animated: true)
                } else if !self.isSettling {
                    self.layout(animated: false)
                    self.updateCallout()
                }
                self.observeRange()
            }
        }
    }

    // MARK: - Callout

    /// Re-registers with Observation whenever the focus or the clock changes,
    /// so the pill follows its event down the ruler — and whenever the
    /// setting that shows it at all is flipped.
    private func observeCallout() {
        withObservationTracking {
            _ = viewModel.focus?.item.id
            _ = viewModel.now
            _ = preferences.sliverShowsFocusPill
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateCallout()
                self.observeCallout()
            }
        }
    }

    private func updateCallout() {
        guard isVisible, !state.isExpanded, !isSettling, preferences.sliverShowsFocusPill,
              let focus = viewModel.focus, let screen else {
            callout.orderOut(nil)
            return
        }

        let barFrame = panel.frame
        let height = barFrame.height
        let ruler = viewModel.ruler
        // Level with the needle, so the pill and the time it counts from are
        // in one place; off the ruler (only possible on a shorter span) it
        // waits at the top.
        // (The strip is inset by its fillets, which the ruler's own insets cover.)
        let now = viewModel.now
        let centreFromTop = ruler.contains(now)
            ? RulerGeometry.y(fraction: ruler.fraction(of: now), height: height)
            : Metrics.rulerTopInset + 8
        var top = centreFromTop - Metrics.calloutHeight / 2
        top = min(height - Metrics.calloutHeight - 4, max(4, top))

        let gapFromSliver = sliverWidth + 8
        let x = state.edge == .right
            ? screen.frame.maxX - gapFromSliver - Metrics.calloutWidth
            : screen.frame.minX + gapFromSliver
        let frame = NSRect(
            x: x,
            y: barFrame.maxY - top - Metrics.calloutHeight,
            width: Metrics.calloutWidth,
            height: Metrics.calloutHeight
        )
        callout.setFrame(frame, display: true)
        if !callout.isVisible { callout.orderFrontRegardless() }
    }

    // MARK: - Clicks outside

    /// A pinned bar stays open through app switches and lost key status; only
    /// an actual click somewhere else lets it go.
    private func installClickMonitors() {
        guard globalClickMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor [weak self] in self?.clickedOutside() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            let window = event.window
            let inside = window === self.panel || window === self.callout
            if !inside, window?.className.contains("StatusBar") != true {
                MainActor.assumeIsolated { self.clickedOutside() }
            }
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
        guard state.isExpanded, !isPointerInside, !isMenuTracking else { return }
        Log.trace("Click outside the bar (window: \(String(describing: NSApp.currentEvent?.window?.className)))")
        if let responder = panel.firstResponder, responder is NSTextView, panel.isKeyWindow { return }
        collapse()
    }
}

/// The callout window's root: the pill for what is on or next, or nothing.
struct CalloutRootView: View {
    @Bindable var viewModel: DeadlineListViewModel
    let edge: ScreenEdge

    var body: some View {
        if let focus = viewModel.focus {
            FocusPillView(
                focus: focus,
                now: viewModel.now,
                formatter: viewModel.formatter,
                countdownFormatter: viewModel.countdownFormatter
            )
            .environment(\.typography, AppTypography(scale: viewModel.preferences.textScale))
        } else {
            Color.clear
        }
    }
}
