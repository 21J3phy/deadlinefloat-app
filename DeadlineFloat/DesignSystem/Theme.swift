import SwiftUI

/// Layout constants. Kept in one place so density stays consistent as the type
/// ramp scales.
enum Metrics {
    static let windowCornerRadius: CGFloat = 20
    static let cardCornerRadius: CGFloat = 12
    static let chipCornerRadius: CGFloat = 7
    static let stripeWidth: CGFloat = 3
    static let contentInset: CGFloat = 9
    static let headerHeight: CGFloat = 34
    static let footerHeight: CGFloat = 22
    static let rowSpacing: CGFloat = 5
    static let rowSpacingCompact: CGFloat = 3
    static let sectionSpacing: CGFloat = 11
    static let controlDiameter: CGFloat = 22

    static let defaultWindowSize = CGSize(width: 340, height: 460)
    static let minimumWindowSize = CGSize(width: 268, height: 190)
    static let maximumWindowSize = CGSize(width: 720, height: 1400)
}

/// True when the OS provides Liquid Glass. Everything below macOS 26 renders a
/// hand-built approximation instead of silently dropping to flat chrome.
enum Runtime {
    static var supportsLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

extension ShapeStyle where Self == Color {
    /// Hairline separators that stay visible on both appearances.
    static var hairline: Color { Color.primary.opacity(0.09) }
}
