import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

/// Wiring tests: `NotificationCardKeyCommand` → `AppModel` actions on the
/// notification card that is actually on screen.
@MainActor
@Suite(.serialized)
struct AppModelNotificationCardKeysTests {
    // Real clock: the completion ring drops completions older than the
    // stale threshold, so fixed 1970 dates would empty it.
    private let now = Date()

    init() {
        UserDefaults.standard.set(true, forKey: "overlay.sound.muted")
        UserDefaults.standard.removeObject(forKey: "app.suppressFrontmostNotifications")
    }

    @Test
    func aNewRequestReplacingTheOpenCardRestartsTheReturnGuard() async throws {
        let model = makeModel()
        start(model, id: "s1")
        requestApproval(model, id: "s1")
        try await waitUntilOpened(model)

        // The first request has been on screen for a while...
        model.notificationCardShownAt = Date().addingTimeInterval(-5)
        #expect(model.notificationCardAge() > 1)

        // ...then a second request replaces the card's content in place.
        requestApproval(model, id: "s1", toolName: "Edit")
        #expect(model.notificationCardAge() < 0.5)
    }

    private func makeModel() -> AppModel {
        let model = AppModel(
            isNotificationSessionAlreadyFrontmost: { _ in false },
            frontmostBundleIdentifierProvider: { nil }
        )
        // Hermetic: a full-screen app on the real display would otherwise
        // hide the overlay panel that hosts the card these keys drive.
        model.disablesOverlayEventMonitoringDuringHarness = true
        model.isSoundMuted = true
        model.notchStatus = .closed
        model.notchOpenReason = nil
        model.notificationCoalescingPolicy = NotificationCoalescingPolicy(
            completionSettleSeconds: 0.05,
            groupCooldownSeconds: 0,
            globalMinimumIntervalSeconds: 0
        )
        return model
    }

