import AppKit
import SwiftUI

/// Builds the window's glass backdrop and embeds the SwiftUI content in it.
///
/// On macOS 26 the content genuinely lives *inside* an `NSGlassEffectView`, which
/// is what produces the real Liquid Glass refraction of the desktop behind the
/// panel. Earlier systems get a rounded container with an always-active
/// `NSVisualEffectView` plus a hairline rim, which reads as the same material.
@MainActor
enum PanelBackdrop {
    static func makeContentView(hosting: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Metrics.windowCornerRadius
            glass.style = .regular
            glass.contentView = hosting
            hosting.translatesAutoresizingMaskIntoConstraints = false
            return glass
        }
        return LegacyGlassContainerView(hosting: hosting)
    }
}

/// macOS 14–15 backdrop: blurred material, rounded corners, specular rim.
@MainActor
private final class LegacyGlassContainerView: NSView {
    private let effectView = NSVisualEffectView()
    private let hosting: NSView

    init(hosting: NSView) {
        self.hosting = hosting
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = Metrics.windowCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        addSubview(effectView)

        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)

        updateBorderColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        hosting.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderColor()
    }

    private func updateBorderColor() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.borderColor = NSColor.white.withAlphaComponent(isDark ? 0.14 : 0.45).cgColor
    }
}
