import Foundation
import Testing
@testable import NotchTuneCore

/// Drives the real `NotchTuneHooks` binary against a real `BridgeServer`.
struct HookRoundTripTests {
    private let fileManager = FileManager.default

    private var builtBinary: URL? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(".build/debug/NotchTuneHooks")
        return fileManager.isExecutableFile(atPath: url.path) ? url : nil
    }

    private func scratchDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("notchtune-roundtrip-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func descriptor(_ agent: AgentIdentifier, home: URL) throws -> HookAgentDescriptor {
        try #require(HookAgentCatalog.descriptors(home: home, claudeDirectory: home.appendingPathComponent(".claude")).first { $0.agent == agent })
    }

    private func installClaude(home: URL, binary: URL) throws -> HookAgentDescriptor {
        let target = try descriptor(.claudeCode, home: home)
        try ClaudeHookInstallationManager(
            claudeDirectory: target.directory,
            managedHooksBinaryURL: home.appendingPathComponent("managed/NotchTuneHooks")
        ).install(hooksBinaryURL: binary)
        return target
    }

    @Test
    func aPingTravelsThroughTheInstalledBinaryAndLeavesNoSession() throws {
        let binary = try #require(builtBinary)
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        let socket = BridgeSocketLocation.uniqueTestURL()
        let activity = HookActivityStore(url: home.appendingPathComponent("activity.json"))
        let server = BridgeServer(socketURL: socket, activityStore: activity)
        try server.start()
        defer { server.stop() }

        let target = try installClaude(home: home, binary: binary)
        #expect(HookRoundTripTest.run(target, socketURL: socket) == .passed)

        // A test must not look like the agent itself checking in.
        #expect(activity.lastEvent(for: .claudeCode) == nil)
    }

    @Test
    func noBridgeFailsAtTheBridgeStep() throws {
        let binary = try #require(builtBinary)
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        let target = try installClaude(home: home, binary: binary)
        let result = HookRoundTripTest.run(target, socketURL: BridgeSocketLocation.uniqueTestURL())
        #expect(result.failedStep == .bridge)
        #expect(result.failure == .bridgeUnreachable)
    }

    @Test
    func aHookMissingFromConfigFailsAtTheConfigStep() throws {
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        let result = HookRoundTripTest.run(try descriptor(.codex, home: home), socketURL: BridgeSocketLocation.uniqueTestURL())
        #expect(result.failedStep == .config)
    }

    @Test
    func aDeletedBinaryFailsAtTheBinaryStep() throws {
        let binary = try #require(builtBinary)
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        let target = try installClaude(home: home, binary: binary)
        try fileManager.removeItem(at: home.appendingPathComponent("managed/NotchTuneHooks"))

        let result = HookRoundTripTest.run(target, socketURL: BridgeSocketLocation.uniqueTestURL())
        #expect(result.failedStep == .binary)
    }

    @Test
    func aBinaryThatIgnoresThePingCountsAsOutdated() throws {
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        // What a pre-doctor binary does: finds no stdin, exits 0, says nothing.
        let old = home.appendingPathComponent("managed/NotchTuneHooks")
        try fileManager.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: old)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: old.path)

        let target = try descriptor(.gemini, home: home)
        try fileManager.createDirectory(at: target.directory, withIntermediateDirectories: true)
        let config = #"{"hooks":{"Stop":[{"hooks":[{"command":"'\#(old.path)' --source gemini"}]}]}}"#
        try Data(config.utf8).write(to: target.configURL)

        let result = HookRoundTripTest.run(target, socketURL: BridgeSocketLocation.uniqueTestURL())
        #expect(result.failure == .binaryOutdated(path: old.path))
    }

    @Test
    func openCodeSkipsTheBinaryAndChecksThePlugin() throws {
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        try server.start()
        defer { server.stop() }

        let target = try descriptor(.openCode, home: home)
        #expect(HookRoundTripTest.run(target, socketURL: socket).failedStep == .config)

        try fileManager.createDirectory(at: target.configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("// old plugin\n".utf8).write(to: target.configURL)
        #expect(HookRoundTripTest.run(target, socketURL: socket).failure == .pluginOutdated(path: target.configURL.path))

        try Data("// notchtune-plugin-revision: 2\n".utf8).write(to: target.configURL)
        #expect(HookRoundTripTest.run(target, socketURL: socket) == .passed)
    }

    @Test
    func anUnknownEventIsAcknowledgedAndCreatesNoSession() throws {
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        let socket = BridgeSocketLocation.uniqueTestURL()
        let activity = HookActivityStore(url: home.appendingPathComponent("activity.json"))
        let server = BridgeServer(socketURL: socket, activityStore: activity)
        try server.start()
        defer { server.stop() }

        let client = BridgeCommandClient(socketURL: socket)
        let response = try client.send(
            .processClaudeHook(ClaudeHookPayload(cwd: "/tmp", hookEventName: .unknown("PostCompact"), sessionID: "s")),
            timeout: 2
        )
        #expect(response == .acknowledged)
        // Unknown still proves the hook works, so it counts as activity.
        #expect(activity.lastEvent(for: .claudeCode) != nil)
    }

    @Test
    func kimiPermissionRequestsAreObserveOnly() throws {
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        try server.start()
        defer { server.stop() }

        var payload = ClaudeHookPayload(cwd: "/tmp", hookEventName: .permissionRequest, sessionID: "s")
        payload.hookSource = "kimi"
        payload.toolName = "Bash"

        // Anything but an immediate ack would mean a card nobody can answer.
        let response = try BridgeCommandClient(socketURL: socket).send(.processClaudeHook(payload), timeout: 2)
        #expect(response == .acknowledged)
    }
}
