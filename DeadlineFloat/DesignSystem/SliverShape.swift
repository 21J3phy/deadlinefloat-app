import SwiftUI

/// The sliver's outline: a strip flush with a screen edge, rounded on its
/// inner side and flaring out at the screen side with reverse-radius fillets
/// at top and bottom, so it reads as the display's bezel reaching into the
/// screen rather than a bar laid on top of it.
///
/// The strip itself sits `fillet` points in from the top and bottom of the
/// rect; the fillets occupy that margin against the screen edge.
struct SliverShape: InsettableShape {
    var edge: ScreenEdge
    var cornerRadius: CGFloat = 6
    var fillet: CGFloat = 8
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> SliverShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in outer: CGRect) -> Path {
        let rect = outer.insetBy(dx: insetAmount, dy: insetAmount)
        // Built for the right edge, then mirrored for the left.
        let width = rect.width
        let top = rect.minY + fillet
        let bottom = rect.maxY - fillet
        let right = rect.maxX
        let left = right - width
        let r = min(cornerRadius, width / 2, (bottom - top) / 2)
        let f = fillet
        let k: CGFloat = 0.552_284_75

        var path = Path()
        path.move(to: CGPoint(x: right - f, y: top))
        // Top fillet: curves up into the screen edge.
        path.addCurve(
            to: CGPoint(x: right, y: top - f),
            control1: CGPoint(x: right - f + k * f, y: top),
            control2: CGPoint(x: right, y: top - f + k * f)
        )
        path.addLine(to: CGPoint(x: right, y: bottom + f))
        // Bottom fillet: curves back in to the strip.
        path.addCurve(
            to: CGPoint(x: right - f, y: bottom),
            control1: CGPoint(x: right, y: bottom + f - k * f),
            control2: CGPoint(x: right - f + k * f, y: bottom)
        )
        path.addLine(to: CGPoint(x: left + r, y: bottom))
        // Inner corners: ordinary rounding.
        path.addCurve(
            to: CGPoint(x: left, y: bottom - r),
            control1: CGPoint(x: left + r - k * r, y: bottom),
            control2: CGPoint(x: left, y: bottom - r + k * r)
        )
        path.addLine(to: CGPoint(x: left, y: top + r))
        path.addCurve(
            to: CGPoint(x: left + r, y: top),
            control1: CGPoint(x: left, y: top + r - k * r),
            control2: CGPoint(x: left + r - k * r, y: top)
        )
        path.closeSubpath()

        if edge == .left {
            let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0)
            return path.applying(mirror)
        }
        return path
    }
}
