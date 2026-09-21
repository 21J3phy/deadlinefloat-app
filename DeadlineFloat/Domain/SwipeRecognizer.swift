import Foundation

/// Which way a row was swiped.
enum SwipeDirection: Equatable, Sendable {
    case left
    case right
}

/// The directions a row responds to.
struct SwipeDirections: OptionSet, Sendable, Equatable {
    let rawValue: Int
    static let left = SwipeDirections(rawValue: 1)
    static let right = SwipeDirections(rawValue: 2)
    static let both: SwipeDirections = [.left, .right]

    func allows(_ direction: SwipeDirection) -> Bool {
        switch direction {
        case .left: return contains(.left)
        case .right: return contains(.right)
        }
    }
}

/// Turns a stream of two-finger trackpad deltas into a horizontal swipe.
///
/// A trackpad swipe arrives as scroll-wheel deltas, not as a drag, so the
/// recogniser accumulates them and decides — once the fingers have moved a
/// little — whether the gesture is horizontal (ours) or vertical (the scroll
/// view's). A horizontal gesture commits when it travels `commitDistance`;
/// beyond that the row keeps following the fingers, with resistance, so the
/// user can feel that there is nothing further to reach.
struct SwipeRecognizer: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case undecided
        case horizontal
        case vertical
    }

    /// Movement before the gesture is classified.
    static let lockDistance: CGFloat = 8
    /// Horizontal travel that commits the swipe.
    static let commitDistance: CGFloat = 88

    private(set) var phase: Phase = .idle
    private(set) var dx: CGFloat = 0
    private(set) var dy: CGFloat = 0
    private(set) var directions: SwipeDirections = []

    mutating func begin(directions: SwipeDirections) {
        phase = .undecided
        dx = 0
        dy = 0
        self.directions = directions
    }

    /// Feeds one movement. Returns `true` when the gesture is horizontal and
    /// the event should be kept from the scroll view.
    mutating func move(dx: CGFloat, dy: CGFloat) -> Bool {
        guard phase != .idle else { return false }
        self.dx += dx
        self.dy += dy
        if phase == .undecided, (self.dx * self.dx + self.dy * self.dy).squareRoot() >= Self.lockDistance {
            phase = abs(self.dx) > abs(self.dy) * 1.2 ? .horizontal : .vertical
        }
        return phase == .horizontal
    }

    /// Ends the gesture, returning the direction to commit, if the swipe
    /// travelled far enough in a direction the row allows.
    mutating func end() -> SwipeDirection? {
        defer { phase = .idle }
        guard phase == .horizontal else { return nil }
        if dx <= -Self.commitDistance, directions.allows(.left) { return .left }
        if dx >= Self.commitDistance, directions.allows(.right) { return .right }
        return nil
    }

    mutating func cancel() {
        phase = .idle
    }

    var isHorizontal: Bool { phase == .horizontal }

    /// Whether the fingers are currently past the commit distance in an
    /// allowed direction — the moment to tap the trackpad.
    var isPastCommit: Bool {
        guard phase == .horizontal else { return false }
        if dx <= -Self.commitDistance, directions.allows(.left) { return true }
        if dx >= Self.commitDistance, directions.allows(.right) { return true }
        return false
    }

    /// How far to draw the row from its resting place. Follows the fingers up
    /// to the commit distance, then with resistance; a direction the row does
    /// not allow only gives a little, so it reads as "nothing here".
    var displayedTranslation: CGFloat {
        guard phase == .horizontal else { return 0 }
        let sign: CGFloat = dx < 0 ? -1 : 1
        let magnitude = abs(dx)
        let allowed = directions.allows(dx < 0 ? .left : .right)
        guard allowed else { return sign * min(magnitude, 40) * 0.25 }
        if magnitude <= Self.commitDistance { return dx }
        return sign * (Self.commitDistance + (magnitude - Self.commitDistance) * 0.3)
    }
}
