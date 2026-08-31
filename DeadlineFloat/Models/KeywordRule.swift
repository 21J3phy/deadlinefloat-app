import Foundation

/// One editable keyword rule.
///
/// The defaults reproduce the brief exactly: titles that start with `DUE`,
/// contain `deadline`, contain `due`, or start with `SUBMIT` are deadlines;
/// titles that start with `DONE`, `CANCELLED` or `MISSED` are not.
struct KeywordRule: Codable, Hashable, Sendable, Identifiable {
    enum Mode: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
        case startsWith
        case contains

        var id: String { rawValue }

        var label: String {
            switch self {
            case .startsWith: return "Starts with"
            case .contains: return "Contains"
            }
        }
    }

    var id: UUID
    var mode: Mode
    var text: String

    init(id: UUID = UUID(), mode: Mode, text: String) {
        self.id = id
        self.mode = mode
        self.text = text
    }

    static func startsWith(_ text: String) -> KeywordRule { KeywordRule(mode: .startsWith, text: text) }
    static func contains(_ text: String) -> KeywordRule { KeywordRule(mode: .contains, text: text) }

    var isUsable: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static let defaultInclude: [KeywordRule] = [
        .startsWith("DUE"),
        .contains("deadline"),
        .contains("due"),
        .startsWith("SUBMIT")
    ]

    static let defaultExclude: [KeywordRule] = [
        .startsWith("DONE"),
        .startsWith("CANCELLED"),
        .startsWith("MISSED")
    ]
}

/// Everything that decides whether an event is shown.
struct FilterConfiguration: Codable, Hashable, Sendable {
    var includeRules: [KeywordRule]
    var excludeRules: [KeywordRule]

    /// Show every event in the range instead of only deadlines. Exclusions still
    /// apply, so `DONE …` stays hidden.
    var showAllEvents: Bool

    /// When on, `contains` rules only match at word boundaries, so `due` does not
    /// fire on `residue`.
    var matchWholeWordsOnly: Bool

    /// Hide events the user has declined.
    var hideDeclinedEvents: Bool

    static let `default` = FilterConfiguration(
        includeRules: KeywordRule.defaultInclude,
        excludeRules: KeywordRule.defaultExclude,
        showAllEvents: false,
        matchWholeWordsOnly: true,
        hideDeclinedEvents: true
    )
}
