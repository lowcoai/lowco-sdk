import Foundation
import os

/// Analytics client for the Lowco Engage service. Use the shared instance:
///
/// ```swift
/// LowcoEngage.shared.configure(apiKey: "lc_…", orgId: "org_123", appId: "app_123")
/// LowcoEngage.shared.track("signup_completed", properties: ["plan": "pro"])
/// LowcoEngage.shared.identify(userId: "user_42", traits: ["email": "ana@example.com"])
/// LowcoEngage.shared.screen("Checkout")
/// ```
///
/// Events are queued in memory and on disk and sent in batches of 50 to
/// `POST {baseURL}/v1/engage/track/batch`: every 10 seconds, as soon as 50
/// are waiting, when the app goes to the background, and on `flush()`.
/// Tracking never throws and never blocks: every method returns at once and
/// is safe to call from any thread. Delivery problems go to
/// `Configuration.onError`. Calls made before `configure` are dropped.
public final class LowcoEngage: @unchecked Sendable {
    /// The shared client.
    public static let shared = LowcoEngage()

    /// This SDK's version (sent as `device_info.engine.version`).
    public static let sdkVersion = "0.1.0"

    /// The API host every Lowco SDK talks to by default.
    public static let defaultBaseURL = URL(string: "https://api.lowco.ai")!

    /// Header carrying the organization id.
    public static let headerOrgId = "X-Org-Id"
    /// Header carrying an `lc_` API key; other credentials travel as `Authorization: Bearer`.
    public static let headerApiKey = "X-Api-Key"
    /// Header selecting the engage app; absent means the org's default app.
    public static let headerEngageAppId = "X-Engage-App-Id"

    /// Whether `apiKey` is a Lowco API key (`lc_…`) rather than an access token.
    public static func isApiKey(_ apiKey: String) -> Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("lc_")
    }

    private let lock = NSLock()
    private var _client: EngageClient?
    private let logger = Logger(subsystem: "ai.lowco.engage", category: "LowcoEngage")

    /// A separate client (for example one per org). Most apps use `shared`.
    public init() {}

    var client: EngageClient? {
        lock.lock()
        defer { lock.unlock() }
        return _client
    }

    // MARK: - Configuration

    /// Configures the client: restores the device id, the session and any
    /// events queued on disk, and starts sending.
    ///
    /// - Parameters:
    ///   - apiKey: Required. An `lc_…` API key is sent as `X-Api-Key`; any
    ///     other value (an OAuth2 access token) as `Authorization: Bearer`.
    ///   - orgId: Required, sent as `X-Org-Id`.
    ///   - appId: The engage app to track into (`X-Engage-App-Id`). Without
    ///     it events go to the org's default app.
    ///   - baseURL: The API host (default `https://api.lowco.ai`).
    public func configure(apiKey: String, orgId: String, appId: String? = nil,
                          baseURL: URL = LowcoEngage.defaultBaseURL) {
        configure(Configuration(apiKey: apiKey, orgId: orgId, appId: appId, baseURL: baseURL))
    }

    /// Configures the client with every option (see `Configuration`). Calling
    /// it again replaces the configuration; what the old one had queued is
    /// kept on disk for its org and app.
    public func configure(_ configuration: Configuration) {
        configure(configuration, environment: nil)
    }

    func configure(_ configuration: Configuration, environment: EngageClient.Environment?) {
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("LowcoEngage: apiKey is required; not configured")
            return
        }
        guard !configuration.orgId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("LowcoEngage: orgId is required; not configured")
            return
        }
        lock.lock()
        let old = _client
        _client = nil
        lock.unlock()
        // The old client saves its queue first, so a client for the same org
        // and app picks it up.
        old?.shutdown()
        let client = EngageClient(configuration: configuration, environment: environment ?? .live(for: configuration))
        lock.lock()
        _client = client
        lock.unlock()
    }

    /// Whether `configure` has succeeded.
    public var isConfigured: Bool {
        client != nil
    }

    // MARK: - Tracking

    /// Queues a custom event. `properties` become its `event_data`; values
    /// may be strings, numbers, booleans, dates, URLs, arrays and
    /// dictionaries of them (anything else is sent as its description).
    public func track(_ name: String, properties: [String: Any] = [:]) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("LowcoEngage: an event needs a name")
            return
        }
        guard let client = requireClient() else { return }
        client.enqueue(name, data: JSONValue.object(from: properties), at: client.now())
    }

    /// Remembers `userId` for every later event (also across launches, until
    /// `reset()`) and queues `_lowco_identify` with `traits` as its
    /// `event_data`, which links this device's events to the person.
    public func identify(userId: String, traits: [String: Any] = [:]) {
        guard !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("LowcoEngage: identify needs a userId")
            return
        }
        guard let client = requireClient() else { return }
        client.enqueue(EngageConstants.identifyEvent, data: JSONValue.object(from: traits), at: client.now(),
                       identify: userId)
    }

    /// Queues a `page_view` for the screen `name`, with `path` and `title`
    /// set to it (what the Android and Flutter SDKs send for a screen),
    /// merged with `properties`.
    public func screen(_ name: String, properties: [String: Any] = [:]) {
        guard let client = requireClient() else { return }
        var data: [String: JSONValue] = ["path": .string(name), "title": .string(name)]
        data.merge(JSONValue.object(from: properties)) { _, new in new }
        client.enqueue(EngageConstants.pageViewEvent, data: data, at: client.now())
    }

    /// Logout: forgets the identified user and starts a new session. The
    /// device id is kept (like the Flutter and Android SDKs), so the
    /// device's later anonymous events stay one visitor; pass
    /// `newDeviceId: true` on a shared device to also start a new anonymous
    /// id. Events already queued keep the user they were tracked with.
    public func reset(newDeviceId: Bool = false) {
        guard let client = requireClient() else { return }
        client.reset(newDeviceId: newDeviceId, at: client.now())
    }

    /// Sends every queued event now, ignoring the retry backoff for the first
    /// batch. `completion` runs on the main queue once the queue is empty or
    /// a batch could not be sent (it stays queued).
    public func flush(completion: (() -> Void)? = nil) {
        guard let client = requireClient() else {
            if let completion { DispatchQueue.main.async(execute: completion) }
            return
        }
        client.flush(force: true, completion: completion)
    }

    /// Sets (or clears) the `location` sent with later events.
    public func setLocation(_ location: LocationInfo?) {
        client?.setLocation(location)
    }

    /// Replaces the detected `device_info` sent with later events.
    public func setDeviceInfo(_ deviceInfo: DeviceInfo) {
        client?.setDeviceInfo(deviceInfo)
    }

    // MARK: - State

    /// The identified user, or nil.
    public var userId: String? { client?.userId }

    /// The persistent anonymous device id (`lowco_uuid`).
    public var deviceId: String? { client?.deviceId }

    /// The current session id (`lowco_session_id`).
    public var sessionId: String? { client?.sessionId }

    /// The `device_info` sent with events.
    public var deviceInfo: DeviceInfo? { client?.deviceInfo }

    /// How many events wait to be sent.
    public var queuedEventCount: Int { client?.queuedEventCount ?? 0 }

    private func requireClient() -> EngageClient? {
        guard let client else {
            logger.error("LowcoEngage is not configured. Call configure(apiKey:orgId:) first.")
            return nil
        }
        return client
    }
}

