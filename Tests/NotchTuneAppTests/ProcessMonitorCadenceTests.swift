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

// MARK: - Monitor cadence

@MainActor
@Suite(.serialized)
struct ProcessMonitorCadenceTests {
    private final class StateBox {
        var state = SessionState()
    }

    /// Fake `ps`/`lsof` output the discovery reads through its command runner.
    private final class FakeProcesses: Sendable {
        private let table = OSAllocatedUnfairLock(initialState: "")
        private let psCalls = OSAllocatedUnfairLock(initialState: 0)

        func set(_ value: String) {
            table.withLock { $0 = value }
        }

        var psCallCount: Int {
            psCalls.withLock { $0 }
        }

        func run(_ executable: String, _ arguments: [String]) -> String? {
            switch executable {
            case "/bin/ps":
                psCalls.withLock { $0 += 1 }
                return table.withLock { $0 }
            case "/usr/sbin/lsof":
                let pid = arguments.dropFirst(2).first ?? "0"
                return "fcwd\nn/tmp/project-\(pid)"
            default:
                return nil
            }
        }
    }

    private final class FetchCounter: Sendable {
        private let count = OSAllocatedUnfairLock(initialState: 0)

        var value: Int {
            count.withLock { $0 }
        }

        func fetch() -> TerminalSnapshotRound {
            count.withLock { $0 += 1 }
            // Mirror this machine's running terminals so the cheap
            // launched/quit check does not force a refresh by itself.
            let running = TerminalSnapshotRound.currentRunningApps()
            return TerminalSnapshotRound(
                ghostty: running.ghostty ? .fetched([], elapsed: 0.01) : .notRunning,
                terminal: running.terminal ? .fetched([], elapsed: 0.01) : .notRunning
            )
        }
    }

    // Agent pids are real, long-lived processes (this test process and its
    // parent): the monitor puts kqueue exit watchers on discovered agents,
    // and a watcher on a nonexistent pid fires immediately.
    private static let firstAgentPID = getpid()
    private static let secondAgentPID = getppid()

    private static let oneAgent = """
      \(firstAgentPID) 301 ttys002 claude
      301 900 ttys002 -/bin/zsh
      900 1 ?? /Applications/Ghostty.app/Contents/MacOS/ghostty
    """

    private static let twoAgents = oneAgent + """

      \(secondAgentPID) 302 ttys003 claude
      302 900 ttys003 -/bin/zsh
    """

    private static let firstAgentCWD = "/tmp/project-\(firstAgentPID)"
    private static let secondAgentCWD = "/tmp/project-\(secondAgentPID)"

