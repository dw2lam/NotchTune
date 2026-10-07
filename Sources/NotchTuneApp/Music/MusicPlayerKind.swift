import AppKit

/// The two real players NotchTune can drive (the Settings → Music picker's
/// non-"None" choices). Raw values match the `music.connectedApp` default.
enum MusicPlayerKind: String, CaseIterable, Codable, Sendable {
    case appleMusic
    case spotify

    /// The player selected in Settings → Music, `nil` for None.
    static func selected(in defaults: UserDefaults = .standard) -> MusicPlayerKind? {
        MusicPlayerKind(rawValue: defaults.string(forKey: musicConnectedAppDefaultsKey) ?? "")
    }

    init?(appName: String) {
        switch appName {
        case "Apple Music": self = .appleMusic
        case "Spotify": self = .spotify
        default: return nil
        }
    }

    var bundleID: String {
        switch self {
        case .appleMusic: MusicConstants.AppleMusic.bundleID
        case .spotify: MusicConstants.Spotify.bundleID
        }
    }

    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        }
    }

    /// Where the app usually lives, used when LaunchServices can't resolve it.
    var fallbackAppURL: URL {
        switch self {
        case .appleMusic: URL(fileURLWithPath: "/System/Applications/Music.app")
        case .spotify: URL(fileURLWithPath: "/Applications/Spotify.app")
        }
    }

    var appURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        return FileManager.default.fileExists(atPath: fallbackAppURL.path) ? fallbackAppURL : nil
    }

    /// Brand accent, used only as a faint wash behind the app icon.
    var accent: NSColor {
        switch self {
        case .appleMusic: NSColor(red: 0.98, green: 0.18, blue: 0.28, alpha: 1)
        case .spotify: NSColor(red: 0.11, green: 0.73, blue: 0.33, alpha: 1)
        }
    }
}

/// The player's REAL app icon (resolved through LaunchServices, like
/// `AgentAppIconProvider`). Reading an icon never launches the app.
@MainActor
enum MusicPlayerIcon {
    private static var cache: [MusicPlayerKind: NSImage] = [:]
    /// When a player was last found not installed. A selected-but-missing
    /// player is looked up again at most every `missRetryInterval` instead
    /// of on every render (LaunchServices query + file check each time).
    private static var misses: [MusicPlayerKind: Date] = [:]
    static let missRetryInterval: TimeInterval = 60
    /// Seam for tests.
    static var resolveAppURL: (MusicPlayerKind) -> URL? = { $0.appURL }

    static func icon(for kind: MusicPlayerKind, now: Date = .now) -> NSImage? {
        if let cached = cache[kind] { return cached }
        if let missedAt = misses[kind], now.timeIntervalSince(missedAt) < missRetryInterval {
            return nil
        }
        guard let url = resolveAppURL(kind) else {
            misses[kind] = now
            return nil
        }
        misses[kind] = nil
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 256, height: 256)
        cache[kind] = icon
        return icon
    }

    static func resetForTests() {
        cache = [:]
        misses = [:]
        resolveAppURL = { $0.appURL }
    }
}
