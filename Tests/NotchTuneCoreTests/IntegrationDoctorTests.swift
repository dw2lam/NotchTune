import Foundation
import Testing
@testable import NotchTuneCore

struct IntegrationDoctorTests {
    private let fileManager = FileManager.default

    private func scratchDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("notchtune-doctor-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func descriptor(_ agent: AgentIdentifier, home: URL) throws -> HookAgentDescriptor {
        try #require(HookAgentCatalog.descriptors(home: home, claudeDirectory: home.appendingPathComponent(".claude")).first { $0.agent == agent })
    }

    private func input(
        hooksPresent: Bool = true,
        intent: AgentHookIntent = .installed,
        issues: [HookHealthReport.Issue] = [],
        lastEventAt: Date? = nil,
        configure: (inout IntegrationDoctor.Input) -> Void = { _ in }
    ) throws -> IntegrationDoctor.Input {
        var result = IntegrationDoctor.Input(
            descriptor: try descriptor(.claudeCode, home: URL(fileURLWithPath: "/tmp/home")),
            intent: intent,
            hooksPresent: hooksPresent,
            toolPresent: true,
            health: HookHealthReport(agent: "claudeCode", issues: issues),
            lastEventAt: lastEventAt
        )
        configure(&result)
        return result
    }

    // MARK: Catalog

    @Test
    func theCatalogCoversEveryHookAgent() throws {
        let agents = HookAgentCatalog.descriptors(home: URL(fileURLWithPath: "/tmp/home")).map(\.agent)
        #expect(Set(agents) == Set(AgentIdentifier.hookAgents))
        #expect(agents.count == 11)
    }

    @Test
    func detectionNeedsTheToolNotJustASharedFolder() throws {
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        // Antigravity creates ~/.gemini too; that alone isn't Gemini CLI.
        try fileManager.createDirectory(at: home.appendingPathComponent(".gemini/antigravity"), withIntermediateDirectories: true)

        #expect(HookAgentCatalog.isToolPresent(try descriptor(.antigravity, home: home), home: home))
        var gemini = try descriptor(.gemini, home: home)
        gemini.executableNames = ["definitely-not-installed"]
        #expect(!HookAgentCatalog.isToolPresent(gemini, home: home))
    }

    @Test
    func aMissingToolIsNotDetected() throws {
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        var codebuddy = try descriptor(.codebuddy, home: home)
        codebuddy.executableNames = ["definitely-not-installed"]
        #expect(!HookAgentCatalog.isToolPresent(codebuddy, home: home))
    }

    @Test
    func kimiPrefersTheCurrentDirectoryAndKeepsTheOldOneWorking() throws {
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        #expect(KimiHookInstallationManager.resolvedDirectory(home: home).lastPathComponent == ".kimi-code")

        try fileManager.createDirectory(at: home.appendingPathComponent(".kimi"), withIntermediateDirectories: true)
        #expect(KimiHookInstallationManager.resolvedDirectory(home: home).lastPathComponent == ".kimi")

        try fileManager.createDirectory(at: home.appendingPathComponent(".kimi-code"), withIntermediateDirectories: true)
        #expect(KimiHookInstallationManager.resolvedDirectory(home: home).lastPathComponent == ".kimi-code")
    }

    @Test
    func kimiHooksUseOnlyFieldsItsConfigAccepts() {
        // Kimi refuses to load a config with extra fields in [[hooks]].
        let contents = KimiHookInstaller.installConfigTOML(existingContents: nil, hookCommand: "'/x/NotchTuneHooks' --source kimi").contents ?? ""
        let keys = Set(contents
            .components(separatedBy: "\n")
            .filter { $0.contains("=") && !$0.hasPrefix("#") }
            .compactMap { $0.split(separator: " ").first.map(String.init) })
        #expect(keys.isSubset(of: ["event", "command", "matcher", "timeout"]))
        #expect(!contents.contains("PermissionRequest"))
    }

    // MARK: Status

    @Test
    func statusFollowsWhatActuallyHappened() throws {
        #expect(IntegrationDoctor.diagnose(try input(lastEventAt: .now)).status == .working)
        #expect(IntegrationDoctor.diagnose(try input()).status == .noEventsYet)
        #expect(IntegrationDoctor.diagnose(try input(hooksPresent: false, intent: .untouched)).status == .notInstalled)
        #expect(IntegrationDoctor.diagnose(try input(hooksPresent: false, intent: .uninstalled)).status == .notInstalled)
    }

