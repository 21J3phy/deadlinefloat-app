import SwiftUI

/// The date-range control: today plus 2, 3 or 4 calendar days.
///
/// A recessed track with a single Liquid Glass pill that slides to the selection
/// — the same shape language as the system's own segmented controls under
/// Liquid Glass.
struct RangeSelector: View {
    var selection: RangeOption
    var onSelect: (RangeOption) -> Void

    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var scheme
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 1) {
            ForEach(RangeOption.allCases) { option in
                segment(for: option)
            }
        }
        .padding(2)
        .background {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.07))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
        }
        .glassGroup(spacing: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Date range")
    }

    private func segment(for option: RangeOption) -> some View {
        let isSelected = option == selection
        return Button {
            guard !isSelected else { return }
            onSelect(option)
        } label: {
            Text(option.shortLabel)
                .font(type.segment)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(minWidth: 26)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Color.clear
                    .glassSurface(in: Capsule(style: .continuous), variant: .control, isInteractive: true)
                    .matchedGeometryEffect(id: "range-pill", in: pill)
            }
        }
        .animation(.snappy(duration: 0.2), value: selection)
        .help("Today plus \(option.longLabel)")
        .accessibilityLabel("Today plus \(option.longLabel)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
