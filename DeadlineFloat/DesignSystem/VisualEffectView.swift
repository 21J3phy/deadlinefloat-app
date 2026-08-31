import AppKit
import SwiftUI

/// `NSVisualEffectView` bridged into SwiftUI.
///
/// The state is pinned to `.active` on purpose: DeadlineFloat is a floating
/// panel that is almost never the key window, and the default `.followsWindowActiveState`
/// makes the material collapse into flat grey the moment focus moves elsewhere.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = isEmphasized
    }
}