    @Test
    func hooksTheUserAskedForButLostNeedRepair() throws {
        let result = IntegrationDoctor.diagnose(try input(hooksPresent: false))
        #expect(result.status == .needsRepair)
        #expect(result.findings == [.hooksMissing])
        #expect(result.fix == .reinstall)
    }

    @Test
    func anOptedOutAgentHasNothingToRepair() throws {
        let result = IntegrationDoctor.diagnose(try input(
            hooksPresent: false,
            intent: .uninstalled,
            issues: [.pluginMissing(expectedPath: "/x"), .binaryNotFound]
        ))
        #expect(result.status == .notInstalled)
        #expect(result.findings.isEmpty)
    }

    @Test
    func aPastEventDoesNotHideACurrentProblem() throws {
        let result = IntegrationDoctor.diagnose(try input(
            issues: [.staleCommandPath(recorded: "/gone", configPath: "/c")],
            lastEventAt: .now
        ))
        #expect(result.status == .needsRepair)
        #expect(result.findings == [.staleCommand(path: "/gone")])
    }

    @Test
    func aMissingManifestAloneIsNotAProblemToShow() throws {
        let result = IntegrationDoctor.diagnose(try input(issues: [.manifestMissing(expectedPath: "/m")], lastEventAt: .now))
        #expect(result.status == .working)
    }

    @Test
    func aMalformedConfigPointsAtTheFileNotAReinstall() throws {
        let result = IntegrationDoctor.diagnose(try input(issues: [.configMalformedJSON(path: "/c")]))
        guard case .openConfig = result.fix else {
            Issue.record("expected openConfig, got \(String(describing: result.fix))")
            return
        }
    }

    @Test
    func claudePolicyIsExplained() throws {
        let disabled = IntegrationDoctor.diagnose(try input { $0.claudePolicy = ClaudeHookPolicy(disableAllHooks: true) })
        #expect(disabled.findings == [.claudeHooksDisabled])
        #expect(disabled.status == .needsRepair)

        let managed = IntegrationDoctor.diagnose(try input { $0.claudePolicy = ClaudeHookPolicy(allowManagedHooksOnly: true) })
        #expect(managed.findings == [.claudeManagedHooksOnly])
    }

