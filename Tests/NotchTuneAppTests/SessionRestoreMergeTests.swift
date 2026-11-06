import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

/// Startup restore runs after off-main I/O, so hook events can land first.
@MainActor
struct SessionRestoreMergeTests {
    private let now = Date()

    private func payload(
        codex: [CodexTrackedSessionRecord] = [],
        claude: [ClaudeTrackedSessionRecord] = [],
        discoveredCodex: [CodexTrackedSessionRecord] = []
    ) -> SessionDiscoveryCoordinator.StartupDiscoveryPayload {
        .init(
            codexRecords: codex,
            codexRecordsNeedPrune: false,
            claudeRecords: claude,
            claudeRecordsNeedPrune: false,
            openCodeRecords: [],
            openCodeRecordsNeedPrune: false,
            cursorRecords: [],
            cursorRecordsNeedPrune: false,
            discoveredCodexRecords: discoveredCodex,
            discoveredClaudeSessions: [],
            hooksBinaryURL: nil
        )
    }

    private func session(
        _ id: String,
        tool: AgentTool = .codex,
        phase: SessionPhase,
        request: PermissionRequest? = nil,
        updatedAt: Date
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            tool: tool,
            phase: phase,
            summary: id,
            updatedAt: updatedAt,
            permissionRequest: request
        )
    }

    private func coordinator(holding initial: [AgentSession]) -> (SessionDiscoveryCoordinator, () -> SessionState) {
        let coordinator = SessionDiscoveryCoordinator()
        final class Box { var state = SessionState() }
        let box = Box()
        box.state = SessionState(sessions: initial)
        coordinator.stateAccessor = { box.state }
        coordinator.stateUpdater = { box.state = $0 }
        return (coordinator, { box.state })
    }

    @Test
    func codexRestoreKeepsAHookEventThatLandedDuringStartupIO() {
        let request = PermissionRequest(title: "Allow Bash", summary: "ls", affectedPath: "/tmp")
        let live = session("live", tool: .claudeCode, phase: .waitingForApproval, request: request, updatedAt: now)
        let (coordinator, state) = coordinator(holding: [live])

        let restored = session("restored", phase: .running, updatedAt: now.addingTimeInterval(-60))
        coordinator.applyStartupDiscoveryPayload(payload(codex: [CodexTrackedSessionRecord(session: restored)]))

        #expect(state().session(id: "live")?.permissionRequest == request)
        #expect(state().session(id: "restored") != nil)
    }

    @Test
    func restoreDemotesAGhostButNotALiveRequestForTheSameSession() {
        let request = PermissionRequest(title: "Allow Bash", summary: "ls", affectedPath: "/tmp")
        let live = session("s1", phase: .waitingForApproval, request: request, updatedAt: now)
        let (coordinator, state) = coordinator(holding: [live])

        let persisted = session("s1", phase: .waitingForApproval, updatedAt: now.addingTimeInterval(5))
        let ghost = session("ghost", phase: .waitingForApproval, updatedAt: now)
        coordinator.applyStartupDiscoveryPayload(payload(codex: [
            CodexTrackedSessionRecord(session: persisted),
            CodexTrackedSessionRecord(session: ghost),
        ]))

        #expect(state().session(id: "s1")?.phase == .waitingForApproval)
        #expect(state().session(id: "s1")?.permissionRequest == request)
        #expect(state().session(id: "ghost")?.phase == .completed)
    }
}
