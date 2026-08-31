import SwiftUI

/// Shown when the range holds nothing. Deliberately calm: an empty list is good
/// news, not an error.
struct EmptyStateView: View {
    let range: RangeOption
    let showingAllEvents: Bool
    let formatter: DeadlineFormatter

    @Environment(\.typography) private var type

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: Symbols.empty)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(formatter.emptyStateText(range: range, showingAllEvents: showingAllEvents))
                .font(type.emptyTitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(showingAllEvents ? "Nothing scheduled in this range." : "Nothing matches your deadline keywords in this range.")
                .font(type.emptyBody)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
