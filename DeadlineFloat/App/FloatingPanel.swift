import AppKit

/// The always-on-top window.
///
/// It is an `NSPanel` with `.nonactivatingPanel` so clicking it never steals
/// focus from whatever you are working in, but it can still become key so its
/// buttons and hover states behave normally.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false

        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }

        minSize = Metrics.minimumWindowSize
        maxSize = Metrics.maximumWindowSize

        // Above ordinary windows, and present on every Space including while
        // another app is full screen.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .participatesInCycle]
    }

    /// `Esc` hides the panel rather than closing it for good.
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
