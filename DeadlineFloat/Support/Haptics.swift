import AppKit

/// The trackpad taps the interface uses. Each maps to one of the system's
/// patterns so it feels like the rest of macOS; on a trackpad without haptics
/// they are silently no-ops.
@MainActor
enum Haptics {
    /// Crossing the barrier between the list and the completed drawer.
    static func barrier() { perform(.alignment) }
    /// A swipe has travelled far enough to commit when released.
    static func threshold() { perform(.alignment) }
    /// A deadline was marked done or brought back.
    static func commit() { perform(.levelChange) }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
