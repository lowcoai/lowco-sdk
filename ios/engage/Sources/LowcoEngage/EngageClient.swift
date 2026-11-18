import Foundation
import os
#if canImport(UIKit) && !os(watchOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum EngageConstants {
    static let batchPath = "/v1/engage/track/batch"
    static let identifyEvent = "_lowco_identify"
    static let pageViewEvent = "page_view"

    static let deviceIdKey = "lowco_uuid"
    static let sessionIdKey = "lowco_session_id"
    static let sessionLastEventKey = "lowco_session_last_event"
    static let userIdKey = "lowco_user_id"

    /// A session ends after this much inactivity (same as the other SDKs).
    static let sessionTimeoutMs: Int64 = 30 * 60 * 1000

    /// The most events /track/batch takes at once.
    static let maxBatchSize = 1000

    static let initialBackoff: TimeInterval = 2
    static let maxBackoff: TimeInterval = 300

    /// The batch row error the service answers when it could not queue an
    /// event for a moment ("couldn't be queued; send it again").
    static let transientRowError = "send it again"
}

/// The engine behind `LowcoEngage`: identity, sessions and the event queue.
///
/// Every piece of state is touched only on `queue` (serial), so the public
/// API is safe from any thread. Events are converted to JSON on the calling
/// thread, appended to the queue and saved to disk; batches of `flushAt`
/// events go to `POST /v1/engage/track/batch`, one request at a time.
final class EngageClient {
    struct Environment {
        var session: URLSession
        /// The client invalidates a session it owns when it shuts down.
        var ownsSession: Bool
        var now: () -> Date
        /// Multiplies each backoff delay (0.8…1.2 in production).
        var jitter: () -> Double
        var deviceInfo: DeviceInfo
        /// The periodic flush timer, scheduled retries and the flush when the
        /// app goes to the background. Tests turn it off and flush themselves.
        var automaticFlush: Bool
        /// How long a change waits before the queue is written to disk, so a
        /// burst of events is one write. 0 writes at once.
        var persistDelay: TimeInterval

        static func live(for configuration: LowcoEngage.Configuration) -> Environment {
            let sessionConfiguration: URLSessionConfiguration
            if let custom = configuration.urlSessionConfiguration {
                sessionConfiguration = custom
            } else {
                sessionConfiguration = .default
                sessionConfiguration.timeoutIntervalForRequest = 30
                sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
                sessionConfiguration.urlCache = nil
            }
            return Environment(
                session: URLSession(configuration: sessionConfiguration),
                ownsSession: true,
                now: { Date() },
                jitter: { Double.random(in: 0.8...1.2) },
                deviceInfo: configuration.deviceInfo ?? DeviceInfoDetector.detect(),
                automaticFlush: true,
                persistDelay: 0.25
            )
        }
    }

    struct BatchRow {
        let index: Int
        let ok: Bool
        let error: String?
    }

    let configuration: LowcoEngage.Configuration
    let queue = DispatchQueue(label: "ai.lowco.engage.client")
    let batchURL: URL
    let headers: [String: String]
    let batchSize: Int
    let maxQueueSize: Int

