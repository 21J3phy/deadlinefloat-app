import Foundation
import Observation

/// What one edge bar is doing right now. Owned by its controller, read by
/// its views.
@MainActor
@Observable
final class EdgeBarState {
    /// Slid out to the full panel, or resting as the sliver.
    var isExpanded = false
    /// Held open by a click or the pin button; hover no longer closes it.
    var isPinned = false
    /// The edge this bar is docked to, after avoiding the Dock.
    var edge: ScreenEdge = .right

    init(isExpanded: Bool = false, isPinned: Bool = false, edge: ScreenEdge = .right) {
        self.isExpanded = isExpanded
        self.isPinned = isPinned
        self.edge = edge
    }
}

/// Maps a ruler fraction to a vertical position, shared by the SwiftUI rail
/// and the AppKit code that places the callout window beside it.
enum RulerGeometry {
    /// The height of the ruler itself, between the insets.
    static func trackHeight(in height: CGFloat) -> CGFloat {
        max(0, height - Metrics.rulerTopInset - Metrics.rulerBottomInset)
    }

    static func y(fraction: Double, height: CGFloat) -> CGFloat {
        Metrics.rulerTopInset + CGFloat(fraction) * trackHeight(in: height)
    }

    static func fraction(y: CGFloat, height: CGFloat) -> Double {
        let usable = max(1, trackHeight(in: height))
        return Double(min(1, max(0, (y - Metrics.rulerTopInset) / usable)))
    }
}