extension LowcoEngage {
    /// Everything `configure` takes. Only `apiKey` and `orgId` are required.
    public struct Configuration {
        /// An `lc_…` API key (sent as `X-Api-Key`) or an OAuth2 access token
        /// (sent as `Authorization: Bearer`).
        public var apiKey: String
        /// Sent as `X-Org-Id`.
        public var orgId: String
        /// The engage app (`X-Engage-App-Id`); nil or blank is the org's
        /// default app.
        public var appId: String?
        /// The API host; `/v1/engage/track/batch` is appended.
        public var baseURL: URL
        /// Seconds between automatic flushes (default 10).
        public var flushInterval: TimeInterval
        /// Events per batch, and the queue length that triggers a flush
        /// (default 50, at most 1000).
        public var flushAt: Int
        /// The most events kept while offline; the oldest are dropped first
        /// (default 1000).
        public var maxQueueSize: Int
        /// Sent as `event_data.app_version` (where the service reads an
        /// event's app version). Defaults to `CFBundleShortVersionString`;
        /// nil sends none.
        public var appVersion: String?
        /// Replaces the detected `device_info`.
        public var deviceInfo: DeviceInfo?
        /// Where the device id, user id and session are kept (default
        /// `.standard`).
        public var userDefaults: UserDefaults
        /// The folder of the on-disk queue (default
        /// `Application Support/<bundle id>/lowco-engage`).
        public var storageDirectory: URL?
        /// The URL session configuration requests use (proxies, tests with
        /// `protocolClasses`). Default: `.default` with a 30 s timeout and no
        /// cache.
        public var urlSessionConfiguration: URLSessionConfiguration?
        /// Called with each delivery problem, on the SDK's queue.
        public var onError: ((EngageError) -> Void)?

        public init(apiKey: String, orgId: String, appId: String? = nil,
                    baseURL: URL = LowcoEngage.defaultBaseURL,
                    flushInterval: TimeInterval = 10, flushAt: Int = 50, maxQueueSize: Int = 1000) {
            self.apiKey = apiKey
            self.orgId = orgId
            self.appId = appId
            self.baseURL = baseURL
            self.flushInterval = flushInterval
            self.flushAt = flushAt
            self.maxQueueSize = maxQueueSize
            self.appVersion = DeviceInfoDetector.appVersion()
            self.deviceInfo = nil
            self.userDefaults = .standard
            self.storageDirectory = nil
            self.urlSessionConfiguration = nil
            self.onError = nil
        }
    }
}
