import Foundation

/// Settings that stop Claude Code running our hooks however well they're
/// installed. Project settings can turn hooks back on or off per repo, so
/// this reports what's known for the user, not for every project.
public struct ClaudeHookPolicy: Equatable, Sendable {
    public var disableAllHooks: Bool
    public var allowManagedHooksOnly: Bool

    public init(disableAllHooks: Bool = false, allowManagedHooksOnly: Bool = false) {
        self.disableAllHooks = disableAllHooks
        self.allowManagedHooksOnly = allowManagedHooksOnly
    }

    public static let defaultManagedSettingsURL = URL(
        fileURLWithPath: "/Library/Application Support/ClaudeCode/managed-settings.json"
    )

    public static func read(
        claudeDirectory: URL = ClaudeConfigDirectory.resolved(),
        managedSettingsURL: URL = ClaudeHookPolicy.defaultManagedSettingsURL
    ) -> ClaudeHookPolicy {
        let user = settings(at: claudeDirectory.appendingPathComponent("settings.json"))
        let managed = settings(at: managedSettingsURL)

        return ClaudeHookPolicy(
            disableAllHooks: (managed["disableAllHooks"] ?? user["disableAllHooks"]) as? Bool ?? false,
            allowManagedHooksOnly: managed["allowManagedHooksOnly"] as? Bool ?? false
        )
    }

    private static func settings(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        return root
    }
}
