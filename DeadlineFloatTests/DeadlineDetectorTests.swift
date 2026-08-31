import XCTest
@testable import DeadlineFloat

final class DeadlineDetectorTests: XCTestCase {
    private let detector = DeadlineDetector(configuration: .default)

    // MARK: - The four default include rules

    func testDefaultIncludeRulesMatchTheBrief() {
        XCTAssertEqual(FilterConfiguration.default.includeRules.map(\.mode), [.startsWith, .contains, .contains, .startsWith])
        XCTAssertEqual(FilterConfiguration.default.includeRules.map(\.text), ["DUE", "deadline", "due", "SUBMIT"])
        XCTAssertEqual(FilterConfiguration.default.excludeRules.map(\.text), ["DONE", "CANCELLED", "MISSED"])
    }

    func testStartsWithDue() {
        XCTAssertTrue(detector.isDeadline(title: "DUE: Homework 7"))
        XCTAssertTrue(detector.isDeadline(title: "due — reading response"))
        XCTAssertTrue(detector.isDeadline(title: "Due Friday"))
    }

    func testContainsDeadline() {
        XCTAssertTrue(detector.isDeadline(title: "Scholarship application deadline"))
        XCTAssertTrue(detector.isDeadline(title: "DEADLINE for abstracts"))
    }

    func testContainsDue() {
        XCTAssertTrue(detector.isDeadline(title: "Lab 09 is due tonight"))
        XCTAssertTrue(detector.isDeadline(title: "Essay (due)"))
        XCTAssertTrue(detector.isDeadline(title: "Report due."))
    }

    func testStartsWithSubmit() {
        XCTAssertTrue(detector.isDeadline(title: "SUBMIT project 3"))
        XCTAssertTrue(detector.isDeadline(title: "submit internship application"))
    }

    func testNonDeadlinesAreIgnored() {
        XCTAssertFalse(detector.isDeadline(title: "Lecture — Linear Algebra"))
        XCTAssertFalse(detector.isDeadline(title: "Coffee with Sam"))
        XCTAssertFalse(detector.isDeadline(title: ""))
    }

    // MARK: - Case, accents and decoration

    func testMatchingIsCaseInsensitive() {
        for title in ["due today", "DUE TODAY", "DuE ToDaY"] {
            XCTAssertTrue(detector.isDeadline(title: title), title)
        }
    }

    func testLeadingEmojiAndPunctuationDoNotBreakStartsWith() {
        XCTAssertTrue(detector.isDeadline(title: "🔴 DUE: Lab 3"))
        XCTAssertTrue(detector.isDeadline(title: "[DUE] Essay"))
        XCTAssertTrue(detector.isDeadline(title: "  ***SUBMIT*** portfolio"))
    }

    func testDiacriticsAreFolded() {
        let configuration = FilterConfiguration(
            includeRules: [.contains("échéance")],
            excludeRules: [],
            showAllEvents: false,
            matchWholeWordsOnly: true,
            hideDeclinedEvents: true
        )
        XCTAssertTrue(DeadlineDetector(configuration: configuration).isDeadline(title: "Rapport echeance vendredi"))
    }

    // MARK: - Word boundaries

    func testWholeWordMatchingAvoidsFalsePositives() {
        XCTAssertFalse(detector.isDeadline(title: "Chemistry residue cleanup"))
        XCTAssertFalse(detector.isDeadline(title: "Subdued lighting test"))
        XCTAssertFalse(detector.isDeadline(title: "Duel Club meeting"), "starts-with DUE must not fire on Duel")
    }

    func testWholeWordMatchingCanBeTurnedOff() {
        var configuration = FilterConfiguration.default
        configuration.matchWholeWordsOnly = false
        let loose = DeadlineDetector(configuration: configuration)
        XCTAssertTrue(loose.isDeadline(title: "Chemistry residue cleanup"))
        XCTAssertTrue(loose.isDeadline(title: "Duel Club meeting"))
    }

    func testOverdueIsNotAWholeWordMatchForDue() {
        XCTAssertFalse(detector.isDeadline(title: "Overdue library books"))
    }

    // MARK: - Exclusions

    func testExclusionsWin() {
        XCTAssertFalse(detector.shouldDisplay(title: "DONE: Homework 7 due"))
        XCTAssertFalse(detector.shouldDisplay(title: "CANCELLED submit portfolio"))
        XCTAssertFalse(detector.shouldDisplay(title: "MISSED deadline for abstracts"))
    }

    func testExclusionsStillApplyWhenShowingAllEvents() {
        var configuration = FilterConfiguration.default
        configuration.showAllEvents = true
        let detector = DeadlineDetector(configuration: configuration)

        XCTAssertTrue(detector.shouldDisplay(title: "Lecture — Linear Algebra"))
        XCTAssertTrue(detector.shouldDisplay(title: "Coffee with Sam"))
        XCTAssertFalse(detector.shouldDisplay(title: "DONE Renew library books"))
    }

    func testExclusionIsAlsoCaseInsensitiveAndDecorationTolerant() {
        XCTAssertTrue(detector.isExcluded(title: "done: essay due"))
        XCTAssertTrue(detector.isExcluded(title: "✅ DONE essay due"))
    }

    // MARK: - Rule hygiene

    func testBlankRulesAreIgnored() {
        let configuration = FilterConfiguration(
            includeRules: [.contains("   "), .startsWith("")],
            excludeRules: [],
            showAllEvents: false,
            matchWholeWordsOnly: true,
            hideDeclinedEvents: true
        )
        XCTAssertFalse(DeadlineDetector(configuration: configuration).isDeadline(title: "anything at all"))
    }

    func testCustomRulesAreHonoured() {
        let configuration = FilterConfiguration(
            includeRules: [.startsWith("TURN IN"), .contains("hand-in")],
            excludeRules: [.contains("draft")],
            showAllEvents: false,
            matchWholeWordsOnly: true,
            hideDeclinedEvents: true
        )
        let detector = DeadlineDetector(configuration: configuration)
        XCTAssertTrue(detector.shouldDisplay(title: "TURN IN lab notebook"))
        XCTAssertTrue(detector.shouldDisplay(title: "Portfolio hand-in"))
        XCTAssertFalse(detector.shouldDisplay(title: "Portfolio hand-in draft"))
        XCTAssertFalse(detector.shouldDisplay(title: "DUE: Homework"), "the default rules are replaced, not merged")
    }

    func testContainsWholeWordHelperEdges() {
        XCTAssertTrue(DeadlineDetector.containsWholeWord("due", in: "due"))
        XCTAssertTrue(DeadlineDetector.containsWholeWord("due", in: "(due)"))
        XCTAssertTrue(DeadlineDetector.containsWholeWord("due", in: "essay due"))
        XCTAssertFalse(DeadlineDetector.containsWholeWord("due", in: "residue"))
        XCTAssertFalse(DeadlineDetector.containsWholeWord("due", in: "duel"))
        XCTAssertFalse(DeadlineDetector.containsWholeWord("", in: "anything"))
    }
}
