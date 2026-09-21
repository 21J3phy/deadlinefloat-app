import AppKit
import SwiftUI

/// A borderless, non-activating window docked to a screen edge.
///
/// Both the bar and its callout pill are this class. Neither takes focus from
/// what you are working in; the bar can still become key so its text fields
/// and scroll views behave, and `Esc` collapses it.
final class EdgeBarPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// Wraps the hosting view and reports the pointer entering and leaving the
/// window, whether or not the app is active. A click that reaches it — one
/// that no SwiftUI control claimed — is reported too, which is how a click on
/// the sliver opens the bar.
@MainActor
final class HoverContainerView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onClick: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The hosting view that takes the first click even when the bar is not key.
@MainActor
final class BarHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
