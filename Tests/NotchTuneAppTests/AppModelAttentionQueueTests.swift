import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

/// Several agents blocked at once: one card on screen, the rest queued
/// oldest-first, and an answer only ever lands on the request it was given for.
@MainActor
@Suite(.serialized)
struct AppModelAttentionQueueTests {
    private let now = Date()

    init() {
        UserDefaults.standard.set(true, forKey: "overlay.sound.muted")
        UserDefaults.standard.removeObject(forKey: "app.suppressFrontmostNotifications")
    }

    /// Commands the model tried to send.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [BridgeCommand] = []

        func record(_ command: BridgeCommand) {
            lock.withLock { stored.append(command) }
        }

        var commands: [BridgeCommand] {
            lock.withLock { stored }
        }
    }

    private struct Unreachable: Error {}

    private func makeModel(failing: Bool = false, recorder: Recorder = Recorder()) -> AppModel {
        let model = AppModel(
            isNotificationSessionAlreadyFrontmost: { _ in false },
            frontmostBundleIdentifierProvider: { nil }
        )
        model.disablesOverlayEventMonitoringDuringHarness = true
        model.isSoundMuted = true
        model.notchStatus = .closed
        model.notchOpenReason = nil
        model.bridgeCommandSender = { command in
            recorder.record(command)
            if failing { throw Unreachable() }
        }
        return model
    }

    private func start(_ model: AppModel, _ id: String, tool: AgentTool = .codex) {
        model.applyTrackedEvent(
            .sessionStarted(SessionStarted(
                sessionID: id,
                title: id,
                tool: tool,
                origin: .live,
                summary: "Started",
                timestamp: now,
                jumpTarget: JumpTarget(terminalApp: "Ghostty", workspaceName: id, paneTitle: id, workingDirectory: "/tmp/\(id)")
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )
    }

    @discardableResult
    private func request(
        _ model: AppModel,
        _ id: String,
        summary: String = "rm -rf build",
        after seconds: TimeInterval = 1,
        suggestions: [ClaudePermissionUpdate] = []
    ) -> PermissionRequest {
        let request = PermissionRequest(
            title: "Bash",
            summary: summary,
            affectedPath: "/tmp",
            toolName: "Bash",
            suggestedUpdates: suggestions
        )
        model.applyTrackedEvent(
            .permissionRequested(PermissionRequested(
                sessionID: id,
                request: request,
                timestamp: now.addingTimeInterval(seconds)
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )
        return request
    }

    private func settle(until condition: () -> Bool) async throws {
        for _ in 0..<80 where !condition() {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func cardID(_ model: AppModel) -> String? {
        model.notchStatus == .opened && model.notchOpenReason == .notification ? model.islandSurface.sessionID : nil
    }

    private func threeWaiting(_ model: AppModel) async throws {
        for id in ["a", "b", "c"] { start(model, id) }
        request(model, "a", after: 1)
        try await settle { cardID(model) == "a" }
        request(model, "b", after: 2)
        request(model, "c", after: 3)
        // Long enough on screen for keys and clicks to count.
        model.notificationCardShownAt = Date().addingTimeInterval(-5)
    }

    // MARK: Queueing

    @Test
    func aNewRequestDoesNotDisplaceTheCardOnScreen() async throws {
        let model = makeModel()
        try await threeWaiting(model)
        try await Task.sleep(for: .milliseconds(30))

        #expect(cardID(model) == "a")
        #expect(model.attentionQueuePosition == AttentionQueuePosition(index: 0, count: 3))
    }

    @Test
    func aCompletionDoesNotDisplaceABlockedAgent() async throws {
        let model = makeModel()
        model.notificationCoalescingPolicy = NotificationCoalescingPolicy(
            completionSettleSeconds: 0.01,
            groupCooldownSeconds: 0,
            globalMinimumIntervalSeconds: 0
        )
        start(model, "a")
        start(model, "b")
        request(model, "a")
        try await settle { cardID(model) == "a" }

        model.applyTrackedEvent(
            .sessionCompleted(SessionCompleted(sessionID: "b", summary: "Done", timestamp: now.addingTimeInterval(2))),
            updateLastActionMessage: false,
            ingress: .bridge
        )
        try await Task.sleep(for: .milliseconds(60))

        #expect(cardID(model) == "a")
    }

    @Test
    func answeringPresentsTheOldestRemainingThenCloses() async throws {
        let model = makeModel()
        try await threeWaiting(model)

        model.approvePermission(for: "a", action: .allowOnce)
        #expect(cardID(model) == "b")
        #expect(model.attentionQueuePosition == AttentionQueuePosition(index: 0, count: 2))

        model.approvePermission(for: "b", action: .deny)
        #expect(cardID(model) == "c")
        #expect(model.attentionQueuePosition == nil)

        model.approvePermission(for: "c", action: .allowOnce)
        #expect(model.notchStatus == .closed)
    }

    @Test
    func theQueueIsOldestFirstWhateverOrderSessionsWereUpdated() async throws {
        let model = makeModel()
        try await threeWaiting(model)
        // A heartbeat bumps the youngest request's session past the others.
        model.applyTrackedEvent(
            .activityUpdated(SessionActivityUpdated(
                sessionID: "b",
                summary: "tick",
                phase: .running,
                timestamp: now.addingTimeInterval(30)
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        #expect(model.attentionQueue.map(\.id) == ["a", "b", "c"])
    }

    @Test
    func aNewerCardTakesTheFreshCardGuards() async throws {
        let model = makeModel()
        try await threeWaiting(model)

        model.approvePermission(for: "a", action: .allowOnce)

        #expect(model.notificationCardAge() < NotificationCardKeyCommand.approvalArmDelay)
    }

    @Test
    func escMovesOnWithoutAnsweringAndNeverCycles() async throws {
        let model = makeModel()
        start(model, "a")
        start(model, "b")
        request(model, "a", after: 1)
        try await settle { cardID(model) == "a" }
        request(model, "b", after: 2)

        #expect(model.performNotificationCardKeyCommand(.dismiss))
        #expect(cardID(model) == "b")

        #expect(model.performNotificationCardKeyCommand(.dismiss))
        try await Task.sleep(for: .milliseconds(30))
        #expect(model.notchStatus == .closed)
        #expect(model.state.session(id: "a")?.phase == .waitingForApproval)
        #expect(model.state.session(id: "b")?.phase == .waitingForApproval)
    }

    @Test
    func aRequestResolvedInTheTerminalHandsTheCardOn() async throws {
        let model = makeModel()
        try await threeWaiting(model)

        model.applyTrackedEvent(
            .actionableStateResolved(ActionableStateResolved(
                sessionID: "a",
                summary: "Approval was handled outside NotchTune.",
                timestamp: now.addingTimeInterval(4)
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        #expect(cardID(model) == "b")
    }

    @Test
    func aRequestBlockedByAToastIsPresentedWhenTheToastGoes() async throws {
        let model = makeModel()
        model.notificationCoalescingPolicy = NotificationCoalescingPolicy(
            completionSettleSeconds: 0.01,
            groupCooldownSeconds: 0,
            globalMinimumIntervalSeconds: 0
        )
        start(model, "toast")
        start(model, "waiting")
        model.applyTrackedEvent(
            .sessionCompleted(SessionCompleted(sessionID: "toast", summary: "Done", timestamp: now.addingTimeInterval(1))),
            updateLastActionMessage: false,
            ingress: .bridge
        )
        try await settle { cardID(model) == "toast" }
        // The pointer is on the toast, so the request can't take over yet.
        model.notePointerInsideIslandSurface()
        request(model, "waiting", after: 2)
        try await Task.sleep(for: .milliseconds(30))
        #expect(cardID(model) == "toast")

        model.overlay.dismissNotificationCard()

        #expect(cardID(model) == "waiting")
    }

    @Test
    func aRequestThatArrivedDuringBrowsingGetsItsCardWhenTheNotchCloses() async throws {
        let model = makeModel()
        start(model, "a")
        model.notchOpen(reason: .click)
        request(model, "a")
        try await Task.sleep(for: .milliseconds(30))
        #expect(cardID(model) == nil)

        model.notchClose()
        try await settle { cardID(model) == "a" }

        #expect(cardID(model) == "a")
    }

    @Test
    func aDifferentRequestInTheSamePhaseIsNotARepeat() async throws {
        let model = makeModel()
        start(model, "a")
        request(model, "a", summary: "first")
        try await settle { cardID(model) == "a" }
        #expect(model.performNotificationCardKeyCommand(.dismiss))
        try await settle { model.notchStatus == .closed }

        // Same phase, same words: a re-emission, so it stays out of the way.
        request(model, "a", summary: "first", after: 2)
        try await Task.sleep(for: .milliseconds(30))
        #expect(model.notchStatus == .closed)

        request(model, "a", summary: "second", after: 3)
        try await settle { cardID(model) == "a" }
        #expect(cardID(model) == "a")
    }

    // MARK: Binding answers to requests

    @Test
    func anAnswerForAReplacedRequestIsDropped() async throws {
        let recorder = Recorder()
        let model = makeModel(recorder: recorder)
        start(model, "a")
        let shown = request(model, "a", summary: "ls")
        try await settle { cardID(model) == "a" }
        let newer = request(model, "a", summary: "rm -rf /", after: 2)

        model.approvePermission(for: "a", requestID: shown.id, action: .allowOnce)
        try await Task.sleep(for: .milliseconds(30))

        #expect(model.state.session(id: "a")?.permissionRequest?.id == newer.id)
        #expect(recorder.commands.isEmpty)
    }

    @Test
    func anAnswerForAReplacedQuestionIsDropped() async throws {
        let model = makeModel()
        start(model, "a")
        let prompt = QuestionPrompt(title: "Which?", options: ["A"])
        model.applyTrackedEvent(
            .questionAsked(QuestionAsked(sessionID: "a", prompt: prompt, timestamp: now)),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        model.answerQuestion(for: "a", requestID: UUID(), answer: QuestionPromptResponse(answer: "A"))

        #expect(model.state.session(id: "a")?.phase == .waitingForAnswer)
    }

    @Test
    func theBridgeCommandNamesTheRequestAnswered() async throws {
        let recorder = Recorder()
        let model = makeModel(recorder: recorder)
        start(model, "a")
        let shown = request(model, "a")

        model.approvePermission(for: "a", requestID: shown.id, action: .allowOnce)
        try await settle { !recorder.commands.isEmpty }

        #expect(recorder.commands == [
            .resolvePermission(sessionID: "a", resolution: .allowOnce(), requestID: shown.id),
        ])
    }

    @Test
    func aClickOnACardThatJustAppearedIsIgnored() async throws {
        let model = makeModel()
        start(model, "a")
        request(model, "a")
        try await settle { cardID(model) == "a" }
        let shown = try #require(model.state.session(id: "a"))

        model.approveFromCard(shown, action: .allowOnce)
        #expect(model.state.session(id: "a")?.phase == .waitingForApproval)

        model.notificationCardShownAt = Date().addingTimeInterval(-1)
        model.approveFromCard(shown, action: .allowOnce)
        #expect(model.state.session(id: "a")?.phase == .running)
    }

    @Test
    func alwaysAllowFromTheKeyboardSendsTheNarrowRule() async throws {
        let recorder = Recorder()
        let model = makeModel(recorder: recorder)
        let suggestion = ClaudePermissionUpdate.addRules(
            destination: .localSettings,
            rules: [ClaudePermissionRuleValue(toolName: "Bash", ruleContent: "git add:*")],
            behavior: .allow
        )
        start(model, "a", tool: .claudeCode)
        let shown = request(model, "a", suggestions: [suggestion])
        try await settle { cardID(model) == "a" }

        #expect(model.performNotificationCardKeyCommand(.alwaysAllow))
        try await settle { !recorder.commands.isEmpty }

        #expect(recorder.commands == [
            .resolvePermission(
                sessionID: "a",
                resolution: .allowOnce(updatedPermissions: [suggestion]),
                requestID: shown.id
            ),
        ])
    }

    // MARK: Rollback

    @Test
    func aFailedSendPutsTheRequestBackAndSaysSo() async throws {
        let model = makeModel(failing: true)
        start(model, "a")
        let shown = request(model, "a")
        try await settle { cardID(model) == "a" }

        model.approvePermission(for: "a", action: .allowOnce)
        #expect(model.state.session(id: "a")?.phase == .running)

        try await settle { model.notice != nil }
        #expect(model.state.session(id: "a")?.phase == .waitingForApproval)
        #expect(model.state.session(id: "a")?.permissionRequest == shown)
        #expect(model.notice?.message.contains("wasn't delivered") == true)
        try await settle { cardID(model) == "a" }
        #expect(cardID(model) == "a")
    }

    @Test
    func aFailedAnswerPutsTheQuestionBack() async throws {
        let model = makeModel(failing: true)
        start(model, "a")
        let prompt = QuestionPrompt(title: "Which?", options: ["A"])
        model.applyTrackedEvent(
            .questionAsked(QuestionAsked(sessionID: "a", prompt: prompt, timestamp: now)),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        model.answerQuestion(for: "a", answer: QuestionPromptResponse(answer: "A"))
        try await settle { model.notice != nil }

        #expect(model.state.session(id: "a")?.phase == .waitingForAnswer)
        #expect(model.state.session(id: "a")?.questionPrompt == prompt)
    }

    @Test
    func aSessionThatMovedOnIsNotRolledBack() async throws {
        let model = makeModel(failing: true)
        start(model, "a")
        request(model, "a")

        model.approvePermission(for: "a", action: .allowOnce)
        // The agent reported in before the failure came back.
        model.applyTrackedEvent(
            .activityUpdated(SessionActivityUpdated(
                sessionID: "a",
                summary: "Running Bash",
                phase: .running,
                timestamp: now.addingTimeInterval(60)
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )
        try await Task.sleep(for: .milliseconds(50))

        #expect(model.state.session(id: "a")?.phase == .running)
        #expect(model.notice == nil)
    }

    @Test
    func aDemoSessionNeverTouchesTheBridge() async throws {
        let recorder = Recorder()
        let model = makeModel(failing: true, recorder: recorder)
        model.state.insertSession(AgentSession(
            id: "demo",
            title: "demo",
            tool: .claudeCode,
            origin: .demo,
            phase: .waitingForApproval,
            summary: "",
            updatedAt: now,
            permissionRequest: PermissionRequest(title: "t", summary: "s", affectedPath: "")
        ))

        model.approvePermission(for: "demo", action: .allowOnce)
        try await Task.sleep(for: .milliseconds(30))

        #expect(recorder.commands.isEmpty)
        #expect(model.state.session(id: "demo")?.phase == .running)
    }
}
