import SwiftUI

/// A scalable type ramp.
///
/// Every font in the app comes from here so the "Text size" preference scales
/// the whole interface coherently instead of only a few labels.
struct AppTypography: Equatable, Sendable {
    var scale: CGFloat = 1.0

    private func pt(_ base: CGFloat) -> CGFloat { (base * scale * 2).rounded() / 2 }

    var headerTitle: Font { .system(size: pt(13), weight: .semibold, design: .rounded) }
    var headerSubtitle: Font { .system(size: pt(10), weight: .medium, design: .rounded) }
    var segment: Font { .system(size: pt(11), weight: .semibold, design: .rounded) }
    var sectionHeader: Font { .system(size: pt(10), weight: .bold, design: .rounded) }
    var rowTitle: Font { .system(size: pt(13), weight: .semibold) }
    var rowTitleCompact: Font { .system(size: pt(12), weight: .medium) }
    var rowMeta: Font { .system(size: pt(11), weight: .medium) }
    var rowTime: Font { .system(size: pt(11), weight: .semibold).monospacedDigit() }
    var countdown: Font { .system(size: pt(10.5), weight: .semibold, design: .rounded).monospacedDigit() }
    var footnote: Font { .system(size: pt(10), weight: .medium) }
    var emptyTitle: Font { .system(size: pt(13), weight: .semibold, design: .rounded) }
    var emptyBody: Font { .system(size: pt(11), weight: .regular) }
    var settingsTitle: Font { .system(size: pt(15), weight: .semibold, design: .rounded) }

    var iconSize: CGFloat { pt(11) }
    var dotSize: CGFloat { pt(7) }
    var rowVerticalPadding: CGFloat { pt(7) }
    var rowVerticalPaddingCompact: CGFloat { pt(4) }
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
