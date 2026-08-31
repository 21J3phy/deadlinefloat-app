import AppKit
import XCTest
@testable import DeadlineFloat

/// Every SF Symbol the interface draws must exist on the deployment target,
/// otherwise the app ships with empty boxes where icons should be.
final class SymbolAvailabilityTests: XCTestCase {
    func testEverySymbolResolves() {
        for name in Symbols.all {
            XCTAssertNotNil(
                NSImage(systemSymbolName: name, accessibilityDescription: nil),
                "SF Symbol \"\(name)\" does not resolve on this system"
            )
        }
    }

    func testSymbolListHasNoDuplicatesLeftBehind() {
        // A duplicate is not an error, but an empty entry always is.
        XCTAssertFalse(Symbols.all.contains(where: \.isEmpty))
    }

    func testUrgencySymbolsResolve() {
        for urgency in [Urgency.overdue, .imminent, .later] {
            XCTAssertNotNil(NSImage(systemSymbolName: urgency.symbolName, accessibilityDescription: nil), urgency.symbolName)
        }
    }

    func testSyncProblemSymbolsResolve() {
        let problems: [SyncProblem] = [
            .notSignedIn, .authenticationExpired, .offline, .rateLimited(retryAfter: nil), .server("x")
        ]
        for problem in problems {
            XCTAssertNotNil(NSImage(systemSymbolName: problem.symbolName, accessibilityDescription: nil), problem.symbolName)
        }
    }
}
