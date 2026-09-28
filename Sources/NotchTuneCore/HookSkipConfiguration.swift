import Foundation

/// Centralizes the per-process hook skip environment contract.
/// The environment-variable contract for "skip hooks for this one child process".
public enum HookSkipConfiguration {
    /// Preferred NotchTune environment key for disabling hooks in this process.
    /// The switch NotchTune recommends for skipping hooks in the current process.
    public static let notchTuneSkipKey = "NOTCHTUNE_SKIP_HOOKS"
    /// Compatibility alias honored from pre-rename Open Island installs.
    /// Legacy switch used by pre-rename Open Island installs.
    public static let legacyOpenIslandSkipKey = "OPEN_ISLAND_SKIP_HOOKS"
    /// Compatibility alias used by existing Vibe Island integrations.
    /// Legacy switch used by existing Vibe Island integrations.
    public static let legacyVibeIslandSkipKey = "VIBE_ISLAND_SKIP"

    /// Returns true when the provided environment explicitly requests hook no-op mode.
    /// True when the given environment explicitly asks to skip hooks.
    public static func shouldSkipHooks(environment: [String: String]) -> Bool {
        isTruthy(environment[notchTuneSkipKey])
            || isTruthy(environment[legacyOpenIslandSkipKey])
            || isTruthy(environment[legacyVibeIslandSkipKey])
    }

    /// Interprets common shell-friendly truthy values and treats everything else as false.
    /// Accepts the usual shell-friendly truthy values; anything else is false.
    private static func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}
