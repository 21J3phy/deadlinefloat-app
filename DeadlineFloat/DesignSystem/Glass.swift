import SwiftUI

/// The role a glass surface plays, which determines how much it refracts.
enum GlassVariant: Sendable {
    /// Whole-window chrome.
    case window
    /// Buttons and the range selector — the floating control layer.
    case control
    /// Larger content surfaces such as the sign-in card.
    case card
    /// Small status pills.
    case chip
}

/// Applies Liquid Glass to a shape.
///
/// On macOS 26 and later this is the real system effect (`glassEffect(_:in:)`),
/// including the specular edge, refraction of whatever is behind the window, and
/// the interactive press response. On macOS 14–15 it falls back to a layered
/// approximation: translucent fill, vertical sheen, specular top edge and a
/// gradient rim, which reads as the same material rather than as flat chrome.
///
/// Glass is reserved for the *control* layer. Content — rows, section titles,
/// the spotlight — sits directly on the window material, which is what keeps
/// the panel reading as one object instead of a stack of tinted boxes.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var variant: GlassVariant = .control
    var tint: Color?
    var isInteractive: Bool = false
    var isHighlighted: Bool = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.isOffscreenRender) private var isOffscreenRender
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background { solidSurface }
        } else if #available(macOS 26.0, *), !isOffscreenRender {
            content.glassEffect(modernGlass, in: shape)
        } else {
            content.background { legacyGlass }
        }
    }

    /// Reduce Transparency: the window background colour, opaque, with a
    /// hairline — text never sits over a moving backdrop.
    private var solidSurface: some View {
        ZStack {
            shape.fill(Color(nsColor: .windowBackgroundColor))
            if let tint { shape.fill(tint.opacity(0.35)) }
            if isHighlighted { shape.fill(Color.primary.opacity(0.08)) }
            shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    // MARK: - macOS 26+

    @available(macOS 26.0, *)
    private var modernGlass: Glass {
        var glass: Glass
        switch variant {
        case .window, .control, .card:
            glass = .regular
        case .chip:
            glass = .clear
        }
        if let tint {
            glass = glass.tint(tint.opacity(modernTintStrength))
        } else if isHighlighted {
            glass = glass.tint(Color.primary.opacity(0.10))
        }
        return glass.interactive(isInteractive)
    }

    private var modernTintStrength: Double {
        switch variant {
        case .chip: return isHighlighted ? 0.28 : 0.18
        default: return isHighlighted ? 0.34 : 0.24
        }
    }

    // MARK: - macOS 14–15 fallback

    private var isDark: Bool { scheme == .dark }

    private var baseFillOpacity: Double {
        let boost = isHighlighted ? 0.07 : 0.0
        switch variant {
        case .window: return (isDark ? 0.12 : 0.40) + boost
        case .control: return (isDark ? 0.14 : 0.52) + boost
        case .card: return (isDark ? 0.08 : 0.42) + boost
        case .chip: return (isDark ? 0.10 : 0.46) + boost
        }
    }

    private var legacyTintStrength: Double {
        switch variant {
        case .chip: return isHighlighted ? 0.22 : 0.15
        default: return isHighlighted ? 0.30 : 0.22
        }
    }

    private var rimOpacity: (top: Double, bottom: Double) {
        switch variant {
        case .window: return isDark ? (0.34, 0.05) : (0.90, 0.20)
        case .control: return isDark ? (0.42, 0.07) : (0.95, 0.26)
        case .card: return isDark ? (0.22, 0.04) : (0.80, 0.16)
        case .chip: return isDark ? (0.28, 0.05) : (0.85, 0.18)
        }
    }

    @ViewBuilder
    private var legacyGlass: some View {
        let rim = rimOpacity
        ZStack {
            // Diffuse body of the material.
            shape.fill(Color.white.opacity(baseFillOpacity))

            // Vertical sheen: brighter at the top, as light falls across glass.
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isDark ? 0.10 : 0.30),
                        Color.white.opacity(0.0),
                        Color.black.opacity(isDark ? 0.05 : 0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            if let tint {
                shape.fill(tint.opacity(legacyTintStrength))
            }

            // Specular rim: bright top-leading edge decaying to the shadow side.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(rim.top),
                        Color.white.opacity((rim.top + rim.bottom) / 2.4),
                        Color.white.opacity(rim.bottom)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        }
        .compositingGroup()
        .shadow(
            color: Color.black.opacity(isDark ? 0.30 : 0.10),
            radius: variant == .control ? 4 : 2,
            y: variant == .control ? 1.5 : 1
        )
    }
}

/// Set while rendering previews offscreen with `ImageRenderer`.
///
/// Four things behave differently in that pass and each is handled explicitly
/// rather than left to produce a broken image:
///
/// * Liquid Glass samples the real backdrop through the window server, which an
///   offscreen pass cannot see, so the layered fallback is used instead;
/// * `NSViewRepresentable` has no live view to draw, so the window drag handle
///   and the settings sidebar material collapse to plain views;
/// * lazy stacks inside a `ScrollView` render no rows at all, so the list draws
///   eagerly;
/// * the spotlight's live clock is replaced by the preview's fixed reference
///   time, so its countdown agrees with the rows around it.
private struct OffscreenRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isOffscreenRender: Bool {
        get { self[OffscreenRenderKey.self] }
        set { self[OffscreenRenderKey.self] = newValue }
    }
}

