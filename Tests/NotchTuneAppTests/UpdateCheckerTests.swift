import Foundation
import Testing
@testable import NotchTuneApp

struct UpdateAutoInstallTests {
    private let ready = Date(timeIntervalSince1970: 1_000_000)

    private func shouldInstall(
        readyFor: TimeInterval = UpdateAutoInstall.readyDelay,
        idleFor: TimeInterval = UpdateAutoInstall.idleThreshold,
        context: UpdateRestartContext = UpdateRestartContext(),
        automaticDownloads: Bool = true
    ) -> Bool {
        UpdateAutoInstall.shouldInstall(
            readySince: ready,
            now: ready.addingTimeInterval(readyFor),
            idleFor: idleFor,
            context: context,
            automaticDownloads: automaticDownloads
        )
    }

    @Test
    func aDayOldUpdateInstallsOnceTheUserIsAway() {
        #expect(shouldInstall())
    }

    @Test
    func aFreshUpdateWaitsForTheUpdateButtonFirst() {
        #expect(!shouldInstall(readyFor: UpdateAutoInstall.readyDelay - 1))
    }

    @Test
    func someoneAtTheMacIsNeverInterrupted() {
        #expect(!shouldInstall(idleFor: UpdateAutoInstall.idleThreshold - 1))
    }

    @Test
    func aWaitingAgentHoldsTheRestart() {
        #expect(!shouldInstall(context: UpdateRestartContext(agentsWaiting: 1)))
    }

    @Test
    func anOpenMirrorHoldsTheRestart() {
        #expect(!shouldInstall(context: UpdateRestartContext(mirrorOpen: true)))
    }

    @Test
    func turningDownloadsOffLeavesTheRestartToTheUser() {
        #expect(!shouldInstall(automaticDownloads: false))
    }

    @Test
    func nothingPreparedMeansNothingToInstall() {
        #expect(!UpdateAutoInstall.shouldInstall(
            readySince: nil,
            now: ready,
            idleFor: .infinity,
            context: UpdateRestartContext(),
            automaticDownloads: true
        ))
    }
}

@MainActor
struct UpdateCheckerSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "UpdateCheckerSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test
    func automaticDownloadsAreOnByDefault() {
        #expect(UpdateChecker(defaults: makeDefaults()).automaticDownloadsEnabled)
    }

    @Test
    func theOptOutSurvivesARelaunch() {
        let defaults = makeDefaults()
        UpdateChecker(defaults: defaults).automaticDownloadsEnabled = false
        #expect(!UpdateChecker(defaults: defaults).automaticDownloadsEnabled)
    }

    /// Runs "Restart to Update" over `agentsWaiting` and reports whether it
    /// asked and whether the update went in.
    private func restart(agentsWaiting: Int, answer: Bool) -> (asked: Bool, installed: Bool) {
        let checker = UpdateChecker(defaults: makeDefaults())
        defer { checker.clearReadyUpdate() }
        var asked = false
        var installed = false
        checker.restartContext = { UpdateRestartContext(agentsWaiting: agentsWaiting) }
        checker.confirmRestartWithAgentsWaiting = {
            asked = true
            return answer
        }
        checker.updateBecameReady(version: "2.3.0") { installed = true }
        checker.installAndRelaunch()
        return (asked, installed)
    }

    @Test
    func restartingWithNoAgentsWaitingGoesStraightThrough() {
        let result = restart(agentsWaiting: 0, answer: false)
        #expect(!result.asked)
        #expect(result.installed)
    }

    @Test
    func restartingOverWaitingAgentsAsksFirst() {
        #expect(restart(agentsWaiting: 2, answer: false) == (asked: true, installed: false))
        #expect(restart(agentsWaiting: 2, answer: true) == (asked: true, installed: true))
    }

    @Test
    func aFinishedCycleTakesTheUpdateButtonAway() {
        let checker = UpdateChecker(defaults: makeDefaults())
        var installed = false
        checker.updateBecameReady(version: "2.3.0") { installed = true }
        #expect(checker.readyVersion == "2.3.0")
        checker.clearReadyUpdate()
        #expect(checker.readyVersion == nil)
        checker.installAndRelaunch()
        #expect(!installed)
    }

    @Test
    func restartingWithNothingPreparedNeverAsks() {
        let checker = UpdateChecker(defaults: makeDefaults())
        var asked = false
        checker.restartContext = { UpdateRestartContext(agentsWaiting: 2) }
        checker.confirmRestartWithAgentsWaiting = {
            asked = true
            return false
        }
        checker.installAndRelaunch()
        #expect(!asked)
    }
}
