import AppKit
import Foundation

/// Reopens NotchTune when it exits without quitting: a crash, or the system
/// killing it. Otherwise the notch just vanishes and nobody notices until
/// they reach for it.
///
/// A small shell process watches this one. Quitting (the menu, Sparkle, a
/// logout, `kill`) leaves a marker first, so the watcher stands down; any
/// other exit reopens the app in the background. Capped at a few reopens an
/// hour so a crash at launch can't loop.
@MainActor
enum CrashRelauncher {
    static let defaultsKey = "app.relaunchAfterCrash"
    nonisolated static let relaunchArgument = "--relaunched-after-crash"
    static let historyKey = "app.crashRelaunches"
    nonisolated static let maxRelaunchesPerHour = 3

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// This launch is the watcher reopening the app after a crash.
    static var wasRelaunchedAfterCrash: Bool {
        CommandLine.arguments.contains(relaunchArgument)
    }

    private static var watcher: Process?
    private static var termSource: DispatchSourceSignal?

    /// The reopens of the last hour, and whether one more is allowed.
    nonisolated static func prune(_ history: [Date], now: Date) -> [Date] {
        history.filter { now.timeIntervalSince($0) < 3600 && $0 <= now }
    }

    nonisolated static func allowsRelaunch(history: [Date], now: Date) -> Bool {
        prune(history, now: now).count < maxRelaunchesPerHour
    }

    /// Records this launch if it was a reopen, then starts watching unless
    /// the cap is reached. Only for the real bundled app: never in the
    /// harness, tests or `swift run`.
    static func start() {
        guard Bundle.main.bundleIdentifier != nil,
              !HarnessHeadless.isActive,
              !HarnessHeadless.isRunningTests else { return }
        installTerminationHandler()

        let defaults = UserDefaults.standard
        let now = Date()
        var history = prune(defaults.array(forKey: historyKey) as? [Date] ?? [], now: now)
        if wasRelaunchedAfterCrash {
            history.append(now)
        }
        defaults.set(history, forKey: historyKey)

        guard isEnabled, allowsRelaunch(history: history, now: now) else { return }
        spawnWatcher()
    }

    /// The watcher can stand down: this exit was asked for.
    static func markCleanExit() {
        FileManager.default.createFile(atPath: markerURL.path, contents: nil)
    }

    /// Turning the setting off mid-run takes effect at once.
    static func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            if watcher == nil, !HarnessHeadless.isActive, !HarnessHeadless.isRunningTests,
               Bundle.main.bundleIdentifier != nil {
                spawnWatcher()
            }
        } else {
            markCleanExit()
            watcher?.terminate()
            watcher = nil
        }
    }

    private static var markerURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("notchtune-clean-exit-\(ProcessInfo.processInfo.processIdentifier)")
    }

    /// Polls every 2 s (a sleeping `sh`, nothing more), then reopens the app
    /// unless the marker says the exit was asked for. Values go in as
    /// arguments, never spliced into the script.
    nonisolated static let watcherScript = """
    pid="$1"; marker="$2"; app="$3"; opener="$4"; poll="$5"
    while kill -0 "$pid" 2>/dev/null; do sleep "$poll"; done
    if [ -e "$marker" ]; then rm -f "$marker"; exit 0; fi
    sleep "$poll"
    exec "$opener" -g "$app" --args \(relaunchArgument)
    """

    /// The watcher's arguments: `/usr/bin/open` reopens the app; tests pass
    /// a stand-in and a shorter poll.
    nonisolated static func watcherArguments(
        pid: Int32, marker: URL, app: URL, opener: String = "/usr/bin/open", poll: String = "2"
    ) -> [String] {
        ["-c", watcherScript, "notchtune-watcher", String(pid), marker.path, app.path, opener, poll]
    }

    private static func spawnWatcher() {
        try? FileManager.default.removeItem(at: markerURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = watcherArguments(
            pid: ProcessInfo.processInfo.processIdentifier,
            marker: markerURL,
            app: Bundle.main.bundleURL
        )
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            watcher = process
        } catch {
            watcher = nil
        }
    }

    /// `kill`, `pkill` and logout send SIGTERM, which AppKit doesn't turn
    /// into a terminate: count it as quitting, not as a crash.
    private static func installTerminationHandler() {
        guard termSource == nil else { return }
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                markCleanExit()
                NSApp.terminate(nil)
            }
        }
        source.resume()
        termSource = source
    }

    // MARK: - The crash report

    /// The newest report macOS wrote for NotchTune, if any.
    nonisolated static func newestCrashReport(
        in directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")
    ) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("NotchTune") && (name.hasSuffix(".ips") || name.hasSuffix(".crash"))
            }
            .max { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l < r
            }
    }

    /// Selects the newest report in Finder, ready to drag into an issue,
    /// or opens the reports folder when there's none yet.
    static func revealCrashReport() {
        if let report = newestCrashReport() {
            NSWorkspace.shared.activateFileViewerSelecting([report])
        } else {
            NSWorkspace.shared.open(
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Logs/DiagnosticReports")
            )
        }
    }
}
