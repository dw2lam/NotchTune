import Foundation
import Testing
@testable import NotchTuneCore

struct LegacyInstallMigrationTests {
    private func makeTempAppSupport() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notchtune-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test
    func movesLegacySupportDirectoryAndLeavesCompatibilitySymlink() throws {
        let fileManager = FileManager.default
        let appSupport = try makeTempAppSupport()
        defer { try? fileManager.removeItem(at: appSupport) }

        let oldDir = appSupport.appendingPathComponent("OpenIsland", isDirectory: true)
        try fileManager.createDirectory(
            at: oldDir.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        let payload = oldDir.appendingPathComponent("bin/OpenIslandHooks")
        try Data("hooks".utf8).write(to: payload)

        LegacyInstallMigration.migrateSupportDirectory(appSupportURL: appSupport, fileManager: fileManager)

        let newPayload = appSupport.appendingPathComponent("NotchTune/bin/OpenIslandHooks")
        #expect(fileManager.fileExists(atPath: newPayload.path))
        // The old path still resolves through the compatibility symlink.
        #expect(fileManager.fileExists(atPath: payload.path))
        let oldType = try fileManager.attributesOfItem(atPath: oldDir.path)[.type] as? FileAttributeType
        #expect(oldType == .typeSymbolicLink)
    }

    @Test
    func migrationIsIdempotentAndNeverClobbersAnExistingNewDirectory() throws {
        let fileManager = FileManager.default
        let appSupport = try makeTempAppSupport()
        defer { try? fileManager.removeItem(at: appSupport) }

        let oldDir = appSupport.appendingPathComponent("OpenIsland", isDirectory: true)
        let newDir = appSupport.appendingPathComponent("NotchTune", isDirectory: true)
        try fileManager.createDirectory(at: oldDir, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: oldDir.appendingPathComponent("marker"))
        try fileManager.createDirectory(at: newDir, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: newDir.appendingPathComponent("marker"))

        LegacyInstallMigration.migrateSupportDirectory(appSupportURL: appSupport, fileManager: fileManager)

        let kept = try Data(contentsOf: newDir.appendingPathComponent("marker"))
        #expect(String(decoding: kept, as: UTF8.self) == "new")
        // Old directory untouched (no move, no symlink) when both exist.
        let oldType = try fileManager.attributesOfItem(atPath: oldDir.path)[.type] as? FileAttributeType
        #expect(oldType == .typeDirectory)

        // Running again is a no-op.
        LegacyInstallMigration.migrateSupportDirectory(appSupportURL: appSupport, fileManager: fileManager)
        #expect(fileManager.fileExists(atPath: oldDir.appendingPathComponent("marker").path))
    }

    @Test
    func defaultsMigrationCopiesLegacyValuesOnceWithoutOverwriting() throws {
        let suiteName = "notchtune-defaults-test-\(UUID().uuidString)"
        let legacyDomain = "notchtune-legacy-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("could not create test defaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            defaults.removePersistentDomain(forName: legacyDomain)
        }

        defaults.setPersistentDomain(
            ["existing": "kept", "migrated": "from-legacy"],
            forName: legacyDomain
        )
        defaults.set("kept-new", forKey: "existing")

        LegacyInstallMigration.migrateDefaults(defaults, legacyDomains: [legacyDomain])

        #expect(defaults.string(forKey: "existing") == "kept-new")
        #expect(defaults.string(forKey: "migrated") == "from-legacy")

        // Marker prevents a second pass from re-copying.
        defaults.setPersistentDomain(["migrated": "changed"], forName: legacyDomain)
        defaults.removeObject(forKey: "migrated")
        LegacyInstallMigration.migrateDefaults(defaults, legacyDomains: [legacyDomain])
        #expect(defaults.object(forKey: "migrated") == nil)
    }
}
