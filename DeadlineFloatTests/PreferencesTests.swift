import XCTest
@testable import DeadlineFloat

final class PreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.niravsurabhi.DeadlineFloat.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaults() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.range, .oneDay)
        XCTAssertEqual(preferences.overdueLookbackDays, 0)
        XCTAssertEqual(preferences.refreshIntervalMinutes, 5, "the brief asks for a five-minute refresh")
        XCTAssertEqual(preferences.textScale, 1.0)
        XCTAssertEqual(preferences.sliverWidth, 12)
        XCTAssertFalse(preferences.sliverShowsTitles)
        XCTAssertTrue(preferences.sliverShowsFocusPill, "the pill is the one label the collapsed bar carries")
        XCTAssertEqual(preferences.windowOpacity, 1.0)
        XCTAssertFalse(preferences.compactMode)
        XCTAssertFalse(preferences.showAllEvents)
        XCTAssertTrue(preferences.mergeDuplicates)
        XCTAssertTrue(preferences.floatAboveFullScreen)
        XCTAssertFalse(preferences.showInDock)
        XCTAssertTrue(preferences.showSpotlight)
        XCTAssertFalse(preferences.menuBarShowsCountdown)
        XCTAssertEqual(preferences.edge, .right)
        XCTAssertTrue(preferences.showsEdgeBar, "the bar lives at the screen edge unless turned off")
        XCTAssertFalse(preferences.allowsEventEditing, "asking Google for more than read access is opt-in")
        XCTAssertNil(preferences.selectedCalendarIDs)
        XCTAssertEqual(preferences.filter, .default)
    }

    func testTurningEditingOnSurvivesRelaunchAndChangesWhatIsAskedFor() {
        XCTAssertEqual(GoogleEndpoints.scopes(allowsEditing: Preferences(defaults: defaults).allowsEventEditing), GoogleEndpoints.scope)

        do {
            let preferences = Preferences(defaults: defaults)
            preferences.allowsEventEditing = true
        }

        let reloaded = Preferences(defaults: defaults)
        XCTAssertTrue(reloaded.allowsEventEditing)
        XCTAssertTrue(GoogleEndpoints.scopes(allowsEditing: reloaded.allowsEventEditing).contains(GoogleEndpoints.editingScope))
    }

    func testSpotlightAndMenuBarChoicesSurviveRelaunch() {
        do {
            let preferences = Preferences(defaults: defaults)
            preferences.showSpotlight = false
            preferences.menuBarShowsCountdown = true
            preferences.edge = .left
            preferences.showsEdgeBar = false
        }
        let reloaded = Preferences(defaults: defaults)
        XCTAssertFalse(reloaded.showSpotlight)
        XCTAssertTrue(reloaded.menuBarShowsCountdown)
        XCTAssertEqual(reloaded.edge, .left)
        XCTAssertFalse(reloaded.showsEdgeBar)
    }

    func testSliverPillCanBeTurnedOffAndStaysOff() {
        do {
            let preferences = Preferences(defaults: defaults)
            preferences.sliverShowsFocusPill = false
        }
        XCTAssertFalse(Preferences(defaults: defaults).sliverShowsFocusPill)
    }

    func testCompletedDeadlinesPersistAndCanBeUndone() {
        do {
            let preferences = Preferences(defaults: defaults)
            XCTAssertTrue(preferences.completedDeadlines.isEmpty)
            preferences.markCompleted("cal|a", at: Date())
            preferences.markCompleted("cal|b", at: Date())
            preferences.markNotCompleted("cal|a")
            XCTAssertFalse(preferences.isCompleted("cal|a"))
            XCTAssertTrue(preferences.isCompleted("cal|b"))
        }
        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(Array(reloaded.completedDeadlines.keys), ["cal|b"])
    }

    func testStaleCompletionsArePrunedOnLoad() {
        do {
            let preferences = Preferences(defaults: defaults)
            preferences.markCompleted("cal|fresh", at: Date())
            preferences.markCompleted("cal|stale", at: Date().addingTimeInterval(-Preferences.completedRetention - 60))
        }
        let reloaded = Preferences(defaults: defaults)
        XCTAssertTrue(reloaded.isCompleted("cal|fresh"))
        XCTAssertFalse(reloaded.isCompleted("cal|stale"))
    }

    func testRangeSurvivesRelaunch() {
        do {
            let preferences = Preferences(defaults: defaults)
            preferences.range = .week
        }
        XCTAssertEqual(Preferences(defaults: defaults).range, .week)
    }

    func testEveryRangeOptionRoundTrips() {
        for option in RangeOption.allCases {
            let preferences = Preferences(defaults: defaults)
            preferences.range = option
            XCTAssertEqual(Preferences(defaults: defaults).range, option)
        }
    }

    func testKeywordsSurviveRelaunch() {
        do {
            let preferences = Preferences(defaults: defaults)
            preferences.filter.includeRules = [.startsWith("TURN IN")]
            preferences.filter.excludeRules = []
            preferences.filter.showAllEvents = true
        }
        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.filter.includeRules.map(\.text), ["TURN IN"])
        XCTAssertTrue(reloaded.filter.excludeRules.isEmpty)
        XCTAssertTrue(reloaded.showAllEvents)
    }

    func testRestoringDefaultKeywords() {
        let preferences = Preferences(defaults: defaults)
        preferences.filter.includeRules = []
        preferences.resetKeywordsToDefaults()
        XCTAssertEqual(preferences.filter.includeRules.map(\.text), ["DUE", "deadline", "due", "SUBMIT"])
        XCTAssertEqual(preferences.filter.excludeRules.map(\.text), ["DONE", "CANCELLED", "MISSED"])
    }

    func testCalendarSelectionStartsUnsetThenPersists() {
        do {
            let preferences = Preferences(defaults: defaults)
            XCTAssertNil(preferences.selectedCalendarIDs)
            preferences.selectedCalendarIDs = ["a", "b"]
        }
        XCTAssertEqual(Preferences(defaults: defaults).selectedCalendarIDs, ["a", "b"])
    }

    func testAnEmptySelectionIsDistinctFromNoSelection() {
        let preferences = Preferences(defaults: defaults)
        preferences.selectedCalendarIDs = []
        XCTAssertEqual(preferences.selectedCalendarIDs, [], "deliberately choosing nothing must not fall back to everything")
        preferences.selectedCalendarIDs = nil
        XCTAssertNil(preferences.selectedCalendarIDs)
    }

    func testTogglingOneCalendarStartsFromEverythingKnown() {
        let preferences = Preferences(defaults: defaults)
        preferences.setCalendar("b", included: false, allKnownIDs: ["a", "b", "c"])
        XCTAssertEqual(preferences.selectedCalendarIDs, ["a", "c"])
        preferences.setCalendar("b", included: true, allKnownIDs: ["a", "b", "c"])
        XCTAssertEqual(preferences.selectedCalendarIDs, ["a", "b", "c"])
    }

    func testNumericPreferencesAreClamped() {
        let preferences = Preferences(defaults: defaults)

        preferences.textScale = 5
        XCTAssertEqual(preferences.textScale, Preferences.textScaleRange.upperBound)
        preferences.textScale = 0
        XCTAssertEqual(preferences.textScale, Preferences.textScaleRange.lowerBound)
        preferences.sliverWidth = 100
        XCTAssertEqual(preferences.sliverWidth, Preferences.sliverWidthRange.upperBound)
        preferences.sliverWidth = 1
        XCTAssertEqual(preferences.sliverWidth, Preferences.sliverWidthRange.lowerBound)

        preferences.windowOpacity = 2
        XCTAssertEqual(preferences.windowOpacity, 1.0)
        preferences.windowOpacity = -1
        XCTAssertEqual(preferences.windowOpacity, Preferences.opacityRange.lowerBound)

        preferences.overdueLookbackDays = -3
        XCTAssertEqual(preferences.overdueLookbackDays, 0)
        preferences.overdueLookbackDays = 400
        XCTAssertEqual(preferences.overdueLookbackDays, 14)

        preferences.refreshIntervalMinutes = 0
        XCTAssertEqual(preferences.refreshIntervalMinutes, 1)
        preferences.refreshIntervalMinutes = 500
        XCTAssertEqual(preferences.refreshIntervalMinutes, 60)
    }

    func testRefreshIntervalIsExpressedInSeconds() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.refreshInterval, 300)
        preferences.refreshIntervalMinutes = 15
        XCTAssertEqual(preferences.refreshInterval, 900)
    }

    func testClientOverrideIsTrimmedAndClearable() {
        let preferences = Preferences(defaults: defaults)
        let other = "999999999999-override.apps.googleusercontent.com"

        XCTAssertEqual(preferences.googleClientID, "", "no override to begin with")
        XCTAssertEqual(preferences.clientConfiguration.source, .bundled)

        preferences.googleClientID = "  \(other)  "
        XCTAssertEqual(preferences.googleClientID, other, "whitespace is trimmed on the way in")
        XCTAssertEqual(preferences.clientConfiguration.source, .userOverride)
        XCTAssertEqual(preferences.clientConfiguration.clientID, other)

        preferences.googleClientID = "   "
        XCTAssertEqual(preferences.googleClientID, "")
        XCTAssertEqual(preferences.clientConfiguration.source, .bundled, "clearing falls back to the built-in client")
    }

    func testTheBundledClientIsWhatResolutionFallsBackTo() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.clientConfiguration.source, .bundled)
        XCTAssertEqual(preferences.clientConfiguration.clientID, GoogleClientConfig.bundled.clientID)
    }
}

