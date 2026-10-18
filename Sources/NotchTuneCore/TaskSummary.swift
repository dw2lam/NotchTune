import Foundation

/// What a finished turn did, worked out locally from the turn's own tool
/// events: "Edited 4 files · tests passed · 3m 12s". Counts, a few short file
/// names and pass/fail only — never file contents or command output.
public struct TaskSummary: Equatable, Codable, Sendable {
    public enum TestStatus: String, Codable, Sendable {
        case passed
        case failed
        /// A test run whose result the agent didn't report.
        case ran
    }

    /// Distinct files the turn edited, created or deleted.
    public var fileCount: Int
    /// Up to `TaskActivityTracker.maxFileNames` base names, in first-edit order.
    public var fileNames: [String]
    /// Shell commands the turn ran (test runs included).
    public var commandCount: Int
    /// The latest test run's outcome, nil when the turn ran no tests.
    public var tests: TestStatus?
    /// From the prompt to the finish, nil when the turn's start wasn't seen.
    public var duration: TimeInterval?

    public init(
        fileCount: Int = 0,
        fileNames: [String] = [],
        commandCount: Int = 0,
        tests: TestStatus? = nil,
        duration: TimeInterval? = nil
    ) {
        self.fileCount = fileCount
        self.fileNames = fileNames
        self.commandCount = commandCount
        self.tests = tests
        self.duration = duration
    }

    /// Nothing worth a line: a turn that only talked.
    public var isEmpty: Bool {
        fileCount == 0 && commandCount == 0 && tests == nil
    }
}

/// Collects each session's current turn from hook events and hands back its
/// `TaskSummary` when the turn finishes. O(1) per event; agnostic of which
/// agent sent it (the tool name and input decide).
public struct TaskActivityTracker: Sendable {
    public static let maxFileNames = 3
    /// Distinct paths remembered per turn; past this, edits stop counting.
    static let maxTrackedPaths = 500
    /// Sessions remembered at once; the least recently active drops first.
    static let maxSessions = 128

    private struct Turn: Sendable {
        var startedAt: Date?
        var lastActivityAt: Date
        var paths: Set<String> = []
        var fileNames: [String] = []
        var commandCount = 0
        var tests: TaskSummary.TestStatus?
    }

    private var turns: [String: Turn] = [:]

    public init() {}

    /// A new prompt: forget the previous turn.
    public mutating func beginTurn(sessionID: String, at date: Date) {
        turns[sessionID] = Turn(startedAt: date, lastActivityAt: date)
        evictIfNeeded()
    }

    /// One finished tool call. `failed` is true for a tool the agent reported
    /// as failed (Claude Code's `PostToolUseFailure`).
    public mutating func recordToolUse(
        sessionID: String,
        toolName: String?,
        input: CodexHookJSONValue?,
        response: CodexHookJSONValue?,
        failed: Bool,
        at date: Date
    ) {
        let edited = failed ? [] : TaskActivityClassifier.editedPaths(toolName: toolName, input: input)
        let command = TaskActivityClassifier.shellCommand(toolName: toolName, input: input)
        guard !edited.isEmpty || command != nil else { return }

        var turn = turns[sessionID] ?? Turn(startedAt: nil, lastActivityAt: date)
        turn.lastActivityAt = date
        for path in edited where turn.paths.count < Self.maxTrackedPaths {
            guard turn.paths.insert(path).inserted else { continue }
            if turn.fileNames.count < Self.maxFileNames {
                turn.fileNames.append((path as NSString).lastPathComponent)
            }
        }
        if let command {
            turn.commandCount += 1
            if TaskActivityClassifier.isTestCommand(command) {
                // The latest run decides: a fix-then-rerun turn reads as passed.
                switch TaskActivityClassifier.commandSucceeded(response: response, failed: failed) {
                case true?: turn.tests = .passed
                case false?: turn.tests = .failed
                case nil: turn.tests = .ran
                }
            }
        }
        turns[sessionID] = turn
        evictIfNeeded()
    }

    /// The turn so far, as a summary; nil when it did nothing worth showing.
    /// The turn is kept, so a repeated or deferred finish reports the same.
    public func summary(sessionID: String, finishedAt date: Date) -> TaskSummary? {
        guard let turn = turns[sessionID] else { return nil }
        let summary = TaskSummary(
            fileCount: turn.paths.count,
            fileNames: turn.fileNames,
            commandCount: turn.commandCount,
            tests: turn.tests,
            duration: turn.startedAt.map { max(0, date.timeIntervalSince($0)) }
        )
        return summary.isEmpty ? nil : summary
    }

    /// The session ended: drop its turn.
    public mutating func endSession(_ sessionID: String) {
        turns.removeValue(forKey: sessionID)
    }

    private mutating func evictIfNeeded() {
        guard turns.count > Self.maxSessions,
              let oldest = turns.min(by: { $0.value.lastActivityAt < $1.value.lastActivityAt })?.key else {
            return
        }
        turns.removeValue(forKey: oldest)
    }
}

