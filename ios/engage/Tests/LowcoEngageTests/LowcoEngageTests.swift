import XCTest
@testable import LowcoEngage

final class LowcoEngageTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var directory: URL!
    private var clock: TestClock!
    private var errors: Box<EngageError>!
    private var engages: [LowcoEngage] = []

    static let start = Date(timeIntervalSince1970: 1_790_000_000.5)
    static let deviceInfo = DeviceInfo(
        os: .init(name: "iOS", version: "17.2"),
        device: .init(type: "mobile", vendor: "Apple", model: "iPhone15,2"),
        cpu: .init(architecture: "arm64"),
        engine: .init(name: "LowcoEngage", version: LowcoEngage.sdkVersion),
        ua: "LowcoEngage (iOS 17.2)"
    )

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "ai.lowco.engage.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lowco-engage-tests-\(UUID().uuidString)", isDirectory: true)
        clock = TestClock(Self.start)
        errors = Box()
    }

    override func tearDown() {
        engages.forEach { $0.client?.shutdown() }
        engages = []
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeEngage(apiKey: String = "token_123", appId: String? = nil,
                            baseURL: String = "https://api.example.test",
                            flushAt: Int = 50, maxQueueSize: Int = 1000) -> LowcoEngage {
        var configuration = LowcoEngage.Configuration(apiKey: apiKey, orgId: "org_1", appId: appId,
                                                      baseURL: URL(string: baseURL)!, flushAt: flushAt,
                                                      maxQueueSize: maxQueueSize)
        configuration.appVersion = "2.3.0"
        configuration.userDefaults = defaults
        configuration.storageDirectory = directory
        let errors = self.errors!
        configuration.onError = { errors.append($0) }
        let clock = self.clock!
        let environment = EngageClient.Environment(
            session: URLSession(configuration: StubURLProtocol.sessionConfiguration()),
            ownsSession: true,
            now: { clock.now },
            jitter: { 1 },
            deviceInfo: Self.deviceInfo,
            automaticFlush: false,
            persistDelay: 0
        )
        let engage = LowcoEngage()
        engage.configure(configuration, environment: environment)
        engages.append(engage)
        return engage
    }

    private func flush(_ engage: LowcoEngage, file: StaticString = #filePath, line: UInt = #line) {
        let done = expectation(description: "flush")
        engage.flush { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    /// The timer's flush: honours the retry backoff.
    private func tick(_ engage: LowcoEngage) {
        let done = expectation(description: "tick")
        engage.client!.flush(force: false) { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    private func waitUntil(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    private var sent: [StubURLProtocol.Captured] { StubURLProtocol.captured }

    // MARK: - Headers and wire format

    func testAccessTokenTravelsAsBearerWithoutAppHeader() throws {
        let engage = makeEngage(apiKey: " token_123 ")
        engage.track("signup_completed")
        flush(engage)

        let request = try XCTUnwrap(sent.first)
        XCTAssertEqual(request.request.httpMethod, "POST")
        XCTAssertEqual(request.request.url?.absoluteString, "https://api.example.test/v1/engage/track/batch")
        XCTAssertEqual(request.header("Authorization"), "Bearer token_123")
        XCTAssertNil(request.header("X-Api-Key"))
        XCTAssertEqual(request.header("X-Org-Id"), "org_1")
        XCTAssertEqual(request.header("Content-Type"), "application/json")
        XCTAssertNil(request.header("X-Engage-App-Id"))
    }

    func testLcKeyTravelsAsXApiKeyAndAppIdIsSent() throws {
        let engage = makeEngage(apiKey: "lc_secret", appId: " app_42 ", baseURL: "https://staging.example.test/")
        engage.track("x")
        flush(engage)

        let request = try XCTUnwrap(sent.first)
        XCTAssertEqual(request.request.url?.absoluteString, "https://staging.example.test/v1/engage/track/batch")
        XCTAssertEqual(request.header("X-Api-Key"), "lc_secret")
        XCTAssertNil(request.header("Authorization"))
        XCTAssertEqual(request.header("X-Engage-App-Id"), "app_42")
        XCTAssertEqual(request.header("X-Org-Id"), "org_1")
    }

    func testBlankAppIdMeansDefaultApp() throws {
        let engage = makeEngage(appId: "   ")
        engage.track("x")
        flush(engage)
        XCTAssertNil(try XCTUnwrap(sent.first).header("X-Engage-App-Id"))
    }

    func testEventHasTheFlutterWireShape() throws {
        let engage = makeEngage()
        engage.track("signup_completed", properties: ["plan": "pro", "seats": 3, "trial": true, "ratio": 0.5])
        flush(engage)

        let events = try XCTUnwrap(sent.first).events
        XCTAssertEqual(events.count, 1)
        let event = events[0]
        XCTAssertEqual(Set(event.keys), ["id", "event_name", "event_data", "user_id", "device_id", "session_id",
                                         "device_info", "location", "event_time"])
        XCTAssertEqual(event["id"] as? String, "")
        XCTAssertEqual(event["event_name"] as? String, "signup_completed")
        XCTAssertTrue(event["user_id"] is NSNull)
        XCTAssertTrue(event["location"] is NSNull)
        XCTAssertEqual(event["device_id"] as? String, engage.deviceId)
        XCTAssertEqual(event["session_id"] as? String, engage.sessionId)
        XCTAssertEqual(event["event_time"] as? String, "2026-09-21T14:13:20.500Z")

        let data = try XCTUnwrap(event["event_data"] as? [String: Any])
        XCTAssertEqual(data["plan"] as? String, "pro")
        XCTAssertEqual(data["seats"] as? Int, 3)
        XCTAssertEqual(data["trial"] as? Bool, true)
        XCTAssertEqual(data["ratio"] as? Double, 0.5)
        XCTAssertEqual(data["app_version"] as? String, "2.3.0")

        let deviceInfo = try XCTUnwrap(event["device_info"] as? [String: Any])
        XCTAssertEqual(deviceInfo["os"] as? [String: String], ["name": "iOS", "version": "17.2"])
        XCTAssertEqual(deviceInfo["device"] as? [String: String],
                       ["type": "mobile", "vendor": "Apple", "model": "iPhone15,2"])
        XCTAssertEqual(deviceInfo["engine"] as? [String: String],
                       ["name": "LowcoEngage", "version": LowcoEngage.sdkVersion])
        XCTAssertEqual(deviceInfo["ua"] as? String, "LowcoEngage (iOS 17.2)")
    }

    func testDeviceIdIsALowercaseUUIDKeptInUserDefaults() throws {
        let engage = makeEngage()
        let deviceId = try XCTUnwrap(engage.deviceId)
        XCTAssertNotNil(UUID(uuidString: deviceId))
        XCTAssertEqual(deviceId, deviceId.lowercased())
        XCTAssertEqual(defaults.string(forKey: "lowco_uuid"), deviceId)
    }

    func testLocationIsSentOnceSet() throws {
        let engage = makeEngage()
        engage.setLocation(LocationInfo(latitude: 12.97, longitude: 77.59, altitudeAccuracy: 3))
        engage.track("x")
        flush(engage)
        let location = try XCTUnwrap(sent.first?.events.first?["location"] as? [String: Double])
        XCTAssertEqual(location, ["latitude": 12.97, "longitude": 77.59, "altitude_accuracy": 3])
    }

    // MARK: - Batching

    func testSendsInBatchesOfFifty() throws {
        let engage = makeEngage()
        let client = try XCTUnwrap(engage.client)
        // Queue 120 at once: no answer can arrive in between.
        client.sync {
            for i in 0..<120 {
                client.enqueueLocked("e\(i)", data: [:], at: clock.now)
            }
        }
        flush(engage)

        XCTAssertEqual(sent.map(\.events.count), [50, 50, 20])
        XCTAssertEqual(sent.flatMap(\.eventNames), (0..<120).map { "e\($0)" })
        XCTAssertEqual(engage.queuedEventCount, 0)
    }

    func testFlushesWhenFiftyEventsWait() {
        let engage = makeEngage()
        for i in 0..<49 {
            engage.track("e\(i)")
        }
        XCTAssertEqual(engage.queuedEventCount, 49)
        XCTAssertTrue(sent.isEmpty)

        engage.track("e49")
        waitUntil { self.sent.count == 1 }
        waitUntil { engage.queuedEventCount == 0 }
        XCTAssertEqual(sent.first?.events.count, 50)
    }

    // MARK: - Results and retries

    func testRejectedRowsAreDroppedAndTransientRowsKept() throws {
        StubURLProtocol.handler = { captured in
            StubURLProtocol.json(200, ["status": 1, "data": ["accepted": 1, "rejected": 2, "results": [
                ["index": 0, "eventName": "a", "ok": true],
                ["index": 1, "eventName": "b", "ok": false, "error": "breaks its strict event definition"],
                ["index": 2, "eventName": "c", "ok": false, "error": "couldn't be queued; send it again"],
            ]]])
        }
        let engage = makeEngage()
        engage.track("a")
        engage.track("b")
        engage.track("c")
        flush(engage)

        let client = try XCTUnwrap(engage.client)
        XCTAssertEqual(client.queuedEvents.map(\.eventName), ["c"])
        XCTAssertEqual(client.retryAttempt, 1)
        XCTAssertEqual(errors.all.map(\.kind), [.rejectedEvents])
        XCTAssertTrue(errors.all.first?.message.contains("b: breaks its strict event definition") ?? false)

        StubURLProtocol.handler = nil
        flush(engage)
        XCTAssertEqual(sent.last?.eventNames, ["c"])
        XCTAssertEqual(engage.queuedEventCount, 0)
        XCTAssertEqual(client.retryAttempt, 0)
    }

    func testServerErrorKeepsTheBatchAndBacksOff() throws {
        StubURLProtocol.handler = { _ in StubURLProtocol.json(500, ["error": ["message": "boom"]]) }
        let engage = makeEngage()
        engage.track("a")
        engage.track("b")
        flush(engage)

        let client = try XCTUnwrap(engage.client)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(engage.queuedEventCount, 2)
        XCTAssertEqual(client.retryAttempt, 1)
        XCTAssertEqual(client.nextAttemptAt, clock.now.addingTimeInterval(2))
        XCTAssertEqual(errors.all.first?.kind, .http)
        XCTAssertEqual(errors.all.first?.statusCode, 500)

        // The timer's flush waits out the backoff.
        StubURLProtocol.handler = nil
        tick(engage)
        XCTAssertEqual(sent.count, 1)

        // A second failure doubles it.
        StubURLProtocol.handler = { _ in StubURLProtocol.json(503, [:]) }
        clock.advance(3)
        tick(engage)
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(client.retryAttempt, 2)
        XCTAssertEqual(client.nextAttemptAt, clock.now.addingTimeInterval(4))

        StubURLProtocol.handler = nil
        clock.advance(5)
        tick(engage)
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sent.last?.eventNames, ["a", "b"])
        XCTAssertEqual(engage.queuedEventCount, 0)
        XCTAssertEqual(client.retryAttempt, 0)
        XCTAssertNil(client.nextAttemptAt)
    }

    func testTooManyRequestsHonoursRetryAfter() throws {
        StubURLProtocol.handler = { _ in StubURLProtocol.json(429, [:], headers: ["Retry-After": "60"]) }
        let engage = makeEngage()
        engage.track("a")
        flush(engage)
        let client = try XCTUnwrap(engage.client)
        XCTAssertEqual(engage.queuedEventCount, 1)
        XCTAssertEqual(client.nextAttemptAt, clock.now.addingTimeInterval(60))
    }

    func testNetworkErrorKeepsTheBatch() throws {
        StubURLProtocol.handler = { _ in .failure(URLError(.notConnectedToInternet)) }
        let engage = makeEngage()
        engage.track("a")
        flush(engage)
        XCTAssertEqual(engage.queuedEventCount, 1)
        XCTAssertEqual(try XCTUnwrap(engage.client).retryAttempt, 1)
        XCTAssertEqual(errors.all.first?.kind, .network)
    }

    func testOtherClientErrorsDropTheBatch() {
        StubURLProtocol.handler = { _ in StubURLProtocol.json(400, ["error": ["message": "AAS-00400", "details": "bad body"]]) }
        let engage = makeEngage()
        engage.track("a")
        engage.track("b")
        flush(engage)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(engage.queuedEventCount, 0)
        XCTAssertEqual(errors.all.first?.kind, .http)
        XCTAssertEqual(errors.all.first?.statusCode, 400)
        XCTAssertTrue(errors.all.first?.message.contains("bad body") ?? false)
    }

    func testForcedFlushIgnoresTheBackoff() {
        StubURLProtocol.handler = { _ in StubURLProtocol.json(500, [:]) }
        let engage = makeEngage()
        engage.track("a")
        flush(engage)
        StubURLProtocol.handler = nil
        flush(engage)
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(engage.queuedEventCount, 0)
    }

    // MARK: - Disk

    func testQueueSurvivesARestart() throws {
        StubURLProtocol.handler = { _ in .failure(URLError(.notConnectedToInternet)) }
        let first = makeEngage()
        first.track("a")
        first.track("b", properties: ["when": Date(timeIntervalSince1970: 0)])
        first.track("c")
        flush(first)
        let deviceId = first.deviceId
        first.client?.shutdown()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, ["queue-org_1-default.json"])

        StubURLProtocol.handler = nil
        let second = makeEngage()
        XCTAssertEqual(second.queuedEventCount, 3)
        XCTAssertEqual(second.deviceId, deviceId)
        flush(second)
        let last = try XCTUnwrap(sent.last)
        XCTAssertEqual(last.eventNames, ["a", "b", "c"])
        let data = last.events[1]["event_data"] as? [String: Any]
        XCTAssertEqual(data?["when"] as? String, "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(second.queuedEventCount, 0)
    }

    func testFullQueueDropsTheOldest() throws {
        let engage = makeEngage(maxQueueSize: 5)
        for i in 0..<8 {
            engage.track("e\(i)")
        }
        XCTAssertEqual(try XCTUnwrap(engage.client).queuedEvents.map(\.eventName), ["e3", "e4", "e5", "e6", "e7"])
    }

    // MARK: - Sessions and identity

    func testSessionRollsOverAfterThirtyIdleMinutes() throws {
        let engage = makeEngage()
        engage.track("a")
        clock.advance(10 * 60)
        engage.track("b")
        clock.advance(31 * 60)
        engage.track("c")
        flush(engage)

        let sessions = try XCTUnwrap(sent.first).events.compactMap { $0["session_id"] as? String }
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(sessions[0], sessions[1])
        XCTAssertNotEqual(sessions[1], sessions[2])
        XCTAssertEqual(defaults.string(forKey: "lowco_session_id"), sessions[2])
        XCTAssertEqual(defaults.string(forKey: "lowco_session_last_event"), String(epochMillis(clock.now)))
    }

    func testSessionIsRestoredWithinThirtyMinutes() {
        let first = makeEngage()
        first.track("a")
        let session = first.sessionId
        first.client?.shutdown()

        clock.advance(29 * 60)
        let second = makeEngage()
        XCTAssertEqual(second.sessionId, session)
        second.client?.shutdown()

        clock.advance(31 * 60)
        let third = makeEngage()
        XCTAssertNotEqual(third.sessionId, session)
    }

    func testIdentifyRemembersTheUserUntilReset() throws {
        let engage = makeEngage()
        engage.track("anonymous")
        engage.identify(userId: "user_42", traits: ["email": "ana@example.com"])
        engage.track("known")
        XCTAssertEqual(engage.userId, "user_42")
        let deviceId = engage.deviceId
        let session = engage.sessionId
        engage.reset()
        engage.track("after_reset")
        flush(engage)

        let events = try XCTUnwrap(sent.first).events
        XCTAssertEqual(events.map { $0["event_name"] as? String }, ["anonymous", "_lowco_identify", "known", "after_reset"])
        XCTAssertTrue(events[0]["user_id"] is NSNull)
        XCTAssertEqual(events[1]["user_id"] as? String, "user_42")
        XCTAssertEqual((events[1]["event_data"] as? [String: Any])?["email"] as? String, "ana@example.com")
        XCTAssertEqual(events[2]["user_id"] as? String, "user_42")
        XCTAssertTrue(events[3]["user_id"] is NSNull)
        XCTAssertEqual(events[3]["device_id"] as? String, deviceId)
        XCTAssertNotEqual(events[3]["session_id"] as? String, session)
        XCTAssertNil(engage.userId)
        XCTAssertEqual(engage.deviceId, deviceId)
    }

    func testIdentifiedUserSurvivesARestart() {
        let first = makeEngage()
        first.identify(userId: "user_42")
        XCTAssertEqual(first.userId, "user_42")
        first.client?.shutdown()
        let second = makeEngage()
        XCTAssertEqual(second.userId, "user_42")
        second.reset()
        XCTAssertNil(second.userId)
        XCTAssertNil(defaults.string(forKey: "lowco_user_id"))
    }

    func testResetCanStartANewDeviceId() {
        let engage = makeEngage()
        let before = engage.deviceId
        engage.reset(newDeviceId: true)
        XCTAssertNotEqual(engage.deviceId, before)
        XCTAssertEqual(defaults.string(forKey: "lowco_uuid"), engage.deviceId)
    }

    func testScreenIsAPageViewWithPathAndTitle() throws {
        let engage = makeEngage()
        engage.screen("Checkout", properties: ["cart_value": 1299, "title": "Checkout – step 2"])
        flush(engage)
        let event = try XCTUnwrap(sent.first?.events.first)
        XCTAssertEqual(event["event_name"] as? String, "page_view")
        let data = try XCTUnwrap(event["event_data"] as? [String: Any])
        XCTAssertEqual(data["path"] as? String, "Checkout")
        XCTAssertEqual(data["title"] as? String, "Checkout – step 2")
        XCTAssertEqual(data["cart_value"] as? Int, 1299)
    }

    // MARK: - Facade

    func testCallsBeforeConfigureAndBadConfigurationsAreIgnored() {
        let engage = LowcoEngage()
        engage.track("dropped")
        engage.identify(userId: "u")
        engage.reset()
        XCTAssertFalse(engage.isConfigured)
        XCTAssertNil(engage.deviceId)
        XCTAssertEqual(engage.queuedEventCount, 0)
        let done = expectation(description: "flush")
        engage.flush { done.fulfill() }
        wait(for: [done], timeout: 2)

        engage.configure(apiKey: "  ", orgId: "org_1")
        XCTAssertFalse(engage.isConfigured)
        engage.configure(apiKey: "key", orgId: "")
        XCTAssertFalse(engage.isConfigured)
        XCTAssertTrue(sent.isEmpty)
    }

    func testBlankNamesAreIgnored() {
        let engage = makeEngage()
        engage.track("  ")
        engage.identify(userId: " ")
        XCTAssertEqual(engage.queuedEventCount, 0)
        XCTAssertNil(engage.userId)
    }

    func testReconfigureKeepsTheQueueOfTheSameApp() {
        StubURLProtocol.handler = { _ in .failure(URLError(.timedOut)) }
        let engage = makeEngage()
        engage.track("a")
        var configuration = engage.client!.configuration
        configuration.flushAt = 10
        let clock = self.clock!
        engage.configure(configuration, environment: EngageClient.Environment(
            session: URLSession(configuration: StubURLProtocol.sessionConfiguration()), ownsSession: true,
            now: { clock.now }, jitter: { 1 }, deviceInfo: Self.deviceInfo, automaticFlush: false, persistDelay: 0))
        XCTAssertEqual(engage.queuedEventCount, 1)
        XCTAssertEqual(engage.client?.batchSize, 10)
    }
}