    private func start(_ model: AppModel, id: String) {
        model.applyTrackedEvent(
            .sessionStarted(SessionStarted(
                sessionID: id,
                title: "Codex · \(id)",
                tool: .codex,
                origin: .live,
                summary: "Started",
                timestamp: now,
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: id,
                    paneTitle: id,
                    workingDirectory: "/tmp/\(id)"
                )
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )
    }

    private func requestApproval(_ model: AppModel, id: String, toolName: String? = "Bash") {
        model.applyTrackedEvent(
            .permissionRequested(PermissionRequested(
                sessionID: id,
                request: PermissionRequest(
                    title: "Bash",
                    summary: "rm -rf build",
                    affectedPath: "/tmp/build",
                    toolName: toolName
                ),
                timestamp: now.addingTimeInterval(1)
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )
    }

    private func ask(_ model: AppModel, id: String) {
        model.applyTrackedEvent(
            .questionAsked(QuestionAsked(
                sessionID: id,
                prompt: QuestionPrompt(title: "Which one?", options: ["A", "B"]),
                timestamp: now.addingTimeInterval(1)
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )
    }

    private func complete(_ model: AppModel, id: String, offset: TimeInterval = 1) {
        model.applyTrackedEvent(
            .sessionCompleted(SessionCompleted(sessionID: id, summary: "Done", timestamp: now.addingTimeInterval(offset))),
            updateLastActionMessage: false,
            ingress: .bridge
        )
    }

    private func waitUntilOpened(_ model: AppModel) async throws {
        for _ in 0..<60 where model.notchStatus != .opened {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test
    func noCardMeansNoCommand() {
        let model = makeModel()
        start(model, id: "s1")
        #expect(model.keyboardNotificationCard == nil)
        #expect(model.performNotificationCardKeyCommand(.allowOnce) == false)
        #expect(model.performNotificationCardKeyCommand(.dismiss) == false)
    }

    @Test
    func cardOpenedByClickIsNotKeyboardControlled() {
        let model = makeModel()
        start(model, id: "s1")
        requestApproval(model, id: "s1")
        model.notchOpen(reason: .click, surface: .sessionList(actionableSessionID: "s1"))
        #expect(model.keyboardNotificationCard == nil)
    }

    @Test
    func denyResolvesTheApprovalOnScreen() async throws {
        let model = makeModel()
        start(model, id: "s1")
        requestApproval(model, id: "s1")
        try await waitUntilOpened(model)
        #expect(model.keyboardNotificationCard?.kind == .approval(supportsAlwaysAllow: true))

        #expect(model.performNotificationCardKeyCommand(.deny))
        #expect(model.state.session(id: "s1")?.phase != .waitingForApproval)
        #expect(model.notchStatus == .closed)
    }

    @Test
    func allowOnceResolvesTheApprovalOnScreen() async throws {
        let model = makeModel()
        start(model, id: "s1")
        requestApproval(model, id: "s1")
        try await waitUntilOpened(model)

        #expect(model.performNotificationCardKeyCommand(.allowOnce))
        #expect(model.state.session(id: "s1")?.phase == .running)
        #expect(model.state.session(id: "s1")?.permissionRequest == nil)
    }

    @Test
    func alwaysAllowNeedsAToolScopedRequest() async throws {
        let model = makeModel()
        start(model, id: "s1")
        requestApproval(model, id: "s1", toolName: nil)
        try await waitUntilOpened(model)

        #expect(model.performNotificationCardKeyCommand(.alwaysAllow) == false)
        #expect(model.state.session(id: "s1")?.phase == .waitingForApproval)
    }

    @Test
    func escapeCollapsesWithoutAnsweringTheApproval() async throws {
        let model = makeModel()
        start(model, id: "s1")
        requestApproval(model, id: "s1")
        try await waitUntilOpened(model)

        #expect(model.performNotificationCardKeyCommand(.dismiss))
        #expect(model.notchStatus == .closed)
        #expect(model.state.session(id: "s1")?.phase == .waitingForApproval)
        #expect(model.state.session(id: "s1")?.permissionRequest != nil)
    }

    @Test
    func approvalKeysDoNotApplyToAQuestion() async throws {
        let model = makeModel()
        start(model, id: "s1")
        ask(model, id: "s1")
        try await waitUntilOpened(model)
        #expect(model.keyboardNotificationCard?.kind == .question)

        #expect(model.performNotificationCardKeyCommand(.allowOnce) == false)
        #expect(model.state.session(id: "s1")?.phase == .waitingForAnswer)
    }

    @Test
    func questionPickAndSubmitDriveTheQuestionView() async throws {
        let model = makeModel()
        start(model, id: "s1")
        ask(model, id: "s1")
        try await waitUntilOpened(model)

        let received = Received()
        let token = NotificationCenter.default.addObserver(
            forName: .notificationCardKeyCommand,
            object: nil,
            queue: nil
        ) { notification in
            let command = NotificationCardKeyCommandBus.command(from: notification, sessionID: "s1")
            MainActor.assumeIsolated { received.commands.append(command) }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        // Submit with nothing selected: the view's Submit is disabled.
        #expect(model.performNotificationCardKeyCommand(.submit))
        #expect(model.state.session(id: "s1")?.phase == .waitingForAnswer)

        #expect(model.performNotificationCardKeyCommand(.pickOption(1)))
        #expect(model.state.session(id: "s1")?.phase == .waitingForAnswer)
        #expect(model.performNotificationCardKeyCommand(.submit))
        #expect(received.commands == [.submit, .pickOption(1), .submit])

        // The overlay panel hosts the real card in-process, so the pick and
        // the submit land end to end: ⌘2 selected "B", Return answered it.
        #expect(model.state.session(id: "s1")?.phase == .running)
        #expect(model.state.session(id: "s1")?.summary.contains("B") == true)
    }

    @Test
    func completionQueueRotatesAndReplyNeedsAvailability() async throws {
        let model = makeModel()
        start(model, id: "s1")
        start(model, id: "s2")
        complete(model, id: "s1", offset: 1)
        complete(model, id: "s2", offset: 2)
        try await waitUntilOpened(model)
        let shown = try #require(model.islandSurface.sessionID)
        #expect(model.keyboardNotificationCard?.kind == .completion(hasReply: false))

        #expect(model.performNotificationCardKeyCommand(.next))
        #expect(model.islandSurface.sessionID != shown)
        #expect(model.performNotificationCardKeyCommand(.previous))
        #expect(model.islandSurface.sessionID == shown)

        // Reply is off by default → ⌘R does not apply.
        #expect(model.performNotificationCardKeyCommand(.openReply) == false)
    }

    @Test
    func cardClockStartsWhenTheCardAppears() async throws {
        let model = makeModel()
        start(model, id: "s1")
        requestApproval(model, id: "s1")
        try await waitUntilOpened(model)

        #expect(model.notificationCardAge() < 1)
        model.notificationCardShownAt = Date().addingTimeInterval(-10)
        #expect(model.notificationCardAge() >= 10)
    }
}

@MainActor
private final class Received {
    var commands: [NotificationCardKeyCommand?] = []
}
