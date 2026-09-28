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
