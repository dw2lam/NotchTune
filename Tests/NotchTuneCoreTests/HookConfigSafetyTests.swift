import Foundation
import Testing
@testable import NotchTuneCore

/// Pins the rule that an installer never damages a config it can't fully see:
/// unreadable is not empty, and uninstalling never deletes the user's file.
struct HookConfigSafetyTests {
    private let fileManager = FileManager.default

    private func scratchDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("notchtune-config-safety-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fakeBinary(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("NotchTuneHooks")
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// A config the installer can see exists but can't read.
    private func lockedFile(at url: URL, contents: String) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
    }

    private func unlockAndRead(_ url: URL) throws -> String {
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test
    func readTellsMissingFromUnreadable() throws {
        let root = try scratchDirectory()
        defer { try? fileManager.removeItem(at: root) }

        #expect(try HookConfigFile.read(root.appendingPathComponent("absent.json")) == nil)

        let locked = root.appendingPathComponent("locked.json")
        try lockedFile(at: locked, contents: "{}")
        #expect(throws: HookConfigFileError.self) {
            try HookConfigFile.read(locked)
        }
        _ = try unlockAndRead(locked)
    }

    @Test
    func uninstallLeavesAnUnreadableConfigInPlace() throws {
        let root = try scratchDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let binary = root.appendingPathComponent("managed/NotchTuneHooks")
        let cases: [(url: URL, uninstall: () throws -> Void)] = [
            (root.appendingPathComponent("claude/settings.json"), {
                try ClaudeHookInstallationManager(claudeDirectory: root.appendingPathComponent("claude"), managedHooksBinaryURL: binary).uninstall()
            }),
            (root.appendingPathComponent("codex/hooks.json"), {
                try CodexHookInstallationManager(codexDirectory: root.appendingPathComponent("codex"), managedHooksBinaryURL: binary, featureKeyProvider: { .current }).uninstall()
            }),
            (root.appendingPathComponent("gemini/settings.json"), {
                try GeminiHookInstallationManager(geminiDirectory: root.appendingPathComponent("gemini"), managedHooksBinaryURL: binary).uninstall()
            }),
            (root.appendingPathComponent("cursor/hooks.json"), {
                try CursorHookInstallationManager(cursorDirectory: root.appendingPathComponent("cursor"), managedHooksBinaryURL: binary).uninstall()
            }),
            (root.appendingPathComponent("agy/hooks.json"), {
                try AntigravityHookInstallationManager(configDirectory: root.appendingPathComponent("agy"), managedHooksBinaryURL: binary).uninstall()
            }),
            (root.appendingPathComponent("kimi/config.toml"), {
                try KimiHookInstallationManager(kimiDirectory: root.appendingPathComponent("kimi"), managedHooksBinaryURL: binary).uninstall()
            }),
        ]

        for (url, uninstall) in cases {
            try lockedFile(at: url, contents: "keep me")
            #expect(throws: HookConfigFileError.self) { try uninstall() }
            #expect(try unlockAndRead(url) == "keep me")
        }
    }

    @Test
    func installLeavesAnUnreadableConfigInPlace() throws {
        let root = try scratchDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let source = try fakeBinary(in: root)
        let directory = root.appendingPathComponent("claude")
        let settings = directory.appendingPathComponent("settings.json")
        try lockedFile(at: settings, contents: #"{"theme":"dark"}"#)

        let manager = ClaudeHookInstallationManager(
            claudeDirectory: directory,
            managedHooksBinaryURL: root.appendingPathComponent("managed/NotchTuneHooks")
        )
        #expect(throws: HookConfigFileError.self) {
            try manager.install(hooksBinaryURL: source)
        }
        #expect(try unlockAndRead(settings) == #"{"theme":"dark"}"#)
    }

    @Test
    func nonUTF8TomlIsNotTreatedAsEmpty() throws {
        let root = try scratchDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let source = try fakeBinary(in: root)
        let binary = root.appendingPathComponent("managed/NotchTuneHooks")
        let bytes = Data([0x6D, 0x6F, 0x64, 0x65, 0x6C, 0x3D, 0xFF, 0xFE, 0x0A])

        let codexDirectory = root.appendingPathComponent("codex")
        try fileManager.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        let codexConfig = codexDirectory.appendingPathComponent("config.toml")
        try bytes.write(to: codexConfig)
        let codex = CodexHookInstallationManager(
            codexDirectory: codexDirectory,
            managedHooksBinaryURL: binary,
            featureKeyProvider: { .current }
        )
        #expect(throws: HookConfigFileError.notUTF8(path: codexConfig.path)) {
            try codex.install(hooksBinaryURL: source)
        }
        #expect(try Data(contentsOf: codexConfig) == bytes)

