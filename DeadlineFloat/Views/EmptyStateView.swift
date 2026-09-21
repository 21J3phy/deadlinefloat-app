import SwiftUI

/// Shown when the range holds nothing. Deliberately calm: an empty list is good
/// news, not an error.
struct EmptyStateView: View {
    let range: RangeOption
    let showingAllEvents: Bool
    let formatter: DeadlineFormatter

    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Palette.success)
                    .frame(width: 120, height: 120)
                    .blur(radius: 36)
                    .opacity(scheme == .dark ? 0.28 : 0.20)
                Circle()
                    .fill(Palette.success.opacity(scheme == .dark ? 0.20 : 0.16))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Circle().strokeBorder(Palette.success.opacity(0.35), lineWidth: 0.8)
                    }
                Image(systemName: Symbols.empty)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Palette.success)
            }
            .frame(width: 70, height: 70)
            .accessibilityHidden(true)

            Text(showingAllEvents ? "Nothing scheduled" : "All clear")
                .font(type.emptyTitle)
                .foregroundStyle(.primary)
                .padding(.top, 2)

            Text(formatter.emptyStateText(range: range, showingAllEvents: showingAllEvents))
                .font(type.emptyBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
