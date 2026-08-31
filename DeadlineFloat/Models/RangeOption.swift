import Foundation

/// The date-range segmented control: today plus 2, 3 or 4 calendar days.
enum RangeOption: Int, CaseIterable, Identifiable, Codable, Sendable {
    case twoDays = 2
    case threeDays = 3
    case fourDays = 4

    static let `default`: RangeOption = .threeDays

    var id: Int { rawValue }
    var days: Int { rawValue }

    /// Label inside the segmented control.
    var shortLabel: String { "\(rawValue)d" }

    /// Label used in menus, settings and the empty state.
    var longLabel: String { "\(rawValue) days" }

    init(days: Int) {
        self = RangeOption(rawValue: days) ?? .default
    }
}
