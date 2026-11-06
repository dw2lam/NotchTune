import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

@MainActor
@Suite(.serialized)
struct AppNoticeTests {
    init() {
        UserDefaults.standard.set(true, forKey: "overlay.sound.muted")
    }

    private func makeModel(noticeDuration: TimeInterval = 60) -> AppModel {
        let model = AppModel()
        model.isSoundMuted = true
        model.notchStatus = .closed
        model.notchOpenReason = nil
        model.overlay.noticeDisplayDuration = noticeDuration
        return model
    }

    private let denied = AppNotice(
        message: "Allow NotchTune to control Ghostty.",
        actionTitle: "Open Settings",
        action: .openPrivacyPane(.automation)
    )

    @Test
    func theSameProblemDoesNotReplaceTheNoticeOnScreen() {
        let model = makeModel()
        let first = AppNotice(message: "Couldn't jump to Ghostty.")
        model.post(first)
        model.post(AppNotice(message: "Couldn't jump to Ghostty."))
        #expect(model.notice?.id == first.id)

        let other = AppNotice(message: "Hooks couldn't be installed.")
        model.post(other)
        #expect(model.notice?.id == other.id)

        model.dismissNotice()
        #expect(model.notice == nil)
    }

    // MARK: - Where a notice goes

    @Test
    func aClosedNotchOpensAToastAndAnOpenPanelShowsABanner() {
        func delivery(
            _ status: NotchStatus,
            _ reason: NotchOpenReason? = nil,
            _ surface: IslandSurface = .sessionList(),
            closing: Bool = false,
            fullscreen: Bool = false
        ) -> AppNoticeDelivery {
            .resolve(status: status, openReason: reason, surface: surface, isClosing: closing, isFullscreen: fullscreen)
        }

        #expect(delivery(.closed) == .toast)
        #expect(delivery(.popping) == .toast)
        #expect(delivery(.opened, .click) == .banner)
        #expect(delivery(.opened, .hover) == .banner)
        #expect(delivery(.opened, .notification, .notice) == .banner)
        // Never under a close, an agent's card, a drag, or a full-screen app.
        #expect(delivery(.closed, closing: true) == .wait)
        #expect(delivery(.opened, .notification, .sessionList(actionableSessionID: "s")) == .wait)
        #expect(delivery(.opened, .drag) == .wait)
        #expect(delivery(.opened, .boot) == .wait)
        #expect(delivery(.closed, fullscreen: true) == .wait)
    }

