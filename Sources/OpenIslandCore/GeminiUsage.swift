import Foundation

public struct GeminiUsageWindow: Equatable, Codable, Sendable {
    public var label: String
    public var usedPercentage: Double
    public var resetsAt: Date?

    public init(label: String, usedPercentage: Double, resetsAt: Date? = nil) {
        self.label = label
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    public var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }
}

public struct GeminiUsageSnapshot: Equatable, Codable, Sendable {
    public var windows: [GeminiUsageWindow]
    public var cachedAt: Date?

    public init(windows: [GeminiUsageWindow], cachedAt: Date? = nil) {
        self.windows = windows
        self.cachedAt = cachedAt
    }

    public init(from decoder: any Decoder) throws {
        // 1. Try decoding as the standard struct {"windows": [...]}
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        if let windows = try? container?.decode([GeminiUsageWindow].self, forKey: .windows) {
            self.windows = windows
            self.cachedAt = try? container?.decodeIfPresent(Date.self, forKey: .cachedAt)
            return
        }

        // 2. Try decoding as a flat array [...]
        if let windows = try? [GeminiUsageWindow](from: decoder) {
            self.windows = windows
            self.cachedAt = nil
            return
        }

        // 3. Try decoding as a dictionary where keys are labels {"RPM": {...}, "TPM": {...}}
        // This matches Claude Code's rate_limits format.
        if let dict = try? [String: PartialUsageWindow](from: decoder) {
            self.windows = dict.map { label, partial in
                GeminiUsageWindow(
                    label: label,
                    usedPercentage: partial.usedPercentage,
                    resetsAt: partial.resetsAt
                )
            }.sorted { $0.label < $1.label }
            self.cachedAt = nil
            return
        }

        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Unable to decode GeminiUsageSnapshot from provided format."
        ))
    }

    private enum CodingKeys: String, CodingKey {
        case windows
        case cachedAt
    }

    private struct PartialUsageWindow: Codable {
        var usedPercentage: Double
        var resetsAt: Date?

        private enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }
    }

    public var isEmpty: Bool {
        windows.isEmpty
    }
}

public enum GeminiUsageLoader {
    public static let defaultCacheURL = URL(fileURLWithPath: "/tmp/open-island-gemini-usage.json")

    public static func load() throws -> GeminiUsageSnapshot? {
        try load(from: defaultCacheURL)
    }

    public static func load(from url: URL) throws -> GeminiUsageSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let snapshot = try decoder.decode(GeminiUsageSnapshot.self, from: data)
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        var finalSnapshot = snapshot
        finalSnapshot.cachedAt = attributes?[.modificationDate] as? Date
        
        return finalSnapshot.isEmpty ? nil : finalSnapshot
    }
}
