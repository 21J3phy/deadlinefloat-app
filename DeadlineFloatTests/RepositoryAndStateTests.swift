import AppKit
import XCTest
@testable import DeadlineFloat

final class CalendarSelectionTests: XCTestCase {
    private let primary = Fixture.calendarEntry(id: "me@example.com", name: "Personal", primary: true, selected: true)
    private let course = Fixture.calendarEntry(id: "cs@example.com", name: "CS 18000", selected: false)
    private var deleted: GoogleCalendarListEntry {
        var entry = Fixture.calendarEntry(id: "gone@example.com", name: "Gone")
        entry.deleted = true
        return entry
    }

    func testAnExplicitSelectionIsUsedVerbatim() {
        let chosen = CalendarRepository.targetCalendars(
            from: [primary, course],
            selection: ["cs@example.com"]
        )
        XCTAssertEqual(chosen.map(\.id), ["cs@example.com"])
    }

    func testNoSelectionFollowsGooglesOwnVisibility() {
        let chosen = CalendarRepository.targetCalendars(from: [primary, course], selection: nil)
        XCTAssertEqual(chosen.map(\.id), ["me@example.com"])
    }

    func testNoSelectionAndNothingTickedFallsBackToEverything() {
        var a = primary; a.selected = false
        var b = course; b.selected = false
        XCTAssertEqual(CalendarRepository.targetCalendars(from: [a, b], selection: nil).count, 2)
    }

    func testDeletedCalendarsAreNeverFetched() {
        let chosen = CalendarRepository.targetCalendars(
            from: [primary, deleted],
            selection: ["me@example.com", "gone@example.com"]
        )
        XCTAssertEqual(chosen.map(\.id), ["me@example.com"])
    }

    func testAnEmptySelectionFetchesNothing() {
        XCTAssertTrue(CalendarRepository.targetCalendars(from: [primary, course], selection: []).isEmpty)
    }

    func testAuthFailureClassification() {
        XCTAssertTrue(CalendarRepository.isAuthFailure(APIError.unauthorized))
        XCTAssertTrue(CalendarRepository.isAuthFailure(APIError.notSignedIn))
        XCTAssertTrue(CalendarRepository.isAuthFailure(APIError.notConfigured))
        XCTAssertFalse(CalendarRepository.isAuthFailure(APIError.offline))
        XCTAssertFalse(CalendarRepository.isAuthFailure(APIError.rateLimited(retryAfter: nil)))
    }
}

final class SyncStateTests: XCTestCase {
    func testProblemMappingFromAPIErrors() {
        XCTAssertEqual(DeadlineListViewModel.problem(for: APIError.unauthorized), .authenticationExpired)
        XCTAssertEqual(DeadlineListViewModel.problem(for: APIError.notSignedIn), .notSignedIn)
        XCTAssertEqual(DeadlineListViewModel.problem(for: APIError.notConfigured), .notSignedIn)
        XCTAssertEqual(DeadlineListViewModel.problem(for: APIError.offline), .offline)
        XCTAssertEqual(DeadlineListViewModel.problem(for: URLError(.notConnectedToInternet)), .offline)

        if case .rateLimited = DeadlineListViewModel.problem(for: APIError.rateLimited(retryAfter: 30)) {} else {
            XCTFail("rate limiting should map to .rateLimited")
        }
        if case .server(let message) = DeadlineListViewModel.problem(for: APIError.server(status: 500, message: "Backend Error")) {
            XCTAssertEqual(message, "Backend Error")
        } else {
            XCTFail("server errors should map to .server")
        }
        XCTAssertEqual(DeadlineListViewModel.problem(for: AuthError.stateMismatch), .authenticationExpired)
    }

    func testProblemsKnowWhetherRetryingOrReconnectingIsTheAnswer() {
        XCTAssertTrue(SyncProblem.offline.isRetryable)
        XCTAssertTrue(SyncProblem.rateLimited(retryAfter: nil).isRetryable)
        XCTAssertTrue(SyncProblem.server("x").isRetryable)
        XCTAssertFalse(SyncProblem.notSignedIn.isRetryable)
        XCTAssertFalse(SyncProblem.authenticationExpired.isRetryable)

        XCTAssertTrue(SyncProblem.notSignedIn.requiresReauthentication)
        XCTAssertTrue(SyncProblem.authenticationExpired.requiresReauthentication)
        XCTAssertFalse(SyncProblem.offline.requiresReauthentication)
    }

