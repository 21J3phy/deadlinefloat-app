import SwiftUI

/// A switch drawn in the app's own material.
///
/// AppKit's stock switch would be the obvious choice, but a hand-drawn one keeps
/// the settings window consistent with the panel's glass language and — since it
/// is pure SwiftUI — it survives the offscreen render used for the README
/// previews, where AppKit-backed controls draw nothing.
struct GlassToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

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
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }

    private func track(isOn: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(scheme == .dark ? 0.17 : 0.13)))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(scheme == .dark ? 0.16 : 0.45), lineWidth: 0.6)
            }
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)
                    .padding(2)
            }
            .animation(.snappy(duration: 0.16), value: isOn)
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
        HStack(spacing: 5) {
            button(symbol: Symbols.remove, enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }
            Text(format(value))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .frame(minWidth: 30)
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
        }
        .buttonStyle(GlassCircleButtonStyle(diameter: 19))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// A slider in the app's material, with a live readout.
struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var width: CGFloat = 148

    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    var body: some View {
        GeometryReader { proxy in
            let usable = max(1, proxy.size.width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(scheme == .dark ? 0.16 : 0.12))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: usable * fraction, height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 0.5)
                    .offset(x: (usable - 14) * fraction)
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let position = min(1, max(0, gesture.location.x / usable))
                        value = range.lowerBound + position * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .frame(width: width, height: 16)
        .opacity(isEnabled ? 1 : 0.45)
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

/// Text-field chrome that matches the glass cards, replacing the stock rounded
/// border which reads as a foreign object inside this window.
struct GlassFieldChrome: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(scheme == .dark ? 0.09 : 0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.16 : 0.12), lineWidth: 0.7)
            }
    }
}

extension View {
    func glassField() -> some View { modifier(GlassFieldChrome()) }
}
