import SwiftUI

/// A switch drawn in the app's own material.
///
/// AppKit's stock switch would be the obvious choice, but a hand-drawn one keeps
/// the settings window consistent with the panel's language and — since it is
/// pure SwiftUI — it survives the offscreen render used for the README
/// previews, where AppKit-backed controls draw nothing.
struct GlassToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                configuration.label
                track(isOn: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }

    private func track(isOn: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(isOn
                  ? AnyShapeStyle(Color.accentColor)
                  : AnyShapeStyle(Color.primary.opacity(scheme == .dark ? 0.20 : 0.14)))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.40), lineWidth: 0.6)
            }
            .overlay {
                if isHovering {
                    Capsule(style: .continuous).fill(Color.white.opacity(0.06))
                }
            }
            .frame(width: 36, height: 21)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 17, height: 17)
                    .shadow(color: .black.opacity(0.30), radius: 1.5, y: 0.8)
                    .padding(2)
            }
            .animation(Motion.control, value: isOn)
            .animation(Motion.quick, value: isHovering)
    }
}

extension ToggleStyle where Self == GlassToggleStyle {
    static var glassSwitch: GlassToggleStyle { GlassToggleStyle() }
}

/// Minus / plus in the same round glass as the header buttons.
struct GlassStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var format: (Int) -> String

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 6) {
            button(symbol: Symbols.remove, enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }
            Text(format(value))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .frame(minWidth: 34)
                .contentTransition(.numericText())
                .animation(Motion.digits, value: value)
            button(symbol: Symbols.add, enabled: value < range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func button(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary)
        }
        .buttonStyle(GlassCircleButtonStyle(diameter: 20))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// A slider in the app's material, with a live readout.
struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var width: CGFloat = 150

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    @State private var isDragging = false

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    private var knobSize: CGFloat { isDragging ? 18 : (isHovering ? 17 : 15) }

    var body: some View {
        GeometryReader { proxy in
            let usable = max(1, proxy.size.width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.track(scheme, contrast))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, usable * fraction), height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.32), radius: 2, y: 0.8)
                    .offset(x: (usable - knobSize) * fraction)
                    .animation(Motion.quick, value: knobSize)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let position = min(1, max(0, gesture.location.x / usable))
                        value = range.lowerBound + position * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(width: width, height: 20)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
        .accessibilityElement()
        .accessibilityValue("\(Int(fraction * 100)) percent")
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}

/// A recessed track with one Liquid Glass pill that slides to the selection —
/// the same shape language as the system's segmented controls under Liquid
/// Glass. Used for the date range in the header and for choices in Settings.
struct SegmentedGlassControl<Value: Hashable>: View {
    struct Option: Identifiable {
        var value: Value
        var label: String
        var symbol: String?
        var help: String?
        var id: Value { value }

        init(_ value: Value, _ label: String, symbol: String? = nil, help: String? = nil) {
            self.value = value
            self.label = label
            self.symbol = symbol
            self.help = help
        }
    }

    let options: [Option]
    @Binding var selection: Value
    var minimumSegmentWidth: CGFloat = 30

    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(2)
        .background {
            Capsule(style: .continuous)
                .fill(Palette.track(scheme, contrast))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                }
        }
        .glassGroup(spacing: 6)
        .fixedSize()
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .contain)
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return SegmentButton(
            label: option.label,
            symbol: option.symbol,
            isSelected: isSelected,
            minimumWidth: minimumSegmentWidth,
            font: type.segment,
            namespace: pill
        ) {
            guard !isSelected else { return }
            if reduceMotion {
                selection = option.value
            } else {
                withAnimation(Motion.control) { selection = option.value }
            }
        }
        .help(option.help ?? option.label)
        .accessibilityLabel(option.help ?? option.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct SegmentButton: View {
    let label: String
    let symbol: String?
    let isSelected: Bool
    let minimumWidth: CGFloat
    let font: Font
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .accessibilityLabel(label)
                } else {
                    Text(label)
                        .font(font)
                        .monospacedDigit()
                }
            }
                .foregroundStyle(isSelected || isHovering ? Color.primary : Color.secondary)
                .frame(minWidth: minimumWidth)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .contentShape(Capsule(style: .continuous))
                .modifier(SegmentPill(isSelected: isSelected, namespace: namespace))
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: isHovering)
        .onHover { isHovering = $0 }
    }
}

/// The sliding pill behind the selected segment.
///
/// On macOS 26 the label itself becomes glass, and `glassEffectID` lets the
/// system morph that glass from the old segment to the new one inside the
/// surrounding `GlassEffectContainer`. Putting the glass in a `.background`
/// instead would composite it *above* the label text, hiding it. Earlier
/// systems draw the layered fallback behind the label and slide it with a
/// matched geometry effect.
private struct SegmentPill: ViewModifier {
    let isSelected: Bool
    let namespace: Namespace.ID

    @Environment(\.isOffscreenRender) private var isOffscreenRender

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !isOffscreenRender {
            if isSelected {
                content
                    .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
                    .glassEffectID("segment-pill", in: namespace)
            } else {
                content
            }
        } else {
            content.background {
                if isSelected {
                    Color.clear
                        .glassSurface(in: Capsule(style: .continuous), variant: .control, isInteractive: true)
                        .matchedGeometryEffect(id: "segment-pill", in: namespace)
                }
            }
        }
    }
}

/// Text-field chrome that matches the settings cards, replacing the stock
/// rounded border which reads as a foreign object inside this window.
struct GlassFieldChrome: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(scheme == .dark ? 0.09 : 0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.16 : 0.12), lineWidth: 0.7)
            }
    }
}

extension View {
    func glassField() -> some View { modifier(GlassFieldChrome()) }
}
