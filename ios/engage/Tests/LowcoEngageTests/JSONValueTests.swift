import XCTest
@testable import LowcoEngage

final class JSONValueTests: XCTestCase {
    func testConvertsCommonValues() {
        let url = URL(string: "https://shop.example/p?id=1")!
        let uuid = UUID()
        let nested: [String: Any] = ["list": [1, "two", false], "map": ["k": 2.5]]
        let optional: String? = nil
        let value = JSONValue.object(from: [
            "string": "a",
            "int": 42,
            "negative": -7,
            "double": 1.25,
            "bool": true,
            "nan": Double.nan,
            "infinity": Double.infinity,
            "date": Date(timeIntervalSince1970: 1_790_000_000.789),
            "url": url,
            "uuid": uuid,
            "nested": nested,
            "null": NSNull(),
            "optional": optional as Any,
            "other": CGPoint(x: 1, y: 2),
        ])
        XCTAssertEqual(value["string"], .string("a"))
        XCTAssertEqual(value["int"], .int(42))
        XCTAssertEqual(value["negative"], .int(-7))
        XCTAssertEqual(value["double"], .double(1.25))
        XCTAssertEqual(value["bool"], .bool(true))
        XCTAssertEqual(value["nan"], .null)
        XCTAssertEqual(value["infinity"], .null)
        XCTAssertEqual(value["date"], .string("2026-09-21T14:13:20.789Z"))
        XCTAssertEqual(value["url"], .string("https://shop.example/p?id=1"))
        XCTAssertEqual(value["uuid"], .string(uuid.uuidString))
        XCTAssertEqual(value["nested"], .object(["list": .array([.int(1), .string("two"), .bool(false)]),
                                                 "map": .object(["k": .double(2.5)])]))
        XCTAssertEqual(value["null"], .null)
        XCTAssertEqual(value["optional"], .null)
        XCTAssertEqual(value["other"]?.stringValue?.isEmpty, false)
    }

    func testRoundTripsThroughJSON() throws {
        let value = JSONValue.object(["a": .array([.int(1), .double(2.5), .bool(true), .null, .string("x")])])
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data), value)
    }

    func testTimestampsAreUTCWithMilliseconds() {
        XCTAssertEqual(isoTimestamp(Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(isoTimestamp(Date(timeIntervalSince1970: 1_790_000_000.789)), "2026-09-21T14:13:20.789Z")
        XCTAssertEqual(isoTimestamp(Date(timeIntervalSince1970: 1_790_000_000.7899)), "2026-09-21T14:13:20.789Z")
    }

    func testDetectedDeviceInfo() {
        let info = DeviceInfoDetector.detect()
        XCTAssertEqual(info.device?.vendor, "Apple")
        XCTAssertEqual(info.engine?.name, "LowcoEngage")
        XCTAssertNotNil(info.os?.version)
        #if os(macOS)
        XCTAssertEqual(info.os?.name, "Mac OS")
        XCTAssertEqual(info.device?.type, "desktop")
        XCTAssertNotNil(info.device?.model)
        #endif
        XCTAssertEqual(info.ua, "LowcoEngage (\(info.os!.name!) \(info.os!.version!))")
    }

    func testApiKeyDetection() {
        XCTAssertTrue(LowcoEngage.isApiKey("lc_abc"))
        XCTAssertTrue(LowcoEngage.isApiKey("  lc_abc"))
        XCTAssertFalse(LowcoEngage.isApiKey("LC_abc"))
        XCTAssertFalse(LowcoEngage.isApiKey("eyJhbGciOi.token"))
        XCTAssertFalse(LowcoEngage.isApiKey(""))
    }

    func testBatchRowsParsing() {
        let body = #"{"status":1,"data":{"accepted":1,"rejected":1,"results":[{"index":0,"eventName":"a","ok":true},{"index":1,"eventName":"","ok":false,"error":"event_name is required"}]}}"#
        let rows = EngageClient.rows(from: Data(body.utf8))
        XCTAssertEqual(rows.map(\.index), [0, 1])
        XCTAssertEqual(rows.map(\.ok), [true, false])
        XCTAssertEqual(rows[1].error, "event_name is required")
        XCTAssertTrue(EngageClient.rows(from: Data("not json".utf8)).isEmpty)
    }
}
