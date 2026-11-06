import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

/// Only paths that fail before touching a config: these must never write to
/// the real ~/.claude and friends.
@MainActor
struct HookInstallationCoordinatorTests {
    private func makeCoordinator() -> HookInstallationCoordinator {
        let suite = "notchtune-coordinator-\(UUID().uuidString)"
        return HookInstallationCoordinator(intentStore: AgentIntentStore(defaults: UserDefaults(suiteName: suite)!))
    }

    @Test
    func aFailedInstallReachesTheUserAndTheAgentsRow() {
        let coordinator = makeCoordinator()
        var notices: [String] = []
        coordinator.onFailure = { notices.append($0) }

        coordinator.installClaudeHooks()

        #expect(notices.count == 1)
        #expect(coordinator.setupFailures[.claudeCode] == notices.first)
        #expect(coordinator.intentStore.intent(for: .claudeCode) == .untouched)
    }

    @Test
    func everyHookAgentReportsAMissingHelper() {
        let coordinator = makeCoordinator()
        var notices = 0
        coordinator.onFailure = { _ in notices += 1 }

        let binaryAgents = AgentIdentifier.hookAgents.filter { $0 != .openCode }
        for agent in binaryAgents {
            coordinator.installHooks(for: agent)
        }

        #expect(notices == binaryAgents.count)
        #expect(binaryAgents.allSatisfy { coordinator.setupFailures[$0] != nil })
    }

    @Test
    func aNoticeOffersAWayToSetup() {
        let model = AppModel()
        model.hooks.installCodexHooks()

        #expect(model.notice?.action == .openSetup)
        #expect(model.notice?.message.isEmpty == false)
    }

    @Test
    func sampleReportsSurviveARefresh() async throws {
        let coordinator = makeCoordinator()
        coordinator.loadSampleDoctorReports()
        let reports = coordinator.doctorReports

        coordinator.runHealthChecks()
        try await Task.sleep(for: .milliseconds(50))

        #expect(coordinator.doctorReports == reports)
    }

    @Test
    func installAllNeverOffersTheUsageBridgeWithoutClaude() {
        let coordinator = makeCoordinator()
        let agents = coordinator.installAllAgents
        #expect(!agents.contains(.claudeUsageBridge) || agents.contains(.claudeCode))
    }
}
