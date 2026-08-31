import XCTest
@testable import DeadlineFloat

final class PKCETests: XCTestCase {
    func testChallengeMatchesTheRFCTestVector() {
        // RFC 7636, Appendix B.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(PKCE.challenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testGeneratedVerifiersAreLongUniqueAndURLSafe() {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var seen = Set<String>()
        for _ in 0..<50 {
            let pkce = PKCE.generate()
            XCTAssertTrue((43...128).contains(pkce.verifier.count), "\(pkce.verifier.count)")
            XCTAssertTrue(pkce.verifier.unicodeScalars.allSatisfy(allowed.contains))
            XCTAssertTrue(pkce.challenge.unicodeScalars.allSatisfy(allowed.contains))
            XCTAssertEqual(pkce.method, "S256")
            XCTAssertTrue(seen.insert(pkce.verifier).inserted, "verifiers must not repeat")
        }
    }

    func testStateTokensAreUnique() {
        let tokens = (0..<50).map { _ in PKCE.stateToken() }
        XCTAssertEqual(Set(tokens).count, tokens.count)
    }

    func testBase64URLHasNoPaddingOrUnsafeCharacters() {
        let encoded = PKCE.base64URL(Data([251, 255, 190, 0, 1]))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
    }
}

final class AuthorizationURLTests: XCTestCase {
    func testAuthorizationURLCarriesEverythingGoogleNeeds() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = try XCTUnwrap(GoogleAuthService.authorizationURL(
            clientID: "123.apps.googleusercontent.com",
            redirectURI: "http://127.0.0.1:51234",
            pkce: pkce,
            state: "state-token"
        ))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.host, "accounts.google.com")
        XCTAssertEqual(values["client_id"], "123.apps.googleusercontent.com")
        XCTAssertEqual(values["redirect_uri"], "http://127.0.0.1:51234")
        XCTAssertEqual(values["response_type"], "code")
        XCTAssertEqual(values["code_challenge"], "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertEqual(values["state"], "state-token")
        XCTAssertEqual(values["access_type"], "offline")
        XCTAssertEqual(values["prompt"], "consent")
    }

    func testOnlyTheReadOnlyCalendarScopeIsRequested() throws {
        let url = try XCTUnwrap(GoogleAuthService.authorizationURL(
            clientID: "x", redirectURI: "http://127.0.0.1:1", pkce: .generate(), state: "s"
        ))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let scope = try XCTUnwrap(items.first { $0.name == "scope" }?.value)

        XCTAssertEqual(scope, "https://www.googleapis.com/auth/calendar.readonly")
        XCTAssertEqual(scope.split(separator: " ").count, 1, "exactly one scope")
        XCTAssertFalse(scope.contains("userinfo"))
        XCTAssertFalse(scope.contains("profile"))
        XCTAssertFalse(scope.contains("email"))
    }

    func testNoClientIDMeansNoURL() {
        XCTAssertNil(GoogleAuthService.authorizationURL(clientID: "", redirectURI: "http://127.0.0.1:1", pkce: .generate(), state: "s"))
    }
}

final class TokenTests: XCTestCase {
    func testExpiryUsesALeeway() {
        let now = Fixture.date(2026, 9, 2, 12, 0, 0)
        let tokens = OAuthTokens(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(30), scope: nil)
        XCTAssertTrue(tokens.isExpired(now: now), "a token expiring in 30s is treated as already expired")
        XCTAssertFalse(tokens.isExpired(now: now.addingTimeInterval(-600)))
    }

    func testRefreshResponseKeepsTheExistingRefreshToken() {
        let now = Fixture.date(2026, 9, 2, 12)
        let response = GoogleTokenResponse(access_token: "new", expires_in: 3599, token_type: "Bearer")
        let tokens = response.tokens(now: now, existingRefreshToken: "keep-me")

        XCTAssertEqual(tokens?.accessToken, "new")
        XCTAssertEqual(tokens?.refreshToken, "keep-me")
        XCTAssertEqual(tokens?.expiresAt, now.addingTimeInterval(3599))
        XCTAssertEqual(tokens?.authorizationHeader, "Bearer new")
    }

