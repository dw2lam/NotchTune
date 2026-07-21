import Foundation

/// One-shot migration of a pre-rename "OpenIsland" install to "NotchTune".
/// Runs before anything else touches the support directory or UserDefaults so
/// Myspace files, the session registry, hook binaries, and every setting
/// survive the rebrand.
public enum LegacyInstallMigration {
    static let defaultsMarkerKey = "notchtune.legacyDefaultsMigrated"
    static let legacySupportDirectoryName = "OpenIsland"
    static let supportDirectoryName = "NotchTune"
    static let legacyDefaultsDomains = ["app.openisland.dev", "OpenIslandApp"]

    public static func run(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        migrateSupportDirectory(appSupportURL: appSupport, fileManager: fileManager)
        migrateCodexSessionStore(appSupportURL: appSupport, fileManager: fileManager)
        migrateDefaults(defaults)
    }

    /// The Codex session↔terminal map used to live in its own lowercase
    /// `Application Support/open-island` directory; fold it into the main one.
    static func migrateCodexSessionStore(appSupportURL: URL, fileManager: FileManager) {
        let oldFile = appSupportURL
            .appendingPathComponent("open-island", isDirectory: true)
            .appendingPathComponent("session-terminals.json")
        let newDir = appSupportURL.appendingPathComponent(supportDirectoryName, isDirectory: true)
        let newFile = newDir.appendingPathComponent("session-terminals.json")
        guard fileManager.fileExists(atPath: oldFile.path),
              !fileManager.fileExists(atPath: newFile.path) else { return }
        try? fileManager.createDirectory(at: newDir, withIntermediateDirectories: true)
        try? fileManager.moveItem(at: oldFile, to: newFile)
    }

    /// Moves `Application Support/OpenIsland` to `.../NotchTune` and leaves a
    /// compatibility symlink behind, so agent configs that still invoke
    /// `.../OpenIsland/bin/OpenIslandHooks` keep working until the hook
    /// installers rewrite them on this same launch.
    static func migrateSupportDirectory(appSupportURL: URL, fileManager: FileManager) {
        let oldDir = appSupportURL.appendingPathComponent(legacySupportDirectoryName, isDirectory: true)
        let newDir = appSupportURL.appendingPathComponent(supportDirectoryName, isDirectory: true)

        // attributesOfItem does not follow symlinks — a symlink here means a
        // previous run already migrated.
        if let type = (try? fileManager.attributesOfItem(atPath: oldDir.path))?[.type] as? FileAttributeType,
           type == .typeSymbolicLink {
            return
        }

        var oldIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: oldDir.path, isDirectory: &oldIsDirectory),
              oldIsDirectory.boolValue,
              !fileManager.fileExists(atPath: newDir.path) else {
            return
        }

        do {
            try fileManager.moveItem(at: oldDir, to: newDir)
            try? fileManager.createSymbolicLink(at: oldDir, withDestinationURL: newDir)
        } catch {
            // Fail open: a fresh NotchTune directory is created lazily and the
            // old install keeps its data.
        }
    }

    /// Copies settings from the pre-rename defaults domains into the current
    /// domain, once, without overwriting anything already written there.
    static func migrateDefaults(
        _ defaults: UserDefaults,
        legacyDomains: [String] = LegacyInstallMigration.legacyDefaultsDomains
    ) {
        guard defaults.object(forKey: defaultsMarkerKey) == nil else { return }
        for domain in legacyDomains {
            guard let legacy = defaults.persistentDomain(forName: domain),
                  !legacy.isEmpty else { continue }
            for (key, value) in legacy where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            break
        }
        defaults.set(true, forKey: defaultsMarkerKey)
    }
}