    @Test
    func aToastOpensPassivelyAndLeavesTheTabAlone() {
        let model = makeModel()
        model.islandActiveTab = .reminders

        model.post(denied)

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .notification)
        #expect(model.islandSurface == .notice)
        #expect(model.islandActiveTab == .reminders)
        // Typing in another app must not land in the notch.
        #expect(OverlayPanelController.shouldActivatePanel(for: model.notchOpenReason) == false)
        #expect(OverlayPanelController.takesKeyOnOpen(for: model.notchOpenReason) == false)
    }

    @Test
    func anOpenPanelKeepsItsSurfaceAndShowsTheBanner() {
        let model = makeModel()
        model.notchOpen(reason: .click)

        model.post(denied)

        #expect(model.notchOpenReason == .click)
        #expect(model.islandSurface == .sessionList())
        #expect(model.overlay.presentedNotice?.id == denied.id)
    }

    @Test
    func aNoticePostedDuringACloseWaitsForTheMorphToFinish() async throws {
        let model = makeModel()
        model.notchOpen(reason: .click)
        model.notchClose()

        // The Jump case: the failure lands while the notch is still closing.
        model.post(AppNotice(message: "Couldn't jump."))
        #expect(model.notchStatus == .closed)

        try await Task.sleep(for: .seconds(CloseMorph.settled + 0.15))
        #expect(model.notchStatus == .opened)
        #expect(model.islandSurface == .notice)
    }

    @Test
    func aNoticeWaitsBehindAnAgentsCardAndFollowsItsClose() async throws {
        let model = makeModel()
        model.notchOpen(reason: .notification, surface: .sessionList(actionableSessionID: "session"))

        model.post(AppNotice(message: "Couldn't jump."))
        #expect(model.islandSurface == .sessionList(actionableSessionID: "session"))

        model.notchClose()
        try await Task.sleep(for: .seconds(CloseMorph.settled + 0.15))
        #expect(model.islandSurface == .notice)
    }

    @Test
    func theBootFlourishGivesWayToALaunchFailure() async throws {
        let model = makeModel()
        model.post(AppNotice(message: "Your Myspace notes couldn't be read."))

        model.performBootAnimation()
        try await Task.sleep(for: .milliseconds(650))

        #expect(model.notchOpenReason == .notification)
        #expect(model.islandSurface == .notice)
        #expect(model.notice != nil)
    }

    // MARK: - How long it stays

    @Test
    func aToastFoldsAwayAndAPlainNoticeGoesWithIt() async throws {
        let model = makeModel(noticeDuration: 0.1)
        model.post(AppNotice(message: "Couldn't jump."))
        #expect(model.islandSurface == .notice)

        try await Task.sleep(for: .milliseconds(300))
        #expect(model.notchStatus == .closed)
        #expect(model.notice == nil)
        // Still on the panel through the morph; gone once it has settled.
        #expect(model.overlay.presentedNotice != nil)

        try await Task.sleep(for: .seconds(CloseMorph.settled + 0.1))
        #expect(model.overlay.presentedNotice == nil)
    }

    @Test
    func aNoticeWithAnActionOutlivesItsToastAndWaitsInThePanel() async throws {
        let model = makeModel(noticeDuration: 0.1)
        model.post(denied)

        try await Task.sleep(for: .milliseconds(300))
        #expect(model.notchStatus == .closed)
        #expect(model.notice?.id == denied.id)

        // Seen already: the settled close must not open it a second time.
        try await Task.sleep(for: .seconds(CloseMorph.settled + 0.15))
        #expect(model.notchStatus == .closed)

        model.notchOpen(reason: .click)
        #expect(model.overlay.presentedNotice?.id == denied.id)
    }

    @Test
    func aBannerExpiresUnlessItHasAnAction() async throws {
        let model = makeModel(noticeDuration: 0.1)
        model.notchOpen(reason: .click)

        model.post(AppNotice(message: "Couldn't jump."))
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.notice == nil)
        #expect(model.notchStatus == .opened)

        model.post(denied)
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.notice?.id == denied.id)
    }

    @Test
    func closingThePanelClearsASeenPlainNotice() {
        let model = makeModel()
        model.notchOpen(reason: .click)
        model.post(AppNotice(message: "Couldn't jump."))

        model.notchClose()

        #expect(model.notice == nil)
    }

    @Test
    func dismissingAToastClosesTheNotchAndKeepsItOnThePanelThroughTheMorph() {
        let model = makeModel()
        model.post(denied)

        model.dismissNotice()

        #expect(model.notice == nil)
        #expect(model.notchStatus == .closed)
        #expect(model.overlay.presentedSurface == .notice)
        #expect(model.overlay.presentedNotice?.id == denied.id)
    }

    @Test
    func anAgentsCardTakesOverFromAToast() {
        let model = makeModel()
        model.post(AppNotice(message: "Couldn't jump."))

        let card = IslandSurface.sessionList(actionableSessionID: "session")
        #expect(model.overlay.shouldPreserveCurrentNotificationSurface(against: card) == false)
        model.notchOpen(reason: .notification, surface: card)

        #expect(model.islandSurface == card)
        #expect(model.notice == nil)
    }

    // MARK: - Jumps

    private final class JumpLog: @unchecked Sendable {
        private let lock = NSLock()
        private var running = 0
        private var overlapped = false
        private var finished: [String] = []

        func run(_ target: JumpTarget, for duration: TimeInterval = 0.08) {
            lock.withLock {
                running += 1
                overlapped = overlapped || running > 1
            }
            Thread.sleep(forTimeInterval: duration)
            lock.withLock {
                running -= 1
                finished.append(target.workspaceName)
            }
        }

        var didOverlap: Bool { lock.withLock { overlapped } }
        var order: [String] { lock.withLock { finished } }
    }

    private func session(id: String, terminal: String = "Ghostty") -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "",
            updatedAt: .now,
            jumpTarget: JumpTarget(terminalApp: terminal, workspaceName: id, paneTitle: "claude")
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test
    func aDeniedJumpAsksForAutomationWithTheAppsName() async throws {
        let model = AppModel(terminalJumpAction: { _ in
            TerminalJumpResult(message: "Activated Ghostty.", automationDeniedApp: "Ghostty")
        })
        model.overlay.noticeDisplayDuration = 60

        model.jumpToSession(session(id: "denied"))
        try await waitUntil { model.notice != nil }

        #expect(model.notice?.message.contains("Allow NotchTune to control Ghostty") == true)
        #expect(model.notice?.action == .openPrivacyPane(.automation))
    }

    @Test
    func aFailedJumpAndAnUnknownTerminalBothSaySo() async throws {
        struct Failed: Error {}
        let model = AppModel(terminalJumpAction: { _ in throw Failed() })
        model.overlay.noticeDisplayDuration = 60

        model.jumpToSession(session(id: "unknown", terminal: "Unknown"))
        #expect(model.notice?.message.contains("doesn't know which terminal") == true)
        model.dismissNotice()

        model.jumpToSession(session(id: "failed"))
        try await waitUntil { model.notice != nil }
        #expect(model.notice?.message.contains("Ghostty") == true)
    }

    @Test
    func quickJumpsNeverRunAtOnceAndTheLastOneWins() async throws {
        let log = JumpLog()
        let model = AppModel(terminalJumpAction: { target in
            log.run(target)
            return TerminalJumpResult(message: target.workspaceName)
        })

        model.jumpToSession(session(id: "first"))
        // Past the lead time, so the first is underway when the rest arrive.
        try await Task.sleep(for: .milliseconds(40))
        model.jumpToSession(session(id: "second"))
        model.jumpToSession(session(id: "third"))

        try await waitUntil { log.order.contains("third") }

        #expect(log.didOverlap == false)
        // The second was replaced before it started, so it never ran.
        #expect(log.order == ["first", "third"])
        #expect(model.lastActionMessage == "third")
    }

    // MARK: - Actions

    @Test
    func privacyPanesPointAtTheirAnchors() {
        #expect(
            AppNotice.PrivacyPane.automation.settingsURL?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        )
    }

    @Test
    func aNoticeWithoutAnActionHasNothingToPerform() {
        let model = makeModel()
        let plain = AppNotice(message: "Couldn't jump.")
        model.post(plain)

        model.performNoticeAction()

        #expect(model.notice?.id == plain.id)
    }

    @Test
    func aBridgeThatWontStartStaysOnScreenAndOffersARetry() {
        struct Refused: Error {}
        let model = makeModel()
        model.bridgeStarter = { throw Refused() }

        model.startIfNeeded(startBridge: true, shouldPerformBootAnimation: false, loadRuntimeState: false)

        #expect(model.bridgeStartFailed)
        #expect(model.notice?.action == .retryBridge)
        #expect(model.notice?.actionTitle == "Try Again")
    }
}
