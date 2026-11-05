import Foundation

/// The `device_info` sent with every event, in the shape the browser SDK's
/// ua-parser result and the Flutter / Android SDKs send. The engage service
/// reads `os.name` ("iOS" → platform ios, "Mac OS" → desktop) and
/// `device.type` / `vendor` / `model`.
public struct DeviceInfo: Equatable {
    public struct OS: Equatable {
        public var name: String?
        public var version: String?

        public init(name: String? = nil, version: String? = nil) {
            self.name = name
            self.version = version
        }
    }

    public struct Device: Equatable {
        /// `mobile`, `tablet` or `desktop`.
        public var type: String?
        public var vendor: String?
        /// The hardware model identifier, e.g. `iPhone15,2` or `Mac14,2`.
        public var model: String?

        public init(type: String? = nil, vendor: String? = nil, model: String? = nil) {
            self.type = type
            self.vendor = vendor
            self.model = model
        }
    }

    public struct CPU: Equatable {
        public var architecture: String?

        public init(architecture: String? = nil) {
            self.architecture = architecture
        }
    }

    public struct Engine: Equatable {
        public var name: String?
        public var version: String?

        public init(name: String? = nil, version: String? = nil) {
            self.name = name
            self.version = version
        }
    }

    public var os: OS?
    public var device: Device?
    public var cpu: CPU?
    public var engine: Engine?
    /// A user-agent-like summary, e.g. `LowcoEngage (iOS 17.2)`.
    public var ua: String?

    public init(os: OS? = nil, device: Device? = nil, cpu: CPU? = nil, engine: Engine? = nil, ua: String? = nil) {
        self.os = os
        self.device = device
        self.cpu = cpu
        self.engine = engine
        self.ua = ua
    }

    var jsonValue: JSONValue {
        var out: [String: JSONValue] = [:]
        if let os {
            out["os"] = .object(compact(["name": os.name, "version": os.version]))
        }
        if let device {
            out["device"] = .object(compact(["type": device.type, "vendor": device.vendor, "model": device.model]))
        }
        if let cpu {
            out["cpu"] = .object(compact(["architecture": cpu.architecture]))
        }
        if let engine {
            out["engine"] = .object(compact(["name": engine.name, "version": engine.version]))
        }
        if let ua {
            out["ua"] = .string(ua)
        }
        return .object(out)
    }
}

/// The `location` sent with events. The SDK never reads the location itself:
/// pass coordinates you already have (`LowcoEngage.shared.setLocation`).
public struct LocationInfo: Equatable {
    public var latitude: Double?
    public var longitude: Double?
    public var accuracy: Double?
    public var altitude: Double?
    public var altitudeAccuracy: Double?
    public var heading: Double?
    public var speed: Double?

    public init(latitude: Double? = nil, longitude: Double? = nil, accuracy: Double? = nil, altitude: Double? = nil,
                altitudeAccuracy: Double? = nil, heading: Double? = nil, speed: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.altitude = altitude
        self.altitudeAccuracy = altitudeAccuracy
        self.heading = heading
        self.speed = speed
    }

    var jsonValue: JSONValue {
        var out: [String: JSONValue] = [:]
        let fields: [(String, Double?)] = [
            ("latitude", latitude), ("longitude", longitude), ("accuracy", accuracy), ("altitude", altitude),
            ("altitude_accuracy", altitudeAccuracy), ("heading", heading), ("speed", speed),
        ]
        for (key, value) in fields {
            if let value, value.isFinite { out[key] = .double(value) }
        }
        return .object(out)
    }
}

/// A delivery problem, passed to `Configuration.onError`. Tracking never
/// throws: events that can be retried stay queued, the rest are dropped and
/// reported here.
public struct EngageError: Error, CustomStringConvertible {
    public enum Kind: Equatable {
        /// No response (offline, timeout). The batch stays queued.
        case network
        /// A non-2xx answer. 408, 429 and 5xx keep the batch queued; any other
        /// status drops it.
        case http
        /// The service refused some events of a batch (no event name, or a
        /// strict event definition they break). Those events are dropped.
        case rejectedEvents
        /// The on-disk queue couldn't be read or written.
        case storage
        /// A batch couldn't be encoded. It is dropped.
        case encoding
    }

    public let kind: Kind
    /// The HTTP status for `.http` (and `.rejectedEvents`, 200).
    public let statusCode: Int?
    public let message: String
    public let underlying: Error?

    init(_ kind: Kind, statusCode: Int? = nil, message: String, underlying: Error? = nil) {
        self.kind = kind
        self.statusCode = statusCode
        self.message = message
        self.underlying = underlying
    }

    public var description: String {
        if let statusCode { return "LowcoEngage \(kind) (\(statusCode)): \(message)" }
        return "LowcoEngage \(kind): \(message)"
    }
}

private func compact(_ fields: [String: String?]) -> [String: JSONValue] {
    var out: [String: JSONValue] = [:]
    for (key, value) in fields {
        if let value { out[key] = .string(value) }
    }
    return out
}