    @Test
    func claudePolicyReadsUserAndManagedSettings() throws {
        let root = try scratchDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let managed = root.appendingPathComponent("managed.json")
        try Data(#"{"disableAllHooks":true}"#.utf8).write(to: root.appendingPathComponent("settings.json"))
        #expect(ClaudeHookPolicy.read(claudeDirectory: root, managedSettingsURL: managed) == ClaudeHookPolicy(disableAllHooks: true))

        try Data(#"{"allowManagedHooksOnly":true}"#.utf8).write(to: managed)
        #expect(ClaudeHookPolicy.read(claudeDirectory: root, managedSettingsURL: managed).allowManagedHooksOnly)
    }

    @Test
    func codexReviewCannotBeFixedForTheUser() throws {
        let result = IntegrationDoctor.diagnose(try input { $0.codexTrust = .needsReview(count: 4) })
        #expect(result.findings == [.codexHooksNeedReview(count: 4)])
        #expect(result.status == .needsRepair)
        #expect(result.fix == nil)
    }

    @Test
    func anUnknownTrustAnswerClaimsNothing() throws {
        #expect(IntegrationDoctor.diagnose(try input(lastEventAt: .now) { $0.codexTrust = .unknown }).status == .working)
    }

    @Test
    func droppedEventsAreCounted() throws {
        let drops = HookDropLog.Entry(count: 3, lastDroppedAt: .now, lastEvent: "Stop", lastField: "session_id")
        let result = IntegrationDoctor.diagnose(try input { $0.drops = drops })
        #expect(result.droppedEvents == 3)
        #expect(result.lastDroppedEvent == "Stop")
    }

    // MARK: Codex trust

    private func hooksList(_ hooks: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["id": 2, "result": ["data": [["hooks": hooks]]]])
    }

    @Test
    func codexTrustReadsTheShapeHooksListReturns() throws {
        let trusted: [String: Any] = ["command": "'/x/NotchTuneHooks'", "trustStatus": "trusted", "enabled": true, "isManaged": false]
        let untrusted: [String: Any] = ["command": "'/x/NotchTuneHooks'", "trustStatus": "untrusted", "enabled": true, "isManaged": false]
        let modified: [String: Any] = ["command": "'/x/NotchTuneHooks'", "trustStatus": "modified", "enabled": true, "isManaged": false]
        let theirs: [String: Any] = ["command": "/usr/local/bin/other", "trustStatus": "untrusted", "enabled": true, "isManaged": false]

        #expect(CodexHookTrustProbe.trust(fromHooksList: try hooksList([trusted, theirs])) == .trusted)
        #expect(CodexHookTrustProbe.trust(fromHooksList: try hooksList([trusted, untrusted, modified])) == .needsReview(count: 2))
        #expect(CodexHookTrustProbe.trust(fromHooksList: try hooksList([theirs])) == .unknown)
        #expect(CodexHookTrustProbe.trust(fromHooksList: Data("{\"error\":{}}".utf8)) == .unknown)
    }

    @Test
    func managedHooksDontNeedReview() throws {
        let managed: [String: Any] = ["command": "'/x/NotchTuneHooks'", "trustStatus": "managed", "enabled": true, "isManaged": true]
        #expect(CodexHookTrustProbe.trust(fromHooksList: try hooksList([managed])) == .trusted)
    }

    /// Env-gated: spawns the real `codex` against a throwaway CODEX_HOME.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NOTCHTUNE_CODEX_INTEGRATION"] == "1"))
    func realCodexReportsFreshHooksAsNeedingReview() throws {
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        let manager = CodexHookInstallationManager(
            codexDirectory: home,
            managedHooksBinaryURL: home.appendingPathComponent("managed/NotchTuneHooks"),
            featureKeyProvider: { .current }
        )
        let binary = home.appendingPathComponent("NotchTuneHooks")
        try Data("#!/bin/sh\n".utf8).write(to: binary)
        try manager.install(hooksBinaryURL: binary)

        #expect(CodexHookTrustProbe.check(codexDirectory: home) == .needsReview(count: 4))
    }

    // MARK: Repair

    @Test
    func repairSkipsEveryAgentTheUserDidNotAskFor() {
        let report = HookHealthReport(agent: "x", issues: [.pluginMissing(expectedPath: "/p")])
        let reports: [AgentIdentifier: HookHealthReport] = [.openCode: report, .claudeCode: report, .codex: report]
        let intents: [AgentIdentifier: AgentHookIntent] = [.openCode: .untouched, .claudeCode: .uninstalled, .codex: .installed]

        let agents = HookRepairPolicy.agentsToRepair(
            reports: reports,
            intent: { intents[$0] ?? .untouched },
            hooksBinaryAvailable: true
        )
        #expect(agents == [.codex])
    }

    @Test
    func openCodeRepairNeedsNoHooksBinary() {
        let report = HookHealthReport(agent: "x", issues: [.pluginOutdated(path: "/p")])
        let agents = HookRepairPolicy.agentsToRepair(
            reports: [.openCode: report, .claudeCode: report],
            intent: { _ in .installed },
            hooksBinaryAvailable: false
        )
        #expect(agents == [.openCode])
    }

    @Test
    func healthChecksCoverTheAgentsThatHadNone() throws {
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        let binary = home.appendingPathComponent("NotchTuneHooks")
        try Data("#!/bin/sh\n".utf8).write(to: binary)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        // Cursor keeps commands flat; Antigravity nests them under a group.
        let cursor = try descriptor(.cursor, home: home)
        try fileManager.createDirectory(at: cursor.directory, withIntermediateDirectories: true)
        try Data(#"{"version":1,"hooks":{"stop":[{"command":"'/gone/NotchTuneHooks' --source cursor"}]}}"#.utf8).write(to: cursor.configURL)
        let cursorReport = HookHealthCheck.check(cursor, hooksBinaryURL: binary, managedHooksBinaryURL: binary)
        #expect(cursorReport.errors == [.staleCommandPath(recorded: "/gone/NotchTuneHooks", configPath: cursor.configURL.path)])

        let antigravity = try descriptor(.antigravity, home: home)
        try fileManager.createDirectory(at: antigravity.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: antigravity.configURL)
        #expect(HookHealthCheck.check(antigravity, hooksBinaryURL: binary, managedHooksBinaryURL: binary).errors
            == [.configMalformedJSON(path: antigravity.configURL.path)])

        // Kimi's commands live in TOML.
        let kimi = try descriptor(.kimi, home: home)
        try fileManager.createDirectory(at: kimi.directory, withIntermediateDirectories: true)
        try Data("[[hooks]]\nevent = \"Stop\"\ncommand = \"'/gone/NotchTuneHooks' --source kimi\"\n".utf8).write(to: kimi.configURL)
        #expect(HookHealthCheck.check(kimi, hooksBinaryURL: binary, managedHooksBinaryURL: binary).errors
            == [.staleCommandPath(recorded: "/gone/NotchTuneHooks", configPath: kimi.configURL.path)])
    }

