import XCTest
@testable import DeadlineFloat

/// The app ships with its own OAuth client so a user never sees a credential
/// field. These tests pin the resolution order and the validation that turns a
/// mistyped client ID into a readable message instead of an opaque failure at
/// Google's authorization endpoint.
final class GoogleClientConfigTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    private let validID = "123456789012-abcdefghijklmnopqrstuvwx.apps.googleusercontent.com"

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

    // MARK: - Resolution order

    func testFallsBackToTheBundledClient() {
        let resolved = GoogleClientConfig.resolve(defaults: defaults, bundle: .main)
        XCTAssertEqual(resolved.source, .bundled)
        XCTAssertEqual(resolved.clientID, GoogleClientConfig.bundled.clientID)
    }

    func testAnOverrideWins() {
        defaults.set(validID, forKey: GoogleClientConfig.clientIDDefaultsKey)
        let resolved = GoogleClientConfig.resolve(defaults: defaults, bundle: .main)
        XCTAssertEqual(resolved.source, .userOverride)
        XCTAssertEqual(resolved.clientID, validID)
        XCTAssertNil(resolved.clientSecret)
    }

    func testAnOverrideCarriesItsSecretWhenThereIsOne() {
        defaults.set(validID, forKey: GoogleClientConfig.clientIDDefaultsKey)
        defaults.set("GOCSPX-example", forKey: GoogleClientConfig.clientSecretDefaultsKey)
        XCTAssertEqual(GoogleClientConfig.resolve(defaults: defaults, bundle: .main).clientSecret, "GOCSPX-example")
    }

    func testAnEmptyOverrideIsIgnored() {
        defaults.set("   ", forKey: GoogleClientConfig.clientIDDefaultsKey)
        XCTAssertEqual(GoogleClientConfig.resolve(defaults: defaults, bundle: .main).source, .bundled)
    }

    func testOverridesAreTrimmedOnTheWayIn() {
        defaults.set("  \(validID)\n", forKey: GoogleClientConfig.clientIDDefaultsKey)
        XCTAssertEqual(GoogleClientConfig.resolve(defaults: defaults, bundle: .main).clientID, validID)
    }

    // MARK: - Validation

    func testAWellFormedClientIDHasNoProblem() {
        let config = GoogleClientConfig(clientID: validID)
        XCTAssertTrue(config.isConfigured)
        XCTAssertTrue(config.isWellFormed)
        XCTAssertNil(config.configurationProblem)
    }

    func testWhitespaceOnlyCountsAsUnconfigured() {
        let config = GoogleClientConfig(clientID: "   \n ")
        XCTAssertFalse(config.isConfigured)
        XCTAssertEqual(config.configurationProblem?.contains("no Google OAuth client"), true)
    }

    func testAClientIDOfTheWrongShapeIsCalledOut() {
        for wrong in ["not-a-client-id", "123456789012", "abc.googleusercontent.com", GoogleClientConfig.clientIDSuffix] {
            let config = GoogleClientConfig(clientID: wrong)
            XCTAssertTrue(config.isConfigured, wrong)
            XCTAssertFalse(config.isWellFormed, wrong)
            XCTAssertEqual(config.configurationProblem?.contains(GoogleClientConfig.clientIDSuffix), true, wrong)
        }
    }

    func testTheSuffixAloneIsNotAClientID() {
        XCTAssertFalse(GoogleClientConfig(clientID: GoogleClientConfig.clientIDSuffix).isWellFormed)
    }

    // MARK: - Scope

    func testOnlyTheReadOnlyCalendarScopeIsEverRequested() {
        XCTAssertEqual(GoogleEndpoints.scope, "https://www.googleapis.com/auth/calendar.readonly")
        XCTAssertFalse(GoogleEndpoints.scope.contains(" "), "a second scope would show up as a space-separated list")
    }

    func testTheAllowlistIsExactlyGooglesTwoEndpoints() {
        XCTAssertEqual(GoogleEndpoints.allowedHosts, ["oauth2.googleapis.com", "www.googleapis.com"])
    }

    func testAnOverrideNamingTheBuiltInClientIsIgnored() throws {
        try XCTSkipUnless(GoogleClientConfig.bundled.isConfigured, "no client compiled in")
        defaults.set(GoogleClientConfig.bundled.clientID, forKey: GoogleClientConfig.clientIDDefaultsKey)
        let resolved = GoogleClientConfig.resolve(defaults: defaults, bundle: .main)
        XCTAssertEqual(resolved.source, .bundled, "a stale copy of the built-in id must not shadow it")
        XCTAssertEqual(resolved.clientSecret, GoogleClientConfig.bundled.clientSecret)
    }

    /// This project's OAuth client requires its secret: Google's token endpoint
    /// answers `client_secret is missing` without one. Blanking it would still
    /// work on any Mac carrying a local override while breaking sign-in for
    /// every user of a released build — exactly the kind of bug that ships.
    func testTheBundledClientCarriesTheSecretItsTokenEndpointRequires() throws {
        try XCTSkipUnless(GoogleClientConfig.bundled.isConfigured, "no client compiled in")
        XCTAssertFalse(
            GoogleClientConfig.bundled.clientSecret?.isEmpty ?? true,
            "the shipping client needs its secret embedded — see GoogleClientConfig"
        )
    }

    /// A guard for the release checklist: fails only when someone has put
    /// something in `bundled` that Google will reject.
    func testTheBundledClientIsEitherEmptyOrWellFormed() {
        let bundled = GoogleClientConfig.bundled
        if bundled.isConfigured {
            XCTAssertTrue(
                bundled.isWellFormed,
                "GoogleClientConfig.bundled is set but is not a Google client ID: \(bundled.clientID)"
            )
        }
    }
}
