import Foundation
import Observation

/// Every user-facing setting, persisted in `UserDefaults`.
///
/// Each public property is computed over a private stored property. Observation
/// tracks the stored value, so views update the moment a setting changes, while
/// the setter is the single place that writes to disk — there is no separate
/// "save" step to forget.
@Observable
final class Preferences {
    enum Keys {
        static let rangeDays = "range.days"
        static let filterConfiguration = "filter.configuration"
        static let selectedCalendarIDs = "calendars.selected"
        static let hasCalendarSelection = "calendars.hasSelection"
        static let mergeDuplicates = "display.mergeDuplicates"
        static let compactMode = "display.compactMode"
        static let textScale = "display.textScale"
        static let windowOpacity = "window.opacity"
        static let floatAboveFullScreen = "window.floatAboveFullScreen"
        static let showInDock = "app.showInDock"
        static let overdueLookbackDays = "range.overdueLookbackDays"
        static let refreshIntervalMinutes = "sync.refreshIntervalMinutes"
        static let windowFrame = "window.frame"
    }

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: Backing storage

    private var rangeDaysStorage: Int
    private var filterStorage: FilterConfiguration
    private var selectedCalendarIDsStorage: Set<String>
    private var hasCalendarSelectionStorage: Bool
    private var mergeDuplicatesStorage: Bool
    private var compactModeStorage: Bool
    private var textScaleStorage: Double
    private var windowOpacityStorage: Double
    private var floatAboveFullScreenStorage: Bool
    private var showInDockStorage: Bool
    private var overdueLookbackDaysStorage: Int
    private var refreshIntervalMinutesStorage: Int
    private var windowFrameStorage: String?

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        rangeDaysStorage = defaults.object(forKey: Keys.rangeDays) as? Int ?? RangeOption.default.days
        filterStorage = Self.decode(FilterConfiguration.self, from: defaults, key: Keys.filterConfiguration) ?? .default
        selectedCalendarIDsStorage = Set(defaults.stringArray(forKey: Keys.selectedCalendarIDs) ?? [])
        hasCalendarSelectionStorage = defaults.bool(forKey: Keys.hasCalendarSelection)
        mergeDuplicatesStorage = defaults.object(forKey: Keys.mergeDuplicates) as? Bool ?? true
        compactModeStorage = defaults.bool(forKey: Keys.compactMode)
        textScaleStorage = defaults.object(forKey: Keys.textScale) as? Double ?? 1.0
        windowOpacityStorage = defaults.object(forKey: Keys.windowOpacity) as? Double ?? 1.0
        floatAboveFullScreenStorage = defaults.object(forKey: Keys.floatAboveFullScreen) as? Bool ?? true
        showInDockStorage = defaults.bool(forKey: Keys.showInDock)
        overdueLookbackDaysStorage = defaults.object(forKey: Keys.overdueLookbackDays) as? Int ?? 0
        refreshIntervalMinutesStorage = defaults.object(forKey: Keys.refreshIntervalMinutes) as? Int ?? 5
        windowFrameStorage = defaults.string(forKey: Keys.windowFrame)
    }

    // MARK: Range

    /// Today plus 2, 3 or 4 calendar days. Defaults to 3 and survives relaunch.
    var range: RangeOption {
        get { RangeOption(days: rangeDaysStorage) }
        set {
            rangeDaysStorage = newValue.days
            defaults.set(newValue.days, forKey: Keys.rangeDays)
        }
    }

    /// How many past days of overdue deadlines to keep visible. `0` matches the
    /// literal "today plus N days" window.
    var overdueLookbackDays: Int {
        get { overdueLookbackDaysStorage }
        set {
            let clamped = min(14, max(0, newValue))
            overdueLookbackDaysStorage = clamped
            defaults.set(clamped, forKey: Keys.overdueLookbackDays)
        }
    }

    // MARK: Filtering

    var filter: FilterConfiguration {
        get { filterStorage }
        set {
            filterStorage = newValue
            Self.encode(newValue, into: defaults, key: Keys.filterConfiguration)
        }
    }

    var showAllEvents: Bool {
        get { filterStorage.showAllEvents }
        set { filter.showAllEvents = newValue }
    }

    func resetKeywordsToDefaults() {
        var updated = filterStorage
        updated.includeRules = KeywordRule.defaultInclude
        updated.excludeRules = KeywordRule.defaultExclude
        filter = updated
    }

    // MARK: Calendars

    /// `nil` until the user picks calendars explicitly, which lets the first
    /// refresh fall back to whatever is ticked in Google Calendar.
    var selectedCalendarIDs: Set<String>? {
        get { hasCalendarSelectionStorage ? selectedCalendarIDsStorage : nil }
        set {
            if let newValue {
                selectedCalendarIDsStorage = newValue
                hasCalendarSelectionStorage = true
                defaults.set(Array(newValue).sorted(), forKey: Keys.selectedCalendarIDs)
                defaults.set(true, forKey: Keys.hasCalendarSelection)
            } else {
                selectedCalendarIDsStorage = []
                hasCalendarSelectionStorage = false
                defaults.removeObject(forKey: Keys.selectedCalendarIDs)
                defaults.set(false, forKey: Keys.hasCalendarSelection)
            }
        }
    }

    func setCalendar(_ id: String, included: Bool, allKnownIDs: [String]) {
        var current = selectedCalendarIDs ?? Set(allKnownIDs)
        if included { current.insert(id) } else { current.remove(id) }
        selectedCalendarIDs = current
    }

    var mergeDuplicates: Bool {
        get { mergeDuplicatesStorage }
        set {
            mergeDuplicatesStorage = newValue
            defaults.set(newValue, forKey: Keys.mergeDuplicates)
        }
    }

    // MARK: Appearance

    var compactMode: Bool {
        get { compactModeStorage }
        set {
            compactModeStorage = newValue
            defaults.set(newValue, forKey: Keys.compactMode)
        }
    }

    static let textScaleRange: ClosedRange<Double> = 0.85...1.45

    var textScale: Double {
        get { textScaleStorage }
        set {
            let clamped = min(Self.textScaleRange.upperBound, max(Self.textScaleRange.lowerBound, newValue))
            textScaleStorage = clamped
            defaults.set(clamped, forKey: Keys.textScale)
        }
    }

    static let opacityRange: ClosedRange<Double> = 0.45...1.0

    var windowOpacity: Double {
        get { windowOpacityStorage }
        set {
            let clamped = min(Self.opacityRange.upperBound, max(Self.opacityRange.lowerBound, newValue))
            windowOpacityStorage = clamped
            defaults.set(clamped, forKey: Keys.windowOpacity)
        }
    }

    // MARK: Window behaviour

    var floatAboveFullScreen: Bool {
        get { floatAboveFullScreenStorage }
        set {
            floatAboveFullScreenStorage = newValue
            defaults.set(newValue, forKey: Keys.floatAboveFullScreen)
        }
    }

    var showInDock: Bool {
        get { showInDockStorage }
        set {
            showInDockStorage = newValue
            defaults.set(newValue, forKey: Keys.showInDock)
        }
    }

    var windowFrameDescription: String? {
        get { windowFrameStorage }
        set {
            windowFrameStorage = newValue
            if let newValue {
                defaults.set(newValue, forKey: Keys.windowFrame)
            } else {
                defaults.removeObject(forKey: Keys.windowFrame)
            }
        }
    }

    // MARK: Sync

    static let refreshIntervalChoices = [1, 5, 15, 30]

    var refreshIntervalMinutes: Int {
        get { refreshIntervalMinutesStorage }
        set {
            let clamped = min(60, max(1, newValue))
            refreshIntervalMinutesStorage = clamped
            defaults.set(clamped, forKey: Keys.refreshIntervalMinutes)
        }
    }

    var refreshInterval: TimeInterval { TimeInterval(refreshIntervalMinutes * 60) }

    // MARK: OAuth client

    var googleClientID: String {
        get { defaults.string(forKey: GoogleClientConfig.clientIDDefaultsKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                defaults.removeObject(forKey: GoogleClientConfig.clientIDDefaultsKey)
            } else {
                defaults.set(trimmed, forKey: GoogleClientConfig.clientIDDefaultsKey)
            }
        }
    }

    var googleClientSecret: String {
        get { defaults.string(forKey: GoogleClientConfig.clientSecretDefaultsKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                defaults.removeObject(forKey: GoogleClientConfig.clientSecretDefaultsKey)
            } else {
                defaults.set(trimmed, forKey: GoogleClientConfig.clientSecretDefaultsKey)
            }
        }
    }

    var clientConfiguration: GoogleClientConfig { GoogleClientConfig.resolve(defaults: defaults) }

    // MARK: Coding helpers

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, into defaults: UserDefaults, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
