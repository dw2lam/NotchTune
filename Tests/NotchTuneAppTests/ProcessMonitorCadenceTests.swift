import Foundation
import os
import Testing
@testable import NotchTuneApp
import NotchTuneCore

// MARK: - Terminal snapshot round

struct TerminalSnapshotRoundTests {
    private typealias Ghostty = TerminalSessionAttachmentProbe.GhosttyTerminalSnapshot

    private let snapshot = Ghostty(sessionID: "g-1", workingDirectory: "/tmp/project", title: "claude · project")

    @Test
    func probeAndResolverSeeTheSameAnswerWithTheirOwnBudgets() {
        // Answered within the probe's 1 s budget: both consumers get the data.
        let fast = TerminalSnapshotRound(ghostty: .fetched([snapshot], elapsed: 0.2), terminal: .notRunning)
        #expect(fast.ghosttyAvailability.snapshots?.count == 1)
        #expect(fast.ghosttyAvailability.appIsRunning)
        #expect(fast.terminalAvailability.snapshots?.isEmpty == true)
        #expect(fast.terminalAvailability.appIsRunning == false)
        #expect(fast.isReusable)

        let sources = fast.resolverSources(live: Self.failingLiveSources(), isTmuxRunning: false)
        #expect(sources.ghostty()?.map(\.sessionID) == ["g-1"])
        #expect(sources.terminal()?.isEmpty == true)

        // Slower than the probe's own 1 s timeout, within the resolver's 3 s:
        // the probe treats it as unavailable (as its own query would have
        // timed out), the resolver still uses it.
        let slow = TerminalSnapshotRound(ghostty: .fetched([snapshot], elapsed: 1.6), terminal: .notRunning)
        #expect(slow.ghosttyAvailability.isAuthoritative == false)
        #expect(slow.ghosttyAvailability.appIsRunning)
        #expect(slow.resolverSources(live: Self.failingLiveSources(), isTmuxRunning: false).ghostty()?.count == 1)
        #expect(slow.isReusable == false)

        let failed = TerminalSnapshotRound(ghostty: .failed, terminal: .notRunning)
        #expect(failed.ghosttyAvailability.isAuthoritative == false)
        #expect(failed.resolverSources(live: Self.failingLiveSources(), isTmuxRunning: false).ghostty() == nil)
        #expect(failed.isReusable == false)
    }

    @Test
    func lazySourcesAreFetchedOncePerRoundAndTmuxIsSkippedWithoutATmuxProcess() {
        let tmuxCalls = OSAllocatedUnfairLock(initialState: 0)
        let weztermCalls = OSAllocatedUnfairLock(initialState: 0)
        let live = TerminalJumpTargetResolver.SnapshotSources(
            ghostty: { Issue.record("live Ghostty must not be queried"); return nil },
            terminal: { Issue.record("live Terminal must not be queried"); return nil },
            tmux: {
                tmuxCalls.withLock { $0 += 1 }
                return [TerminalJumpTargetResolver.TmuxPaneSnapshot(paneID: "main:1.0", tty: "/dev/ttys004", title: "zsh")]
            },
            weztermFamily: { _ in
                weztermCalls.withLock { $0 += 1 }
                return []
            }
        )

        let round = TerminalSnapshotRound(ghostty: .notRunning, terminal: .notRunning)

        let withoutTmux = round.resolverSources(live: live, isTmuxRunning: false)
        #expect(withoutTmux.tmux() == nil)
        #expect(tmuxCalls.withLock { $0 } == 0)

        for _ in 0..<3 {
            let sources = round.resolverSources(live: live, isTmuxRunning: true)
            #expect(sources.tmux()?.first?.paneID == "main:1.0")
            #expect(sources.weztermFamily("com.github.wez.wezterm")?.isEmpty == true)
        }
        #expect(tmuxCalls.withLock { $0 } == 1)
        #expect(weztermCalls.withLock { $0 } == 1)
    }

    @Test
    func resolverOnlyAsksForTheTerminalsItsSessionsNeed() {
        let calls = OSAllocatedUnfairLock(initialState: [String]())
        let sources = TerminalJumpTargetResolver.SnapshotSources(
            ghostty: { calls.withLock { $0.append("ghostty") }; return [] },
            terminal: { calls.withLock { $0.append("terminal") }; return [] },
            tmux: { calls.withLock { $0.append("tmux") }; return nil },
            weztermFamily: { _ in calls.withLock { $0.append("wezterm") }; return [] }
        )

        let session = AgentSession(
            id: "terminal-session",
            title: "Claude · project",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "",
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                workspaceName: "project",
                paneTitle: "claude",
                workingDirectory: "/tmp/project",
                terminalTTY: "/dev/ttys009"
            )
        )

        _ = TerminalJumpTargetResolver().resolveJumpTargets(
            for: [session],
            activeProcesses: [],
            sources: sources
        )
        #expect(calls.withLock { $0 } == ["tmux", "terminal"])
    }

    private static func failingLiveSources() -> TerminalJumpTargetResolver.SnapshotSources {
        TerminalJumpTargetResolver.SnapshotSources(
            ghostty: { nil },
            terminal: { nil },
            tmux: { nil },
            weztermFamily: { _ in nil }
        )
    }
}
