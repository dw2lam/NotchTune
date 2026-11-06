import Darwin
import Foundation

/// Counts hook events the CLI read but couldn't decode.
///
/// A dropped event reaches nobody by design (hooks fail open, stderr goes to
/// the agent), so the CLI leaves a note here and the doctor reads it. Only the
/// event name and the field path are kept: never the payload, which can hold
/// prompts and file contents.
public struct HookDropLog: Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var count: Int
        public var lastDroppedAt: Date
        public var lastEvent: String?
        public var lastField: String?

        public init(count: Int, lastDroppedAt: Date, lastEvent: String?, lastField: String?) {
            self.count = count
            self.lastDroppedAt = lastDroppedAt
            self.lastEvent = lastEvent
            self.lastField = lastField
        }
    }

    public let url: URL

    public init(url: URL = HookDropLog.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        BridgeSocketLocation.defaultURL
            .deletingLastPathComponent()
            .appendingPathComponent("hook-drops.json")
    }

    /// Entries keyed by the `--source` the CLI ran with.
    public func read() -> [String: Entry] {
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }

        return Self.decode(data)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Never blocks the hook: if another hook holds the lock, this drop goes
    /// uncounted rather than stalling the agent.
    public func record(source: String, event: String?, field: String?, at date: Date = .now) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let descriptor = open(url.path, O_RDWR | O_CREAT, 0o600)
        guard descriptor >= 0 else {
            return
        }
        defer { close(descriptor) }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            return
        }
        defer { flock(descriptor, LOCK_UN) }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var entries = Self.decode((try? handle.readToEnd()) ?? Data())
        var entry = entries[source] ?? Entry(count: 0, lastDroppedAt: date, lastEvent: nil, lastField: nil)
        entry.count += 1
        entry.lastDroppedAt = date
        entry.lastEvent = event
        entry.lastField = field
        entries[source] = entry

        guard let data = try? Self.encoder.encode(entries) else {
            return
        }

        try? handle.truncate(atOffset: 0)
        try? handle.write(contentsOf: data)
    }

    /// The JSON key path a decoding error points at, without its value.
    public static func fieldPath(of error: any Error) -> String? {
        let context: DecodingError.Context?
        switch error as? DecodingError {
        case let .keyNotFound(key, context):
            return (context.codingPath + [key]).map(\.stringValue).joined(separator: ".")
        case let .typeMismatch(_, value), let .valueNotFound(_, value), let .dataCorrupted(value):
            context = value
        default:
            context = nil
        }

        return context.map { $0.codingPath.map(\.stringValue).joined(separator: ".") }
    }

    /// Best-effort event name from a payload that didn't decode.
    public static func eventName(in payload: Data) -> String? {
        let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        return root?["hook_event_name"] as? String
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static func decode(_ data: Data) -> [String: Entry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Entry].self, from: data)) ?? [:]
    }
}
