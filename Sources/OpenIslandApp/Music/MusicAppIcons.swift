import AppKit

struct MusicAppIcons {
    func getIcon(file path: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path.path()) else { return nil }
        return NSWorkspace.shared.icon(forFile: path.path())
    }

    func getIcon(bundleID: String) -> NSImage? {
        guard let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return getIcon(file: path)
    }
}
