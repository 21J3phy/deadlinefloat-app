import XCTest
@testable import DeadlineFloat

final class HTTPClientTests: XCTestCase {
    private func request(_ urlString: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = method
        return request
    }

    // MARK: - Guardrails

    func testOnlyGoogleHostsAreAllowed() {
        let client = HTTPClient.testing(transport: FakeTransport(status: 200, json: "{}"))
        XCTAssertNoThrow(try client.validate(request("https://www.googleapis.com/calendar/v3/colors")))
        XCTAssertNoThrow(try client.validate(request("https://oauth2.googleapis.com/token", method: "POST")))

        for blocked in [
            "https://analytics.example.com/collect",
            "https://calendar.google.com/anything",
            "https://accounts.google.com/o/oauth2/v2/auth",
            "https://www.googleapis.com.evil.test/calendar/v3/colors"
        ] {
            XCTAssertThrowsError(try client.validate(request(blocked)), blocked) { error in
                guard case APIError.disallowedRequest = error else {
                    return XCTFail("expected disallowedRequest for \(blocked), got \(error)")
                }
            }
        }
    }

    func testPlainHTTPIsRefused() {
        let client = HTTPClient.testing(transport: FakeTransport(status: 200, json: "{}"))
        XCTAssertThrowsError(try client.validate(request("http://www.googleapis.com/calendar/v3/colors")))
    }

    func testCalendarAPIRefusesEveryWriteButAnEventPatch() {
        let client = HTTPClient.testing(transport: FakeTransport(status: 200, json: "{}"))
        for method in ["POST", "PUT", "PATCH", "DELETE"] {
            XCTAssertThrowsError(
                try client.validate(request("https://www.googleapis.com/calendar/v3/calendars/x/events", method: method)),
                "\(method) on the event list must be refused"
            ) { error in
                guard case APIError.disallowedRequest(let detail) = error else {
                    return XCTFail("expected disallowedRequest, got \(error)")
                }
                XCTAssertTrue(detail.contains(method), detail)
            }
        }
    }

    func testOneEventMayBePatched() {
        let client = HTTPClient.testing(transport: FakeTransport(status: 200, json: "{}"))
        XCTAssertNoThrow(try client.validate(
            request("https://www.googleapis.com/calendar/v3/calendars/primary%40example.com/events/e1", method: "PATCH")
        ))
    }

    func testTheEventPatchIsTheOnlyWriteThatFits() {
        let client = HTTPClient.testing(transport: FakeTransport(status: 200, json: "{}"))

        // An event's own URL, but the wrong verb.
        for method in ["POST", "PUT", "DELETE"] {
            XCTAssertThrowsError(
                try client.validate(request("https://www.googleapis.com/calendar/v3/calendars/x/events/e1", method: method)),
                "\(method) on one event must be refused"
            )
        }

        // A PATCH, but not at an event's own URL.
        for path in [
            "/calendar/v3/calendars/x",
            "/calendar/v3/users/me/calendarList/x",
            "/calendar/v3/calendars/x/acl/rule1",
            "/calendar/v3/calendars/x/events/e1/instances",
            "/calendar/v3/colors"
        ] {
            XCTAssertThrowsError(
                try client.validate(request("https://www.googleapis.com\(path)", method: "PATCH")),
                "PATCH \(path) must be refused"
            )
        }
    }

    func testTheWriteGuardIsDecidedOnTheShapeOfThePath() {
        XCTAssertTrue(HTTPClient.isPermitted(
            method: "patch",
            url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/a%40b.com/events/e1?sendUpdates=none")!
        ), "a percent-encoded calendar id is still one path component")
        XCTAssertTrue(HTTPClient.isPermitted(
            method: "GET",
            url: URL(string: "https://www.googleapis.com/calendar/v3/anything/at/all")!
        ))
        XCTAssertFalse(HTTPClient.isPermitted(
            method: "DELETE",
            url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/x/events/e1")!
        ))
    }

    func testTokenEndpointMayBePosted() {
        let client = HTTPClient.testing(transport: FakeTransport(status: 200, json: "{}"))
        XCTAssertNoThrow(try client.validate(request("https://oauth2.googleapis.com/token", method: "POST")))
    }

    // MARK: - Status handling

    func testUnauthorizedIsSurfacedImmediately() throws {
        let transport = FakeTransport(status: 401, json: #"{"error":{"code":401,"message":"Invalid Credentials"}}"#)
        let client = HTTPClient.testing(transport: transport)

        XCTAssertThrowsError(try awaitValue { try await client.get(URL(string: "https://www.googleapis.com/calendar/v3/colors")!, accessToken: "t") }) { error in
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
        XCTAssertEqual(transport.callCount, 1, "401 must not be retried")
    }

    func testRateLimitingIsRetriedThenReported() throws {
        let sleeps = SleepRecorder()
        let body = #"{"error":{"code":429,"message":"Rate Limit Exceeded","errors":[{"reason":"rateLimitExceeded"}]}}"#
        let transport = FakeTransport(status: 429, json: body)
        let client = HTTPClient.testing(transport: transport, retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: 1, maxDelay: 30), recordedSleeps: sleeps)

        XCTAssertThrowsError(try awaitValue { try await client.get(URL(string: "https://www.googleapis.com/calendar/v3/colors")!, accessToken: "t") }) { error in
            guard case APIError.rateLimited = error else { return XCTFail("expected rateLimited, got \(error)") }
        }
        XCTAssertEqual(transport.callCount, 3)
        XCTAssertEqual(sleeps.values, [1.0, 2.0], "exponential backoff with the fixed 0.5 jitter")
    }

    func testRetryAfterHeaderIsHonoured() throws {
        let sleeps = SleepRecorder()
        let transport = FakeTransport(status: 503, json: "{}", headers: ["Retry-After": "7"])
        let client = HTTPClient.testing(transport: transport, retryPolicy: RetryPolicy(maxAttempts: 2), recordedSleeps: sleeps)

        _ = try? awaitValue { try await client.get(URL(string: "https://www.googleapis.com/calendar/v3/colors")!, accessToken: "t") }
        XCTAssertEqual(sleeps.values, [7.0])
    }

    func testTransientFailureThenSuccess() throws {
        let transport = FakeTransport { request, index in
            let status = index == 0 ? 500 : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"items":[]}"#.utf8), response)
        }
        let client = HTTPClient.testing(transport: transport)
        let result = try awaitValue { try await client.get(URL(string: "https://www.googleapis.com/calendar/v3/colors")!, accessToken: "t") }
        XCTAssertEqual(result.status, 200)
        XCTAssertEqual(transport.callCount, 2)
    }

