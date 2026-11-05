import Foundation

/// One queued event: the wire JSON and a local id that tells it apart from
/// later events while its batch is in flight.
struct QueuedEvent: Codable, Equatable {
    let localId: String
    let body: JSONValue

    var eventName: String {
        body["event_name"]?.stringValue ?? ""
    }
}

/// The on-disk copy of the queue: one JSON file per org and app, so events
/// never leave with another org's headers after a reconfigure.
final class EventStore {
    private struct File: Codable {
        var version: Int
        var events: [QueuedEvent]
    }

    let fileURL: URL?

    init(directory: URL?, orgId: String, appId: String?) {
        let name = "queue-\(Self.safeName(orgId))-\(Self.safeName(appId ?? "default")).json"
        fileURL = directory?.appendingPathComponent(name, isDirectory: false)
    }

    /// `Application Support/<bundle id>/lowco-engage`.
    static func defaultDirectory(fileManager: FileManager = .default,
                                 bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> URL? {
        guard var dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            dir.appendPathComponent(bundleIdentifier, isDirectory: true)
        }
        return dir.appendingPathComponent("lowco-engage", isDirectory: true)
    }

    func load() throws -> [QueuedEvent] {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [] }
        return try JSONDecoder().decode(File.self, from: data).events
    }

    func save(_ events: [QueuedEvent]) throws {
        guard let url = fileURL else { return }
        var dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Queued analytics are not worth an iCloud backup.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(File(version: 1, events: events))
        try data.write(to: url, options: [.atomic])
    }

    static func safeName(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> Character in
            let ok = scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
            return ok ? Character(scalar) : "_"
        }
        let name = String(scalars.prefix(64))
        return name.isEmpty ? "_" : name
    }
}
