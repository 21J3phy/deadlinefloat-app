import SwiftUI

/// A scalable type ramp.
///
/// Every font in the app comes from here so the "Text size" preference scales
/// the whole interface coherently instead of only a few labels. Numbers are set
/// in the rounded design with monospaced digits, so countdowns tick without the
/// text shifting sideways.
struct AppTypography: Equatable, Sendable {
    var scale: CGFloat = 1.0

    private func pt(_ base: CGFloat) -> CGFloat { (base * scale * 2).rounded() / 2 }

    // Chrome
    var segment: Font { .system(size: pt(11.5), weight: .semibold) }
    var sectionHeader: Font { .system(size: pt(10.5), weight: .bold) }
    var footnote: Font { .system(size: pt(10.5), weight: .medium) }

    // Rows
    var rowTitle: Font { .system(size: pt(13), weight: .semibold) }
    var rowTitleCompact: Font { .system(size: pt(12.5), weight: .medium) }
    var rowMeta: Font { .system(size: pt(11), weight: .medium) }
    var rowTime: Font { .system(size: pt(12), weight: .semibold).monospacedDigit() }
    var countdown: Font { .system(size: pt(11), weight: .semibold).monospacedDigit() }

    // Spotlight
    var spotlightEyebrow: Font { .system(size: pt(10), weight: .bold) }
    var spotlightTitle: Font { .system(size: pt(15.5), weight: .semibold) }
    var spotlightCountdown: Font { .system(size: pt(24), weight: .semibold).monospacedDigit() }
    var spotlightWhen: Font { .system(size: pt(11), weight: .medium) }

    // Empty and sign-in states
    var emptyTitle: Font { .system(size: pt(15), weight: .semibold) }
    var emptyBody: Font { .system(size: pt(11.5), weight: .regular) }

    var iconSize: CGFloat { pt(11.5) }
    var dotSize: CGFloat { pt(7) }
    var rowVerticalPadding: CGFloat { pt(7) }
    var rowVerticalPaddingCompact: CGFloat { pt(4.5) }
    var lineGap: CGFloat { pt(2.5) }
}

private struct TypographyKey: EnvironmentKey {
    static let defaultValue = AppTypography()
}

private struct CompactModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var typography: AppTypography {
        get { self[TypographyKey.self] }
        set { self[TypographyKey.self] = newValue }
    }

    var isCompactMode: Bool {
        get { self[CompactModeKey.self] }
        set { self[CompactModeKey.self] = newValue }
    }
}
