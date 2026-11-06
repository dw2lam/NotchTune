import Foundation

/// When each agent's hooks last reached the app. The difference between
/// "installed" and "working" is whether this ever moves.
///
/// Written from the bridge queue on every hook, so a save happens at most once
/// per `saveInterval`; losing a few seconds on quit doesn't change the answer.
public final class HookActivityStore: @unchecked Sendable {
    private let url: URL
    private let saveInterval: TimeInterval
    private let lock = NSLock()
    private var lastEvents: [String: Date]
    private var lastSavedAt: Date?

    public init(url: URL = HookActivityStore.defaultURL, saveInterval: TimeInterval = 10) {
        self.url = url
        self.saveInterval = saveInterval
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        lastEvents = (try? Data(contentsOf: url))
            .flatMap { try? decoder.decode([String: Date].self, from: $0) } ?? [:]
    }

    public static var defaultURL: URL {
        BridgeSocketLocation.defaultURL
            .deletingLastPathComponent()
            .appendingPathComponent("hook-activity.json")
    }

    public func record(_ agent: AgentIdentifier, at date: Date = .now) {
        let snapshot: [String: Date]? = lock.withLock {
            lastEvents[agent.rawValue] = date
            if let lastSavedAt, date.timeIntervalSince(lastSavedAt) < saveInterval {
                return nil
            }
            lastSavedAt = date
            return lastEvents
        }

        if let snapshot {
            save(snapshot)
        }
    }

    public func lastEvent(for agent: AgentIdentifier) -> Date? {
        lock.withLock { lastEvents[agent.rawValue] }
    }

    private func save(_ snapshot: [String: Date]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
