import AppKit
import Darwin
import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

/// Opt-in benchmark for the background process monitor. It runs the real
/// monitor tick against this machine's real processes and terminals (the
/// same read-only `ps`/`lsof`/AppleScript queries the app makes), so it is
/// skipped unless explicitly enabled:
///
///     NOTCHTUNE_MONITOR_BENCH=1 swift test --filter ProcessMonitorBenchmarkTests
///
/// Optional knobs: `NOTCHTUNE_MONITOR_BENCH_TICKS` (back-to-back ticks for the
/// per-tick numbers, default 8) and `NOTCHTUNE_MONITOR_BENCH_SECONDS` (length
/// of the steady-state loop run, default 30).
@MainActor
@Suite(.serialized)
struct ProcessMonitorBenchmarkTests {
    nonisolated static let isEnabled = ProcessInfo.processInfo.environment["NOTCHTUNE_MONITOR_BENCH"] == "1"

    private final class StateBox {
        var state = SessionState()
        var writes = 0
    }

    private struct Meter {
        var wallNs: UInt64
        var cpuNs: UInt64
        var childCPUNs: UInt64
        var ghosttyCPUNs: UInt64
        var counters: MonitorInstrumentation.Snapshot

        static func now() -> Meter {
            Meter(
                wallNs: clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW),
                cpuNs: clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID),
                childCPUNs: childrenCPUNs(),
                ghosttyCPUNs: ghosttyCPUNs(),
                counters: MonitorInstrumentation.snapshot()
            )
        }

        static func childrenCPUNs() -> UInt64 {
            var usage = rusage()
            getrusage(RUSAGE_CHILDREN, &usage)
            func ns(_ value: timeval) -> UInt64 {
                UInt64(value.tv_sec) * 1_000_000_000 + UInt64(value.tv_usec) * 1_000
            }
            return ns(usage.ru_utime) + ns(usage.ru_stime)
        }

        /// CPU consumed by Ghostty itself (it answers the AppleScript
        /// queries). Noisy — Ghostty also renders — so indicative only.
        static func ghosttyCPUNs() -> UInt64 {
            guard let pid = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.mitchellh.ghostty")
                .first?.processIdentifier else {
                return 0
            }
            var info = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard result == 0 else {
                return 0
            }
            var timebase = mach_timebase_info_data_t()
            mach_timebase_info(&timebase)
            let ticks = info.ri_user_time + info.ri_system_time
            return ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
        }
    }

    private struct Delta {
        var wallMs: Double
        var cpuMs: Double
        var childCPUMs: Double
        var ghosttyCPUMs: Double
        var ticks: Int
        var fullTicks: Int
        var spawns: Int
        var appleScripts: Int
        var spawnsByExecutable: [String: Int]
        var appleScriptsByTarget: [String: Int]

        init(_ start: Meter, _ end: Meter) {
            wallMs = Double(end.wallNs - start.wallNs) / 1e6
            cpuMs = Double(end.cpuNs - start.cpuNs) / 1e6
            childCPUMs = Double(end.childCPUNs - start.childCPUNs) / 1e6
            ghosttyCPUMs = Double(end.ghosttyCPUNs &- start.ghosttyCPUNs) / 1e6
            ticks = end.counters.ticks - start.counters.ticks
            fullTicks = end.counters.fullTicks - start.counters.fullTicks
            spawns = end.counters.subprocessSpawns - start.counters.subprocessSpawns
            appleScripts = end.counters.appleScriptCalls - start.counters.appleScriptCalls
            spawnsByExecutable = end.counters.spawnsByExecutable.reduce(into: [:]) { result, entry in
                let delta = entry.value - (start.counters.spawnsByExecutable[entry.key] ?? 0)
                if delta > 0 { result[entry.key] = delta }
            }
            appleScriptsByTarget = end.counters.appleScriptCallsByTarget.reduce(into: [:]) { result, entry in
                let delta = entry.value - (start.counters.appleScriptCallsByTarget[entry.key] ?? 0)
                if delta > 0 { result[entry.key] = delta }
            }
        }
    }

    private static let syntheticPrefix = "claude-process:"

    /// Builds a coordinator whose state is seeded with one live, hook-managed
    /// session per agent process currently running on this machine — the
    /// shape the real app has while those agents are tracked.
    private func makeCoordinator() -> (ProcessMonitoringCoordinator, StateBox, Int) {
        let box = StateBox()
        let coordinator = ProcessMonitoringCoordinator()
        coordinator.syntheticClaudeSessionPrefix = Self.syntheticPrefix
        coordinator.stateAccessor = { box.state }
        coordinator.stateUpdater = {
            box.state = $0
            box.writes += 1
        }

        let processes = ActiveAgentProcessDiscovery().discover()
        let now = Date.now
        let sessions = processes.map { process -> AgentSession in
            let cwd = process.workingDirectory
            let workspace = cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Workspace"
            var session = AgentSession(
                id: process.sessionID ?? UUID().uuidString.lowercased(),
                title: "\(process.tool.rawValue) · \(workspace)",
                tool: process.tool,
                origin: .live,
                attachmentState: .attached,
                phase: .running,
                summary: "Benchmark session",
                updatedAt: now,
                jumpTarget: JumpTarget(
                    terminalApp: process.terminalApp ?? "Ghostty",
                    workspaceName: workspace,
                    paneTitle: "Agent \(workspace)",
                    workingDirectory: cwd,
                    terminalTTY: process.terminalTTY
                )
            )
            session.isHookManaged = true
            session.isProcessAlive = true
            return session
        }
        box.state = SessionState(sessions: sessions)
        return (coordinator, box, processes.count)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func report(_ label: String, _ delta: Delta, per divisor: Double, unit: String) {
        print("""
        BENCH \(label): wall=\(format(delta.wallMs / divisor))ms cpu(self)=\(format(delta.cpuMs / divisor))ms \
        cpu(children)=\(format(delta.childCPUMs / divisor))ms cpu(ghostty)=\(format(delta.ghosttyCPUMs / divisor))ms \
        spawns=\(format(Double(delta.spawns) / divisor)) applescript=\(format(Double(delta.appleScripts) / divisor)) per \(unit) \
        | ticks=\(delta.ticks) full=\(delta.fullTicks) spawnsBy=\(delta.spawnsByExecutable.sorted { $0.key < $1.key }) \
        appleScriptBy=\(delta.appleScriptsByTarget.sorted { $0.key < $1.key })
        """)
    }

    @Test(.enabled(if: ProcessMonitorBenchmarkTests.isEnabled))
    func perTickCost() async {
        let tickCount = Int(ProcessInfo.processInfo.environment["NOTCHTUNE_MONITOR_BENCH_TICKS"] ?? "") ?? 8
        let (coordinator, box, processCount) = makeCoordinator()
        print("BENCH setup: \(processCount) agent processes, \(box.state.sessions.count) seeded sessions")

        // Discovery alone.
        let discovery = coordinator.activeAgentProcessDiscovery
        _ = discovery.discover()
        let discoveryStart = Meter.now()
        for _ in 0..<tickCount {
            _ = discovery.discover()
        }
        report("discover()", Delta(discoveryStart, Meter.now()), per: Double(tickCount), unit: "call")

        // Warm-up tick (startup reconcile, first snapshots).
        await coordinator.runMonitorTick()
        let writesBefore = box.writes
        let start = Meter.now()
        for _ in 0..<tickCount {
            await coordinator.runMonitorTick()
        }
        let delta = Delta(start, Meter.now())
        report("back-to-back tick", delta, per: Double(tickCount), unit: "tick")
        print("BENCH back-to-back tick: state writes=\(box.writes - writesBefore) over \(tickCount) ticks")
    }

    @Test(.enabled(if: ProcessMonitorBenchmarkTests.isEnabled))
    func steadyStateLoop() async {
        let seconds = Double(ProcessInfo.processInfo.environment["NOTCHTUNE_MONITOR_BENCH_SECONDS"] ?? "") ?? 30
        let (coordinator, box, _) = makeCoordinator()
        // Let startup settle (first reconcile + initial fast ticks).
        coordinator.reconcileSessionAttachments()
        coordinator.startMonitoringIfNeeded()
        try? await Task.sleep(for: .seconds(6))

        let writesBefore = box.writes
        let start = Meter.now()
        try? await Task.sleep(for: .seconds(seconds))
        let delta = Delta(start, Meter.now())
        coordinator.stopMonitoring()

        let minutes = delta.wallMs / 60_000
        report("steady-state loop (\(Int(seconds))s)", delta, per: minutes, unit: "minute")
        let meanInterval = delta.ticks > 0 ? delta.wallMs / 1000 / Double(delta.ticks) : 0
        print("BENCH steady-state loop: mean tick interval=\(format(meanInterval))s state writes=\(box.writes - writesBefore)")
    }
}

