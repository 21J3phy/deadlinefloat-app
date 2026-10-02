import Foundation

/// The stretch of each day the ruler and the calendar draw: from `startHour`
/// to `endHour`.
///
/// Midnight to midnight is the honest default — nothing is left out, and 3 AM
/// is where 3 AM is. But few people's days are twenty-four hours long, and the
/// small hours spend that height on nothing. Shortening the span puts the same
/// height behind fewer hours, so every block is taller, easier to read and
/// easier to take hold of.
///
/// `endHour` at or below `startHour` means the following morning, which is
/// what lets a day run to 1 AM. Nothing is ever hidden by the choice: an event
/// outside the span is still drawn, pinned to whichever end of its day it fell
/// off, and still counted everywhere else in the app.
struct DaySpan: Equatable, Hashable, Sendable, Codable {
    /// 0–23. The hour the day begins.
    private(set) var startHour: Int
    /// 0–23. On the same day when it is later than `startHour`, otherwise the
    /// next morning.
    private(set) var endHour: Int

    /// Midnight to midnight: the whole day, and the default.
    static let wholeDay = DaySpan(startHour: 0, endHour: 0)

    /// A ruler shorter than this is not a day, it is a sliver with three
    /// labels on it. The end is pushed out rather than the choice refused.
    static let minimumHours = 6

    init(startHour: Int, endHour: Int) {
        let start = Self.wrapped(startHour)
        var end = Self.wrapped(endHour)
        if Self.length(from: start, to: end) < Self.minimumHours {
            end = Self.wrapped(start + Self.minimumHours)
        }
        self.startHour = start
        self.endHour = end
    }

    /// True when the span runs through midnight into the next morning — which
    /// includes the whole day, whose end is the next midnight.
    var wraps: Bool { endHour <= startHour }

    /// How many hours long it is on an ordinary day. Twenty-three or
    /// twenty-five on the two days a year the clocks move.
    var hours: Int { Self.length(from: startHour, to: endHour) }

    var isWholeDay: Bool { self == .wholeDay }

    private static func wrapped(_ hour: Int) -> Int {
        let remainder = hour % 24
        return remainder < 0 ? remainder + 24 : remainder
    }

    private static func length(from start: Int, to end: Int) -> Int {
        end <= start ? 24 - start + end : end - start
    }
}