final class SnapshotCacheTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("deadlinefloat-tests-\(UUID().uuidString)")
            .appendingPathComponent("snapshot.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        super.tearDown()
    }

    func testMissingFileLoadsAsNil() {
        XCTAssertNil(SnapshotCache(fileURL: url).load())
    }

    func testRoundTripSurvivesOffline() {
        let cache = SnapshotCache(fileURL: url)
        let snapshot = DemoData.snapshot(now: Fixture.date(2026, 9, 2, 12), calendar: Fixture.calendar())
        cache.save(snapshot)

        let restored = SnapshotCache(fileURL: url).load()
        XCTAssertEqual(restored?.calendars.count, snapshot.calendars.count)
        XCTAssertEqual(restored?.allEvents.count, snapshot.allEvents.count)
        XCTAssertEqual(restored?.fetchedAt.timeIntervalSince1970 ?? 0, snapshot.fetchedAt.timeIntervalSince1970, accuracy: 1)
    }

    func testCorruptFileIsIgnoredRatherThanCrashing() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("this is not json".utf8).write(to: url)
        XCTAssertNil(SnapshotCache(fileURL: url).load())
    }

    func testClearRemovesTheFile() {
        let cache = SnapshotCache(fileURL: url)
        cache.save(.empty)
        XCTAssertNotNil(cache.load())
        cache.clear()
        XCTAssertNil(cache.load())
    }
}
