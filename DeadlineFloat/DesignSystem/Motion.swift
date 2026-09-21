import SwiftUI

/// The handful of animations the interface uses, so every transition shares
/// one feel. Views consult `accessibilityReduceMotion` before using the ones
/// that move things.
enum Motion {
    /// Hover highlights and other instant feedback.
    static let quick = Animation.easeOut(duration: 0.14)
    /// Selection pills and toggles.
    static let control = Animation.snappy(duration: 0.22, extraBounce: 0.02)
    /// Rows entering, leaving and reordering.
    static let list = Animation.spring(response: 0.36, dampingFraction: 0.86)
    /// Countdown digits rolling over.
    static let digits = Animation.snappy(duration: 0.26)
    /// Whole panes cross-fading.
    static let pane = Animation.easeInOut(duration: 0.18)
    /// The sliver stretching sideways into the panel, and shrinking back.
    static let morph = Animation.smooth(duration: morphDuration)
    /// How long that takes; the window narrows only once it is over.
    static let morphDuration: TimeInterval = 0.38

    /// Rows fade and rise into place; removal is a plain fade so a disappearing
    /// row never looks like it slid somewhere.
    static var rowTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity
        )
    }

    /// A row leaving after a swipe keeps travelling the way it was pushed.
    static var rowExit: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity.combined(with: .offset(x: -40))
        )
    }
}
