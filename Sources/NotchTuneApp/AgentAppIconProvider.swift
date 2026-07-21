import AppKit

/// Resolves the REAL app icon for a usage provider — pulled straight from the
/// installed application bundle via NSWorkspace, never a drawn stand-in.
/// Providers whose agent is CLI-only (no app installed) return nil and the
/// caller falls back to the full text name.
@MainActor
enum AgentAppIconProvider {
    /// Candidate bundle identifiers per provider title, first installed wins.
    private static let bundleIdentifiers: [String: [String]] = [
        "Claude": ["com.anthropic.claudefordesktop"],
        "Codex": ["com.openai.codex"],
        "Gemini": ["com.google.gemini"],
        "Cursor": ["com.todesktop.230313mzl4w4u92"],
        "Antigravity": ["com.google.antigravity", "dev.antigravity.app"],
    ]

    private static var cache: [String: NSImage?] = [:]

    static func icon(forProviderTitle title: String) -> NSImage? {
        if let cached = cache[title] {
            return cached
        }
        let resolved = resolve(title: title)
        cache[title] = resolved
        return resolved
    }

    private static func resolve(title: String) -> NSImage? {
        guard let candidates = bundleIdentifiers[title] else { return nil }
        for bundleID in candidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 28, height: 28)
                return icon
            }
        }
        return nil
    }
}
