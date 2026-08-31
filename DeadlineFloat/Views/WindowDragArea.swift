import AppKit
import SwiftUI

/// Makes any region of the panel a drag handle.
///
/// `isMovableByWindowBackground` alone stops working wherever a SwiftUI control
/// takes the mouse down, so the header explicitly forwards the drag to the
/// window. Works identically on macOS 14 through 26.
struct WindowDragArea: View {
    @Environment(\.isOffscreenRender) private var isOffscreenRender

    var body: some View {
        // An `NSViewRepresentable` has no live view during an offscreen render
        // and would draw a placeholder, so it collapses to nothing there.
        if isOffscreenRender {
            Color.clear
        } else {
            DragForwarder()
        }
    }
}

private struct DragForwarder: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragForwardingView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragForwardingView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
