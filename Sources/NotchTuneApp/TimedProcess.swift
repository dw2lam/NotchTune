import Foundation

/// Runs a subprocess with a deadline. `waitUntilExit()` has none: an osascript
/// stuck on an app that stopped answering held its caller forever.
enum TimedProcess {
    struct Output: Sendable {
        var status: Int32
        var standardOutput: Data
        var standardError: Data

        var text: String {
            String(data: standardOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        var errorText: String {
            String(data: standardError, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    enum Failure: Error {
        case timedOut
    }

    private final class Buffer: @unchecked Sendable {
        var data = Data()
    }

    /// Both pipes drain while the process runs: read only after it exits, a
    /// child that fills a pipe (64 KB) blocks on the write and never exits.
    static func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let exited = DispatchGroup()
        exited.enter()
        process.terminationHandler = { _ in exited.leave() }

        try process.run()

        let drained = DispatchGroup()
        let output = drain(outputPipe, into: drained)
        let errors = drain(errorPipe, into: drained)

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 0.2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            throw Failure.timedOut
        }

        // A grandchild can keep the pipe open after the child exits.
        _ = drained.wait(timeout: .now() + 0.2)
        return Output(
            status: process.terminationStatus,
            standardOutput: output.data,
            standardError: errors.data
        )
    }

    private static func drain(_ pipe: Pipe, into group: DispatchGroup) -> Buffer {
        let buffer = Buffer()
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async(group: group) {
            buffer.data = handle.readDataToEndOfFile()
        }
        return buffer
    }
}
