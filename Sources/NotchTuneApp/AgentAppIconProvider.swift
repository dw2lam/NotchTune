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
    private static var installedAppIconCache: [String: NSImage?] = [:]

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
    static let bundledLogoNames: [String: String] = [
        "Claude": "agent-logo-claude",
        "Codex": "agent-logo-codex",
        "Gemini": "agent-logo-gemini",
        "Kimi": "agent-logo-kimi",
        "OpenCode": "agent-logo-opencode",
        "Qwen": "agent-logo-qwen",
        "Qwen Code": "agent-logo-qwen",
    ]

    /// The installed application's own icon, or nil when the agent's app
    /// isn't installed — never the bundled logo fallback. Cached: Settings
    /// asks for it from view bodies, and a LaunchServices lookup plus a fresh
    /// icon image per render is wasted work.
    static func installedAppIcon(forProviderTitle title: String) -> NSImage? {
        if let cached = installedAppIconCache[title] {
            return cached
        }
        var resolved: NSImage?
        if let candidates = bundleIdentifiers[title] {
            for bundleID in candidates {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    resolved = NSWorkspace.shared.icon(forFile: url.path)
                    break
                }
            }
        }
        installedAppIconCache[title] = resolved
        return resolved
    }

    /// The bundled brand logo for `title`, or nil when there is none — or
    /// when the image has no visible pixels, so callers fall back to the
    /// text name instead of drawing an empty square.
    static func bundledLogo(forProviderTitle title: String) -> NSImage? {
        guard let resource = bundledLogoNames[title],
              let url = Bundle.appResources.url(forResource: resource, withExtension: "png"),
              let logo = NSImage(contentsOf: url),
              hasVisiblePixels(logo)
        else {
            return nil
        }
        return logo
    }

    /// True when at least one pixel of `image` is not fully transparent.
    static func hasVisiblePixels(_ image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        // Logos are tiny; cap the scan so an unexpectedly large image stays cheap.
        let width = min(cgImage.width, 256)
        let height = min(cgImage.height, 256)
        guard width > 0, height > 0 else { return false }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drewImage else { return false }
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }
    }

    private static func resolve(title: String) -> NSImage? {
        // Prefer the REAL installed app's icon. Copy it: the cached original
        // is shared with Settings, which must not see a resized image.
        if let icon = installedAppIcon(forProviderTitle: title)?.copy() as? NSImage {
            icon.size = NSSize(width: 28, height: 28)
            return icon
        }

        // CLI-only agents fall back to the bundled brand logo.
        if let logo = bundledLogo(forProviderTitle: title) {
            logo.size = NSSize(width: 28, height: 28)
            return logo
        }

        return nil
    }
}
