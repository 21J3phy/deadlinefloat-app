import Foundation

/// The two resting places of the panel's scroll view: the default view, with
/// the active list at the top, and the completed drawer that sits above it.
///
/// The list is one scroll view whose content is `[completed drawer][active
/// list]`. Scrolling is free inside either part, but moving from one to the
/// other means crossing a barrier: a scroll that ends short of it snaps back to
/// where it started, and one that crosses it lands on the other side. The
/// barrier is measured from the side you are leaving, so it is hysteretic —
/// leaving the default view takes `barrierDepth` of upward travel, and coming
/// back takes `barrierDepth` of downward travel — which is what makes it feel
/// like a notch rather than a line.
struct DrawerDetents: Equatable, Sendable {
    enum Side: Equatable, Sendable {
        case active
        case completed
    }

    /// Content offset at which the active list begins — the drawer's height.
    var activeTop: CGFloat
    /// Height of the scroll view's viewport.
    var viewportHeight: CGFloat

    /// How far past the edge a scroll must travel before it counts as crossing.
    static let barrierDepth: CGFloat = 72

    /// Where the drawer rests: its top, or — for a drawer taller than the
    /// viewport — the offset that shows its bottom, nearest the active list.
    var completedRest: CGFloat { max(0, activeTop - viewportHeight) }

    /// The offset the barrier sits at when leaving `side`.
    func barrier(leaving side: Side) -> CGFloat {
        switch side {
        case .active: return activeTop - min(Self.barrierDepth, activeTop / 2)
        case .completed: return min(completedRest + Self.barrierDepth, activeTop)
        }
    }

    /// Which side an offset is on, given the side the user is currently on.
    func side(at offset: CGFloat, current: Side) -> Side {
        switch current {
        case .active: return offset < barrier(leaving: .active) ? .completed : .active
        case .completed: return offset > barrier(leaving: .completed) ? .active : .completed
        }
    }

    /// Where a scroll that would end at `proposed` actually comes to rest.
    func restingOffset(for proposed: CGFloat, from side: Side) -> CGFloat {
        switch side {
        case .active:
            if proposed >= activeTop { return proposed }
            return proposed < barrier(leaving: .active) ? completedRest : activeTop
        case .completed:
            if proposed <= completedRest { return proposed }
            return proposed > barrier(leaving: .completed) ? activeTop : completedRest
        }
    }
}