    func testStaleDataIsOnlyReportedWhenThereIsDataToShow() {
        var state = SyncState.initial
        XCTAssertFalse(state.isShowingStaleData)

        state.problem = .offline
        XCTAssertFalse(state.isShowingStaleData, "an offline first launch has nothing stale to show")

        state.lastSuccessfulRefresh = Date()
        XCTAssertTrue(state.isShowingStaleData)

        state.problem = nil
        XCTAssertFalse(state.isShowingStaleData)
    }

    func testAccountLabelComesFromThePrimaryCalendar() {
        let calendars = [
            Fixture.calendarEntry(id: "shared@example.com", name: "Shared"),
            Fixture.calendarEntry(id: "me@example.com", name: "Personal", primary: true)
        ]
        XCTAssertEqual(DeadlineListViewModel.accountLabel(from: calendars), "me@example.com")
        XCTAssertNil(DeadlineListViewModel.accountLabel(from: [calendars[0]]))
    }
}

@MainActor
final class WindowPlacementTests: XCTestCase {
    // `NSScreen` cannot be constructed, so placement is checked against the
    // real screens of the machine running the tests.

    func testFrameOnAnExistingScreenIsLeftAlone() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let frame = NSRect(
            x: screen.visibleFrame.midX - 170,
            y: screen.visibleFrame.midY - 230,
            width: 340,
            height: 460
        )
        XCTAssertEqual(FloatingPanelController.clampToVisibleScreens(frame), frame)
    }

    func testFrameOnAVanishedDisplayIsBroughtBack() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let offscreen = NSRect(x: -9_000, y: -9_000, width: 340, height: 460)
        let corrected = try XCTUnwrap(FloatingPanelController.clampToVisibleScreens(offscreen))

        XCTAssertNotEqual(corrected, offscreen)
        XCTAssertEqual(corrected.size, offscreen.size, "only the position moves")
        XCTAssertTrue(screen.visibleFrame.intersects(corrected))
    }

    func testDefaultFrameUsesTheStandardSizeAndSitsOnScreen() throws {
        let frame = FloatingPanelController.defaultFrame()
        XCTAssertEqual(frame.size, Metrics.defaultWindowSize)
        if let screen = NSScreen.main {
            XCTAssertTrue(screen.visibleFrame.intersects(frame))
        }
    }

    func testNoScreensMeansNoFrame() {
        XCTAssertNil(FloatingPanelController.clampToVisibleScreens(NSRect(x: 0, y: 0, width: 340, height: 460), screens: []))
    }

    func testMinimumSizeIsSmallerThanTheDefault() {
        XCTAssertLessThan(Metrics.minimumWindowSize.width, Metrics.defaultWindowSize.width)
        XCTAssertLessThan(Metrics.minimumWindowSize.height, Metrics.defaultWindowSize.height)
        XCTAssertGreaterThan(Metrics.maximumWindowSize.width, Metrics.defaultWindowSize.width)
    }
}

final class DemoDataTests: XCTestCase {
    func testDemoSnapshotProducesEveryKindOfSection() {
        let calendar = Fixture.calendar()
        let now = Fixture.date(2026, 9, 2, 14, 0)
        let snapshot = DemoData.snapshot(now: now, calendar: calendar)
        let assembler = DeadlineAssembler(calendar: calendar, locale: Fixture.locale)
        let sections = assembler.sections(
            from: snapshot,
            selectedCalendarIDs: nil,
            window: DateWindow(now: now, days: 3, calendar: calendar),
            now: now
        )

        XCTAssertEqual(sections.first?.kind, .overdue)
        XCTAssertTrue(sections.contains { $0.kind == .today })
        XCTAssertTrue(sections.contains { $0.kind == .tomorrow })
        XCTAssertGreaterThanOrEqual(sections.flatMap(\.deadlines).count, 6)
    }

    func testDemoDataExcludesItsDoneEvent() {
        let calendar = Fixture.calendar()
        let now = Fixture.date(2026, 9, 2, 14, 0)
        let assembler = DeadlineAssembler(calendar: calendar, locale: Fixture.locale)
        let titles = assembler.sections(
            from: DemoData.snapshot(now: now, calendar: calendar),
            selectedCalendarIDs: nil,
            window: DateWindow(now: now, days: 4, calendar: calendar),
            now: now
        ).flatMap { $0.deadlines.map(\.title) }

        XCTAssertFalse(titles.contains { $0.hasPrefix("DONE") })
    }

    func testDemoPaletteCoversGooglesPublishedColours() {
        XCTAssertEqual(DemoData.palette.event?.count, GooglePalette.eventBackgrounds.count)
        XCTAssertEqual(DemoData.palette.calendar?.count, GooglePalette.calendarBackgrounds.count)
    }
}
