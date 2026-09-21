import AppKit
import SwiftUI

/// Layout constants, all on one 4-point grid.
///
/// Two insets organise the panel. *Chrome* — the header controls, the footer,
/// the edges of the spotlight card and of every row's hover fill — sits
/// `contentInset` (12) from the window edge. *Content* — the spotlight's text,
/// the colour bars, section labels, and the right-hand column of every row —
/// sits `contentInset + cardPadding` (24) in; rows use `rowInset` (10) so a
/// title has a little more room, and their text hangs off the colour bar.
/// Every vertical gap between blocks is `blockGap` (12).
enum Metrics {
    static let windowCornerRadius: CGFloat = 22
    static let rowCornerRadius: CGFloat = 10
    static let spotlightCornerRadius: CGFloat = 16

    static let contentInset: CGFloat = 12
    static let cardPadding: CGFloat = 12
    static let rowInset: CGFloat = 10
    static let blockGap: CGFloat = 12
    static let rowSpacing: CGFloat = 1
    static let sectionSpacing: CGFloat = 12
    static let controlDiameter: CGFloat = 26
    static let colorBarWidth: CGFloat = 3
    static let colorBarGap: CGFloat = 8

    // The edge bar.

    /// The ruler strip flush with the screen edge: the default width, which
    /// Settings can change (`Preferences.sliverWidth`).
    static let sliverWidth: CGFloat = 12
    /// The air beside the strip inside the collapsed window.
    static let sliverAir: CGFloat = 12
    /// The collapsed edge bar: the sliver plus a little air beside it.
    static func collapsedBarWidth(sliver: CGFloat) -> CGFloat { sliver + sliverAir }
    /// The task column of the open panel.
    static let taskPaneWidth: CGFloat = 320
    /// The hour labels beside the calendar.
    static let calendarGutter: CGFloat = 44
    /// One calendar column, by how many the panel shows: fewer days, wider days.
    static func dayColumnWidth(for range: RangeOption) -> CGFloat {
        switch range {
        case .oneDay: return 220
        case .twoDays: return 160
        case .threeDays: return 136
        case .week: return 92
        }
    }
    /// Between the last column and the screen edge (or the panel's outer
    /// edge), so blocks settle a grid unit in from where they grew out of.
    static let calendarEdgeInset: CGFloat = 12
    static func calendarWidth(for range: RangeOption) -> CGFloat {
        calendarGutter + dayColumnWidth(for: range) * CGFloat(range.days) + calendarEdgeInset
    }
    /// The open panel: the tasks and the calendar. The sliver is gone by then —
    /// it has become the calendar's blocks.
    static func expandedBarWidth(for range: RangeOption) -> CGFloat {
        taskPaneWidth + calendarWidth(for: range)
    }
    /// Space above the first hour mark — room for the calendar's day headers, which
    /// the sliver leaves empty so its segments line up with the blocks — and
    /// below the last.
    static let rulerTopInset: CGFloat = 54
    static let rulerBottomInset: CGFloat = 14
    static let calendarBlockMinimumHeight: CGFloat = 22
    /// The next-event pill that floats beside the sliver.
    static let calloutWidth: CGFloat = 224
    static let calloutHeight: CGFloat = 46
}

/// True when the OS provides Liquid Glass. Everything below macOS 26 renders a
/// hand-built approximation instead of silently dropping to flat chrome.
enum Runtime {
    static var supportsLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

/// The few semantic colours the interface uses beyond the Google palette.
///
/// Urgency is red and amber, the current event green — Google Calendar's own
/// text colours: its red and green 700 on light, its red and green 300 on
/// dark, its yellow 600 for amber on dark. Each is a dynamic colour, pushed
/// further in both directions when Increase Contrast is on, and every one
/// clears WCAG's 4.5:1 for small text on the panel's surface. Everything else
/// is drawn from `.primary` at a small opacity, which is what keeps the window
/// reading as one material rather than a stack of tinted boxes.
enum Palette {
    static let overdue = dynamic(light: "#C5221F", dark: "#F28B82", lightHighContrast: "#A50E0E", darkHighContrast: "#F6AEA9")
    static let imminent = dynamic(light: "#A64A00", dark: "#F9AB00", lightHighContrast: "#7F3800", darkHighContrast: "#FDD663")
    static let success = dynamic(light: "#188038", dark: "#81C995", lightHighContrast: "#0D652D", darkHighContrast: "#A8DAB5")

    /// Laid over the glass when the bar is open, so the sheet reads as dark
    /// (or, in light mode, as paper) whatever happens to be behind it.
    static func scrim(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast = .standard) -> Color {
        scheme == .dark
            ? Color.black.opacity(boosted(0.42, contrast))
            : Color.white.opacity(boosted(0.38, contrast))
    }

    /// Laid over `scrim` on the sliver, so the strip stands out against
    /// whatever is behind it — near-black glass over a white page — while
    /// the open panel keeps its lighter scrim; the extra depth fades as the
    /// strip stretches into the sheet.
    static func sliverScrim(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast = .standard) -> Color {
        scheme == .dark
            ? Color.black.opacity(boosted(0.6, contrast))
            : Color.white.opacity(boosted(0.5, contrast))
    }

    /// A colour that resolves per appearance, including the high-contrast
    /// appearances macOS switches to when Increase Contrast is on.
    private static func dynamic(light: String, dark: String, lightHighContrast: String, darkHighContrast: String) -> Color {
        func nsColor(_ hex: String) -> NSColor {
            let rgb = RGBColor(hex: hex) ?? .black
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }
        let resolved = NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
            case .darkAqua: return nsColor(dark)
            case .accessibilityHighContrastAqua: return nsColor(lightHighContrast)
            case .accessibilityHighContrastDarkAqua: return nsColor(darkHighContrast)
            default: return nsColor(light)
            }
        }
        return Color(nsColor: resolved)
    }

    /// Hairline separators that stay visible on both appearances.
    static let hairline = Color.primary.opacity(0.09)

    /// Scales a fill opacity up when the user has asked for increased contrast.
    static func boosted(_ opacity: Double, _ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? min(1, opacity * 1.9) : opacity
    }

    static func rowHover(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast = .standard) -> Color {
        Color.primary.opacity(boosted(scheme == .dark ? 0.075 : 0.055, contrast))
    }

    static func rowPressed(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast = .standard) -> Color {
        Color.primary.opacity(boosted(scheme == .dark ? 0.11 : 0.085, contrast))
    }

    static func overdueWash(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast = .standard) -> Color {
        overdue.opacity(boosted(scheme == .dark ? 0.14 : 0.10, contrast))
    }

    /// Fill for cards in the settings window and behind the spotlight.
    static func cardFill(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast = .standard) -> Color {
        Color.primary.opacity(boosted(scheme == .dark ? 0.065 : 0.035, contrast))
    }

    static func cardStroke(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast = .standard) -> Color {
        Color.primary.opacity(boosted(scheme == .dark ? 0.11 : 0.08, contrast))
    }

    /// Recessed track behind a segmented control or slider.
    static func track(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast = .standard) -> Color {
        Color.primary.opacity(boosted(scheme == .dark ? 0.10 : 0.07, contrast))
    }
}

extension ShapeStyle where Self == Color {
    /// Hairline separators that stay visible on both appearances.
    static var hairline: Color { Palette.hairline }
}
