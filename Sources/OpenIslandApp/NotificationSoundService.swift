import AppKit

/// Manages notification sound playback using macOS system sounds.
@MainActor
struct NotificationSoundService {
    private static let soundsDirectory = "/System/Library/Sounds"
    private static let defaultsKey = "notification.sound.name"
    static let defaultSoundName = "Bottle"

    static var customSoundsDirectory: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let customSoundsDir = appSupport.appendingPathComponent("OpenIslandApp/Sounds", isDirectory: true)
        if !fm.fileExists(atPath: customSoundsDir.path) {
            try? fm.createDirectory(at: customSoundsDir, withIntermediateDirectories: true, attributes: nil)
        }
        return customSoundsDir
    }

    /// Returns the list of available system sound names (without file extension).
    static func availableSounds() -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: soundsDirectory) else {
            return []
        }
        return contents
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
    }

    /// Returns the list of available custom sound names (with extensions).
    static func availableCustomSounds() -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: customSoundsDirectory.path) else {
            return []
        }
        return contents
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    /// The currently selected sound name, persisted in UserDefaults.
    static var selectedSoundName: String {
        get {
            UserDefaults.standard.string(forKey: defaultsKey) ?? defaultSoundName
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    /// Plays a system sound or custom sound by name.
    static func play(_ name: String) {
        // 1. Try playing as a custom sound (name will be a filename with extension, e.g. "sound.mp3")
        let customURL = customSoundsDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: customURL.path) {
            if let sound = NSSound(contentsOf: customURL, byReference: true) {
                sound.stop()
                sound.play()
                return
            }
        }

        // 2. Fall back to system sound named `name`
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.stop()
            sound.play()
        }
    }

    /// Plays the user-selected notification sound, respecting the mute setting.
    static func playNotification(isMuted: Bool) {
        guard !isMuted else { return }
        play(selectedSoundName)
    }

    /// Copies a sound file to the custom sounds directory and returns the filename on success.
    static func addCustomSound(from url: URL) throws -> String {
        let fm = FileManager.default
        let filename = url.lastPathComponent
        let destinationURL = customSoundsDirectory.appendingPathComponent(filename)

        // If file already exists, remove it first to overwrite cleanly
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        try fm.copyItem(at: url, to: destinationURL)
        return filename
    }

    /// Deletes a custom sound file by filename.
    static func deleteCustomSound(_ filename: String) throws {
        let fm = FileManager.default
        let url = customSoundsDirectory.appendingPathComponent(filename)
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }
}