    func testAFreshRefreshTokenReplacesTheOldOne() {
        let response = GoogleTokenResponse(access_token: "a", refresh_token: "brand-new", expires_in: 60)
        XCTAssertEqual(response.tokens(now: Date(), existingRefreshToken: "old")?.refreshToken, "brand-new")
    }

    func testResponseWithoutAnAccessTokenIsRejected() {
        let response = GoogleTokenResponse(error: "invalid_grant", error_description: "Token has been expired or revoked.")
        XCTAssertNil(response.tokens(now: Date(), existingRefreshToken: nil))
    }

    func testTerminalRefreshFailuresAreRecognised() {
        XCTAssertTrue(GoogleAuthService.isTerminalRefreshFailure(APIError.unauthorized))
        XCTAssertTrue(GoogleAuthService.isTerminalRefreshFailure(APIError.server(status: 400, message: "")))
        XCTAssertTrue(GoogleAuthService.isTerminalRefreshFailure(AuthError.refreshFailed("invalid_grant")))
        XCTAssertTrue(GoogleAuthService.isTerminalRefreshFailure(AuthError.refreshFailed("Token has been expired or revoked.")))
        XCTAssertFalse(GoogleAuthService.isTerminalRefreshFailure(APIError.offline))
        XCTAssertFalse(GoogleAuthService.isTerminalRefreshFailure(APIError.rateLimited(retryAfter: nil)))
    }

    func testKeychainlessStoreRoundTrip() throws {
        let store = InMemoryTokenStore()
        XCTAssertNil(try store.load())
        let tokens = OAuthTokens(accessToken: "a", refreshToken: "r", expiresAt: Date(), scope: GoogleEndpoints.scope)
        try store.save(tokens)
        XCTAssertEqual(try store.load(), tokens)
        try store.clear()
        XCTAssertNil(try store.load())
    }
}

final class LoopbackRedirectServerTests: XCTestCase {
    func testParsesTheAuthorizationCodeFromARequestLine() {
        let request = "GET /?code=4/0AVG7fiQ&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcalendar.readonly&state=xyz HTTP/1.1\r\nHost: 127.0.0.1:51234\r\n\r\n"
        let parameters = LoopbackRedirectServer.queryParameters(fromRequest: request)
        XCTAssertEqual(parameters["code"], "4/0AVG7fiQ")
        XCTAssertEqual(parameters["state"], "xyz")
        XCTAssertEqual(parameters["scope"], "https://www.googleapis.com/auth/calendar.readonly")
    }

    func testParsesAnErrorRedirect() {
        let request = "GET /?error=access_denied&state=xyz HTTP/1.1\r\n\r\n"
        let parameters = LoopbackRedirectServer.queryParameters(fromRequest: request)
        XCTAssertEqual(parameters["error"], "access_denied")
        XCTAssertNil(parameters["code"])
    }

    func testIgnoresRequestsWithoutAQuery() {
        XCTAssertTrue(LoopbackRedirectServer.queryParameters(fromRequest: "GET /favicon.ico HTTP/1.1\r\n\r\n").isEmpty)
        XCTAssertTrue(LoopbackRedirectServer.queryParameters(fromRequest: "").isEmpty)
        XCTAssertTrue(LoopbackRedirectServer.queryParameters(fromRequest: "garbage").isEmpty)
    }

    func testResponsePageMentionsTheOutcome() {
        XCTAssertTrue(LoopbackRedirectServer.responseHTML(success: true, error: nil).contains("DeadlineFloat is connected"))
        let failure = LoopbackRedirectServer.responseHTML(success: false, error: "access_denied")
        XCTAssertTrue(failure.contains("Sign-in was not completed"))
        XCTAssertTrue(failure.contains("access_denied"))
    }

    func testBindsAnEphemeralLoopbackPort() throws {
        let server = LoopbackRedirectServer()
        defer { server.stop() }
        let port = try server.start()
        XCTAssertGreaterThan(port, 1024)
        XCTAssertEqual(server.redirectURI, "http://127.0.0.1:\(port)")
    }
}
