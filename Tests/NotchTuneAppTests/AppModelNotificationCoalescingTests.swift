import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

/// Wiring tests: `AppModel.applyTrackedEvent` → `NotificationCoalescer` →
/// the single notification presentation path. Uses a shrunken settle window
/// so the trailing debounce can be observed without long sleeps, and keeps
/// the sound muted so no test plays audio.
@MainActor
@Suite(.serialized)
struct AppModelNotificationCoalescingTests {
    private static let settleSeconds: TimeInterval = 0.08
    private let now = Date(timeIntervalSince1970: 5_000)

    init() {
        UserDefaults.standard.set(true, forKey: "overlay.sound.muted")
        UserDefaults.standard.removeObject(forKey: "app.suppressFrontmostNotifications")
    }

    private func makeModel(frontmost: @escaping @Sendable (AgentSession) async -> Bool = { _ in false }) -> AppModel {
        let model = AppModel(
            isNotificationSessionAlreadyFrontmost: frontmost,
            frontmostBundleIdentifierProvider: { nil }
        )
        model.isSoundMuted = true
        model.notchStatus = .closed
        model.notchOpenReason = nil
        model.notificationCoalescingPolicy = NotificationCoalescingPolicy(
            completionSettleSeconds: Self.settleSeconds,
            groupCooldownSeconds: 20,
            globalMinimumIntervalSeconds: 3
        )
        return model
    }

