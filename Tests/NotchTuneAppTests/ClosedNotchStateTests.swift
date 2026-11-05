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
    func onlyMusicStatesUseTheMusicSurface() {
        #expect(ClosedNotchState.compactMusic.showsMusicSurface)
        #expect(ClosedNotchState.musicNotification.showsMusicSurface)
        #expect(!ClosedNotchState.pill.showsMusicSurface)
        #expect(!ClosedNotchState.liveActivity.showsMusicSurface)
        #expect(!ClosedNotchState.hidden.showsMusicSurface)
    }
}
