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

    /// Bundled brand logos for agents that run CLI-only (no installed app to
    /// pull an icon from). Rasterized from the marketing site's brand SVGs.
    private static let bundledLogoNames: [String: String] = [
        "Claude": "agent-logo-claude",
        "Codex": "agent-logo-codex",
        "Gemini": "agent-logo-gemini",
        "Kimi": "agent-logo-kimi",
        "OpenCode": "agent-logo-opencode",
        "Qwen": "agent-logo-qwen",
        "Qwen Code": "agent-logo-qwen",
    ]

    private static func resolve(title: String) -> NSImage? {
        // Prefer the REAL installed app's icon.
        if let candidates = bundleIdentifiers[title] {
            for bundleID in candidates {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: 28, height: 28)
                    return icon
                }
            }
        }

        // CLI-only agents fall back to the bundled brand logo.
        if let resource = bundledLogoNames[title],
           let url = Bundle.appResources.url(forResource: resource, withExtension: "png"),
           let logo = NSImage(contentsOf: url) {
            logo.size = NSSize(width: 28, height: 28)
            return logo
        }

        return nil
    }
}