/// Reads a tool call's name and input the way each agent spells them.
public enum TaskActivityClassifier {
    private static let editToolNames: Set<String> = [
        // Claude Code (and the agents sharing its hook format)
        "edit", "multiedit", "write", "notebookedit",
        // Gemini CLI, OpenCode, Cursor and friends
        "write_file", "replace", "edit_file", "create_file", "str_replace_editor",
        "str_replace_based_edit_tool", "patch", "writefile", "editfile",
    ]
    private static let patchToolNames: Set<String> = ["apply_patch", "applypatch"]
    private static let shellToolNames: Set<String> = [
        "bash", "shell", "exec_command", "local_shell", "run_shell_command",
        "container.exec", "terminal", "run_terminal_cmd", "powershell",
    ]
    private static let pathKeys = ["file_path", "filePath", "notebook_path", "path", "target_file", "filename"]

    /// Files a tool call edited, created or deleted (absolute or as given).
    public static func editedPaths(toolName: String?, input: CodexHookJSONValue?) -> [String] {
        guard let name = toolName?.lowercased() else { return [] }
        if patchToolNames.contains(name) {
            return input.map { patchPaths(in: $0) } ?? []
        }
        guard editToolNames.contains(name), case let .object(object)? = input else { return [] }
        for key in pathKeys {
            if case let .string(path)? = object[key], !path.isEmpty {
                return [path]
            }
        }
        return []
    }

    /// The command line of a shell tool call, nil for any other tool.
    public static func shellCommand(toolName: String?, input: CodexHookJSONValue?) -> String? {
        guard let name = toolName?.lowercased(), shellToolNames.contains(name) else { return nil }
        guard let input else { return "" }
        switch input {
        case let .string(command):
            return command
        case let .object(object):
            switch object["command"] ?? object["cmd"] {
            case let .string(command)?:
                return command
            case let .array(parts)?:
                // Codex's exec form: ["bash", "-lc", "swift test"].
                return parts.compactMap { if case let .string(part) = $0 { part } else { nil } }.joined(separator: " ")
            default:
                return ""
            }
        default:
            return ""
        }
    }

    /// File paths named by an `apply_patch` envelope (`*** Update File: …`).
    public static func patchPaths(in value: CodexHookJSONValue) -> [String] {
        switch value {
        case let .string(text):
            return patchPaths(in: text)
        case let .object(object):
            return object.keys.sorted().flatMap { patchPaths(in: object[$0]!) }
        case let .array(items):
            return items.flatMap { patchPaths(in: $0) }
        default:
            return []
        }
    }

    static func patchPaths(in text: String) -> [String] {
        guard text.contains("*** ") else { return [] }
        let markers = ["*** Add File: ", "*** Update File: ", "*** Delete File: ", "*** Move to: "]
        var paths: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            for marker in markers where line.hasPrefix(marker) {
                let path = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty, !paths.contains(path) { paths.append(path) }
            }
        }
        return paths
    }

    private static let testCommandPatterns: [NSRegularExpression] = [
        #"\b(swift|go|cargo|dotnet|mix|deno|bun|flutter|dart|zig)\s+test\b"#,
        #"\b(npm|pnpm|yarn)\s+(run\s+)?test\b"#,
        #"\bcargo\s+nextest\b"#,
        #"\bxcodebuild\b.*\btest(-without-building)?\b"#,
        #"\b(pytest|jest|vitest|rspec|phpunit|ctest|tox|nox)\b"#,
        #"\bpython[0-9.]*\s+-m\s+(pytest|unittest)\b"#,
        #"\b(\./)?gradlew?\b.*\btest\b"#,
        #"\bmvnw?\b.*\btest\b"#,
        #"\bmake\s+(test|check)\b"#,
        #"\brake\s+(test|spec)\b"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    /// A command that runs a test suite (quoted text, like a commit message
    /// that mentions "pytest", doesn't count).
    public static func isTestCommand(_ command: String) -> Bool {
        let unquoted = command.replacingOccurrences(
            of: #"'[^']*'|"[^"]*""#,
            with: " ",
            options: .regularExpression
        )
        let range = NSRange(unquoted.startIndex..., in: unquoted)
        return testCommandPatterns.contains { $0.firstMatch(in: unquoted, range: range) != nil }
    }

    /// Whether a shell call succeeded: its reported failure, an exit code in
    /// the response, or nil when the agent didn't say.
    public static func commandSucceeded(response: CodexHookJSONValue?, failed: Bool) -> Bool? {
        if failed { return false }
        guard let response else { return nil }
        switch response {
        case let .object(object):
            if case .boolean(true)? = object["interrupted"] { return nil }
            for key in ["exit_code", "exitCode", "returncode", "return_code"] {
                if case let .number(code)? = object[key] { return code == 0 }
            }
            if case let .object(metadata)? = object["metadata"],
               case let .number(code)? = metadata["exit_code"] {
                return code == 0
            }
            if case let .boolean(success)? = object["success"] { return success }
            if case let .string(output)? = object["output"] { return exitCode(in: output).map { $0 == 0 } }
            // Claude Code's Bash result (stdout/stderr): a non-zero exit is
            // reported as a failure instead, so a plain result passed.
            if object["stdout"] != nil || object["stderr"] != nil { return true }
            return nil
        case let .string(output):
            return exitCode(in: output).map { $0 == 0 }
        default:
            return nil
        }
    }

    /// "Exit code: 1" / "exit code 0" / "Process exited with code 2".
    static func exitCode(in text: String) -> Int? {
        let pattern = #"(?i)(?:exit(?:ed)?\s*(?:with\s+)?code|exit_code)\s*[:=]?\s*(-?\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[range])
    }
}