extension View {
    /// Wraps the view in a Liquid Glass surface of the given shape.
    func glassSurface<S: InsettableShape>(
        in shape: S,
        variant: GlassVariant = .control,
        tint: Color? = nil,
        isInteractive: Bool = false,
        isHighlighted: Bool = false
    ) -> some View {
        modifier(
            GlassSurface(
                shape: shape,
                variant: variant,
                tint: tint,
                isInteractive: isInteractive,
                isHighlighted: isHighlighted
            )
        )
    }

    /// Groups nearby glass surfaces so they merge and share one render pass.
    /// A no-op before macOS 26.
    @ViewBuilder
    func glassGroup(spacing: CGFloat? = nil) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// Marks this subtree as an offscreen render pass.
    func offscreenRendering() -> some View {
        environment(\.isOffscreenRender, true)
    }
}

// MARK: - Button styles

/// A round icon button that is its own piece of glass.
struct GlassCircleButtonStyle: ButtonStyle {
    var diameter: CGFloat = Metrics.controlDiameter
    var isHighlighted: Bool = false
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .glassSurface(
                in: Circle(),
                variant: .control,
                isInteractive: true,
                isHighlighted: isHighlighted || isHovering
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .animation(Motion.quick, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

/// An icon button that lives *inside* a shared glass capsule — the header's
/// control group. It draws no glass of its own, only a hover disc, so several
/// of them read as one control.
struct GlassIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = Metrics.controlDiameter
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovering && isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (isHovering ? 0.09 : 0)))
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(Motion.quick, value: configuration.isPressed)
            .animation(Motion.quick, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

/// A pill-shaped text button. `isProminent` makes it the one call to action on
/// screen: accent-tinted glass with white text.
struct GlassPillButtonStyle: ButtonStyle {
    var isProminent: Bool = false
    var isLarge: Bool = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isOffscreenRender) private var isOffscreenRender
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isLarge ? 13 : 12, weight: isProminent ? .semibold : .medium))
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .padding(.horizontal, isLarge ? 16 : 12)
            .padding(.vertical, isLarge ? 8 : 5.5)
            .contentShape(Capsule())
            .background { prominentFallback }
            .modifier(surface)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : (isEnabled ? 1 : 0.5))
            .animation(Motion.quick, value: configuration.isPressed)
            .animation(Motion.quick, value: isHovering)
            .onHover { isHovering = $0 }
    }

    private var surface: some ViewModifier {
        GlassSurface(
            shape: Capsule(style: .continuous),
            variant: .control,
            tint: isProminent ? Color.accentColor : nil,
            isInteractive: true,
            isHighlighted: isHovering
        )
    }

    /// Before macOS 26 the layered glass cannot carry enough tint to read as a
    /// primary button, so the prominent style gets a solid accent body underneath.
    @ViewBuilder
    private var prominentFallback: some View {
        if isProminent, !Runtime.supportsLiquidGlass || isOffscreenRender {
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(isHovering ? 1 : 0.92))
        }
    }
}