        let kimiDirectory = root.appendingPathComponent("kimi")
        try fileManager.createDirectory(at: kimiDirectory, withIntermediateDirectories: true)
        let kimiConfig = kimiDirectory.appendingPathComponent("config.toml")
        try bytes.write(to: kimiConfig)
        let kimi = KimiHookInstallationManager(kimiDirectory: kimiDirectory, managedHooksBinaryURL: binary)
        #expect(throws: HookConfigFileError.notUTF8(path: kimiConfig.path)) {
            try kimi.install(hooksBinaryURL: source)
        }
        #expect(try Data(contentsOf: kimiConfig) == bytes)
    }

    @Test
    func uninstallKeepsAConfigThatOnlyHeldOurHooks() throws {
        let root = try scratchDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let source = try fakeBinary(in: root)
        let binary = root.appendingPathComponent("managed/NotchTuneHooks")

        let claude = ClaudeHookInstallationManager(claudeDirectory: root.appendingPathComponent("claude"), managedHooksBinaryURL: binary)
        try claude.install(hooksBinaryURL: source)
        try claude.uninstall()
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("claude/settings.json").path))

        let cursor = CursorHookInstallationManager(cursorDirectory: root.appendingPathComponent("cursor"), managedHooksBinaryURL: binary)
        try cursor.install(hooksBinaryURL: source)
        try cursor.uninstall()
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("cursor/hooks.json").path))

        let kimi = KimiHookInstallationManager(kimiDirectory: root.appendingPathComponent("kimi"), managedHooksBinaryURL: binary)
        try kimi.install(hooksBinaryURL: source)
        try kimi.uninstall()
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("kimi/config.toml").path))
    }

    @Test
    func installWritesThroughASymlinkedConfig() throws {
        let root = try scratchDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let source = try fakeBinary(in: root)
        let dotfiles = root.appendingPathComponent("dotfiles/settings.json")
        try fileManager.createDirectory(at: dotfiles.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"theme":"dark"}"#.utf8).write(to: dotfiles)

        let directory = root.appendingPathComponent("claude")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let link = directory.appendingPathComponent("settings.json")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: dotfiles)

        let manager = ClaudeHookInstallationManager(
            claudeDirectory: directory,
            managedHooksBinaryURL: root.appendingPathComponent("managed/NotchTuneHooks")
        )
        try manager.install(hooksBinaryURL: source)

        #expect(try fileManager.destinationOfSymbolicLink(atPath: link.path) == dotfiles.path)
        #expect(try String(contentsOf: dotfiles, encoding: .utf8).contains("NotchTuneHooks"))
    }

    // MARK: Hooks binary

    @Test
    func updateRestoresAMissingBinaryWhenAskedTo() throws {
        let root = try scratchDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let source = try fakeBinary(in: root)
        let installed = root.appendingPathComponent("bin/NotchTuneHooks")

        #expect(try !ManagedHooksBinary.updateIfNeeded(from: source, to: installed, restoreIfMissing: false))
        #expect(!fileManager.fileExists(atPath: installed.path))

        #expect(try ManagedHooksBinary.updateIfNeeded(from: source, to: installed))
        #expect(fileManager.isExecutableFile(atPath: installed.path))
    }

    @Test
    func failedUpdateKeepsTheWorkingBinaryAndLeavesNoStagingFile() throws {
        let root = try scratchDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let installed = root.appendingPathComponent("bin/NotchTuneHooks")
        try fileManager.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("working".utf8).write(to: installed)

        #expect(throws: (any Error).self) {
            try ManagedHooksBinary.install(from: root.appendingPathComponent("gone"), to: installed)
        }

        #expect(try String(contentsOf: installed, encoding: .utf8) == "working")
        #expect(try fileManager.contentsOfDirectory(atPath: installed.deletingLastPathComponent().path) == ["NotchTuneHooks"])
    }

    @Test
    func updateReplacesAChangedBinary() throws {
        let root = try scratchDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let source = try fakeBinary(in: root)
        let installed = root.appendingPathComponent("bin/NotchTuneHooks")
        try fileManager.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: installed)

        #expect(try ManagedHooksBinary.updateIfNeeded(from: source, to: installed))
        #expect(try Data(contentsOf: installed) == Data(contentsOf: source))
        #expect(fileManager.isExecutableFile(atPath: installed.path))
    }
}
