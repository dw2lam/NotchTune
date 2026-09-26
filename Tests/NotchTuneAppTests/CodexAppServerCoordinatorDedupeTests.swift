import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

/// The Codex app-server re-sends `thread/status/changed` with the same
/// `waitingOnApproval` / `waitingOnUserInput` flag on every status tick.
/// The coordinator must emit the attention event once per waiting phase
/// and again only after the thread has left that phase.
@MainActor
struct CodexAppServerCoordinatorDedupeTests {
    private func status(_ json: String) throws -> CodexThreadStatus {
        try JSONDecoder().decode(CodexThreadStatus.self, from: Data(json.utf8))
    }

    private func makeCoordinator() -> (CodexAppServerCoordinator, () -> [AgentEvent]) {
        let coordinator = CodexAppServerCoordinator()
        final class Box: @unchecked Sendable { var events: [AgentEvent] = [] }
        let box = Box()
        coordinator.onEvent = { box.events.append($0) }
        return (coordinator, { box.events })
    }

    private func isPermissionRequested(_ event: AgentEvent) -> Bool {
        if case .permissionRequested = event { return true }
        return false
    }

    private func isQuestionAsked(_ event: AgentEvent) -> Bool {
        if case .questionAsked = event { return true }
        return false
    }

    @Test
    func repeatedWaitingOnApprovalEmitsPermissionRequestedOnce() throws {
        let (coordinator, events) = makeCoordinator()
        let waiting = try status(#"{"type":"active","activeFlags":["waitingOnApproval"]}"#)

        coordinator.handleNotification(.threadStatusChanged(threadId: "t1", status: waiting))
        coordinator.handleNotification(.threadStatusChanged(threadId: "t1", status: waiting))
        coordinator.handleNotification(.threadStatusChanged(threadId: "t1", status: waiting))

        #expect(events().filter(isPermissionRequested).count == 1)
    }

    @Test
    func leavingWaitingPhaseReArmsTheNextApproval() throws {
        let (coordinator, events) = makeCoordinator()
        let waiting = try status(#"{"type":"active","activeFlags":["waitingOnApproval"]}"#)
        let working = try status(#"{"type":"active","activeFlags":[]}"#)

        coordinator.handleNotification(.threadStatusChanged(threadId: "t1", status: waiting))
        coordinator.handleNotification(.threadStatusChanged(threadId: "t1", status: working))
        coordinator.handleNotification(.threadStatusChanged(threadId: "t1", status: waiting))

        #expect(events().filter(isPermissionRequested).count == 2)
    }

    @Test
    func switchingBetweenApprovalAndAnswerEmitsEachOnce() throws {
        let (coordinator, events) = makeCoordinator()
        let approval = try status(#"{"type":"active","activeFlags":["waitingOnApproval"]}"#)
        let answer = try status(#"{"type":"active","activeFlags":["waitingOnUserInput"]}"#)

        coordinator.handleNotification(.threadStatusChanged(threadId: "t1", status: approval))
        coordinator.handleNotification(.threadStatusChanged(threadId: "t1", status: answer))
        coordinator.handleNotification(.threadStatusChanged(threadId: "t1", status: answer))

        #expect(events().filter(isPermissionRequested).count == 1)
        #expect(events().filter(isQuestionAsked).count == 1)
    }

    @Test
    func dedupeIsPerThread() throws {
        let (coordinator, events) = makeCoordinator()
        let waiting = try status(#"{"type":"active","activeFlags":["waitingOnApproval"]}"#)

        coordinator.handleNotification(.threadStatusChanged(threadId: "t1", status: waiting))
        coordinator.handleNotification(.threadStatusChanged(threadId: "t2", status: waiting))

        #expect(events().filter(isPermissionRequested).count == 2)
    }
}
