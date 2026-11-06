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

        public init(status: Int32, stdout: Data) {
            self.status = status
            self.stdout = stdout
        }

        public var text: String? {
            String(data: stdout, encoding: .utf8)
        }
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let stdout = Pipe()
        let stdin = input.map { _ in Pipe() }
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        if let stdin {
            process.standardInput = stdin
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        if let stdin, let input {
            try? stdin.fileHandleForWriting.write(contentsOf: input)
            try? stdin.fileHandleForWriting.close()
        }

        // Drain while it runs: a child that fills the pipe buffer can't exit.
        let collected = OutputBuffer()
        let drained = DispatchSemaphore(value: 0)
        let reader = stdout.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async {
            collected.set(reader.readDataToEndOfFile())
            drained.signal()
        }

        guard exited.wait(timeout: .now() + deadline) == .success else {
            kill(process.processIdentifier, SIGKILL)
            return nil
        }

        // A grandchild can keep the pipe open past the helper's own exit.
        _ = drained.wait(timeout: .now() + 0.05)
        return Output(status: process.terminationStatus, stdout: collected.get())
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
