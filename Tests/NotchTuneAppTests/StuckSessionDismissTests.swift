import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

/// A local session nothing else will clear can be dismissed by hand, but not
/// one with a live request: that would hide a blocked agent.
@MainActor
@Suite(.serialized)
struct StuckSessionDismissTests {
    private let now = Date()

    private func session(
        phase: SessionPhase,
        request: PermissionRequest? = nil,
        quietFor seconds: TimeInterval = 0
    ) -> AgentSession {
        AgentSession(
            id: "s1",
            title: "s1",
            tool: .claudeCode,
            phase: phase,
            summary: "",
            updatedAt: now.addingTimeInterval(-seconds),
            permissionRequest: request
        )
    }

    @Test
    func aGhostApprovalIsDismissible() {
        #expect(session(phase: .waitingForApproval).isDismissibleLocally(at: now))
        #expect(session(phase: .waitingForAnswer).isDismissibleLocally(at: now))
    }

    @Test
    func aLiveRequestIsNot() {
        let request = PermissionRequest(title: "t", summary: "s", affectedPath: "")
        let session = session(phase: .waitingForApproval, request: request, quietFor: 86_000)

        #expect(!session.isDismissibleLocally(at: now))
    }

    @Test
    func aRunningSessionOnlyOnceItHasGoneQuiet() {
        #expect(!session(phase: .running, quietFor: 60).isDismissibleLocally(at: now))
        #expect(session(phase: .running, quietFor: AgentSession.stuckSessionThreshold).isDismissibleLocally(at: now))
    }

    @Test
    func remoteAndDemoRowsAreLeftToTheirOwnControls() {
        var remote = session(phase: .waitingForApproval)
        remote.isRemote = true
        #expect(!remote.isDismissibleLocally(at: now))

        var demo = session(phase: .waitingForApproval)
        demo.origin = .demo
        #expect(!demo.isDismissibleLocally(at: now))
    }

    @Test
    func dismissingRemovesTheRowFromTheIsland() {
        var hookManaged = session(phase: .waitingForApproval)
        hookManaged.isHookManaged = true
        var polled = session(phase: .waitingForAnswer)
        polled.id = "s2"

        var state = SessionState(sessions: [hookManaged, polled])
        state.dismissSession(id: "s1")
        state.dismissSession(id: "s2")

        #expect(state.session(id: "s1")?.isVisibleInIsland == false)
        #expect(state.session(id: "s2")?.isVisibleInIsland == false)
        #expect(state.session(id: "s1")?.phase == .completed)
    }

    @Test
    func aPolledSessionThatIsReallyAliveComesBack() {
        var state = SessionState(sessions: [session(phase: .running, quietFor: 3_600)])
        state.dismissSession(id: "s1")

        state.markProcessLiveness(aliveSessionIDs: ["s1"])

        #expect(state.session(id: "s1")?.isVisibleInIsland == true)
    }
}
