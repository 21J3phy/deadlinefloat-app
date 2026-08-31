import Foundation

/// Decides whether an event title describes a deadline.
///
/// Matching is case- and diacritic-insensitive. `Starts with` rules ignore
/// leading decoration, so `🔴 DUE: Lab 3` and `[DUE] Essay` both match a
/// `Starts with DUE` rule. When *Match whole words only* is on (the default),
/// `contains due` fires on `Essay due Friday` but not on `residue`, and
/// `starts with DUE` does not fire on `Duel Club`.
struct DeadlineDetector: Sendable {
    let configuration: FilterConfiguration

    init(configuration: FilterConfiguration) {
        self.configuration = configuration
    }

    /// The final answer: should this title be shown?
    func shouldDisplay(title: String) -> Bool {
        // Exclusions always win, including in "show all events" mode — that is
        // what keeps `DONE …` and `CANCELLED …` out of the list.
        if isExcluded(title: title) { return false }
        if configuration.showAllEvents { return true }
        return isDeadline(title: title)
    }

    func isDeadline(title: String) -> Bool {
        matchesAny(configuration.includeRules, title: title)
    }

    func isExcluded(title: String) -> Bool {
        matchesAny(configuration.excludeRules, title: title)
    }

    // MARK: - Matching

    private func matchesAny(_ rules: [KeywordRule], title: String) -> Bool {
        let normalized = title.normalizedForMatching
        guard !normalized.isEmpty else { return false }
        let stripped = normalized.strippingLeadingDecoration
        for rule in rules where rule.isUsable {
            if matches(rule, normalized: normalized, stripped: stripped) { return true }
        }
        return false
    }

    private func matches(_ rule: KeywordRule, normalized: String, stripped: String) -> Bool {
        let needle = rule.text.normalizedForMatching
        guard !needle.isEmpty else { return false }

        switch rule.mode {
        case .startsWith:
            guard stripped.hasPrefix(needle) else { return false }
            guard configuration.matchWholeWordsOnly else { return true }
            let remainder = stripped.dropFirst(needle.count)
            guard let next = remainder.first else { return true }
            return !Self.isWordCharacter(next)

        case .contains:
            guard configuration.matchWholeWordsOnly else { return normalized.contains(needle) }
            return Self.containsWholeWord(needle, in: normalized)
        }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// Substring search that requires non-word characters (or a string edge) on
    /// both sides of the match.
    static func containsWholeWord(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return false }
        var searchStart = haystack.startIndex

        while searchStart < haystack.endIndex,
              let found = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let beforeOK: Bool
            if found.lowerBound == haystack.startIndex {
                beforeOK = true
            } else {
                let previous = haystack[haystack.index(before: found.lowerBound)]
                beforeOK = !isWordCharacter(previous)
            }

            let afterOK: Bool
            if found.upperBound == haystack.endIndex {
                afterOK = true
            } else {
                afterOK = !isWordCharacter(haystack[found.upperBound])
            }

            // A needle that begins or ends with punctuation supplies its own
            // boundary on that side.
            let needleStartsWithWord = needle.first.map(isWordCharacter) ?? false
            let needleEndsWithWord = needle.last.map(isWordCharacter) ?? false

            if (beforeOK || !needleStartsWithWord) && (afterOK || !needleEndsWithWord) {
                return true
            }
            searchStart = haystack.index(after: found.lowerBound)
        }
        return false
    }
}
