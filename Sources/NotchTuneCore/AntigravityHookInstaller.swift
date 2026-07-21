import Foundation

public struct AntigravityHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-antigravity-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct AntigravityHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool

    public init(contents: Data?, changed: Bool, managedHooksPresent: Bool) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
    }
}

public enum AntigravityHookInstallerError: Error, LocalizedError {
    case invalidHooksJSON

    public var errorDescription: String? {
        switch self {
        case .invalidHooksJSON:
            "The existing Antigravity hooks.json is not valid JSON."
        }
    }
}

/// Manages NotchTune's entry inside Antigravity's `~/.gemini/config/hooks.json`.
///
/// Antigravity (the `agy` CLI) loads a `hooks.json` whose top level is keyed by
/// hook-group *name*; each group maps native event names to handler lists. We
/// own a single group named `open-island`, so installing/removing is just
/// adding/dropping that one key — other groups are left untouched.
///
/// Antigravity in practice only fires `PreToolUse` / `PostToolUse` (per tool
/// call) — it sends no turn- or session-end event — so we map both of those to
/// our `BeforeAgent` ("working") event and let the app settle the session to
/// idle on a debounce. `Stop` is wired to `SessionEnd` as a clean end in case a
/// future agy build emits it.
public enum AntigravityHookInstaller {
    /// Top-level hook-group name we own in hooks.json.
    public static let groupName = "open-island"

    /// Native Antigravity event → the `--event` we forward to NotchTuneHooks.
    private static let eventSpecs: [(native: String, mapped: String)] = [
        ("PreToolUse", "BeforeAgent"),
        ("PostToolUse", "BeforeAgent"),
        ("Stop", "SessionEnd"),
    ]

    public static func hookCommand(for binaryPath: String, mappedEvent: String) -> String {
        "\(shellQuote(binaryPath)) --source antigravity --event \(mappedEvent)"
    }

    /// Command without the per-event suffix — used by the manifest as a stable
    /// identifier for "these are our hooks".
    public static func baseHookCommand(for binaryPath: String) -> String {
        "\(shellQuote(binaryPath)) --source antigravity"
    }

    public static func installHooksJSON(
        existingData: Data?,
        binaryPath: String
    ) throws -> AntigravityHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)

        var group: [String: Any] = [:]
        for spec in eventSpecs {
            group[spec.native] = [managedGroup(
                hookCommand: hookCommand(for: binaryPath, mappedEvent: spec.mapped)
            )]
        }
        rootObject[groupName] = group

        let data = try serialize(rootObject)
        return AntigravityHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true
        )
    }

    public static func uninstallHooksJSON(
        existingData: Data?
    ) throws -> AntigravityHookFileMutation {
        guard let existingData else {
            return AntigravityHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
        }

        var rootObject = try loadRootObject(from: existingData)
        let present = rootObject[groupName] != nil
        rootObject.removeValue(forKey: groupName)

        let contents = rootObject.isEmpty ? nil : try serialize(rootObject)
        return AntigravityHookFileMutation(
            contents: contents,
            changed: present,
            managedHooksPresent: present
        )
    }

    /// Whether a hooks.json already contains our managed group.
    public static func managedHooksPresent(in data: Data?) -> Bool {
        guard let data,
              let root = try? loadRootObject(from: data),
              let group = root[groupName] as? [String: Any] else {
            return false
        }
        // Confirm at least one handler is actually ours, not a stale empty key.
        return group.values.contains { value in
            guard let groups = value as? [[String: Any]] else { return false }
            return groups.contains { isManagedGroup($0) }
        }
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = object as? [String: Any] else {
            throw AntigravityHookInstallerError.invalidHooksJSON
        }

        return rootObject
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func managedGroup(hookCommand: String) -> [String: Any] {
        [
            "matcher": "*",
            "hooks": [[
                "type": "command",
                "command": hookCommand,
                "name": "NotchTune",
            ]],
        ]
    }

    private static func isManagedGroup(_ group: [String: Any]) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return isNotchTuneAntigravityHookCommand(command)
        }
    }

    private static func isNotchTuneAntigravityHookCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        return (normalized.contains("notchtunehooks") || normalized.contains("vibeislandhooks"))
            && normalized.contains("antigravity")
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