    private let env: Environment
    private let store: EventStore
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "ai.lowco.engage", category: "LowcoEngage")

    // State: touched only on `queue`.
    private var events: [QueuedEvent] = []
    private var _userId: String?
    private var _deviceId: String = ""
    private var _sessionId: String = ""
    private var lastEventTime: Int64 = 0
    private var _deviceInfo: DeviceInfo?
    private var _location: LocationInfo?
    private var inFlight = false
    private var forceNext = false
    private var waiters: [() -> Void] = []
    private var _retryAttempt = 0
    private var _nextAttemptAt: Date?
    private var retryScheduled = false
    private var dirty = false
    private var saveScheduled = false
    private var isShutdown = false
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []

    init(configuration: LowcoEngage.Configuration, environment: Environment) {
        self.configuration = configuration
        env = environment
        defaults = configuration.userDefaults
        headers = Self.headers(for: configuration)
        batchURL = Self.batchURL(base: configuration.baseURL)
        batchSize = min(max(1, configuration.flushAt), EngageConstants.maxBatchSize)
        maxQueueSize = max(1, configuration.maxQueueSize)
        store = EventStore(directory: configuration.storageDirectory ?? EventStore.defaultDirectory(),
                           orgId: configuration.orgId.trimmingCharacters(in: .whitespacesAndNewlines),
                           appId: configuration.appId?.trimmingCharacters(in: .whitespacesAndNewlines))
        _deviceInfo = environment.deviceInfo

        do {
            events = try store.load()
        } catch {
            report(EngageError(.storage, message: "couldn't read the queued events: \(error)", underlying: error))
        }
        if events.count > maxQueueSize {
            events.removeFirst(events.count - maxQueueSize)
        }

        if let stored = defaults.string(forKey: EngageConstants.deviceIdKey), !stored.isEmpty {
            _deviceId = stored
        } else {
            _deviceId = Self.newId()
            defaults.set(_deviceId, forKey: EngageConstants.deviceIdKey)
        }
        if let stored = defaults.string(forKey: EngageConstants.userIdKey), !stored.isEmpty {
            _userId = stored
        }
        initializeSession(nowMs: epochMillis(environment.now()))

        if environment.automaticFlush {
            startTimer()
            observeLifecycle()
        }
    }

    deinit {
        timer?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        if dirty && !isShutdown {
            try? store.save(events)
        }
        if env.ownsSession {
            env.session.finishTasksAndInvalidate()
        }
    }

    // MARK: - Public surface (any thread)

    func now() -> Date {
        env.now()
    }

    /// Queues an event. `identify` remembers that user id first.
    func enqueue(_ name: String, data: [String: JSONValue], at time: Date, identify: String? = nil) {
        queue.async { [self] in
            enqueueLocked(name, data: data, at: time, identify: identify)
        }
    }

    func reset(newDeviceId: Bool, at time: Date) {
        queue.async { [self] in
            guard !isShutdown else { return }
            _userId = nil
            defaults.removeObject(forKey: EngageConstants.userIdKey)
            if newDeviceId {
                _deviceId = Self.newId()
                defaults.set(_deviceId, forKey: EngageConstants.deviceIdKey)
            }
            startNewSession(epochMillis(time))
        }
    }

    /// Sends everything queued, batch by batch. `force` ignores the retry
    /// backoff for the first attempt. `completion` runs on the main queue
    /// once the queue is empty or a batch failed.
    func flush(force: Bool = true, completion: (() -> Void)? = nil) {
        queue.async { [self] in
            requestFlushLocked(force: force, completion: completion)
        }
    }

    func setLocation(_ location: LocationInfo?) {
        queue.async { [self] in _location = location }
    }

    func setDeviceInfo(_ deviceInfo: DeviceInfo) {
        queue.async { [self] in _deviceInfo = deviceInfo }
    }

    var userId: String? { queue.sync { _userId } }
    var deviceId: String { queue.sync { _deviceId } }
    var sessionId: String { queue.sync { _sessionId } }
    var deviceInfo: DeviceInfo? { queue.sync { _deviceInfo } }
    var queuedEventCount: Int { queue.sync { events.count } }
    var queuedEvents: [QueuedEvent] { queue.sync { events } }
    var retryAttempt: Int { queue.sync { _retryAttempt } }
    var nextAttemptAt: Date? { queue.sync { _nextAttemptAt } }

    /// Runs `body` on the client's queue (tests use it to queue events
    /// without a request completing in between).
    func sync<T>(_ body: () throws -> T) rethrows -> T {
        try queue.sync(execute: body)
    }

    /// Saves the queue, stops the timer and drops later calls. Never call it
    /// on `queue`.
    func shutdown() {
        queue.sync {
            saveNowLocked()
            isShutdown = true
            timer?.cancel()
            timer = nil
            finishLocked()
        }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }

    // MARK: - Queue (on `queue`)

    func enqueueLocked(_ name: String, data: [String: JSONValue], at time: Date, identify: String? = nil) {
        guard !isShutdown else { return }
        if let identify {
            _userId = identify
            defaults.set(identify, forKey: EngageConstants.userIdKey)
        }
        let ms = epochMillis(time)
        ensureActiveSession(ms)
        var eventData: [String: JSONValue] = [:]
        if let version = configuration.appVersion, !version.isEmpty {
            // The service reads an event's app version from event_data.app_version.
            eventData["app_version"] = .string(version)
        }
        eventData.merge(data) { _, new in new }
        let body: [String: JSONValue] = [
            "id": .string(""),
            "event_name": .string(name),
            "event_data": .object(eventData),
            "user_id": _userId.map(JSONValue.string) ?? .null,
            "device_id": .string(_deviceId),
            "session_id": .string(_sessionId),
            "device_info": _deviceInfo?.jsonValue ?? .null,
            "location": _location?.jsonValue ?? .null,
            "event_time": .string(isoTimestamp(millis: ms)),
        ]
        events.append(QueuedEvent(localId: UUID().uuidString, body: .object(body)))
        if events.count > maxQueueSize {
            events.removeFirst(events.count - maxQueueSize)
        }
        scheduleSaveLocked()
        if events.count >= batchSize {
            requestFlushLocked(force: false, completion: nil)
        }
    }

    func requestFlushLocked(force: Bool, completion: (() -> Void)?) {
        if let completion {
            waiters.append(completion)
        }
        if force {
            forceNext = true
        }
        guard !inFlight else { return }
        sendNextLocked()
    }

    private func sendNextLocked() {
        guard !isShutdown, !events.isEmpty else {
            finishLocked()
            return
        }
        if !forceNext, let next = _nextAttemptAt, env.now() < next {
            finishLocked()
            return
        }
        forceNext = false
        let batch = Array(events.prefix(batchSize))
        let body: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            body = try encoder.encode(["events": batch.map(\.body)])
        } catch {
            report(EngageError(.encoding, message: "couldn't encode a batch: \(error)", underlying: error))
            removeLocked(Set(batch.map(\.localId)))
            sendNextLocked()
            return
        }
        var request = URLRequest(url: batchURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body
        inFlight = true
        env.session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.queue.async {
                self.handleLocked(batch: batch, data: data, response: response, error: error)
            }
        }.resume()
    }

    private func handleLocked(batch: [QueuedEvent], data: Data?, response: URLResponse?, error: Error?) {
        inFlight = false
        guard !isShutdown else {
            finishLocked()
            return
        }
        let ids = Set(batch.map(\.localId))
        if let error {
            report(EngageError(.network, message: error.localizedDescription, underlying: error))
            registerFailureLocked(retryAfter: nil)
            finishLocked()
            return
        }
        guard let http = response as? HTTPURLResponse else {
            report(EngageError(.network, message: "no HTTP response"))
            registerFailureLocked(retryAfter: nil)
            finishLocked()
            return
        }
        let status = http.statusCode
        switch status {
        case 200..<300:
            var keep = Set<String>()
            var rejected: [String] = []
            for row in Self.rows(from: data) where !row.ok && row.index >= 0 && row.index < batch.count {
                let event = batch[row.index]
                if (row.error ?? "").contains(EngageConstants.transientRowError) {
                    keep.insert(event.localId)
                } else {
                    rejected.append("\(event.eventName): \(row.error ?? "rejected")")
                }
            }
            removeLocked(ids.subtracting(keep))
            if !rejected.isEmpty {
                report(EngageError(.rejectedEvents, statusCode: status,
                                   message: "\(rejected.count) event(s) rejected: \(rejected.joined(separator: "; "))"))
            }
            if !keep.isEmpty {
                registerFailureLocked(retryAfter: nil)
                finishLocked()
                return
            }
            _retryAttempt = 0
            _nextAttemptAt = nil
            sendNextLocked()
        case 408, 429, 500...599:
            report(EngageError(.http, statusCode: status, message: Self.message(from: data, status: status)))
            registerFailureLocked(retryAfter: Self.retryAfter(http))
            finishLocked()
        default:
            // Any other 4xx will not get better by sending it again.
            report(EngageError(.http, statusCode: status,
                               message: "dropped \(batch.count) event(s): \(Self.message(from: data, status: status))"))
            removeLocked(ids)
            finishLocked()
        }
    }

    private func removeLocked(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        events.removeAll { ids.contains($0.localId) }
        scheduleSaveLocked()
    }

    private func registerFailureLocked(retryAfter: TimeInterval?) {
        _retryAttempt += 1
        let exponent = Double(min(_retryAttempt - 1, 16))
        var delay = min(EngageConstants.maxBackoff, EngageConstants.initialBackoff * pow(2, exponent)) * env.jitter()
        if let retryAfter {
            delay = max(delay, min(retryAfter, 3600))
        }
        _nextAttemptAt = env.now().addingTimeInterval(delay)
        guard env.automaticFlush, !retryScheduled else { return }
        retryScheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.retryScheduled = false
            self.requestFlushLocked(force: false, completion: nil)
        }
    }

    private func finishLocked() {
        forceNext = false
        guard !waiters.isEmpty else { return }
        let done = waiters
        waiters = []
        DispatchQueue.main.async {
            done.forEach { $0() }
        }
    }

    // MARK: - Sessions (same rules as the Flutter and Android SDKs)

    private func initializeSession(nowMs: Int64) {
        if let stored = defaults.string(forKey: EngageConstants.sessionIdKey), !stored.isEmpty,
           let raw = defaults.string(forKey: EngageConstants.sessionLastEventKey),
           let last = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           nowMs - Int64(last) <= EngageConstants.sessionTimeoutMs {
            _sessionId = stored
            lastEventTime = Int64(last)
            return
        }
        startNewSession(nowMs)
    }

    private func startNewSession(_ timestamp: Int64) {
        _sessionId = Self.newId()
        lastEventTime = timestamp
        persistSession()
    }

    private func ensureActiveSession(_ timestamp: Int64) {
        if _sessionId.isEmpty || timestamp - lastEventTime > EngageConstants.sessionTimeoutMs {
            startNewSession(timestamp)
            return
        }
        lastEventTime = timestamp
        persistSession()
    }

    private func persistSession() {
        defaults.set(_sessionId, forKey: EngageConstants.sessionIdKey)
        defaults.set(String(lastEventTime), forKey: EngageConstants.sessionLastEventKey)
    }

    // MARK: - Disk

    private func scheduleSaveLocked() {
        dirty = true
        if env.persistDelay <= 0 {
            saveNowLocked()
            return
        }
        guard !saveScheduled else { return }
        saveScheduled = true
        queue.asyncAfter(deadline: .now() + env.persistDelay) { [weak self] in
            guard let self else { return }
            self.saveScheduled = false
            self.saveNowLocked()
        }
    }

    private func saveNowLocked() {
        guard dirty, !isShutdown else { return }
        dirty = false
        do {
            try store.save(events)
        } catch {
            report(EngageError(.storage, message: "couldn't save the queue: \(error)", underlying: error))
        }
    }

    // MARK: - Automatic flushes

    private func startTimer() {
        let interval = max(1, configuration.flushInterval)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.requestFlushLocked(force: false, completion: nil)
        }
        timer.resume()
        self.timer = timer
    }

    private func observeLifecycle() {
        guard let name = Self.backgroundNotification else { return }
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            self?.appWillLeaveForeground()
        }
        observers.append(token)
    }

    /// Saves the queue and sends it while the app still runs.
    func appWillLeaveForeground() {
        queue.async { [self] in
            saveNowLocked()
            requestFlushLocked(force: true, completion: nil)
        }
    }

    static var backgroundNotification: Notification.Name? {
        #if canImport(UIKit) && !os(watchOS)
        return UIApplication.didEnterBackgroundNotification
        #elseif canImport(AppKit)
        return NSApplication.willResignActiveNotification
        #else
        return nil
        #endif
    }

    // MARK: - Helpers

    private func report(_ error: EngageError) {
        logger.debug("\(error.description, privacy: .public)")
        configuration.onError?(error)
    }

    static func newId() -> String {
        UUID().uuidString.lowercased()
    }

    /// The credential (`X-Api-Key` for an `lc_` API key, otherwise
    /// `Authorization: Bearer`), `X-Org-Id`, and `X-Engage-App-Id` when an
    /// app is set — the Flutter SDK's `trackHeaders`.
    static func headers(for configuration: LowcoEngage.Configuration) -> [String: String] {
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var headers = [
            "Content-Type": "application/json",
            LowcoEngage.headerOrgId: configuration.orgId.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        if LowcoEngage.isApiKey(apiKey) {
            headers[LowcoEngage.headerApiKey] = apiKey
        } else {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        if let appId = configuration.appId?.trimmingCharacters(in: .whitespacesAndNewlines), !appId.isEmpty {
            headers[LowcoEngage.headerEngageAppId] = appId
        }
        return headers
    }

    static func batchURL(base: URL) -> URL {
        var root = base.absoluteString
        while root.hasSuffix("/") {
            root.removeLast()
        }
        return URL(string: root + EngageConstants.batchPath) ?? base.appendingPathComponent("v1/engage/track/batch")
    }

    /// `data.results` of a /track/batch answer; empty when there is none.
    static func rows(from data: Data?) -> [BatchRow] {
        guard let data,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = object["data"] as? [String: Any],
              let results = payload["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { row in
            guard let index = (row["index"] as? NSNumber)?.intValue else { return nil }
            return BatchRow(index: index, ok: (row["ok"] as? Bool) ?? false, error: row["error"] as? String)
        }
    }

    static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Double(raw.trimmingCharacters(in: .whitespaces)), seconds > 0 else { return nil }
        return seconds
    }

    /// The service's error message ({"error": {"message", "details"}}),
    /// else the start of the body.
    static func message(from data: Data?, status: Int) -> String {
        guard let data, !data.isEmpty else { return "status \(status)" }
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let error = object["error"] as? [String: Any] {
                if let details = error["details"] as? String, !details.isEmpty { return details }
                if let message = error["message"] as? String, !message.isEmpty { return message }
            }
            if let message = object["message"] as? String, !message.isEmpty { return message }
        }
        let text = String(decoding: data.prefix(256), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "status \(status)" : text
    }
}
