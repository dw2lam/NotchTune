import AppKit

/// Manages notification sound playback using macOS system sounds.
@MainActor
struct NotificationSoundService {
    /// A selectable sound slot. Both slots draw from the same system + custom
    /// sound lists, but persist their selection independently.
    enum SoundType {
        case notification
        case nudge
    }

    private static let soundsDirectory = "/System/Library/Sounds"
    private static let notificationDefaultsKey = "notification.sound.name"
    private static let nudgeDefaultsKey = "feature.nudge.sound.name"
    static let defaultSoundName = "Bottle"
    static let nudgeDefaultSoundName = "Submarine"

    static func defaultSoundName(for type: SoundType) -> String {
        switch type {
        case .notification: return defaultSoundName
        case .nudge: return nudgeDefaultSoundName
        }
    }

    private static func defaultsKey(for type: SoundType) -> String {
        switch type {
        case .notification: return notificationDefaultsKey
        case .nudge: return nudgeDefaultsKey
        }
    }

    static var customSoundsDirectory: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let customSoundsDir = appSupport.appendingPathComponent("NotchTuneApp/Sounds", isDirectory: true)
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

    /// The currently selected sound name for a given slot, persisted in UserDefaults.
    static func selectedSoundName(for type: SoundType) -> String {
        UserDefaults.standard.string(forKey: defaultsKey(for: type)) ?? defaultSoundName(for: type)
    }

    static func setSelectedSoundName(_ name: String, for type: SoundType) {
        UserDefaults.standard.set(name, forKey: defaultsKey(for: type))
    }

    /// Legacy accessor for the notification slot, kept so existing call sites compile.
    static var selectedSoundName: String {
        get { selectedSoundName(for: .notification) }
        set { setSelectedSoundName(newValue, for: .notification) }
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
        play(selectedSoundName(for: .notification))
    }

    /// Plays the user-selected sound for a given slot, respecting the mute setting.
    static func play(type: SoundType, isMuted: Bool) {
        guard !isMuted else { return }
        play(selectedSoundName(for: type))
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
