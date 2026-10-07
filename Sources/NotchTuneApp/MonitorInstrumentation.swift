import Foundation
import os

/// Process-wide counters for the background process monitor.
///
/// Every subprocess the monitor spawns and every AppleScript query it sends
/// to a terminal is recorded here, so the monitor's steady-state cost can be
/// measured without a profiler (see `ProcessMonitorBenchmarkTests`). The
/// counters are a single unfair-lock-protected struct; recording is a few
/// nanoseconds and has no observable effect on behaviour.
enum MonitorInstrumentation {
    struct Snapshot: Sendable, Equatable {
        var ticks = 0
        var fullTicks = 0
        var subprocessSpawns = 0
        var appleScriptCalls = 0
        var spawnsByExecutable: [String: Int] = [:]
        var appleScriptCallsByTarget: [String: Int] = [:]
    }

    private static let state = OSAllocatedUnfairLock(initialState: Snapshot())

    static func recordSpawn(executablePath: String) {
        let name = (executablePath as NSString).lastPathComponent
        state.withLock { snapshot in
            snapshot.subprocessSpawns += 1
            snapshot.spawnsByExecutable[name, default: 0] += 1
        }
    }

    static func recordAppleScript(target: String) {
        state.withLock { snapshot in
            snapshot.appleScriptCalls += 1
            snapshot.appleScriptCallsByTarget[target, default: 0] += 1
        }
    }

    static func recordTick(full: Bool) {
        state.withLock { snapshot in
            snapshot.ticks += 1
            if full {
                snapshot.fullTicks += 1
            }
        }
    }

    static func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}
