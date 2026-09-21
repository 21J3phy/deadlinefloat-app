import SwiftUI

/// How far the sliver has become the panel: 0 is the strip at the screen
/// edge, 1 the open panel. Views inside the bar read it to stretch, dissolve
/// and fade in step. The dropdown panel and offscreen renders see 1.
private struct MorphProgressKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

extension EnvironmentValues {
    var morphProgress: Double {
        get { self[MorphProgressKey.self] }
        set { self[MorphProgressKey.self] = newValue }
    }
}

/// The sliver's width from Settings, for everything that draws the strip or
/// stretches out of it.
private struct SliverWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = Metrics.sliverWidth
}

extension EnvironmentValues {
    var sliverWidth: CGFloat {
        get { self[SliverWidthKey.self] }
        set { self[SliverWidthKey.self] = newValue }
    }
}

/// Carries the morph through an animation. Being animatable, its body runs
/// for every frame with the in-between value, so everything below it that
/// reads `morphProgress` moves with it — including a subtree inserted in the
/// same update the stretch begins.
struct MorphProgress: ViewModifier, Animatable {
    var progress: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.environment(\.morphProgress, progress)
    }
}

/// The shape and timing of the sliver stretching into the panel.
///
/// The strip widens sideways from the screen edge until it is the sheet; its
/// inner corners round out from the strip's radius to the panel's and its
/// fillets flatten on the way. It is the same glass throughout. The content
/// fades in inside the sheet over the second half, so nothing ever shows
/// outside it.
enum MorphGeometry {
    static func shape(edge: ScreenEdge, progress: Double) -> SliverShape {
        SliverShape(
            edge: edge,
            cornerRadius: lerp(DayRailView.cornerRadius, Metrics.windowCornerRadius, progress),
            fillet: lerp(DayRailView.fillet, 0, progress)
        )
    }

    /// The sheet's width, from the strip's to the panel's.
    static func width(of full: CGFloat, from strip: CGFloat, progress: Double) -> CGFloat {
        lerp(strip, full, progress)
    }

    /// Content inside the sheet: tasks, hour lines, labels, other days.
    static func reveal(_ progress: Double) -> Double { unit((progress - 0.4) / 0.6) }
    /// What only the strip has, such as the needle's dot.
    static func strip(_ progress: Double) -> Double { 1 - unit(progress / 0.25) }

    /// Clamped, so a spring's overshoot never turns a fillet inside out.
    static func lerp(_ from: CGFloat, _ to: CGFloat, _ t: Double) -> CGFloat {
        from + (to - from) * CGFloat(unit(t))
    }

    static func mix(_ from: Double, _ to: Double, _ t: Double) -> Double {
        from + (to - from) * unit(t)
    }

    static func blend(_ from: CGRect, _ to: CGRect, _ t: Double) -> CGRect {
        CGRect(
            x: lerp(from.minX, to.minX, t),
            y: lerp(from.minY, to.minY, t),
            width: lerp(from.width, to.width, t),
            height: lerp(from.height, to.height, t)
        )
    }

    private static func unit(_ x: Double) -> Double { min(1, max(0, x)) }
}

/// The sheet at the current point of the morph: the sliver's dark glass,
/// widening from the screen edge into the panel's.
struct MorphSheet: View {
    let edge: ScreenEdge
    /// The panel's width when fully open.
    let fullWidth: CGFloat

    @Environment(\.morphProgress) private var progress
    @Environment(\.sliverWidth) private var sliverWidth
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = MorphGeometry.shape(edge: edge, progress: progress)
        Color.clear
            .glassSurface(in: shape, variant: .window)
            .overlay { shape.fill(Palette.scrim(scheme, contrast)) }
            // The strip's extra depth, gone by the time the content shows.
            .overlay {
                shape.fill(Palette.sliverScrim(scheme, contrast))
                    .opacity(1 - MorphGeometry.reveal(progress))
            }
            .frame(width: MorphGeometry.width(of: fullWidth, from: sliverWidth, progress: progress))
            .frame(maxHeight: .infinity)
    }
}

/// Holds the panel's content at its full layout and shows only as much of
/// it as the sheet has grown to cover — a plain rectangular clip, so the
/// glass inside it keeps compositing on screen.
struct MorphClip<Content: View>: View {
    let edge: ScreenEdge
    let fullWidth: CGFloat
    @ViewBuilder let content: Content

    @Environment(\.morphProgress) private var progress
    @Environment(\.sliverWidth) private var sliverWidth

    var body: some View {
        content
            .frame(width: fullWidth)
            .frame(width: MorphGeometry.width(of: fullWidth, from: sliverWidth, progress: progress), alignment: edge == .right ? .trailing : .leading)
            .clipped()
    }
}

/// An event's title run along its block on the sliver: laid out along the
/// block's length, then turned to stand on the strip — top to bottom on a
/// right-hand bar, bottom to top on a left-hand one, like a spine — and dark
/// or light by the block's colour, as on the calendar.
struct SliverTitle: View {
    let item: Deadline
    /// The block's length down the strip.
    let length: CGFloat
    /// The strip's width.
    let width: CGFloat
    let edge: ScreenEdge

    /// Long enough to carry a few characters.
    static let minimumLength: CGFloat = 44

    private var ink: Color {
        item.color.relativeLuminance > 0.42 ? Color(white: 0.11) : .white
    }

    var body: some View {
        let size = min(11, max(7, (width * 0.75).rounded()))
        Text(item.title)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: max(0, length - 8), height: width)
            .rotationEffect(.degrees(edge == .right ? 90 : -90))
            .frame(width: width, height: length)
            .accessibilityHidden(true)
    }
}

/// Fades content in as the sheet grows around it, and out as it shrinks.
struct MorphReveal: ViewModifier {
    @Environment(\.morphProgress) private var progress

    func body(content: Content) -> some View {
        content.opacity(MorphGeometry.reveal(progress))
    }
}
