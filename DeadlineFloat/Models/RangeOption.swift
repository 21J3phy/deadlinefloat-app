import Foundation

/// How many days the panel shows: one, two, three, or the week. Each adds a
/// column to the calendar and widens the bar.
enum RangeOption: Int, CaseIterable, Identifiable, Codable, Sendable {
    case oneDay = 1
    case twoDays = 2
    case threeDays = 3
    case week = 7

    static let `default`: RangeOption = .oneDay

    var id: Int { rawValue }
    var days: Int { rawValue }

    /// Label inside the segmented control.
    var shortLabel: String {
        self == .week ? "Week" : "\(rawValue)d"
    }

    /// Label used in settings and the empty state.
    var longLabel: String {
        switch self {
        case .oneDay: return "1 day"
        case .week: return "week"
        default: return "\(rawValue) days"
        }
    }

    init(days: Int) {
        self = RangeOption(rawValue: days) ?? .default
    }
}