    func testForbiddenWithoutARateLimitReasonIsNotRetried() throws {
        let body = #"{"error":{"code":403,"message":"Insufficient Permission","errors":[{"reason":"insufficientPermissions"}]}}"#
        let transport = FakeTransport(status: 403, json: body)
        let client = HTTPClient.testing(transport: transport)

        XCTAssertThrowsError(try awaitValue { try await client.get(URL(string: "https://www.googleapis.com/calendar/v3/colors")!, accessToken: "t") }) { error in
            guard case APIError.server(let status, let message) = error else { return XCTFail("got \(error)") }
            XCTAssertEqual(status, 403)
            XCTAssertEqual(message, "Insufficient Permission")
        }
        XCTAssertEqual(transport.callCount, 1)
    }

    func testOfflineIsReportedWithoutRetrying() throws {
        let transport = FakeTransport { _, _ in throw URLError(.notConnectedToInternet) }
        let client = HTTPClient.testing(transport: transport)

        XCTAssertThrowsError(try awaitValue { try await client.get(URL(string: "https://www.googleapis.com/calendar/v3/colors")!, accessToken: "t") }) { error in
            XCTAssertEqual(error as? APIError, .offline)
        }
        XCTAssertEqual(transport.callCount, 1)
    }

    func testAuthorizationHeaderIsAttached() throws {
        let transport = FakeTransport(status: 200, json: "{}")
        let client = HTTPClient.testing(transport: transport)
        _ = try awaitValue { try await client.get(URL(string: "https://www.googleapis.com/calendar/v3/colors")!, accessToken: "abc") }
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
    }

    // MARK: - Retry policy

    func testRetryPolicyClassification() {
        let policy = RetryPolicy()
        for status in [408, 429, 500, 502, 503, 504] {
            XCTAssertTrue(policy.isRetryable(status: status, reason: nil), "\(status)")
        }
        for status in [400, 401, 404, 409, 422] {
            XCTAssertFalse(policy.isRetryable(status: status, reason: nil), "\(status)")
        }
        XCTAssertTrue(policy.isRetryable(status: 403, reason: "rateLimitExceeded"))
        XCTAssertTrue(policy.isRetryable(status: 403, reason: "userRateLimitExceeded"))
        XCTAssertTrue(policy.isRetryable(status: 403, reason: "quotaExceeded"))
        XCTAssertFalse(policy.isRetryable(status: 403, reason: "insufficientPermissions"))
        XCTAssertFalse(policy.isRetryable(status: 403, reason: nil))
    }

    func testBackoffGrowsAndIsCapped() {
        let policy = RetryPolicy(maxAttempts: 8, baseDelay: 1, maxDelay: 10)
        XCTAssertEqual(policy.delay(attempt: 1, retryAfter: nil, jitter: 0.5), 1.0, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(attempt: 2, retryAfter: nil, jitter: 0.5), 2.0, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(attempt: 3, retryAfter: nil, jitter: 0.5), 4.0, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(attempt: 9, retryAfter: nil, jitter: 0.5), 10.0, accuracy: 0.0001)
    }

    func testJitterStaysWithinBounds() {
        let policy = RetryPolicy(baseDelay: 4, maxDelay: 60)
        XCTAssertEqual(policy.delay(attempt: 1, retryAfter: nil, jitter: 0), 3.0, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(attempt: 1, retryAfter: nil, jitter: 1), 5.0, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(attempt: 1, retryAfter: nil, jitter: 99), 5.0, accuracy: 0.0001)
    }

    func testRetryAfterIsCappedToo() {
        let policy = RetryPolicy(maxDelay: 30)
        XCTAssertEqual(policy.delay(attempt: 1, retryAfter: 500, jitter: 0.5), 30)
    }

    func testFormEncodingIsStableAndEscaped() {
        let encoded = HTTPClient.formEncode(["b": "two words", "a": "x/y+z", "grant_type": "refresh_token"])
        XCTAssertEqual(encoded, "a=x%2Fy%2Bz&b=two%20words&grant_type=refresh_token")
    }

    func testOfflineClassification() {
        XCTAssertTrue(HTTPClient.isOffline(URLError(.notConnectedToInternet)))
        XCTAssertTrue(HTTPClient.isOffline(URLError(.timedOut)))
        XCTAssertTrue(HTTPClient.isOffline(URLError(.dnsLookupFailed)))
        XCTAssertFalse(HTTPClient.isOffline(URLError(.badServerResponse)))
    }
}
