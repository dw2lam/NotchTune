import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

struct HoverAndMusicChipTests {
    @Test
    func hoverOpenModesHaveIncreasingDwellAndOffNeverOpens() {
        #expect(HoverOpenMode.off.delay == nil)
        let delays = [HoverOpenMode.quick, .normal, .relaxed].compactMap(\.delay)
        #expect(delays == delays.sorted())
        #expect(HoverOpenMode.normal.delay! > 0.15)
    }

    @Test
    func musicChipWidensTheRightWingByItsWidth() {
        var activity = IslandLiveActivity(
            kind: .working, sessionID: "s", tool: .codex,
            title: "Codex · repo", subtitle: "Running swift test",
            since: .now, otherCount: 0
        )
        let without = activity.trailingWidth
        activity.showsMusicChip = true
        #expect(activity.trailingWidth == without + IslandLiveActivity.musicChipWidth)
    }
}

struct MusicSwipeSkipTests {
    @Test
    func aSwipeSkipLeavesAnAgentPillAlone() {
        // The arrows answered the swipe: the new track must not swap a
        // working agent's pill over to the music surface, or pop the notch.
        #expect(MusicTrackNotificationOutcome.resolve(
            trackChanged: true, fromSwipe: true, musicOwnsPill: false, notchClosed: true
        ) == .ignore)
    }

    @Test
    func aSwipeSkipUpdatesTheMusicPillWithoutPopping() {
        #expect(MusicTrackNotificationOutcome.resolve(
            trackChanged: true, fromSwipe: true, musicOwnsPill: true, notchClosed: true
        ) == .show)
    }

    @Test
    func aTrackChangeFromElsewhereStillPops() {
        #expect(MusicTrackNotificationOutcome.resolve(
            trackChanged: true, fromSwipe: false, musicOwnsPill: false, notchClosed: true
        ) == .showAndPop)
        #expect(MusicTrackNotificationOutcome.resolve(
            trackChanged: false, fromSwipe: false, musicOwnsPill: true, notchClosed: true
        ) == .show)
    }

    @MainActor
    @Test
    func showingSkipFeedbackMarksTheComingTrackChangeAsTheSwipes() {
        let model = AppModel()
        #expect(!model.isTrackChangeFromSwipe)
        model.showMusicSkipFeedback(.next)
        #expect(model.isTrackChangeFromSwipe)
        #expect(model.musicSkipFeedback?.direction == .next)
    }

    @MainActor
    @Test
    func skipArrowsRunTheirWaveInCoreAnimation() {
        let view = MusicSkipArrowsNSView(frame: NSRect(x: 0, y: 0, width: 30, height: 32))
        view.configure(direction: .previous, layout: MusicSkipArrowsLayout(height: 32))
        #expect(view.runningAnimationKeys.count == 2)
        #expect(view.runningAnimationKeys.allSatisfy { $0 == ["glow", "nudge"] })
    }
}
