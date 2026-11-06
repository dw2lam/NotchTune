import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

/// A reply is typed and entered as a command, so it may only ever reach the
/// session's own terminal.
@MainActor
@Suite(.serialized)
struct TerminalReplySafetyTests {
    private let now = Date()

    private func session(terminalApp: String = "Ghostty", terminalID: String? = "term-1", tmux: String? = nil) -> AgentSession {
        AgentSession(
            id: "s1",
            title: "Claude",
            tool: .claudeCode,
            phase: .completed,
            summary: "Done",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: terminalApp,
                workspaceName: "repo",
                paneTitle: "claude",
                workingDirectory: "/tmp/repo",
                terminalSessionID: terminalID,
                tmuxTarget: tmux
            )
        )
    }

    @Test
    func theGhosttyScriptMatchesOnlyTheExactTerminal() throws {
        let target = try #require(session().jumpTarget)
        let script = TerminalTextSender.ghosttySendScript(text: "ls", target: target)

        #expect(script.contains("(id of aTerminal as text) is \"term-1\""))
        #expect(!script.contains("working directory"))
        #expect(!script.contains("name of aTerminal"))
        #expect(!script.contains("/tmp/repo"))
    }

    @Test
    func aGhosttySessionWithoutAnIDIsNeverSentTo() {
        for missing in [nil, ""] as [String?] {
            let session = session(terminalID: missing)
            #expect(!TerminalTextSender.canReply(to: session, enabled: true))
            #expect(!TerminalTextSender.send("rm -rf build", to: session))
        }
    }

    @Test
    func repliesStayAvailableWhereTheTargetIsExact() {
        #expect(TerminalTextSender.canReply(to: session(), enabled: true))
        #expect(TerminalTextSender.canReply(to: session(terminalApp: "Terminal", terminalID: nil, tmux: "%3"), enabled: true))
        #expect(!TerminalTextSender.canReply(to: session(), enabled: false))
    }

    @Test
    func aFailedReplyPostsANoticeAndKeepsTheText() async throws {
        let model = makeModel()
        model.replySender = { _, _ in false }
        let session = session()
        model.state.insertSession(session)

        model.replyToSession(session, text: "keep going")
        try await waitUntil { model.unsentReplies["s1"] != nil }

        #expect(model.unsentReplies["s1"] == "keep going")
        #expect(model.notice?.message.contains("wasn't sent") == true)
    }

    @Test
    func aDeliveredReplyClearsAnEarlierFailure() async throws {
        let model = makeModel()
        model.replySender = { _, _ in true }
        let session = session()
        model.state.insertSession(session)
        model.unsentReplies["s1"] = "older attempt"

        model.replyToSession(session, text: "again")
        try await waitUntil { model.lastActionMessage.hasPrefix("Sent reply") }

        #expect(model.unsentReplies["s1"] == nil)
        #expect(model.notice == nil)
    }

    private func makeModel() -> AppModel {
        let model = AppModel(
            isNotificationSessionAlreadyFrontmost: { _ in false },
            frontmostBundleIdentifierProvider: { nil }
        )
        model.disablesOverlayEventMonitoringDuringHarness = true
        model.isSoundMuted = true
        return model
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
