import Foundation
import NotchTuneCore

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

    static func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> Output {
        do {
            let output = try BoundedProcess.runThrowing(
                executablePath: executable,
                arguments: arguments,
                deadline: timeout,
                capturesStandardError: true
            )
            return Output(status: output.status, standardOutput: output.stdout, standardError: output.stderr)
        } catch BoundedProcess.Failure.timedOut {
            throw Failure.timedOut
        }
    }
}
