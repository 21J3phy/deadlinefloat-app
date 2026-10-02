import AppKit
import XCTest
@testable import DeadlineFloat

/// The pill beside the sliver is its own window, so turning it off has to take
/// the window off the screen — not merely stop drawing into it.
@MainActor
final class EdgeBarPillTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var controller: EdgeBarController!
    private var environment: AppEnvironment!

    override func setUp() {
        super.setUp()
        suiteName = "com.niravsurabhi.DeadlineFloat.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        controller?.invalidate()
        controller = nil
        environment = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Whether any pill — the callout panel, found by the size only it has —
    /// is on the screen. Panels from earlier tests linger in `NSApp.windows`
    /// after they are ordered out, so the question has to be about what is
    /// showing, not about which window objects exist.
    private var isPillOnScreen: Bool {
        NSApp.windows.contains {
            $0 is EdgeBarPanel
                && $0.isVisible
                && abs($0.frame.width - Metrics.calloutWidth) < 1
                && abs($0.frame.height - Metrics.calloutHeight) < 1
        }
    }

    private func makeController() -> EdgeBarController {
        let environment = AppEnvironment(isDemo: true, defaults: defaults, clock: { Date() })
        environment.viewModel.start()
        XCTAssertNotNil(environment.viewModel.focus, "the demo day always has something on or next")
        self.environment = environment
        return EdgeBarController(
            displayID: CGMainDisplayID(),
            preferences: environment.preferences,
            viewModel: environment.viewModel,
            onOpenSettings: {}
        )
    }

    func testThePillShowsBesideTheSliverByDefault() {
        controller = makeController()
        controller.show()
        XCTAssertTrue(isPillOnScreen)
    }

    func testTurningThePillOffTakesItsWindowOffTheScreen() async throws {
        controller = makeController()
        controller.show()
        XCTAssertTrue(isPillOnScreen, "precondition: the pill is on")

        environment.preferences.sliverShowsFocusPill = false
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertFalse(isPillOnScreen, "the pill must leave the screen the moment it is turned off")
    }

    func testTurningItBackOnBringsThePillBack() async throws {
        controller = makeController()
        controller.show()

        environment.preferences.sliverShowsFocusPill = false
        try await Task.sleep(for: .milliseconds(200))
        environment.preferences.sliverShowsFocusPill = true
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(isPillOnScreen)
    }
}