    private func session(id: String, cwd: String) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · project",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "",
            updatedAt: .now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "project",
                paneTitle: "claude",
                workingDirectory: cwd
            )
        )
        session.isHookManaged = true
        session.isProcessAlive = true
        return session
    }

    private func makeCoordinator(
        processes: FakeProcesses,
        counter: FetchCounter
    ) -> (ProcessMonitoringCoordinator, StateBox) {
        let box = StateBox()
        let coordinator = ProcessMonitoringCoordinator(
            activeAgentProcessDiscovery: ActiveAgentProcessDiscovery { executable, arguments in
                processes.run(executable, arguments)
            },
            terminalRoundFetcher: { _ in counter.fetch() }
        )
        coordinator.syntheticClaudeSessionPrefix = "claude-process:"
        coordinator.stateAccessor = { box.state }
        coordinator.stateUpdater = { box.state = $0 }
        return (coordinator, box)
    }

    @Test
    func terminalSnapshotsAreReusedUntilSomethingChanges() async {
        let processes = FakeProcesses()
        processes.set(Self.oneAgent)
        let counter = FetchCounter()
        let (coordinator, box) = makeCoordinator(processes: processes, counter: counter)
        defer { coordinator.stopMonitoring() }
        box.state = SessionState(sessions: [session(id: "s-1", cwd: Self.firstAgentCWD)])

        await coordinator.runMonitorTick()
        #expect(counter.value == 1)

        // Nothing changed: light ticks reuse the round.
        await coordinator.runMonitorTick()
        await coordinator.runMonitorTick()
        #expect(counter.value == 1)
        #expect(processes.psCallCount == 3)

        // A new agent process appears.
        processes.set(Self.twoAgents)
        await coordinator.runMonitorTick()
        #expect(counter.value == 2)
        await coordinator.runMonitorTick()
        #expect(counter.value == 2)

        // Tracked sessions change outside the monitor (e.g. a bridge event).
        var sessions = box.state.sessions
        sessions.append(session(id: "s-2", cwd: Self.secondAgentCWD))
        box.state = SessionState(sessions: sessions)
        await coordinator.runMonitorTick()
        #expect(counter.value == 3)
        await coordinator.runMonitorTick()
        #expect(counter.value == 3)

        // An agent exits.
        processes.set(Self.oneAgent)
        await coordinator.runMonitorTick()
        #expect(counter.value == 4)

        // Snapshots past their maximum age are refreshed.
        coordinator.invalidateTerminalSnapshots()
        await coordinator.runMonitorTick()
        #expect(counter.value == 5)
    }

    @Test
    func noTerminalQueriesWithoutSessionsOrAgents() async {
        let processes = FakeProcesses()
        processes.set("  900 1 ?? /Applications/Ghostty.app/Contents/MacOS/ghostty")
        let counter = FetchCounter()
        let (coordinator, _) = makeCoordinator(processes: processes, counter: counter)
        defer { coordinator.stopMonitoring() }

        await coordinator.runMonitorTick()
        await coordinator.runMonitorTick()
        #expect(counter.value == 0)
    }

    @Test
    func cadenceBacksOffWhenStableAndStaysFastWhileAttentionIsNeeded() async {
        let processes = FakeProcesses()
        processes.set(Self.oneAgent)
        let counter = FetchCounter()
        let (coordinator, box) = makeCoordinator(processes: processes, counter: counter)
        defer { coordinator.stopMonitoring() }
        box.state = SessionState(sessions: [session(id: "s-1", cwd: Self.firstAgentCWD)])

        // With no fast window left, a stable monitor backs off…
        coordinator.fastCadenceWindow = .zero
        await coordinator.runMonitorTick()
        #expect(await coordinator.runMonitorTick() == ProcessMonitoringCoordinator.idleTickInterval)

        // …but not while a session waits for the user,
        var waiting = box.state.sessions[0]
        waiting.phase = .waitingForApproval
        box.state = SessionState(sessions: [waiting])
        #expect(await coordinator.runMonitorTick() == ProcessMonitoringCoordinator.activeTickInterval)
        #expect(await coordinator.runMonitorTick() == ProcessMonitoringCoordinator.activeTickInterval)

        // nor while initial sessions are still resolving.
        waiting.phase = .running
        box.state = SessionState(sessions: [waiting])
        #expect(await coordinator.runMonitorTick() == ProcessMonitoringCoordinator.idleTickInterval)
        coordinator.isResolvingInitialLiveSessions = true
        #expect(await coordinator.runMonitorTick() == ProcessMonitoringCoordinator.activeTickInterval)
    }

    @Test
    func cadenceStaysFastForAWhileAfterAChange() async {
        let processes = FakeProcesses()
        processes.set(Self.oneAgent)
        let counter = FetchCounter()
        let (coordinator, box) = makeCoordinator(processes: processes, counter: counter)
        defer { coordinator.stopMonitoring() }
        box.state = SessionState(sessions: [session(id: "s-1", cwd: Self.firstAgentCWD)])
        coordinator.fastCadenceWindow = .seconds(60)

        // The first tick sees everything as new; later stable ticks stay at
        // the original cadence until the window has passed.
        #expect(await coordinator.runMonitorTick() == ProcessMonitoringCoordinator.activeTickInterval)
        #expect(await coordinator.runMonitorTick() == ProcessMonitoringCoordinator.activeTickInterval)
        #expect(await coordinator.runMonitorTick() == ProcessMonitoringCoordinator.activeTickInterval)
    }

    @Test
    func promptTickRequestCutsTheIdleWaitShort() async throws {
        let processes = FakeProcesses()
        processes.set(Self.oneAgent)
        let counter = FetchCounter()
        let (coordinator, box) = makeCoordinator(processes: processes, counter: counter)
        defer { coordinator.stopMonitoring() }
        box.state = SessionState(sessions: [session(id: "s-1", cwd: Self.firstAgentCWD)])
        coordinator.fastCadenceWindow = .zero

        // Settle so the loop's next wait is the 5 s idle interval.
        await coordinator.runMonitorTick()
        await coordinator.runMonitorTick()
        let ticksBefore = processes.psCallCount

        coordinator.startMonitoringIfNeeded()
        try await waitUntil(timeout: .seconds(1)) { processes.psCallCount == ticksBefore + 1 }

        coordinator.requestPromptTick()
        // Next tick no sooner than 2 s after the previous one started, and
        // well before the 5 s idle interval would have elapsed.
        let woken = try await waitUntil(timeout: .milliseconds(3_500)) { processes.psCallCount == ticksBefore + 2 }
        #expect(woken)
    }

    @Test
    func agentProcessExitCutsTheIdleWaitShort() async throws {
        let agent = Process()
        agent.executableURL = URL(fileURLWithPath: "/bin/sleep")
        agent.arguments = ["30"]
        try agent.run()
        defer {
            if agent.isRunning {
                agent.terminate()
            }
            agent.waitUntilExit()
        }

        let agentPID = agent.processIdentifier
        let processes = FakeProcesses()
        processes.set("""
          \(agentPID) 301 ttys002 claude
          301 900 ttys002 -/bin/zsh
          900 1 ?? /Applications/Ghostty.app/Contents/MacOS/ghostty
        """)
        let counter = FetchCounter()
        let (coordinator, box) = makeCoordinator(processes: processes, counter: counter)
        defer { coordinator.stopMonitoring() }
        box.state = SessionState(sessions: [session(id: "s-1", cwd: "/tmp/project-\(agentPID)")])
        coordinator.fastCadenceWindow = .zero

        await coordinator.runMonitorTick()
        await coordinator.runMonitorTick()
        let ticksBefore = processes.psCallCount

        coordinator.startMonitoringIfNeeded()
        try await waitUntil(timeout: .seconds(1)) { processes.psCallCount == ticksBefore + 1 }

        // The agent exits during the 5 s idle wait: its exit watcher wakes the
        // monitor at the original 2 s cadence.
        agent.terminate()
        let woken = try await waitUntil(timeout: .milliseconds(3_500)) { processes.psCallCount == ticksBefore + 2 }
        #expect(woken)
    }

    @discardableResult
    private func waitUntil(timeout: Duration, _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }
}
