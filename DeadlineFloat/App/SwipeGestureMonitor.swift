import AppKit
import Observation
import SwiftUI

/// Identifies a row for swipe tracking: the list it is in plus its deadline.
/// A deadline that has just been completed leaves the active list and enters
/// the drawer under a different key, so the row sliding out never inherits
/// the translation of the row sliding in.
struct SwipeRowKey: Hashable, Sendable {
    enum List: Hashable, Sendable {
        case active
        case completed
    }

    var list: List
    var deadlineID: String
}

/// Turns two-finger trackpad swipes over rows into completions.
///
/// SwiftUI's `DragGesture` sees mouse drags, not trackpad swipes: on macOS a
/// swipe is a run of scroll-wheel events. So one local event monitor watches
/// the panel's scroll events, works out which row the pointer is over from the
/// frames rows report, and hands the deltas to a `SwipeRecognizer`. Once a
/// gesture is horizontal its events are swallowed so the list does not scroll
/// sideways underneath; vertical gestures pass straight through untouched.
@MainActor
@Observable
final class SwipeGestureMonitor {
    private struct Target {
        var frame: CGRect
        var directions: SwipeDirections
    }

    /// The row being swiped right now, if any.
    private(set) var activeKey: SwipeRowKey?
    /// How far that row is drawn from its resting place.
    private(set) var translation: CGFloat = 0
    /// True once the swipe has gone far enough to commit on release.
    private(set) var isPastCommit = false

    var onCommit: ((SwipeRowKey, SwipeDirection) -> Void)?

    @ObservationIgnored private var targets: [SwipeRowKey: Target] = [:]
    @ObservationIgnored private var recognizer = SwipeRecognizer()
    @ObservationIgnored private var pendingKey: SwipeRowKey?
    @ObservationIgnored private var swallowMomentum = false
    @ObservationIgnored private var monitorToken: Any?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private weak var hosting: NSView?

    func install(window: NSWindow, hosting: NSView) {
        self.window = window
        self.hosting = hosting
        guard monitorToken == nil else { return }
        monitorToken = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            let swallowed = MainActor.assumeIsolated { self.handle(event) }
            return swallowed ? nil : event
        }
    }

    func uninstall() {
        if let monitorToken {
            NSEvent.removeMonitor(monitorToken)
            self.monitorToken = nil
        }
        settleTask?.cancel()
    }

    // MARK: - Rows

    func register(_ key: SwipeRowKey, frame: CGRect, directions: SwipeDirections) {
        targets[key] = Target(frame: frame, directions: directions)
    }

    func unregister(_ key: SwipeRowKey) {
        targets.removeValue(forKey: key)
        if activeKey == key { activeKey = nil; translation = 0; isPastCommit = false }
    }

    func translation(for key: SwipeRowKey) -> CGFloat {
        activeKey == key ? translation : 0
    }

    func isPastCommit(for key: SwipeRowKey) -> Bool {
        activeKey == key && isPastCommit
    }

    // MARK: - Events

    /// Returns `true` when the event belongs to a swipe and must not reach the
    /// scroll view.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, event.hasPreciseScrollingDeltas else { return false }

        if !event.momentumPhase.isEmpty {
            // Momentum after a horizontal swipe would scroll the list; eat it.
            let swallow = swallowMomentum
            if event.momentumPhase == .ended || event.momentumPhase == .cancelled { swallowMomentum = false }
            return swallow
        }

        switch event.phase {
        case .began:
            swallowMomentum = false
            settleTask?.cancel()
            guard let (key, target) = target(at: event.locationInWindow) else {
                recognizer.cancel()
                pendingKey = nil
                return false
            }
            recognizer.begin(directions: target.directions)
            pendingKey = key
            return false

        case .changed:
            guard let pendingKey else { return false }
            // Deltas are reported as content movement; undo the natural-scrolling
            // inversion so the row follows the fingers whichever way it is set.
            let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            let dy = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
            guard recognizer.move(dx: dx, dy: dy) else { return false }

            activeKey = pendingKey
            translation = recognizer.displayedTranslation
            let past = recognizer.isPastCommit
            if past != isPastCommit {
                isPastCommit = past
                if past { Haptics.threshold() }
            }
            return true

        case .ended, .cancelled:
            let wasHorizontal = recognizer.isHorizontal
            let direction: SwipeDirection?
            if event.phase == .ended {
                direction = recognizer.end()
            } else {
                recognizer.cancel()
                direction = nil
            }
            swallowMomentum = wasHorizontal
            pendingKey = nil
            isPastCommit = false

            if let direction, let key = activeKey {
                Haptics.commit()
                onCommit?(key, direction)
                // Leave the row where the fingers left it until its exit
                // animation has run, then forget it.
                settleTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(450))
                    guard let self, !Task.isCancelled, self.activeKey == key else { return }
                    self.activeKey = nil
                    self.translation = 0
                }
            } else if wasHorizontal {
                withAnimation(Motion.control) { translation = 0 }
                let key = activeKey
                settleTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(260))
                    guard let self, !Task.isCancelled, self.activeKey == key else { return }
                    self.activeKey = nil
                }
            }
            return wasHorizontal

        default:
            return false
        }
    }

    private func target(at locationInWindow: NSPoint) -> (SwipeRowKey, Target)? {
        guard let hosting else { return nil }
        var point = hosting.convert(locationInWindow, from: nil)
        if !hosting.isFlipped { point.y = hosting.bounds.height - point.y }
        return targets.first { $0.value.frame.contains(point) }.map { ($0.key, $0.value) }
    }
}
