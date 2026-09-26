import Foundation
import Testing
@testable import NotchTuneCore

/// Pins `BridgeServer.codexStopEvent(for:timestamp:)`: a Codex `Stop` hook
/// with `stop_hook_active == true` is a continuation of the same turn, not a
/// fresh completion, so it must settle the session without producing the
/// notification-bearing `sessionCompleted` event.
struct BridgeServerCodexStopTests {
    private let timestamp = Date(timeIntervalSince1970: 1_000)

    private func stopPayload(stopHookActive: Bool?) -> CodexHookPayload {
        var payload = CodexHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .stop,
            model: "gpt-5",
            permissionMode: .default,
            sessionID: "codex-1",
            transcriptPath: "/tmp/demo/rollout.jsonl"
        )
        payload.stopHookActive = stopHookActive
        payload.lastAssistantMessage = "All done."
        return payload
    }

    @Test
    func plainStopEmitsSessionCompleted() {
        let event = BridgeServer.codexStopEvent(for: stopPayload(stopHookActive: nil), timestamp: timestamp)
        #expect(event == .sessionCompleted(SessionCompleted(sessionID: "codex-1", summary: "All done.", timestamp: timestamp)))
    }

    @Test
    func stopWithInactiveStopHookEmitsSessionCompleted() {
        let event = BridgeServer.codexStopEvent(for: stopPayload(stopHookActive: false), timestamp: timestamp)
        guard case .sessionCompleted = event else {
            Issue.record("expected sessionCompleted, got \(event)")
            return
        }
    }

    @Test
    func stopWithActiveStopHookSettlesWithoutAFreshCompletion() {
        let event = BridgeServer.codexStopEvent(for: stopPayload(stopHookActive: true), timestamp: timestamp)
        #expect(event == .activityUpdated(SessionActivityUpdated(
            sessionID: "codex-1",
            summary: "All done.",
            phase: .completed,
            timestamp: timestamp
        )))

        // State still ends up completed, so nothing reads as "running" forever.
        var state = SessionState()
        state.apply(.sessionStarted(SessionStarted(
            sessionID: "codex-1",
            title: "Codex",
            tool: .codex,
            summary: "",
            timestamp: timestamp
        )))
        state.apply(.activityUpdated(SessionActivityUpdated(sessionID: "codex-1", summary: "", phase: .running, timestamp: timestamp)))
        state.apply(event)
        #expect(state.session(id: "codex-1")?.phase == .completed)
        #expect(state.session(id: "codex-1")?.summary == "All done.")
    }
}
