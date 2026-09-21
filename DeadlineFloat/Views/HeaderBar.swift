import SwiftUI

/// The task pane's header: the date range on the left, one grouped glass
/// capsule of controls on the right. The app's name is deliberately absent —
/// the bar is the brand.
struct HeaderBar: View {
    let range: RangeOption
    let isRefreshing: Bool
    let isPinned: Bool
    var onSelectRange: (RangeOption) -> Void
    var onRefresh: () -> Void
    var onSettings: () -> Void
    var onTogglePin: () -> Void

    @Environment(\.typography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            SegmentedGlassControl(
                options: RangeOption.allCases.map {
                    .init($0, $0.shortLabel, help: $0 == .oneDay ? "Today" : "Today plus \($0.days - 1) more day\($0.days == 2 ? "" : "s")")
                },
                selection: Binding(get: { range }, set: onSelectRange),
                minimumSegmentWidth: 22
            )
            .accessibilityLabel("Date range")

            Spacer(minLength: 6)

            controls
        }
        .padding(.horizontal, Metrics.contentInset)
        .padding(.top, Metrics.contentInset)
        .padding(.bottom, Metrics.blockGap)
        .glassGroup(spacing: 10)
    }

    private var controls: some View {
        HStack(spacing: 1) {
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? Symbols.pinned : Symbols.pin)
                    .font(.system(size: type.iconSize, weight: .semibold))
                    .foregroundStyle(isPinned ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(GlassIconButtonStyle())
            .help(isPinned ? "Unpin — the bar closes when the pointer leaves" : "Pin the bar open")
            .accessibilityLabel(isPinned ? "Unpin" : "Pin")

            Button(action: onRefresh) {
                Image(systemName: Symbols.refresh)
                    .font(.system(size: type.iconSize, weight: .semibold))
                    .rotationEffect(.degrees(isRefreshing && !reduceMotion ? 360 : 0))
                    .animation(
                        isRefreshing && !reduceMotion
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: isRefreshing
                    )
            }
            .buttonStyle(GlassIconButtonStyle())
            .help("Refresh now (⌘R)")
            .accessibilityLabel("Refresh")
            .disabled(isRefreshing)

            Button(action: onSettings) {
                Image(systemName: Symbols.settings)
                    .font(.system(size: type.iconSize, weight: .semibold))
            }
            .buttonStyle(GlassIconButtonStyle())
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
        .padding(2)
        .glassSurface(in: Capsule(style: .continuous), variant: .control)
    }
}
