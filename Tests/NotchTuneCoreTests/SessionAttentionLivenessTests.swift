import Foundation
import Testing
@testable import NotchTuneCore

/// An agent blocked on the user must survive liveness polling, and an
/// attention phase with nothing behind it must not survive anything.
struct SessionAttentionLivenessTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func hookManagedSession(
        phase: SessionPhase,
        request: PermissionRequest? = nil,
        prompt: QuestionPrompt? = nil
    ) -> AgentSession {
        var session = AgentSession(
            id: "s1",
            title: "Claude",
            tool: .claudeCode,
            phase: phase,
            summary: "Allow Bash?",
            updatedAt: now,
            permissionRequest: request,
            questionPrompt: prompt
        )
        session.isHookManaged = true
        return session
    }

    private let request = PermissionRequest(title: "Allow Bash", summary: "ls", affectedPath: "/tmp")

    @Test
    func aWaitingAgentNeverSeenByDiscoveryIsNotEnded() {
        var state = SessionState(sessions: [hookManagedSession(phase: .waitingForApproval, request: request)])

        for _ in 0..<5 {
            state.markProcessLiveness(aliveSessionIDs: [])
        }

        let session = state.session(id: "s1")
        #expect(session?.phase == .waitingForApproval)
        #expect(session?.isSessionEnded == false)
        #expect(session?.permissionRequest != nil)
    }

    @Test
    func anAgentWaitingOnAQuestionIsNotEnded() {
        let prompt = QuestionPrompt(title: "Which?", options: ["a"])
        var state = SessionState(sessions: [hookManagedSession(phase: .waitingForAnswer, prompt: prompt)])

        for _ in 0..<5 {
            state.markProcessLiveness(aliveSessionIDs: [])
        }

        #expect(state.session(id: "s1")?.phase == .waitingForAnswer)
    }

    @Test
    func aGhostWaitingPhaseStillEndsWhenTheProcessIsGone() {
        var state = SessionState(sessions: [hookManagedSession(phase: .waitingForApproval)])

        state.markProcessLiveness(aliveSessionIDs: [])
        state.markProcessLiveness(aliveSessionIDs: [])

        #expect(state.session(id: "s1")?.isSessionEnded == true)
        #expect(state.session(id: "s1")?.phase == .completed)
    }

    @Test
    func aRunningHookSessionStillEndsAfterTwoMissedTicks() {
        var state = SessionState(sessions: [hookManagedSession(phase: .running)])

        state.markProcessLiveness(aliveSessionIDs: [])
        #expect(state.session(id: "s1")?.isSessionEnded == false)
        state.markProcessLiveness(aliveSessionIDs: [])
        #expect(state.session(id: "s1")?.isSessionEnded == true)
    }

    @Test
    func restoredRecordsDropAttentionPhasesTheyCannotBackUp() {
        let session = AgentSession(
            id: "s1",
            title: "Agent",
            tool: .claudeCode,
            phase: .waitingForApproval,
            summary: "Allow Bash?",
            updatedAt: now
        )

        let restored = [
            ClaudeTrackedSessionRecord(session: session).restorableSession,
            CodexTrackedSessionRecord(session: session).restorableSession,
            OpenCodeTrackedSessionRecord(session: session).restorableSession,
            CursorTrackedSessionRecord(session: session).restorableSession,
        ]

        for session in restored {
            #expect(session.phase == .completed)
            #expect(session.attachmentState == .stale)
            #expect(!session.summary.contains("Allow Bash"))
        }
    }

    @Test
    func restoringKeepsPhasesThatNeedNoRequest() {
        for phase in [SessionPhase.running, .completed] {
            let session = AgentSession(
                id: "s1",
                title: "Agent",
                tool: .claudeCode,
                phase: phase,
                summary: "Working",
                updatedAt: now
            )
            let restored = ClaudeTrackedSessionRecord(session: session).restorableSession
            #expect(restored.phase == phase)
            #expect(restored.summary == "Working")
        }
    }

    @Test
    func aRestoredGhostLeavesTheIslandOnceItsSessionEnds() {
        var session = AgentSession(
            id: "s1",
            title: "Agent",
            tool: .claudeCode,
            phase: .waitingForAnswer,
            summary: "Which?",
            updatedAt: now
        ).withoutOrphanedAttention
        session.isProcessAlive = false

        #expect(!session.isVisibleInIsland)
    }
}
