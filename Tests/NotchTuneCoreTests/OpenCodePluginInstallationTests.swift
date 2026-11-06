import Foundation
import Testing
@testable import NotchTuneCore

struct OpenCodePluginInstallationTests {
    private let fileManager = FileManager.default
    private let plugin = Data("// notchtune-plugin-revision: 2\nexport default {}\n".utf8)

    private func makeManager() throws -> (manager: OpenCodePluginInstallationManager, root: URL) {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("notchtune-opencode-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return (OpenCodePluginInstallationManager(openCodeConfigDirectory: root), root)
    }

    @Test
    func installDoesNotCreateOrRewriteConfig() throws {
        let (manager, root) = try makeManager()
        defer { try? fileManager.removeItem(at: root) }

        let status = try manager.install(pluginSourceData: plugin)
        #expect(status.isInstalled)
        #expect(status.pluginIsCurrent)
        #expect(!fileManager.fileExists(atPath: root.appendingPathComponent("config.json").path))
    }

    @Test
    func installLeavesJSONCAlone() throws {
        let (manager, root) = try makeManager()
        defer { try? fileManager.removeItem(at: root) }

        let config = root.appendingPathComponent("config.json")
        let jsonc = "{\n  // my provider\n  \"model\": \"a/b\",\n}\n"
        try Data(jsonc.utf8).write(to: config)

        try manager.install(pluginSourceData: plugin)
        #expect(try String(contentsOf: config, encoding: .utf8) == jsonc)
    }

    @Test
    func removingOurReferenceKeepsEveryOtherEntry() throws {
        let (manager, root) = try makeManager()
        defer { try? fileManager.removeItem(at: root) }

        let config = root.appendingPathComponent("config.json")
        let reference = "file://\(root.path)/plugins/open-island.js"
        let original: [String: Any] = [
            "model": "a/b",
            "plugin": [reference, "opencode-other", ["opencode-tuple", ["enabled": true]]],
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: config)

        try manager.install(pluginSourceData: plugin)

        let result = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        let plugins = try #require(result["plugin"] as? [Any])
        #expect(result["model"] as? String == "a/b")
        #expect(plugins.count == 2)
        #expect(plugins[0] as? String == "opencode-other")
        #expect((plugins[1] as? [Any])?.first as? String == "opencode-tuple")
    }

    @Test
    func uninstallReportsAReferenceItCannotRemove() throws {
        let (manager, root) = try makeManager()
        defer { try? fileManager.removeItem(at: root) }

        try manager.install(pluginSourceData: plugin)
        let config = root.appendingPathComponent("config.json")
        let jsonc = "{\n  // keep\n  \"plugin\": [\"file:///x/open-island.js\"],\n}\n"
        try Data(jsonc.utf8).write(to: config)

        let status = try manager.uninstall()
        #expect(!status.pluginFilePresent)
        #expect(status.configCleanupProblem != nil)
        #expect(try String(contentsOf: config, encoding: .utf8) == jsonc)
    }

    @Test
    func uninstallStaysQuietWhenConfigNeverMentionedThePlugin() throws {
        let (manager, root) = try makeManager()
        defer { try? fileManager.removeItem(at: root) }

        try manager.install(pluginSourceData: plugin)
        try Data("{\n  // mine\n}\n".utf8).write(to: root.appendingPathComponent("config.json"))

        #expect(try manager.uninstall().configCleanupProblem == nil)
    }

    @Test
    func olderPluginFilesReadAsOutdated() {
        #expect(OpenCodePluginInstallationManager.pluginRevision(in: Data("// Open Island plugin\n".utf8)) == 0)
        #expect(OpenCodePluginInstallationManager.pluginRevision(in: nil) == 0)
        #expect(OpenCodePluginInstallationManager.pluginRevision(in: plugin) == 2)
    }

    /// The Swift constant and the shipped file have to move together, or the
    /// doctor nags about a plugin it just installed.
    @Test
    func bundledPluginMatchesTheExpectedRevisionAndWritesNoDebugLog() throws {
        let resource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NotchTuneApp/Resources/notchtune-opencode.js")
        let data = try Data(contentsOf: resource)
        let source = String(decoding: data, as: UTF8.self)

        #expect(
            OpenCodePluginInstallationManager.pluginRevision(in: data)
                == OpenCodePluginInstallationManager.currentPluginRevision
        )
        #expect(!source.contains("/tmp/"))
        #expect(!source.contains("appendFileSync"))
        // The approval card marks a long command as cut; cut here, it can't.
        #expect(!source.contains("JSON.stringify(toolInput).slice(0, 200)"))
    }
}
