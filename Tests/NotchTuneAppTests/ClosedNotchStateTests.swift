import Testing
@testable import NotchTuneApp

struct ClosedNotchStateTests {
    private func state(
        notification: Bool = false,
        music: Bool = false,
        collapses: Bool = false,
        live: Bool = false
    ) -> ClosedNotchState {
        .resolve(
            showsMusicNotification: notification,
            showsCompactMusic: music,
            collapsesBehindNotch: collapses,
            hasLiveActivity: live
        )
    }

    @Test
    func eachStateResolves() {
        #expect(state() == .pill)
        #expect(state(live: true) == .liveActivity)
        #expect(state(collapses: true) == .hidden)
        #expect(state(music: true) == .compactMusic)
        #expect(state(notification: true) == .musicNotification)
    }

    @Test
    func theOrderOfPrecedenceHolds() {
        // A track change outranks everything, and music never hides.
        #expect(state(notification: true, music: true, collapses: true, live: true) == .musicNotification)
        #expect(state(music: true, collapses: true, live: true) == .compactMusic)
        // Collapsed beats a live activity: auto-hide wins until a peek.
        #expect(state(collapses: true, live: true) == .hidden)
    }

    @Test
    func aCloseOnlyTucksIntoTheNotchWithNothingToShow() {
        #expect(ClosedNotchState.hidden.closesIntoHardwareNotch)
        for state in [ClosedNotchState.pill, .liveActivity, .compactMusic, .musicNotification] {
            #expect(!state.closesIntoHardwareNotch)
        }
    }

    @Test
    func theCloseTimelineStaysInOrder() {
        #expect(CloseMorph.pillFadeDelay + CloseMorph.pillFadeDuration < CloseMorph.surfaceUnmount)
        #expect(CloseMorph.duration < CloseMorph.surfaceUnmount)
        #expect(CloseMorph.surfaceUnmount < CloseMorph.settled)
    }

    @Test @MainActor
    func aCloseHoldsThePanelThenLetsGo() async throws {
        let model = AppModel()
        model.notchOpen(reason: .click)
        model.islandActiveTab = .mirror
        model.notchClose()

        // The morph runs over what was on the panel.
        #expect(model.overlay.presentedOpenReason == .click)
        #expect(model.islandActiveTab == .mirror)

        try await Task.sleep(for: .seconds(CloseMorph.settled + 0.15))
        #expect(model.overlay.presentedOpenReason == nil)
        #expect(model.islandActiveTab == .agents)
    }

    @Test @MainActor
    func reopeningMidCloseLeavesMirrorSoAHoverCantStartTheCamera() {
        let model = AppModel()
        model.notchOpen(reason: .click)
        model.islandActiveTab = .mirror
        model.notchClose()
        model.notchOpen(reason: .hover)

        #expect(model.islandActiveTab == .agents)
        #expect(model.overlay.presentedOpenReason == .hover)
    }

    @Test @MainActor
    func aSecondCloseDoesNotCutTheHoldShort() {
        let model = AppModel()
        model.notchOpen(reason: .click)
        model.notchClose()
        model.notchClose()

        #expect(model.overlay.presentedOpenReason == .click)
    }
}
