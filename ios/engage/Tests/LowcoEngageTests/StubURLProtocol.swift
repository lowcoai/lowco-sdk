import Foundation

/// Answers every request of a session it is registered on with a canned
/// reply and records what was sent. Requests' bodies reach a URLProtocol as
/// `httpBodyStream`, so they are read from there.
final class StubURLProtocol: URLProtocol {
    struct Captured {
        let request: URLRequest
        let body: Data

        var json: [String: Any] {
            ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]) ?? [:]
        }

        var events: [[String: Any]] {
            json["events"] as? [[String: Any]] ?? []
        }

        var eventNames: [String] {
            events.compactMap { $0["event_name"] as? String }
        }

        func header(_ name: String) -> String? {
            request.value(forHTTPHeaderField: name)
        }
    }

    enum Reply {
        case response(status: Int, body: Data, headers: [String: String])
        case failure(Error)
    }

    private static let lock = NSLock()
    private static var _handler: ((Captured) -> Reply)?
    private static var _captured: [Captured] = []

    /// Answers a request; nil accepts every event of every batch.
    static var handler: ((Captured) -> Reply)? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); _handler = newValue; lock.unlock() }
    }

    static var captured: [Captured] {
        lock.lock()
        defer { lock.unlock() }
        return _captured
    }

    static func reset() {
        lock.lock()
        _handler = nil
        _captured = []
        lock.unlock()
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    /// 200 with every event accepted.
    static func accepted(_ captured: Captured) -> Reply {
        let rows: [[String: Any]] = captured.events.enumerated().map { index, event in
            ["index": index, "eventName": event["event_name"] ?? "", "ok": true]
        }
        return json(200, ["status": 1, "data": ["accepted": rows.count, "rejected": 0, "results": rows]])
    }

    static func json(_ status: Int, _ object: Any, headers: [String: String] = [:]) -> Reply {
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        var all = headers
        all["Content-Type"] = "application/json"
        return .response(status: status, body: body, headers: all)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let captured = Captured(request: request, body: Self.readBody(of: request))
        Self.lock.lock()
        Self._captured.append(captured)
        let handler = Self._handler
        Self.lock.unlock()
        switch (handler ?? Self.accepted)(captured) {
        case let .response(status, body, headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// A clock tests move by hand.
final class TestClock {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

/// A thread-safe list.
final class Box<T> {
    private let lock = NSLock()
    private var items: [T] = []

    func append(_ item: T) {
        lock.lock()
        items.append(item)
        lock.unlock()
    }

    var all: [T] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}
