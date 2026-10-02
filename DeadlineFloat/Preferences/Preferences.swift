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
        static let showSpotlight = "display.spotlight"
        static let menuBarCountdown = "menubar.countdown"
        static let completedDeadlines = "tasks.completed"
        static let edge = "bar.edge"
        static let edgeBarEnabled = "bar.edge.enabled"
        static let sliverWidth = "bar.sliver.width"
        static let sliverTitles = "bar.sliver.titles"
        static let sliverPill = "bar.sliver.pill"
        static let allowsEditing = "calendar.allowsEditing"
        static let dayStartHour = "calendar.dayStartHour"
        static let dayEndHour = "calendar.dayEndHour"
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
    private var showSpotlightStorage: Bool
    private var menuBarCountdownStorage: Bool
    private var completedDeadlinesStorage: [String: Date]
    private var edgeStorage: ScreenEdge
    private var edgeBarEnabledStorage: Bool
    private var sliverWidthStorage: Double
    private var sliverTitlesStorage: Bool
    private var sliverPillStorage: Bool
    private var allowsEditingStorage: Bool
    private var daySpanStorage: DaySpan

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
        showSpotlightStorage = defaults.object(forKey: Keys.showSpotlight) as? Bool ?? true
        menuBarCountdownStorage = defaults.bool(forKey: Keys.menuBarCountdown)
        edgeStorage = defaults.string(forKey: Keys.edge).flatMap(ScreenEdge.init(rawValue:)) ?? .right
        edgeBarEnabledStorage = defaults.object(forKey: Keys.edgeBarEnabled) as? Bool ?? true
        let storedSliverWidth = defaults.object(forKey: Keys.sliverWidth) as? Double ?? Self.defaultSliverWidth
        sliverWidthStorage = min(Self.sliverWidthRange.upperBound, max(Self.sliverWidthRange.lowerBound, storedSliverWidth))
        sliverTitlesStorage = defaults.bool(forKey: Keys.sliverTitles)
        sliverPillStorage = defaults.object(forKey: Keys.sliverPill) as? Bool ?? true
        allowsEditingStorage = defaults.bool(forKey: Keys.allowsEditing)
        daySpanStorage = DaySpan(
            startHour: defaults.object(forKey: Keys.dayStartHour) as? Int ?? DaySpan.wholeDay.startHour,
            endHour: defaults.object(forKey: Keys.dayEndHour) as? Int ?? DaySpan.wholeDay.endHour
        )

        // Completed ids are pruned on load so the set never grows without
        // bound; an event that old is long outside any window the app shows.
        let cutoff = Date().addingTimeInterval(-Self.completedRetention)
        let stored = Self.decode([String: Date].self, from: defaults, key: Keys.completedDeadlines) ?? [:]
        completedDeadlinesStorage = stored.filter { $0.value > cutoff }
        if completedDeadlinesStorage.count != stored.count {
            Self.encode(completedDeadlinesStorage, into: defaults, key: Keys.completedDeadlines)
        }
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

    /// Lift the next deadline out of the list and show it large, with a live
    /// countdown, at the top of the panel.
    var showSpotlight: Bool {
        get { showSpotlightStorage }
        set {
            showSpotlightStorage = newValue
            defaults.set(newValue, forKey: Keys.showSpotlight)
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

    /// Show the countdown to the next deadline beside the menu bar icon.
    var menuBarShowsCountdown: Bool {
        get { menuBarCountdownStorage }
        set {
            menuBarCountdownStorage = newValue
            defaults.set(newValue, forKey: Keys.menuBarCountdown)
        }
    }

    /// The sliver at the screen edge of every display. Off, the panel drops
    /// down from the menu bar instead.
    var showsEdgeBar: Bool {
        get { edgeBarEnabledStorage }
        set {
            edgeBarEnabledStorage = newValue
            defaults.set(newValue, forKey: Keys.edgeBarEnabled)
        }
    }

    static let sliverWidthRange: ClosedRange<Double> = 8...40
    static let defaultSliverWidth: Double = 12

    /// How wide the sliver at the screen edge is, in points.
    var sliverWidth: Double {
        get { sliverWidthStorage }
        set {
            let clamped = min(Self.sliverWidthRange.upperBound, max(Self.sliverWidthRange.lowerBound, newValue))
            sliverWidthStorage = clamped
            defaults.set(clamped, forKey: Keys.sliverWidth)
        }
    }

    /// Run each event's title along its block on the sliver, on blocks long
    /// enough to carry it.
    var sliverShowsTitles: Bool {
        get { sliverTitlesStorage }
        set {
            sliverTitlesStorage = newValue
            defaults.set(newValue, forKey: Keys.sliverTitles)
        }
    }

    /// The pill beside the sliver with what is on now, or next. It is the
    /// one label the collapsed bar carries, and it floats above other
    /// windows, so it can be turned off and leave only the ruler.
    var sliverShowsFocusPill: Bool {
        get { sliverPillStorage }
        set {
            sliverPillStorage = newValue
            defaults.set(newValue, forKey: Keys.sliverPill)
        }
    }

    // MARK: Editing

    /// Whether blocks on the calendar can be dragged to a new time.
    ///
    /// This is the one setting that changes what Google is asked to allow, so
    /// it starts off: the app requests the read-only scope it has always
    /// requested and is incapable of changing anything until somebody asks for
    /// more. Turning it on takes effect at the next connection, because the
    /// permission is granted at sign-in — and the OAuth consent screen must
    /// already list the editing scope, or Google will refuse the sign-in
    /// rather than quietly grant less.
    var allowsEventEditing: Bool {
        get { allowsEditingStorage }
        set {
            allowsEditingStorage = newValue
            defaults.set(newValue, forKey: Keys.allowsEditing)
        }
    }

    // MARK: The day the ruler draws

    /// The hours the ruler and the calendar show.
    ///
    /// Stored as two plain hours rather than an encoded value, so the
    /// preference is legible in `defaults read` and a nonsense pair recorded
    /// by hand is repaired by `DaySpan` on the way in rather than crashing.
    var daySpan: DaySpan {
        get { daySpanStorage }
        set {
            daySpanStorage = newValue
            defaults.set(newValue.startHour, forKey: Keys.dayStartHour)
            defaults.set(newValue.endHour, forKey: Keys.dayEndHour)
        }
    }

    /// Which screen edge the optional bar docks to.
    var edge: ScreenEdge {
        get { edgeStorage }
        set {
            edgeStorage = newValue
            defaults.set(newValue.rawValue, forKey: Keys.edge)
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

    // MARK: Completed deadlines

    /// How long a completion is remembered.
    static let completedRetention: TimeInterval = 30 * 24 * 60 * 60

    /// Deadline ids the user has marked done, with when they did so.
    var completedDeadlines: [String: Date] {
        get { completedDeadlinesStorage }
        set {
            completedDeadlinesStorage = newValue
            Self.encode(newValue, into: defaults, key: Keys.completedDeadlines)
        }
    }

    func isCompleted(_ id: String) -> Bool {
        completedDeadlinesStorage[id] != nil
    }

    func markCompleted(_ id: String, at date: Date = Date()) {
        var updated = completedDeadlinesStorage
        updated[id] = date
        completedDeadlines = updated
    }

    func markNotCompleted(_ id: String) {
        var updated = completedDeadlinesStorage
        updated.removeValue(forKey: id)
        completedDeadlines = updated
    }

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
