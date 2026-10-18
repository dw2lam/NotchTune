import Foundation
import Testing
@testable import NotchTuneApp

/// General's welcome: the greeting for the hour, the name it uses, and the
/// one-line status of the island.
struct SettingsWelcomeTests {
    @Test
    func theGreetingFollowsTheHour() {
        let expected: [(Int, SettingsWelcome.DayPart)] = [
            (0, .night), (4, .night), (5, .morning), (11, .morning),
            (12, .afternoon), (16, .afternoon), (17, .evening), (21, .evening),
            (22, .night), (23, .night),
        ]
        for (hour, part) in expected {
            #expect(SettingsWelcome.dayPart(forHour: hour) == part, "hour \(hour)")
        }
    }

    @Test
    func theGreetingUsesTheFirstNameOrNone() {
        #expect(SettingsWelcome.firstName(fromFullName: "David Lam") == "David")
        #expect(SettingsWelcome.firstName(fromFullName: "  Ada  Lovelace ") == "Ada")
        #expect(SettingsWelcome.firstName(fromFullName: "Prince") == "Prince")
        #expect(SettingsWelcome.firstName(fromFullName: "") == nil)
        #expect(SettingsWelcome.firstName(fromFullName: "   ") == nil)
    }

    @Test
    func anAgentThatNeedsYouOutranksWork() {
        #expect(SettingsWelcome.agents(attentionCount: 2, runningCount: 3) == .needYou(2))
        #expect(SettingsWelcome.agents(attentionCount: 0, runningCount: 3) == .working(3))
        #expect(SettingsWelcome.agents(attentionCount: 0, runningCount: 0) == .quiet)
    }

    @Test
    func theCharacterPosesLikeTheIsland() {
        #expect(SettingsWelcome.Agents.needYou(1).mode == .waiting)
        #expect(SettingsWelcome.Agents.working(1).mode == .running)
        #expect(SettingsWelcome.Agents.quiet.mode == .idle)
    }

    @Test
    func nowPlayingNamesOnlyAPlayingTrack() {
        #expect(SettingsWelcome.nowPlaying(title: "Teardrop", artist: "Massive Attack", isPlaying: true) == "Teardrop — Massive Attack")
        #expect(SettingsWelcome.nowPlaying(title: "Teardrop", artist: " ", isPlaying: true) == "Teardrop")
        #expect(SettingsWelcome.nowPlaying(title: "Teardrop", artist: "Massive Attack", isPlaying: false) == nil)
        #expect(SettingsWelcome.nowPlaying(title: "", artist: "Massive Attack", isPlaying: true) == nil)
    }
}

/// The app line and update status that moved onto General from About and
/// Updates.
struct SettingsWelcomeAppTests {
    @Test
    func theVersionCarriesItsBuildWhenItHasOne() {
        #expect(SettingsWelcome.versionLine(version: "2.1.5", build: "1180") == "2.1.5 (1180)")
        #expect(SettingsWelcome.versionLine(version: "2.1.5", build: nil) == "2.1.5")
        #expect(SettingsWelcome.versionLine(version: "2.1.5", build: "2.1.5") == "2.1.5")
        #expect(SettingsWelcome.versionLine(version: nil, build: "1180") == nil)
        #expect(SettingsWelcome.versionLine(version: " ", build: "1180") == nil)
    }

    @Test
    func theUpdateLineSaysTheMostPressingThing() {
        let checked = Date(timeIntervalSince1970: 1_000)
        #expect(SettingsWelcome.updateStatus(isChecking: true, availableVersion: "2.2.0", lastCheck: checked) == .checking)
        #expect(SettingsWelcome.updateStatus(isChecking: false, availableVersion: "2.2.0", lastCheck: checked) == .available("2.2.0"))
        #expect(SettingsWelcome.updateStatus(isChecking: false, availableVersion: nil, lastCheck: checked) == .upToDate(checkedAt: checked))
        #expect(SettingsWelcome.updateStatus(isChecking: false, availableVersion: nil, lastCheck: nil) == .automatic)
    }
}