    private func start(_ model: AppModel, id: String, cwd: String = "/tmp/repo") {
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
                    workspaceName: "repo",
                    paneTitle: id,
                    workingDirectory: cwd
                )
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )
    }

    private func complete(_ model: AppModel, id: String) {
        model.applyTrackedEvent(
            .sessionCompleted(SessionCompleted(sessionID: id, summary: "Done", timestamp: now.addingTimeInterval(1))),
            updateLastActionMessage: false,
            ingress: .bridge
        )
    }

    private func run(_ model: AppModel, id: String) {
        model.applyTrackedEvent(
            .activityUpdated(SessionActivityUpdated(
                sessionID: id,
                summary: "Prompt: keep going",
                phase: .running,
                timestamp: now.addingTimeInterval(2)
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )
    }

    private func approve(_ model: AppModel, id: String) {
        model.applyTrackedEvent(
            .permissionRequested(PermissionRequested(
                sessionID: id,
                request: PermissionRequest(title: "Edit", summary: "main.swift", affectedPath: "/tmp/main.swift"),
                timestamp: now.addingTimeInterval(1)
            )),
            updateLastActionMessage: false,
            ingress: .bridge
        )
    }

    /// Wait until the notch opens or the settle window (plus slack) elapses.
    private func waitForSettle(_ model: AppModel, opened: Bool) async throws {
        let ticks = Int((Self.settleSeconds * 4) / 0.01)
        for _ in 0..<ticks {
            if opened, model.notchStatus == .opened { return }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test
    func completionIsHeldThenPresentedThroughNotificationPath() async throws {
        let model = makeModel()
        start(model, id: "s1")
        complete(model, id: "s1")

        // Held: the flash fires immediately, the notch does not open yet.
        #expect(model.completionFlashSessionID == "s1")
        #expect(model.notchStatus == .closed)
        #expect(model.pendingCompletionSessionIDsForTests() == ["s1"])

        try await waitForSettle(model, opened: true)

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .notification)
        #expect(model.islandSurface == .sessionList(actionableSessionID: "s1"))
        #expect(model.pendingCompletionSessionIDsForTests().isEmpty)
    }

    @Test
    func runningSignalInsideSettleWindowCancelsTheBump() async throws {
        let model = makeModel()
        start(model, id: "s1")
        complete(model, id: "s1")
        run(model, id: "s1")

        #expect(model.pendingCompletionSessionIDsForTests().isEmpty)
        try await waitForSettle(model, opened: false)

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
    }

    @Test
    func siblingThreadGoingBackToRunningCancelsPendingSiblingCompletion() async throws {
        let model = makeModel()
        start(model, id: "thread-1")
        start(model, id: "thread-2")
        complete(model, id: "thread-1")
        run(model, id: "thread-2")   // same tool + cwd → same group

        #expect(model.pendingCompletionSessionIDsForTests().isEmpty)
        try await waitForSettle(model, opened: false)
        #expect(model.notchStatus == .closed)
    }

    @Test
    func burstOfSiblingCompletionsYieldsOneBumpThenSubtleRepeats() async throws {
        let model = makeModel()
        start(model, id: "thread-1")
        start(model, id: "thread-2")
        start(model, id: "thread-3")

        complete(model, id: "thread-1")
        complete(model, id: "thread-2")
        #expect(model.pendingCompletionSessionIDsForTests() == ["thread-2"])

        try await waitForSettle(model, opened: true)
        #expect(model.notchStatus == .opened)
        #expect(model.islandSurface == .sessionList(actionableSessionID: "thread-2"))

        // User closed the card; a further completion in the group inside
        // the cooldown only flashes.
        model.notchClose()
        model.completionFlashSessionID = nil
        complete(model, id: "thread-3")
        // Checked before the settle wait: the flash clears itself after 2s,
        // which a loaded full-suite run can outlast.
        #expect(model.completionFlashSessionID == "thread-3")
        try await waitForSettle(model, opened: false)

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
    }

    @Test
    func frontmostCompletionBouncesThePillInsteadOfOpeningTheToast() async throws {
        let model = makeModel(frontmost: { $0.id == "s1" })
        model.suppressFrontmostNotifications = true
        start(model, id: "s1")
        complete(model, id: "s1")
        model.completionFlashSessionID = nil   // isolate the settled cue

        // Settle + async frontmost check → `.subtle` with a bounce.
        var sawPop = false
        for _ in 0..<Int((Self.settleSeconds * 6) / 0.01) {
            if model.notchStatus == .popping { sawPop = true; break }
            #expect(model.notchStatus != .opened)
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(sawPop)
        #expect(model.completionFlashSessionID == "s1")
        #expect(model.notchOpenReason == nil)
        #expect(model.islandSurface == .sessionList())
    }

    @Test
    func frontmostApprovalStaysSuppressed() async throws {
        let model = makeModel(frontmost: { $0.id == "s1" })
        model.suppressFrontmostNotifications = true
        start(model, id: "s1")
        approve(model, id: "s1")

        for _ in 0..<20 {
            #expect(model.notchStatus == .closed)
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.notchOpenReason == nil)
    }

    @Test
    func frontmostCompletionOpensNormallyWhenSuppressionIsOff() async throws {
        let model = makeModel(frontmost: { $0.id == "s1" })
        model.suppressFrontmostNotifications = false
        start(model, id: "s1")
        complete(model, id: "s1")

        try await waitForSettle(model, opened: true)

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .notification)
    }

    @Test
    func completionDoesNotOpenWhileCardForSameSessionIsAlreadyShowing() async throws {
        let model = makeModel()
        start(model, id: "s1")
        approve(model, id: "s1")
        try await waitForSettle(model, opened: true)
        #expect(model.notchStatus == .opened)
        #expect(model.islandSurface == .sessionList(actionableSessionID: "s1"))

        // Approval resolved → completion on the very same card: no re-open.
        complete(model, id: "s1")
        try await waitForSettle(model, opened: false)
        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .notification)
        #expect(model.islandSurface == .sessionList(actionableSessionID: "s1"))
    }

    @Test
    func repeatedApprovalForSessionAlreadyWaitingIsSuppressed() async throws {
        let model = makeModel()
        start(model, id: "s1")
        approve(model, id: "s1")
        try await waitForSettle(model, opened: true)
        #expect(model.notchStatus == .opened)

        model.notchClose()
        approve(model, id: "s1")   // same session, still waitingForApproval
        try await waitForSettle(model, opened: false)

        #expect(model.notchStatus == .closed)
    }

    @Test
    func firstApprovalPresentsEvenRightAfterACompletionBump() async throws {
        let model = makeModel()
        start(model, id: "s1")
        complete(model, id: "s1")
        try await waitForSettle(model, opened: true)
        #expect(model.notchStatus == .opened)

        model.notchClose()
        run(model, id: "s1")
        approve(model, id: "s1")
        try await waitForSettle(model, opened: true)

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .notification)
        #expect(model.islandSurface == .sessionList(actionableSessionID: "s1"))
    }
}
