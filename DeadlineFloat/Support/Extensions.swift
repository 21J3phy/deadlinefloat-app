import Foundation

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension String {
    /// Trimmed, case- and diacritic-insensitive form used for keyword matching.
    var normalizedForMatching: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Drops leading emoji, punctuation and whitespace so that "starts with"
    /// rules still fire on titles such as `🔴 DUE: Lab 3` or `[DUE] Essay`.
    var strippingLeadingDecoration: String {
        var scalars = Substring(self)
        while let first = scalars.first, !first.isLetter, !first.isNumber {
            scalars = scalars.dropFirst()
        }
        return String(scalars)
    }
}

extension Date {
    func adding(days: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: self) ?? addingTimeInterval(TimeInterval(days) * 86_400)
    }
}

extension Calendar {
    /// A calendar pinned to a time zone, leaving every other component intact.
    func inTimeZone(_ timeZone: TimeZone) -> Calendar {
        var copy = self
        copy.timeZone = timeZone
        return copy
    }
}
