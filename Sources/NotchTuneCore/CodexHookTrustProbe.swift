import Darwin
import Foundation

public enum CodexHookTrust: Equatable, Sendable {
    case trusted
    /// Hooks Codex is skipping until the user reviews them in `/hooks`.
    case needsReview(count: Int)
    /// No answer: no `codex` here, or one too old to report trust.
    case unknown
}

/// Asks Codex itself whether it will run our hooks.
///
/// Codex keeps per-hook trust in `[hooks.state."<key>"] trusted_hash` and
/// skips anything new or changed. The hash is its own, so rather than copying
/// the format this uses the app-server's `hooks/list`, which also answers for
/// hooks that changed since they were trusted. NotchTune never writes that
/// trust: reviewing a hook is the user's decision, in Codex.
public enum CodexHookTrustProbe {
    public static func check(
        codexDirectory: URL,
        deadline: TimeInterval = 4
    ) -> CodexHookTrust {
        for command in CodexHookInstaller.codexCommandCandidates() {
            if let response = hooksListResponse(
                executableURL: command.executableURL,
                arguments: command.prefixArguments + ["app-server"],
                codexDirectory: codexDirectory,
                deadline: deadline
            ) {
                return trust(fromHooksList: response)
            }
        }

        return .unknown
    }

    /// Reads the `hooks/list` reply: `result.data[].hooks[]`.
    public static func trust(fromHooksList response: Data) -> CodexHookTrust {
        guard let root = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let layers = result["data"] as? [[String: Any]] else {
            return .unknown
        }

        let ours = layers
            .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            .filter { hook in
                let command = (hook["command"] as? String ?? "").lowercased()
                return command.contains("notchtunehooks") || command.contains("openislandhooks")
            }

        guard !ours.isEmpty else {
            return .unknown
        }

        let skipped = ours.filter { hook in
            if hook["isManaged"] as? Bool == true {
                return false
            }
            return hook["trustStatus"] as? String != "trusted" || hook["enabled"] as? Bool == false
        }

        return skipped.isEmpty ? .trusted : .needsReview(count: skipped.count)
    }

    /// The app-server quits at stdin EOF, before it answers, so stdin stays
    /// open until the reply is in and then the process is killed.
    private static func hooksListResponse(
        executableURL: URL,
        arguments: [String],
        codexDirectory: URL,
        deadline: TimeInterval
    ) -> Data? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = codexDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexDirectory.path
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            kill(process.processIdentifier, SIGKILL)
        }

        let reader = ReplyReader(id: 2)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                reader.finish()
            } else {
                reader.append(chunk)
            }
        }

        let messages: [[String: Any]] = [
            ["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "notchtune", "title": "NotchTune", "version": "1"]]],
            ["method": "initialized", "params": [String: Any]()],
            ["id": 2, "method": "hooks/list", "params": ["cwds": [codexDirectory.path]]],
        ]
        BoundedProcess.ignoreBrokenPipe(on: stdin.fileHandleForWriting)
        for message in messages {
            guard var line = try? JSONSerialization.data(withJSONObject: message) else {
                return nil
            }
            line.append(UInt8(ascii: "\n"))
            try? stdin.fileHandleForWriting.write(contentsOf: line)
        }

        return reader.wait(deadline: deadline)
    }

    private final class ReplyReader: @unchecked Sendable {
        private let id: Int
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var buffer = Data()
        private var reply: Data?

        init(id: Int) {
            self.id = id
        }

        func append(_ chunk: Data) {
            let finished: Bool = lock.withLock {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = buffer[buffer.startIndex..<newline]
                    buffer = Data(buffer[buffer.index(after: newline)...])
                    let root = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
                    if root?["id"] as? Int == id {
                        reply = Data(line)
                        return true
                    }
                }
                return false
            }

            if finished {
                done.signal()
            }
        }

        func finish() {
            done.signal()
        }

        func wait(deadline: TimeInterval) -> Data? {
            _ = done.wait(timeout: .now() + deadline)
            return lock.withLock { reply }
        }
    }
}
