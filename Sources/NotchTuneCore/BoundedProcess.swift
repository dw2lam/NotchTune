import Darwin
import Foundation

/// Runs a helper with a hard deadline. Hooks sit on the agent's critical path
/// and the app's main actor can't wait either, so nothing here may block on a
/// child that never exits (a pending Automation prompt holds `osascript`
/// open indefinitely).
public enum BoundedProcess {
    public struct Output: Equatable, Sendable {
        public var status: Int32
        public var stdout: Data
        /// Empty unless the run asked for it.
        public var stderr: Data

        public init(status: Int32, stdout: Data, stderr: Data = Data()) {
            self.status = status
            self.stdout = stdout
            self.stderr = stderr
        }

        public var text: String? {
            String(data: stdout, encoding: .utf8)
        }
    }

    public enum Failure: Error, Equatable {
        case timedOut
    }

    /// `nil` when the helper couldn't start or missed the deadline; a late
    /// child is killed, never waited for.
    public static func run(
        executablePath: String,
        arguments: [String],
        deadline: TimeInterval,
        environment: [String: String]? = nil,
        input: Data? = nil
    ) -> Output? {
        try? runThrowing(
            executablePath: executablePath,
            arguments: arguments,
            deadline: deadline,
            environment: environment,
            input: input
        )
    }

    /// `run`, for callers that need to tell a launch failure from
    /// `Failure.timedOut`, or want what the helper said on stderr.
    public static func runThrowing(
        executablePath: String,
        arguments: [String],
        deadline: TimeInterval,
        environment: [String: String]? = nil,
        input: Data? = nil,
        capturesStandardError: Bool = false
    ) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let stdout = Pipe()
        let stderr = capturesStandardError ? Pipe() : nil
        let stdin = input.map { _ in Pipe() }
        process.standardOutput = stdout
        process.standardError = stderr ?? FileHandle.nullDevice
        if let stdin {
            process.standardInput = stdin
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        try process.run()

        // Drain while it runs: a child that fills a pipe buffer can't exit.
        let drained = DispatchGroup()
        let output = drain(stdout, into: drained)
        let errors = stderr.map { drain($0, into: drained) }

        if let stdin, let input {
            ignoreBrokenPipe(on: stdin.fileHandleForWriting)
            try? stdin.fileHandleForWriting.write(contentsOf: input)
            try? stdin.fileHandleForWriting.close()
        }

        guard exited.wait(timeout: .now() + deadline) == .success else {
            kill(process.processIdentifier, SIGKILL)
            throw Failure.timedOut
        }

        // A grandchild can keep a pipe open past the helper's own exit.
        _ = drained.wait(timeout: .now() + 0.05)
        return Output(
            status: process.terminationStatus,
            stdout: output.get(),
            stderr: errors?.get() ?? Data()
        )
    }

    /// Writing to a child that has already exited raises SIGPIPE, which
    /// kills this whole process; `try?` can't catch a signal. With this the
    /// write just fails.
    public static func ignoreBrokenPipe(on handle: FileHandle) {
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    private static func drain(_ pipe: Pipe, into group: DispatchGroup) -> OutputBuffer {
        let buffer = OutputBuffer()
        let reader = pipe.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            buffer.set(reader.readDataToEndOfFile())
        }
        return buffer
    }

    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func set(_ value: Data) {
            lock.withLock { data = value }
        }

        func get() -> Data {
            lock.withLock { data }
        }
    }
}
