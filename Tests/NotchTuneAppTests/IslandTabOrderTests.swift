import Testing
@testable import NotchTuneApp

struct IslandTabOrderTests {
    @Test
    func aSavedOrderIsRestored() {
        let order = IslandTab.order(stored: ["mirror", "agents", "music", "reminders", "myspace"])
        #expect(order == [.mirror, .agents, .music, .reminders, .myspace])
    }

    @Test
    func aSavedOrderIsAlwaysEveryTabExactlyOnce() {
        // Nothing saved yet.
        #expect(IslandTab.order(stored: []) == IslandTab.allCases)
        // Unknown names, repeats, and a tab added since it was saved.
        let order = IslandTab.order(stored: ["music", "calculator", "music", "agents"])
        #expect(order == [.music, .agents, .myspace, .reminders, .mirror])
    }

    @Test
    func draggingTakesTheTargetsPlaceInBothDirections() {
        let start = IslandTab.allCases
        #expect(IslandTab.order(start, moving: .mirror, onto: .agents) == [.mirror, .agents, .music, .myspace, .reminders])
        #expect(IslandTab.order(start, moving: .agents, onto: .mirror) == [.music, .myspace, .reminders, .mirror, .agents])
    }

    @Test
    func movingStopsAtTheEnds() {
        let start = IslandTab.allCases
        #expect(IslandTab.order(start, moving: .agents, by: -1) == start)
        #expect(IslandTab.order(start, moving: .mirror, by: 1) == start)
        #expect(IslandTab.order(start, moving: .music, by: 1) == [.agents, .myspace, .music, .reminders, .mirror])
    }
}
