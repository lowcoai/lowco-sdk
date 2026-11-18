import Foundation

/// A JSON value. Event properties are converted to it on the calling thread,
/// so a queued event never holds on to (or races with) the caller's objects.
enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Converts properties to JSON values (see `from(_:)`).
    static func object(from properties: [String: Any]) -> [String: JSONValue] {
        properties.mapValues { from($0) }
    }

    /// Converts any value to JSON: strings, numbers and booleans as they are;
    /// `Date` as an ISO-8601 UTC string with milliseconds; `URL` and `UUID` as
    /// strings; `Data` as base64; arrays and dictionaries recursively; `nil`,
    /// `NSNull` and non-finite numbers (NaN, infinity) as `null`; anything
    /// else as its description.
    static func from(_ value: Any?) -> JSONValue {
        guard let value = unwrap(value) else { return .null }
        switch value {
        case is NSNull:
            return .null
        case let v as JSONValue:
            return v
        case let v as String:
            return .string(v)
        case let v as Substring:
            return .string(String(v))
        case let v as Character:
            return .string(String(v))
        case let v as NSNumber:
            return number(v)
        case let v as Date:
            return .string(isoTimestamp(v))
        case let v as URL:
            return .string(v.absoluteString)
        case let v as UUID:
            return .string(v.uuidString)
        case let v as Data:
            return .string(v.base64EncodedString())
        case let v as [String: Any]:
            return .object(v.mapValues { from($0) })
        case let v as [AnyHashable: Any]:
            var out: [String: JSONValue] = [:]
            for (key, element) in v {
                out[String(describing: key.base)] = from(element)
            }
            return .object(out)
        case let v as [Any]:
            return .array(v.map { from($0) })
        default:
            return .string(String(describing: value))
        }
    }

    private static func number(_ n: NSNumber) -> JSONValue {
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
            return .bool(n.boolValue)
        }
        if CFNumberIsFloatType(n) {
            let d = n.doubleValue
            return d.isFinite ? .double(d) : .null
        }
        // An unsigned value above Int64.max can only travel as a double.
        if String(cString: n.objCType) == "Q", n.uint64Value > UInt64(Int64.max) {
            return .double(n.doubleValue)
        }
        return .int(n.int64Value)
    }

    /// `Optional<Optional<…>>` boxed in `Any` → the wrapped value or nil.
    private static func unwrap(_ value: Any?) -> Any? {
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        guard let child = mirror.children.first else { return nil }
        return unwrap(child.value)
    }

    /// The value as a Foundation object (`JSONSerialization` style).
    var foundationValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map(\.foundationValue)
        case .object(let o): return o.mapValues(\.foundationValue)
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
}

extension JSONValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int64.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d.isFinite ? d : 0)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

private let timestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return f
}()

/// Epoch milliseconds of `date`, truncated (like Dart's
/// `millisecondsSinceEpoch`). The microsecond nudge absorbs floating-point
/// error such as 1790000000.789 being stored as …788999.
func epochMillis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000 + 0.001).rounded(.down))
}

/// ISO-8601 UTC with milliseconds and a `Z` suffix, like JavaScript's
/// `Date.toISOString` and the Flutter SDK's `event_time`.
func isoTimestamp(_ date: Date) -> String {
    isoTimestamp(millis: epochMillis(date))
}

func isoTimestamp(millis: Int64) -> String {
    var seconds = millis / 1000
    var ms = millis % 1000
    if ms < 0 {
        ms += 1000
        seconds -= 1
    }
    let whole = Date(timeIntervalSince1970: TimeInterval(seconds))
    return timestampFormatter.string(from: whole) + String(format: ".%03dZ", Int(ms))
}
