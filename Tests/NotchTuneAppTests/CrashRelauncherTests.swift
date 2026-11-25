import Foundation
import Testing
@testable import NotchTuneApp

@Suite(.serialized)
struct CrashRelauncherTests {
    private let now = Date(timeIntervalSince1970: 100_000)

    @Test
    func reopensAreCappedAtThreeAnHour() {
        #expect(CrashRelauncher.allowsRelaunch(history: [], now: now))
        let two = [now.addingTimeInterval(-60), now.addingTimeInterval(-120)]
        #expect(CrashRelauncher.allowsRelaunch(history: two, now: now))
        let three = two + [now.addingTimeInterval(-1800)]
        #expect(CrashRelauncher.allowsRelaunch(history: three, now: now) == false)
        // Older than an hour no longer counts.
        let stale = two + [now.addingTimeInterval(-3601)]
        #expect(CrashRelauncher.allowsRelaunch(history: stale, now: now))
        #expect(CrashRelauncher.prune(stale, now: now).count == 2)
    }

    @Test
    func theNewestNotchTuneReportIsTheOneShown() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(CrashRelauncher.newestCrashReport(in: dir) == nil)

        let old = dir.appendingPathComponent("NotchTune-2026-11-20-101010.ips")
        let new = dir.appendingPathComponent("NotchTune-2026-11-23-101010.ips")
        let other = dir.appendingPathComponent("Safari-2026-11-24-101010.ips")
        for (url, age) in [(old, -7200.0), (new, -60.0), (other, 0.0)] {
            FileManager.default.createFile(atPath: url.path, contents: Data("{}".utf8))
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(age)], ofItemAtPath: url.path
            )
        }
        #expect(CrashRelauncher.newestCrashReport(in: dir)?.lastPathComponent == new.lastPathComponent)
    }

    // MARK: - The watcher script, run for real with a stand-in for `open`

    @Test
    func aCrashReopensTheAppInTheBackground() throws {
        let run = try watch(cleanExit: false)
        defer { try? FileManager.default.removeItem(at: run.dir) }
        let opened = try String(contentsOf: run.log, encoding: .utf8)
        #expect(opened.trimmingCharacters(in: .whitespacesAndNewlines)
            == "-g \(run.app.path) --args \(CrashRelauncher.relaunchArgument)")
    }

    @Test
    func aQuitLeavesTheAppClosed() throws {
        let run = try watch(cleanExit: true)
        defer { try? FileManager.default.removeItem(at: run.dir) }
        #expect(FileManager.default.fileExists(atPath: run.log.path) == false)
        // The watcher cleans its marker up.
        #expect(FileManager.default.fileExists(atPath: run.marker.path) == false)
    }

    private struct WatchRun {
        let dir: URL
        let log: URL
        let marker: URL
        let app: URL
    }

    /// Watches a short-lived process standing in for NotchTune, and records
    /// what the watcher would have opened instead of opening it.
    private func watch(cleanExit: Bool) throws -> WatchRun {
        let dir = try temporaryDirectory()
        let log = dir.appendingPathComponent("opened.txt")
        let marker = dir.appendingPathComponent("clean-exit")
        let app = dir.appendingPathComponent("Notch Tune.app")
        let opener = dir.appendingPathComponent("open.sh")
        try "#!/bin/sh\necho \"$@\" > \"\(log.path)\"\n".write(to: opener, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: opener.path)

        let notchTune = Process()
        notchTune.executableURL = URL(fileURLWithPath: "/bin/sleep")
        notchTune.arguments = ["0.3"]
        try notchTune.run()

        let watcher = Process()
        watcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        watcher.arguments = CrashRelauncher.watcherArguments(
            pid: notchTune.processIdentifier, marker: marker, app: app, opener: opener.path, poll: "0.1"
        )
        try watcher.run()

        if cleanExit {
            FileManager.default.createFile(atPath: marker.path, contents: nil)
        }
        notchTune.waitUntilExit()
        watcher.waitUntilExit()
        return WatchRun(dir: dir, log: log, marker: marker, app: app)
    }

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashRelauncherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
