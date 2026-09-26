import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

/// Pure-logic tests for `NotificationCoalescer`. Time is passed in
/// explicitly, so no test sleeps.
struct NotificationCoalescerTests {
    private let t0 = Date(timeIntervalSince1970: 10_000)
    private let codexA = NotificationGroupKey(tool: .codex, workspace: "/tmp/a")
    private let codexB = NotificationGroupKey(tool: .codex, workspace: "/tmp/b")

    private func completion(_ id: String) -> SessionCompleted {
        SessionCompleted(sessionID: id, summary: "done", timestamp: t0)
    }

    private func makeCoalescer() -> NotificationCoalescer {
        NotificationCoalescer(policy: NotificationCoalescingPolicy(
            completionSettleSeconds: 1.5,
            groupCooldownSeconds: 20,
            globalMinimumIntervalSeconds: 3
        ))
    }

    // MARK: Completions: debounce

    @Test
    func heldCompletionPresentsOnceSettled() {
        var c = makeCoalescer()
        let deadline = c.holdCompletion(completion("s1"), group: codexA, now: t0)

        #expect(deadline == t0.addingTimeInterval(1.5))
        #expect(c.pendingCompletion(in: codexA)?.payload.sessionID == "s1")

        let settled = c.settleCompletion(in: codexA, isAlreadyPresented: false, now: deadline)
        #expect(settled?.payload.sessionID == "s1")
        #expect(settled?.decision == .present)
        #expect(c.pendingCompletion(in: codexA) == nil)
    }

    @Test
    func runningSignalWithinSettleWindowCancelsPendingCompletion() {
        var c = makeCoalescer()
        c.holdCompletion(completion("s1"), group: codexA, now: t0)

        let cancelled = c.cancelPendingCompletion(in: codexA)
        #expect(cancelled?.sessionID == "s1")

        // The timer firing afterwards finds nothing to present.
        let settled = c.settleCompletion(in: codexA, isAlreadyPresented: false, now: t0.addingTimeInterval(1.5))
        #expect(settled == nil)
    }

    @Test
    func newerCompletionInSameGroupSupersedesPendingOne() {
        var c = makeCoalescer()
        c.holdCompletion(completion("thread-1"), group: codexA, now: t0)
        c.holdCompletion(completion("thread-2"), group: codexA, now: t0.addingTimeInterval(0.4))

        #expect(c.pendingCompletions.count == 1)
        let settled = c.settleCompletion(in: codexA, isAlreadyPresented: false, now: t0.addingTimeInterval(1.9))
        #expect(settled?.payload.sessionID == "thread-2")
        #expect(settled?.decision == .present)
    }

    // MARK: Completions: cooldown + rate limit

    @Test
    func completionInsideGroupCooldownIsSubtle() {
        var c = makeCoalescer()
        c.holdCompletion(completion("s1"), group: codexA, now: t0)
        _ = c.settleCompletion(in: codexA, isAlreadyPresented: false, now: t0.addingTimeInterval(1.5))

        let later = t0.addingTimeInterval(10)
        c.holdCompletion(completion("s1"), group: codexA, now: later)
        let second = c.settleCompletion(in: codexA, isAlreadyPresented: false, now: later.addingTimeInterval(1.5))
        #expect(second?.decision == .subtle)

        // Past the cooldown the group bumps again.
        let muchLater = t0.addingTimeInterval(30)
        c.holdCompletion(completion("s1"), group: codexA, now: muchLater)
        let third = c.settleCompletion(in: codexA, isAlreadyPresented: false, now: muchLater.addingTimeInterval(1.5))
        #expect(third?.decision == .present)
    }

    @Test
    func subtleCompletionDoesNotExtendCooldown() {
        var c = makeCoalescer()
        c.holdCompletion(completion("s1"), group: codexA, now: t0)
        _ = c.settleCompletion(in: codexA, isAlreadyPresented: false, now: t0.addingTimeInterval(1.5))

        // Subtle at +15s must not push the cooldown out to +35s.
        c.holdCompletion(completion("s1"), group: codexA, now: t0.addingTimeInterval(15))
        #expect(c.settleCompletion(in: codexA, isAlreadyPresented: false, now: t0.addingTimeInterval(16.5))?.decision == .subtle)

        c.holdCompletion(completion("s1"), group: codexA, now: t0.addingTimeInterval(22))
        #expect(c.settleCompletion(in: codexA, isAlreadyPresented: false, now: t0.addingTimeInterval(23.5))?.decision == .present)
    }

