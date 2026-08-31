import SwiftUI

/// The minimal header: identity on the left, the three controls on the right,
/// and the whole strip doubles as the window's drag handle.
struct HeaderBar: View {
    let overdueCount: Int
    let isRefreshing: Bool
    var onRefresh: () -> Void
    var onSettings: () -> Void
    var onHide: () -> Void

    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: Symbols.appMark)
                .font(.system(size: type.iconSize + 1, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("DeadlineFloat")
                .font(type.headerTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)

            if overdueCount > 0 {
                overdueChip
                    .transition(.opacity)
            }

            Spacer(minLength: 4)

            controls
        }
        .padding(.horizontal, Metrics.contentInset)
        .frame(height: Metrics.headerHeight)
        .background { WindowDragArea() }
        .glassGroup(spacing: 10)
    }

    private var overdueChip: some View {
        Text("\(overdueCount) overdue")
            .font(type.footnote)
            .monospacedDigit()
            .foregroundStyle(Color.red.opacity(scheme == .dark ? 0.95 : 0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassSurface(
                in: Capsule(style: .continuous),
                variant: .chip,
                tint: Color.red
            )
            .accessibilityLabel("\(overdueCount) overdue")
    }

    private var controls: some View {
        HStack(spacing: 5) {
            Button(action: onRefresh) {
                Image(systemName: Symbols.refresh)
                    .font(.system(size: type.iconSize, weight: .semibold))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: isRefreshing
                    )
            }
            .buttonStyle(GlassCircleButtonStyle())
            .help("Refresh now")
            .accessibilityLabel("Refresh")
            .disabled(isRefreshing)

            Button(action: onSettings) {
                Image(systemName: Symbols.settings)
                    .font(.system(size: type.iconSize, weight: .semibold))
            }
            .buttonStyle(GlassCircleButtonStyle())
            .help("Settings")
            .accessibilityLabel("Settings")

            Button(action: onHide) {
                Image(systemName: Symbols.hide)
                    .font(.system(size: type.iconSize - 1, weight: .bold))
            }
            .buttonStyle(GlassCircleButtonStyle())
            .help("Hide window — reopen from the menu bar")
            .accessibilityLabel("Hide window")
        }
        .foregroundStyle(.primary)
    }
}
