import Foundation

/// A titled group of deadlines. Section order is the order the app renders them.
struct DeadlineSection: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case overdue
        case today
        case tomorrow
        /// Any later day, keyed by its local midnight.
        case day(Date)
    }

    let kind: Kind
    let title: String
    let deadlines: [Deadline]

    var id: String {
        switch kind {
        case .overdue: return "overdue"
        case .today: return "today"
        case .tomorrow: return "tomorrow"
        case .day(let date): return "day-\(date.timeIntervalSinceReferenceDate)"
        }
    }

    var isOverdue: Bool { kind == .overdue }
}
