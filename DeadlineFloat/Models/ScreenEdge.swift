import Foundation

/// The screen edge the bar docks to.
enum ScreenEdge: String, CaseIterable, Identifiable, Codable, Sendable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }

    var opposite: ScreenEdge {
        self == .left ? .right : .left
    }
}