    @Test
    func globalRateLimitDowngradesOtherGroupsWithinThreeSeconds() {
        var c = makeCoalescer()
        c.holdCompletion(completion("a"), group: codexA, now: t0)
        #expect(c.settleCompletion(in: codexA, isAlreadyPresented: false, now: t0.addingTimeInterval(1.5))?.decision == .present)

        // A different group settling 1s later is rate-limited.
        c.holdCompletion(completion("b"), group: codexB, now: t0.addingTimeInterval(1))
        #expect(c.settleCompletion(in: codexB, isAlreadyPresented: false, now: t0.addingTimeInterval(2.5))?.decision == .subtle)

        // Once 3s have elapsed since the last full bump, a third group presents.
        let claude = NotificationGroupKey(tool: .claudeCode, workspace: "/tmp/c")
        c.holdCompletion(completion("c"), group: claude, now: t0.addingTimeInterval(3.5))
        #expect(c.settleCompletion(in: claude, isAlreadyPresented: false, now: t0.addingTimeInterval(5))?.decision == .present)
    }

    @Test
    func completionAlreadyOnScreenIsSuppressed() {
        var c = makeCoalescer()
        c.holdCompletion(completion("s1"), group: codexA, now: t0)
        let settled = c.settleCompletion(in: codexA, isAlreadyPresented: true, now: t0.addingTimeInterval(1.5))
        #expect(settled?.decision == .suppress)

        // Suppression is not a bump: the group is still free to present.
        c.holdCompletion(completion("s1"), group: codexA, now: t0.addingTimeInterval(2))
        #expect(c.settleCompletion(in: codexA, isAlreadyPresented: false, now: t0.addingTimeInterval(3.5))?.decision == .present)
    }

    // MARK: Approvals / questions

    @Test
    func firstApprovalAlwaysPresentsEvenInsideCooldownAndRateLimit() {
        var c = makeCoalescer()
        c.holdCompletion(completion("s1"), group: codexA, now: t0)
        _ = c.settleCompletion(in: codexA, isAlreadyPresented: false, now: t0.addingTimeInterval(1.5))

        let decision = c.decideRequest(
            group: codexA,
            isRepeatOfPendingRequest: false,
            isAlreadyPresented: false,
            now: t0.addingTimeInterval(2)
        )
        #expect(decision == .present)
    }

    @Test
    func repeatOfPendingApprovalIsSuppressed() {
        var c = makeCoalescer()
        #expect(c.decideRequest(group: codexA, isRepeatOfPendingRequest: false, isAlreadyPresented: false, now: t0) == .present)
        #expect(c.decideRequest(group: codexA, isRepeatOfPendingRequest: true, isAlreadyPresented: false, now: t0.addingTimeInterval(1)) == .suppress)
    }

    @Test
    func approvalForCardAlreadyOnScreenIsSuppressed() {
        var c = makeCoalescer()
        #expect(c.decideRequest(group: codexA, isRepeatOfPendingRequest: false, isAlreadyPresented: true, now: t0) == .suppress)
    }

    @Test
    func approvalBumpStartsGroupCooldownForCompletions() {
        var c = makeCoalescer()
        #expect(c.decideRequest(group: codexA, isRepeatOfPendingRequest: false, isAlreadyPresented: false, now: t0) == .present)

        c.holdCompletion(completion("s1"), group: codexA, now: t0.addingTimeInterval(5))
        #expect(c.settleCompletion(in: codexA, isAlreadyPresented: false, now: t0.addingTimeInterval(6.5))?.decision == .subtle)
    }

    // MARK: Grouping

    private func session(
        id: String,
        tool: AgentTool = .codex,
        cwd: String? = nil,
        workspaceName: String = "ws"
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            tool: tool,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "",
            updatedAt: t0,
            jumpTarget: cwd.map {
                JumpTarget(terminalApp: "Ghostty", workspaceName: workspaceName, paneTitle: id, workingDirectory: $0)
            }
        )
    }

    @Test
    func siblingSessionsInSameToolAndCwdShareAGroup() {
        let a = NotificationGroupKey(session: session(id: "thread-1", cwd: "/tmp/repo"))
        let b = NotificationGroupKey(session: session(id: "thread-2", cwd: "/tmp/repo/"))
        #expect(a == b)
    }

    @Test
    func differentToolOrCwdAreDifferentGroups() {
        let codex = NotificationGroupKey(session: session(id: "s1", tool: .codex, cwd: "/tmp/repo"))
        let claude = NotificationGroupKey(session: session(id: "s2", tool: .claudeCode, cwd: "/tmp/repo"))
        let other = NotificationGroupKey(session: session(id: "s3", tool: .codex, cwd: "/tmp/other"))
        #expect(codex != claude)
        #expect(codex != other)
    }

    @Test
    func sessionWithoutWorkspaceIsItsOwnGroup() {
        let a = NotificationGroupKey(session: session(id: "s1"))
        let b = NotificationGroupKey(session: session(id: "s2"))
        #expect(a != b)
    }
}