    @Test
    func aThirdPartyCommandIsNeverCalledStale() throws {
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        let binary = home.appendingPathComponent("NotchTuneHooks")
        try Data("#!/bin/sh\n".utf8).write(to: binary)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let gemini = try descriptor(.gemini, home: home)
        try fileManager.createDirectory(at: gemini.directory, withIntermediateDirectories: true)
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"command":"/gone/other-tool"}]}]}}"#.utf8).write(to: gemini.configURL)
        #expect(HookHealthCheck.check(gemini, hooksBinaryURL: binary, managedHooksBinaryURL: binary).isHealthy)
    }

    @Test
    func anOutdatedPluginIsRepairable() throws {
        let home = try scratchDirectory()
        defer { try? fileManager.removeItem(at: home) }

        let openCode = try descriptor(.openCode, home: home)
        try fileManager.createDirectory(at: openCode.configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("// Open Island plugin for OpenCode\n".utf8).write(to: openCode.configURL)

        let report = HookHealthCheck.check(openCode)
        #expect(report.repairableIssues == [.pluginOutdated(path: openCode.configURL.path)])
    }

    // MARK: Drop log and activity

    @Test
    func dropsAccumulatePerSourceWithoutThePayload() throws {
        let root = try scratchDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let log = HookDropLog(url: root.appendingPathComponent("drops.json"))
        log.record(source: "claude", event: "Stop", field: "session_id")
        log.record(source: "claude", event: "PreToolUse", field: nil)
        log.record(source: "codex", event: nil, field: nil)

        let entries = log.read()
        #expect(entries["claude"]?.count == 2)
        #expect(entries["claude"]?.lastEvent == "PreToolUse")
        #expect(entries["codex"]?.count == 1)

        let permissions = try fileManager.attributesOfItem(atPath: log.url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test
    func dropFieldPathNamesTheKeyNotTheValue() {
        struct Payload: Decodable { var session_id: String }
        do {
            _ = try JSONDecoder().decode(Payload.self, from: Data(#"{"prompt":"my secret"}"#.utf8))
            Issue.record("expected a failure")
        } catch {
            #expect(HookDropLog.fieldPath(of: error) == "session_id")
        }
        #expect(HookDropLog.eventName(in: Data(#"{"hook_event_name":"Stop"}"#.utf8)) == "Stop")
        #expect(HookDropLog.eventName(in: Data("not json".utf8)) == nil)
    }

    @Test
    func activitySurvivesARestart() throws {
        let root = try scratchDirectory()
        defer { try? fileManager.removeItem(at: root) }

        let url = root.appendingPathComponent("activity.json")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        HookActivityStore(url: url).record(.codex, at: date)

        #expect(HookActivityStore(url: url).lastEvent(for: .codex) == date)
        #expect(HookActivityStore(url: url).lastEvent(for: .cursor) == nil)
    }

    @Test
    func sourcesMapToTheirAgents() {
        #expect(AgentIdentifier(hookSource: "claude") == .claudeCode)
        #expect(AgentIdentifier(hookSource: "droid") == .factory)
        #expect(AgentIdentifier(hookSource: "qwen") == .qwenCode)
        #expect(AgentIdentifier(hookSource: "nope") == nil)
    }
}
