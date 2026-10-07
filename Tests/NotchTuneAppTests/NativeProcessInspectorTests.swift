import Darwin
import Foundation
import Testing
@testable import NotchTuneApp

/// The native process table / open-file reader must agree with the `ps` and
/// `lsof` output the process monitor used to parse.
struct NativeProcessInspectorTests {
    private func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else {
            return path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    @Test
    func processTableAndCommandLineMatchPSForAChildProcess() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("native-inspector-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        child.currentDirectoryURL = directory
        try child.run()
        defer {
            child.terminate()
            child.waitUntilExit()
        }
        let pid = child.processIdentifier

        let table = try #require(NativeProcessInspector.processTable())
        let entry = try #require(table.first { $0.pid == pid })
        #expect(entry.parentPID == getpid())
        #expect(entry.shortName == "sleep")

        let reader = NativeProcessInspector.CommandLineReader()
        let command = reader.commandLine(pid: pid, shortName: entry.shortName)

        let psLine = run("/bin/ps", ["-o", "pid=,ppid=,tty=,command=", "-p", "\(pid)"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let columns = psLine.split(maxSplits: 3, whereSeparator: \.isWhitespace).map(String.init)
        try #require(columns.count == 4)
        #expect(columns[0] == "\(pid)")
        #expect(columns[1] == "\(entry.parentPID)")
        // Discovery trims the command column the same way.
        #expect(columns[3].trimmingCharacters(in: .whitespacesAndNewlines) == command)
        #expect(command == "/bin/sleep 30")
        if columns[2] == "??" {
            #expect(entry.terminalTTY == nil)
        } else {
            #expect(entry.terminalTTY == "/dev/\(columns[2])")
        }

        // lsof's `fcwd` entry is the same path libproc reports.
        let openFiles = try #require(NativeProcessInspector.openFiles(pid: pid))
        let lsofOutput = run("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-Fn"])
        let lsofLines = lsofOutput.split(whereSeparator: \.isNewline).map(String.init)
        let cwdIndex = try #require(lsofLines.firstIndex(of: "fcwd"))
        #expect(openFiles.workingDirectory == String(lsofLines[cwdIndex + 1].dropFirst()))
        #expect(openFiles.workingDirectory?.hasSuffix(directory.lastPathComponent) == true)
        #expect(openFiles.paths.first == openFiles.workingDirectory)
    }

    @Test
    func openFilesListsDescriptorPathsInDescriptorOrder() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("native-inspector-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("a.jsonl")
        let second = directory.appendingPathComponent("b.jsonl")
        FileManager.default.createFile(atPath: first.path, contents: Data())
        FileManager.default.createFile(atPath: second.path, contents: Data())
        let firstHandle = try FileHandle(forReadingFrom: first)
        let secondHandle = try FileHandle(forReadingFrom: second)
        defer {
            try? firstHandle.close()
            try? secondHandle.close()
        }

        let openFiles = try #require(NativeProcessInspector.openFiles(pid: getpid()))
        let firstIndex = try #require(openFiles.paths.firstIndex(of: realPath(first.path)))
        let secondIndex = try #require(openFiles.paths.firstIndex(of: realPath(second.path)))
        #expect(firstIndex < secondIndex)

        let cwdOnly = try #require(NativeProcessInspector.openFiles(pid: getpid(), includeDescriptors: false))
        #expect(cwdOnly.paths == cwdOnly.workingDirectory.map { [$0] } ?? [])
    }

    @Test
    func commandLineFallsBackWhenArgumentsAreUnreadable() {
        // pid 1 (launchd) is root-owned: KERN_PROCARGS2 is refused for a
        // regular user, so the reader falls back to the executable path.
        let reader = NativeProcessInspector.CommandLineReader()
        let command = reader.commandLine(pid: 1, shortName: "launchd")
        #expect(command == "/sbin/launchd" || command == "(launchd)" || command.hasPrefix("/sbin/launchd"))
    }
}
