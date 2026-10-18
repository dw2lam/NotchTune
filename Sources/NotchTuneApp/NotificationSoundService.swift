import AppKit

/// Manages notification sound playback: NotchTune's bundled sound pack, the
/// macOS system sounds, and sounds the user imports.
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

    // MARK: Bundled pack

    /// One sound of the bundled NotchTune pack: `Resources/Sounds/notchtune-<slug>.wav`,
    /// synthesized by `scripts/generate-notification-sounds.py`.
    struct BundledSound: Identifiable, Hashable, Sendable {
        /// The persisted selection, `notchtune.<slug>`. It can't collide with
        /// a system sound name or a custom sound (those carry an extension).
        let id: String
        let title: String
        let url: URL
    }

    nonisolated static let bundledSoundPrefix = "notchtune."
    nonisolated private static let bundledFilePrefix = "notchtune-"

    /// The pack, listed once from the app's resource bundle, by title.
    static let bundledSounds: [BundledSound] = bundledSounds(in: .appResources)

    nonisolated static func bundledSounds(in bundle: Bundle) -> [BundledSound] {
        // SwiftPM's `.process` flattens Resources/Sounds into the bundle root;
        // look in both places so either layout resolves.
        let urls = (bundle.urls(forResourcesWithExtension: "wav", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "wav", subdirectory: "Sounds") ?? [])
        var seen = Set<String>()
        return urls.compactMap { url -> BundledSound? in
            let stem = url.deletingPathExtension().lastPathComponent
            guard stem.hasPrefix(bundledFilePrefix) else { return nil }
            let slug = String(stem.dropFirst(bundledFilePrefix.count))
            guard !slug.isEmpty, seen.insert(slug).inserted else { return nil }
            return BundledSound(id: bundledSoundPrefix + slug, title: title(forSlug: slug), url: url)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// "ding-dong" → "Ding Dong".
    nonisolated static func title(forSlug slug: String) -> String {
        slug.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    // MARK: Custom sounds

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

    /// Where a stored sound name plays from.
    enum SoundSource: Equatable {
        case bundled(URL)
        case custom(URL)
        case system(String)
    }

    /// Resolves a stored name: a bundled `notchtune.<slug>`, then a custom
    /// file name (with extension), else a system sound name. A bundled id
    /// that no longer ships falls back to the default sound.
    static func source(for name: String) -> SoundSource {
        if name.hasPrefix(bundledSoundPrefix) {
            if let sound = bundledSounds.first(where: { $0.id == name }) {
                return .bundled(sound.url)
            }
            return .system(defaultSoundName)
        }
        let customURL = customSoundsDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: customURL.path) {
            return .custom(customURL)
        }
        return .system(name)
    }

    /// Bundled sounds, decoded once and reused (they never change on disk).
    private static var loadedBundledSounds: [URL: NSSound] = [:]
    /// Keeps the sound that's playing alive until it finishes.
    private static var playingSound: NSSound?

    /// Plays a bundled, custom or system sound by its stored name.
    static func play(_ name: String) {
        let sound: NSSound?
        switch source(for: name) {
        case .bundled(let url):
            if let cached = loadedBundledSounds[url] {
                sound = cached
            } else {
                sound = NSSound(contentsOf: url, byReference: true)
                loadedBundledSounds[url] = sound
            }
        case .custom(let url):
            // Re-read: an import can replace a file of the same name.
            sound = NSSound(contentsOf: url, byReference: true)
        case .system(let systemName):
            sound = NSSound(named: NSSound.Name(systemName))
        }
        guard let sound else { return }
        playingSound?.stop()
        sound.stop()
        sound.play()
        playingSound = sound
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
