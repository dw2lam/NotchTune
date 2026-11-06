import Foundation
import Testing
@testable import NotchTuneCore

/// `config.toml` belongs to the user. These are the shapes a line-based edit
/// gets wrong: each must end up valid, enabled and otherwise untouched.
struct CodexConfigEditingTests {
    private func enable(_ contents: String) throws -> CodexFeatureMutation {
        let mutation = CodexHookInstaller.enableCodexHooksFeature(in: contents, preferredKey: .current)
        try CodexHookInstaller.verifyFeatureMutation(mutation, original: contents, preferredKey: .current)
        return mutation
    }

    @Test
    func headerWithCommentIsTheSameTable() throws {
        let result = try enable("[features] # flags\nother = true\n\n[tui]\ntheme = \"x\"\n")
        #expect(result.contents == "[features] # flags\nother = true\nhooks = true\n\n[tui]\ntheme = \"x\"\n")
    }

    @Test
    func crlfFilesStayCRLF() throws {
        let result = try enable("[features]\r\nother = true\r\n")
        #expect(result.contents == "[features]\r\nother = true\r\nhooks = true\r\n")
        #expect(CodexHookInstaller.isCodexHooksFeatureEnabled(in: result.contents))
    }

    @Test
    func dottedFeaturesStayDotted() throws {
        let result = try enable("model = \"x\"\nfeatures.other = true\n\n[tui]\ntheme = \"x\"\n")
        #expect(result.contents == "model = \"x\"\nfeatures.other = true\nfeatures.hooks = true\n\n[tui]\ntheme = \"x\"\n")
        #expect(!result.contents.contains("[features]"))
    }

    @Test
    func inlineFeaturesStayInline() throws {
        let result = try enable("features = { other = true }\nmodel = \"x\"\n")
        #expect(result.contents == "features = { other = true, hooks = true }\nmodel = \"x\"\n")
    }

    @Test
    func subtableIsNotTheFeaturesTable() throws {
        let result = try enable("[features.experimental]\nhooks = false\n")
        #expect(result.contents.contains("[features]\nhooks = true"))
        #expect(result.contents.contains("[features.experimental]\nhooks = false"))
    }

    @Test
    func bracketInsideAMultiLineArrayDoesNotEndTheTable() throws {
        let contents = "[features]\nmatrix = [\n  [1],\n  [2]\n]\nother = true\n\n[tui]\n"
        let result = try enable(contents)
        #expect(result.contents == "[features]\nmatrix = [\n  [1],\n  [2]\n]\nother = true\nhooks = true\n\n[tui]\n")
    }

    @Test
    func headerLookalikeInsideAMultiLineStringIsIgnored() throws {
        let contents = "note = \"\"\"\n[features]\nhooks = false\n\"\"\"\n"
        let result = try enable(contents)
        #expect(result.contents.hasPrefix(contents))
        #expect(result.contents.hasSuffix("[features]\nhooks = true"))
        #expect(CodexHookInstaller.isCodexHooksFeatureEnabled(in: result.contents))
    }

    @Test
    func legacyFlagMigratesInPlace() throws {
        let result = try enable("[features]\ncodex_hooks = true\n")
        #expect(result.contents == "[features]\nhooks = true\n")
        #expect(!result.featureEnabledByInstaller)
    }

    @Test
    func enablingTwiceChangesNothing() throws {
        let first = try enable("[features] # flags\nother = true\n")
        let second = try enable(first.contents)
        #expect(!second.changed)
    }

    @Test
    func aFalseFlagIsTurnedOnWhereItIs() throws {
        let result = try enable("[features]\nhooks = false # off for now\nother = true\n")
        #expect(result.contents == "[features]\nhooks = true\nother = true\n")
        #expect(result.featureEnabledByInstaller)
    }

    @Test
    func duplicateTablesAreRefused() {
        let contents = "[features]\na = true\n\n[features]\nb = true\n"
        let mutation = CodexHookInstaller.enableCodexHooksFeature(in: contents, preferredKey: .current)
        #expect(throws: CodexHookInstallerError.self) {
            try CodexHookInstaller.verifyFeatureMutation(mutation, original: contents, preferredKey: .current)
        }
    }

    @Test
    func verificationCatchesALostLine() {
        let original = "[features]\nother = true\nmodel = \"x\"\n"
        let mutation = CodexFeatureMutation(
            contents: "[features]\nhooks = true\n",
            changed: true,
            featureEnabledByInstaller: true
        )
        #expect(throws: CodexHookInstallerError.self) {
            try CodexHookInstaller.verifyFeatureMutation(mutation, original: original, preferredKey: .current)
        }
    }

    @Test
    func disableRemovesOnlyTheFlagInEachForm() {
        #expect(
            CodexHookInstaller.disableCodexHooksFeatureIfManaged(in: "[features] # flags\nhooks = true\nother = true\n").contents
                == "[features] # flags\nother = true\n"
        )
        #expect(
            CodexHookInstaller.disableCodexHooksFeatureIfManaged(in: "features.hooks = true\nfeatures.other = true\n").contents
                == "features.other = true\n"
        )
        #expect(
            CodexHookInstaller.disableCodexHooksFeatureIfManaged(in: "features = { hooks = true, other = true }\n").contents
                == "features = { other = true }\n"
        )
    }

    @Test
    func explicitFalseIsDetectedInEveryForm() {
        #expect(CodexHookInstaller.isCodexHooksFeatureExplicitlyDisabled(in: "[features]\nhooks = false\n"))
        #expect(CodexHookInstaller.isCodexHooksFeatureExplicitlyDisabled(in: "features.codex_hooks = false\n"))
        #expect(CodexHookInstaller.isCodexHooksFeatureExplicitlyDisabled(in: "features = { hooks = false }\n"))
        #expect(!CodexHookInstaller.isCodexHooksFeatureExplicitlyDisabled(in: "model = \"x\"\n"))
    }

    @Test
    func installRefusesAnUneditableConfigBeforeWritingAnything() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchtune-codex-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("NotchTuneHooks")
        try Data("#!/bin/sh\n".utf8).write(to: source)
        let config = root.appendingPathComponent("config.toml")
        let contents = "[features]\na = true\n\n[features]\nb = true\n"
        try Data(contents.utf8).write(to: config)

        let manager = CodexHookInstallationManager(
            codexDirectory: root,
            managedHooksBinaryURL: root.appendingPathComponent("managed/NotchTuneHooks"),
            featureKeyProvider: { .current }
        )
        #expect(throws: CodexHookInstallerError.self) {
            try manager.install(hooksBinaryURL: source)
        }
        #expect(try String(contentsOf: config, encoding: .utf8) == contents)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hooks.json").path))
    }
}
