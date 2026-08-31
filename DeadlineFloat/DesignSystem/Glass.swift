import SwiftUI

/// The role a glass surface plays, which determines how much it refracts.
enum GlassVariant: Sendable {
    /// Whole-window chrome.
    case window
    /// Buttons and the range selector — the floating control layer.
    case control
    /// Deadline rows.
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
struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var variant: GlassVariant = .card
    var tint: Color?
    var isInteractive: Bool = false
    var isHighlighted: Bool = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.isOffscreenRender) private var isOffscreenRender

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !isOffscreenRender {
            content.glassEffect(modernGlass, in: shape)
        } else {
            content.background { legacyGlass }
        }
    }

    // MARK: - macOS 26+

    @available(macOS 26.0, *)
    private var modernGlass: Glass {
        var glass: Glass
        switch variant {
        case .window, .control:
            glass = .regular
        case .card, .chip:
            glass = .clear
        }
        if let tint {
            glass = glass.tint(tint.opacity(modernTintStrength))
        } else if isHighlighted {
            glass = glass.tint(Color.primary.opacity(0.08))
        }
        return glass.interactive(isInteractive)
    }

    private var modernTintStrength: Double {
        switch variant {
        case .card: return isHighlighted ? 0.16 : 0.09
        default: return isHighlighted ? 0.30 : 0.20
        }
    }

    // MARK: - macOS 14–15 fallback

    private var isDark: Bool { scheme == .dark }

    private var baseFillOpacity: Double {
        let boost = isHighlighted ? 0.06 : 0.0
        switch variant {
        case .window: return (isDark ? 0.16 : 0.42) + boost
        case .control: return (isDark ? 0.13 : 0.50) + boost
        case .card: return (isDark ? 0.085 : 0.46) + boost
        case .chip: return (isDark ? 0.10 : 0.44) + boost
        }
    }

    private var legacyTintStrength: Double {
        switch variant {
        case .card: return isHighlighted ? 0.16 : 0.085
        default: return isHighlighted ? 0.26 : 0.17
        }
    }

    private var rimOpacity: (top: Double, bottom: Double) {
        switch variant {
        case .window: return isDark ? (0.34, 0.05) : (0.90, 0.20)
        case .control: return isDark ? (0.40, 0.06) : (0.95, 0.24)
        case .card: return isDark ? (0.22, 0.04) : (0.80, 0.16)
        case .chip: return isDark ? (0.26, 0.05) : (0.85, 0.18)
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

            // A whisper of the event's own Google colour. The stripe and the
            // calendar name carry the identity; a heavy wash here would make
            // the list harder to read, not easier.
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
            color: Color.black.opacity(isDark ? 0.28 : 0.10),
            radius: variant == .control ? 4 : 2,
            y: variant == .control ? 1.5 : 1
        )
    }
}

/// Set while rendering previews offscreen with `ImageRenderer`.
///
/// Three things behave differently in that pass and each is handled explicitly
/// rather than left to produce a broken image:
///
/// * Liquid Glass samples the real backdrop through the window server, which an
///   offscreen pass cannot see, so the layered fallback is used instead;
/// * `NSViewRepresentable` has no live view to draw, so the window drag handle
///   collapses to nothing;
/// * lazy stacks inside a `ScrollView` render no rows at all, so the list draws
///   eagerly.
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
        variant: GlassVariant = .card,
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

/// A round icon button in the floating control layer.
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
            .opacity(configuration.isPressed ? 0.62 : 1)
            .onHover { isHovering = $0 }
    }
}

/// A pill-shaped text button used in empty and error states.
struct GlassPillButtonStyle: ButtonStyle {
    var isProminent: Bool = false
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .contentShape(Capsule())
            .glassSurface(
                in: Capsule(),
                variant: .control,
                tint: isProminent ? Color.accentColor : nil,
                isInteractive: true,
                isHighlighted: isHovering
            )
            .opacity(configuration.isPressed ? 0.62 : 1)
            .onHover { isHovering = $0 }
    }
}
