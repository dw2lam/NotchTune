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

/// One turn's activity so far: the files it edited, the commands it ran and
/// its latest test result. Shared by the hook-fed `TaskActivityTracker` and
/// Codex's rollout reader.
struct TaskTurnActivity: Equatable, Sendable {
    var startedAt: Date?
    var lastActivityAt: Date
    var paths: Set<String> = []
    var fileNames: [String] = []
    var commandCount = 0
    var tests: TaskSummary.TestStatus?

    init(startedAt: Date?, lastActivityAt: Date) {
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
    }

    /// Nothing recorded yet.
    var isEmpty: Bool { paths.isEmpty && commandCount == 0 }

    mutating func recordEdits(_ edited: [String], at date: Date) {
        guard !edited.isEmpty else { return }
        lastActivityAt = max(lastActivityAt, date)
        for path in edited where paths.count < TaskActivityTracker.maxTrackedPaths {
            guard paths.insert(path).inserted else { continue }
            if fileNames.count < TaskActivityTracker.maxFileNames {
                fileNames.append((path as NSString).lastPathComponent)
            }
        }
    }

    /// A shell command; `succeeded` is its whole command line's exit status
    /// (nil when unknown), read against the test run inside it.
    mutating func recordCommand(_ command: String, succeeded: Bool?, at date: Date) {
        lastActivityAt = max(lastActivityAt, date)
        commandCount += 1
        // The latest run decides: a fix-then-rerun turn reads as passed.
        if let status = TaskActivityClassifier.testAttribution(command).status(commandSucceeded: succeeded) {
            tests = status
        }
    }

    func summary(finishedAt date: Date) -> TaskSummary? {
        let summary = TaskSummary(
            fileCount: paths.count,
            fileNames: fileNames,
            commandCount: commandCount,
            tests: tests,
            duration: startedAt.map { max(0, date.timeIntervalSince($0)) }
        )
        return summary.isEmpty ? nil : summary
    }
}

/// Collects each session's current turn from hook events and hands back its
/// `TaskSummary` when the turn finishes. O(1) per event. It is fed by the
/// Claude Code-format hooks (and Codex's opt-in `PostToolUse`); Codex's
/// standard install is summarised from its rollout instead
/// (`CodexRolloutReducer`). Agents whose hooks don't report tool calls get
/// no summary.
public struct TaskActivityTracker: Sendable {
    public static let maxFileNames = 3
    /// Distinct paths remembered per turn; past this, edits stop counting.
    static let maxTrackedPaths = 500
    /// Sessions remembered at once; the least recently active drops first.
    static let maxSessions = 128

    /// How a tool call ended.
    public enum ToolOutcome: Sendable {
        case succeeded
        /// The agent reported the call as failed (Claude Code's `PostToolUseFailure`).
        case failed
        /// The user stopped it: nothing it meant to do can be counted on.
        case interrupted
    }

    private var turns: [String: TaskTurnActivity] = [:]

    public init() {}

    /// A new prompt: forget the previous turn.
    public mutating func beginTurn(sessionID: String, at date: Date) {
        turns[sessionID] = TaskTurnActivity(startedAt: date, lastActivityAt: date)
        evictIfNeeded()
    }

    /// One finished tool call. `infersSuccessFromOutput`: the source reports
    /// failed calls separately (Claude Code's `PostToolUseFailure`), so a
    /// plain stdout/stderr result means the command succeeded.
    public mutating func recordToolUse(
        sessionID: String,
        toolName: String?,
        input: CodexHookJSONValue?,
        response: CodexHookJSONValue?,
        outcome: ToolOutcome,
        infersSuccessFromOutput: Bool = false,
        at date: Date
    ) {
        // Only a call that went through edited anything.
        let edited = outcome == .succeeded ? TaskActivityClassifier.editedPaths(toolName: toolName, input: input) : []
        let command = TaskActivityClassifier.shellCommand(toolName: toolName, input: input)
        guard !edited.isEmpty || command != nil else { return }

        var turn = turns[sessionID] ?? TaskTurnActivity(startedAt: nil, lastActivityAt: date)
        turn.recordEdits(edited, at: date)
        if let command {
            let succeeded = TaskActivityClassifier.commandSucceeded(
                input: input,
                response: response,
                outcome: outcome,
                infersSuccessFromOutput: infersSuccessFromOutput
            )
            turn.recordCommand(command, succeeded: succeeded, at: date)
        }
        turns[sessionID] = turn
        evictIfNeeded()
    }

    /// The turn so far, as a summary; nil when it did nothing worth showing.
    /// The turn is kept, so a repeated or deferred finish reports the same.
    public func summary(sessionID: String, finishedAt date: Date) -> TaskSummary? {
        turns[sessionID]?.summary(finishedAt: date)
    }

    /// When the turn last did something (its prompt, or its latest tool call).
    public func lastActivity(sessionID: String) -> Date? {
        turns[sessionID]?.lastActivityAt
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
        // Other agents' spellings, for hooks that report tool calls in kind
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
                return commandLine(fromArgv: parts.compactMap { if case let .string(part) = $0 { part } else { nil } })
            default:
                return ""
            }
        default:
            return ""
        }
    }

    /// An exec-style argv as one command line: Codex's `["bash", "-lc",
    /// "swift test"]` is its script; anything else, its words.
    static func commandLine(fromArgv argv: [String]) -> String {
        if argv.count >= 3, isShell(argv[0]), isCommandFlag(argv[1]) {
            return argv[2]
        }
        return argv.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
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
        let markers = ["*** Add File: ", "*** Update File: ", "*** Delete File: "]
        let moveMarker = "*** Move to: "
        var paths: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix(moveMarker) {
                // A rename is one file: the update's path becomes its new name.
                let target = line.dropFirst(moveMarker.count).trimmingCharacters(in: .whitespaces)
                guard !target.isEmpty else { continue }
                if let last = paths.indices.last { paths.remove(at: last) }
                if !paths.contains(target) { paths.append(target) }
                continue
            }
            for marker in markers where line.hasPrefix(marker) {
                let path = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty, !paths.contains(path) { paths.append(path) }
            }
        }
        return paths
    }

    // MARK: Test runs

    /// How far a command line's exit status speaks for the test run in it.
    public enum TestRunAttribution: Int, Comparable, Sendable {
        /// No test runner.
        case none
        /// A runner ran, but the status belongs to something else (it was
        /// piped, chained with `;` / `||`, or sent to the background).
        case ranOnly
        /// Success means the tests passed; a failure may be a later command's.
        case successOnly
        /// The status is the runner's.
        case full

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        /// The test result for a command line that exited with `commandSucceeded`.
        public func status(commandSucceeded: Bool?) -> TaskSummary.TestStatus? {
            switch self {
            case .none: return nil
            case .ranOnly: return .ran
            case .successOnly: return commandSucceeded == true ? .passed : .ran
            case .full:
                switch commandSucceeded {
                case true?: return .passed
                case false?: return .failed
                case nil: return .ran
                }
            }
        }
    }

    /// A command that runs a test suite. Only a runner at the head of a
    /// command (after `cd … &&`, `env X=1`, `npx`, `bash -lc '…'` and the
    /// like) counts; `pip install pytest`, `cat jest.config.js` or a commit
    /// message mentioning one don't.
    public static func isTestCommand(_ command: String) -> Bool {
        testAttribution(command) != .none
    }

    public static func testAttribution(_ command: String) -> TestRunAttribution {
        attribution(of: ShellCommandLine.segments(command), depth: 0)
    }

    private static func attribution(of segments: [ShellCommandLine.Segment], depth: Int) -> TestRunAttribution {
        guard !segments.isEmpty else { return .none }
        var pipefail = false
        var pipefailAt: [Bool] = []
        var runners: [(index: Int, inner: TestRunAttribution)] = []
        for (index, segment) in segments.enumerated() {
            let words = ShellCommandLine.coreWords(segment.words)
            if words.first == "set", words.contains(where: { $0 == "pipefail" || $0.hasSuffix("pipefail") }) {
                pipefail = true
            }
            pipefailAt.append(pipefail)
            if depth < 2, let script = ShellCommandLine.inlineScript(words) {
                let inner = attribution(of: ShellCommandLine.segments(script), depth: depth + 1)
                if inner != .none { runners.append((index, inner)) }
            } else if isTestRunner(words) {
                runners.append((index, .full))
            }
        }
        guard !runners.isEmpty else { return .none }

        let last = segments.count - 1
        // A trailing `&` backgrounds the last command; a trailing `;` is nothing.
        let lastIsBackgrounded = segments[last].operatorAfter == "&"
        var best = TestRunAttribution.ranOnly
        for (index, inner) in runners {
            let before = index > 0 ? segments[index - 1].operatorAfter : nil
            // After `||` it may never run; sent to the background, it reports nothing.
            if before == "||" || segments[index].operatorAfter == "&" {
                continue
            }
            let connectors = (index..<last).map { segments[$0].operatorAfter }
            // With `pipefail`, piping into pass-through filters (`| tail -40`)
            // keeps the runner's status.
            let pipesThrough = index < last
                && pipefailAt[index]
                && connectors.allSatisfy { $0 == "|" }
                && segments[(index + 1)...].allSatisfy { ShellCommandLine.isPassThroughFilter(ShellCommandLine.coreWords($0.words)) }
            let successAttributable = !lastIsBackgrounded
                && connectors.allSatisfy { $0 == "&&" || ($0 == "|" && pipefailAt[index]) }
            let earlierAreHarmless = (0..<index).allSatisfy { earlier in
                let op = segments[earlier].operatorAfter
                if op == ";" || op == "\n" { return true }
                if op == "&&" { return ShellCommandLine.isSetupCommand(ShellCommandLine.coreWords(segments[earlier].words)) }
                // Feeding the runner through a pipe: its status is still the runner's.
                return op == "|" && earlier == index - 1
            }
            let failureAttributable = !lastIsBackgrounded && earlierAreHarmless && (index == last || pipesThrough)

            var candidate: TestRunAttribution = failureAttributable && successAttributable
                ? .full
                : (successAttributable ? .successOnly : .ranOnly)
            candidate = min(candidate, inner == .none ? .ranOnly : inner)
            best = max(best, candidate)
        }
        return best
    }

    private static func isTestRunner(_ words: [String]) -> Bool {
        guard let head = words.first else { return false }
        let name = (head as NSString).lastPathComponent.lowercased()
        let args = Array(words.dropFirst())
        if args.contains(where: { ["--version", "--help", "-h"].contains($0) }) { return false }

        switch name {
        case "swift", "go", "dotnet", "mix", "deno", "flutter", "dart", "zig", "rails":
            return ShellCommandLine.positionals(args).first == "test"
        case "cargo":
            let sub = ShellCommandLine.positionals(args).first { !$0.hasPrefix("+") }
            return sub == "test" || sub == "nextest"
        case "npm", "pnpm", "yarn", "bun":
            return runsTestScript(manager: name, args: args)
        case "pytest", "py.test", "jest", "vitest", "mocha", "ava", "rspec", "phpunit",
             "ctest", "tox", "nox", "karma", "jasmine", "nosetests", "pest":
            return true
        case "playwright":
            return ShellCommandLine.positionals(args).first == "test"
        case "cypress":
            return ShellCommandLine.positionals(args).first == "run"
        case "xcodebuild":
            return args.contains("test") || args.contains("test-without-building")
        case "gradle", "gradlew":
            return gradleTasks(args).contains { task in
                let leaf = task.split(separator: ":").last.map(String.init) ?? task
                return leaf == "test" || leaf == "check" || leaf.hasSuffix("Test")
            }
        case "mvn", "mvnw":
            if args.contains(where: { $0.hasPrefix("-DskipTests") || $0.hasPrefix("-Dmaven.test.skip=true") }) {
                return false
            }
            return ShellCommandLine.positionals(args).contains { ["test", "verify", "integration-test", "surefire:test"].contains($0) }
        case "make", "gmake", "just":
            return ShellCommandLine.positionals(args).contains { $0 == "test" || $0 == "tests" || $0 == "check" || $0.hasPrefix("test-") || $0.hasPrefix("test_") }
        case "rake":
            return ShellCommandLine.positionals(args).contains { $0 == "test" || $0 == "spec" || $0.hasPrefix("test:") || $0.hasPrefix("spec:") }
        default:
            if name.hasPrefix("python") {
                guard let module = args.firstIndex(of: "-m"), module + 1 < args.count else { return false }
                return ["pytest", "unittest", "nose2"].contains(args[module + 1])
            }
            return false
        }
    }

    /// `npm test`, `pnpm -r test`, `yarn workspace app test`, `bun run test:unit`.
    private static func runsTestScript(manager: String, args: [String]) -> Bool {
        var rest = ShellCommandLine.positionals(args, valueFlags: ["--filter", "-F", "-C", "--dir", "--prefix", "--cwd", "-w", "--workspace"])
        if manager == "yarn", rest.first == "workspace", rest.count >= 2 {
            rest.removeFirst(2)
        }
        guard let sub = rest.first else { return false }
        if ["test", "t", "tst", "tests"].contains(sub) { return manager != "bun" || sub == "test" }
        if ["run", "run-script", "rum", "urn"].contains(sub), rest.count >= 2 {
            let script = rest[1]
            return script == "test" || script == "tests" || script.hasPrefix("test:") || script.hasPrefix("test-")
        }
        return false
    }

    /// Gradle's tasks, minus the ones `-x` / `--exclude-task` leave out.
    private static func gradleTasks(_ args: [String]) -> [String] {
        var tasks: [String] = []
        var skipNext = false
        for arg in args {
            if skipNext { skipNext = false; continue }
            if arg == "-x" || arg == "--exclude-task" { skipNext = true; continue }
            if arg.hasPrefix("-") { continue }
            tasks.append(arg)
        }
        return tasks
    }

    // MARK: Exit status

    /// Whether a shell call succeeded: its reported failure, an exit code in
    /// the response, or nil when the agent didn't say (an interrupt or a run
    /// sent to the background say nothing either).
    public static func commandSucceeded(
        input: CodexHookJSONValue? = nil,
        response: CodexHookJSONValue?,
        outcome: TaskActivityTracker.ToolOutcome,
        infersSuccessFromOutput: Bool = false
    ) -> Bool? {
        switch outcome {
        case .failed: return false
        case .interrupted: return nil
        case .succeeded: break
        }
        if case let .object(object)? = input, case .boolean(true)? = object["run_in_background"] {
            return nil
        }
        guard let response else { return nil }
        switch response {
        case let .object(object):
            if case .boolean(true)? = object["interrupted"] { return nil }
            if object["backgroundTaskId"] != nil || object["background_task_id"] != nil { return nil }
            for key in ["exit_code", "exitCode", "returncode", "return_code"] {
                if case let .number(code)? = object[key] { return code == 0 }
            }
            if case let .object(metadata)? = object["metadata"],
               case let .number(code)? = metadata["exit_code"] {
                return code == 0
            }
            if case let .boolean(success)? = object["success"] { return success }
            if case let .string(output)? = object["output"] { return exitCode(in: output).map { $0 == 0 } }
            // A plain stdout/stderr result: success only where failed calls
            // arrive separately (Claude Code's PostToolUseFailure).
            if infersSuccessFromOutput, object["stdout"] != nil || object["stderr"] != nil { return true }
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

    static func isShell(_ word: String) -> Bool {
        ["sh", "bash", "zsh", "dash", "fish"].contains((word as NSString).lastPathComponent)
    }

    /// `-c`, `-lc`, `-ic`, `-euc`…
    static func isCommandFlag(_ word: String) -> Bool {
        word.hasPrefix("-") && !word.hasPrefix("--") && word.contains("c")
    }
}

/// Just enough shell parsing to tell which command in a line ran the tests
/// and whether the line's exit status is that command's: quotes, escapes,
/// and the `&&` `||` `|` `;` `&` operators between commands.
enum ShellCommandLine {
    struct Segment: Equatable {
        var words: [String]
        /// The operator joining it to the next command (`&&`, `||`, `|`,
        /// `;`, `&`, newline), nil at the end.
        var operatorAfter: String?
    }

    static func segments(_ line: String) -> [Segment] {
        var segments: [Segment] = []
        var words: [String] = []
        var word = ""
        var hasWord = false
        var quote: Character?
        let chars = Array(line)
        var index = 0

        func endWord() {
            if hasWord { words.append(word) }
            word = ""
            hasWord = false
        }
        func endSegment(_ op: String?) {
            endWord()
            if !words.isEmpty {
                segments.append(Segment(words: words, operatorAfter: op))
            } else if let op, let lastIndex = segments.indices.last, op != "\n" {
                segments[lastIndex].operatorAfter = op
            }
            words = []
        }

        while index < chars.count {
            let char = chars[index]
            if let open = quote {
                if char == open {
                    quote = nil
                } else if char == "\\", open == "\"", index + 1 < chars.count {
                    index += 1
                    word.append(chars[index])
                } else {
                    word.append(char)
                }
                index += 1
                continue
            }
            switch char {
            case "'", "\"":
                quote = char
                hasWord = true
            case "\\":
                if index + 1 < chars.count {
                    index += 1
                    if chars[index] != "\n" { word.append(chars[index]); hasWord = true }
                }
            case " ", "\t", "(", ")", "{", "}":
                endWord()
            case "#" where !hasWord:
                // A comment runs to the end of the line.
                while index + 1 < chars.count, chars[index + 1] != "\n" { index += 1 }
            case "\n", ";":
                endSegment(String(char))
            case "&":
                let previous = index > 0 ? chars[index - 1] : " "
                let next = index + 1 < chars.count ? chars[index + 1] : " "
                if previous == ">" || previous == "<" || next == ">" {
                    // A redirection (`2>&1`, `&>file`), not an operator.
                    word.append(char)
                    hasWord = true
                } else if next == "&" {
                    endSegment("&&")
                    index += 1
                } else {
                    endSegment("&")
                }
            case "|":
                let next = index + 1 < chars.count ? chars[index + 1] : " "
                if next == "|" {
                    endSegment("||")
                    index += 1
                } else {
                    if next == "&" { index += 1 }
                    endSegment("|")
                }
            default:
                word.append(char)
                hasWord = true
            }
            index += 1
        }
        endSegment(nil)
        return segments
    }

    /// The command itself, past `VAR=1`, `env`, `time`, `timeout 60`, `npx`,
    /// `uv run`, `bundle exec` and similar launchers.
    static func coreWords(_ words: [String]) -> [String] {
        var rest = words[...]
        while let head = rest.first {
            let name = (head as NSString).lastPathComponent
            if isAssignment(head) {
                rest = rest.dropFirst()
                continue
            }
            switch name {
            case "env":
                rest = rest.dropFirst()
                while let next = rest.first, next.hasPrefix("-") || isAssignment(next) {
                    rest = rest.dropFirst()
                    if next == "-u", !rest.isEmpty { rest = rest.dropFirst() }
                }
            case "time", "nohup", "command", "exec", "sudo", "caffeinate", "xcrun":
                rest = rest.dropFirst()
                while let next = rest.first, next.hasPrefix("-") { rest = rest.dropFirst() }
            case "nice":
                rest = rest.dropFirst()
                if rest.first == "-n" { rest = rest.dropFirst(2) }
            case "timeout", "gtimeout":
                rest = rest.dropFirst()
                while let next = rest.first, next.hasPrefix("-") {
                    rest = rest.dropFirst()
                    if ["-s", "-k", "--signal", "--kill-after"].contains(next), !rest.isEmpty { rest = rest.dropFirst() }
                }
                rest = rest.dropFirst()  // the duration
            case "npx", "bunx", "pnpx":
                rest = rest.dropFirst()
                while let next = rest.first, next.hasPrefix("-") {
                    rest = rest.dropFirst()
                    if ["-p", "--package"].contains(next), !rest.isEmpty { rest = rest.dropFirst() }
                }
            case "uv", "poetry", "pipenv", "hatch", "pdm", "rye":
                guard rest.dropFirst().first == "run" else { return Array(rest) }
                rest = rest.dropFirst(2)
                while let next = rest.first, next.hasPrefix("-") { rest = rest.dropFirst() }
            case "bundle":
                guard rest.dropFirst().first == "exec" else { return Array(rest) }
                rest = rest.dropFirst(2)
            case "pnpm", "yarn":
                guard let sub = rest.dropFirst().first, sub == "exec" || sub == "dlx" else { return Array(rest) }
                rest = rest.dropFirst(2)
            default:
                return Array(rest)
            }
        }
        return Array(rest)
    }

    /// The script of `bash -lc '…'` / `sh -c "…"`, nil otherwise.
    static func inlineScript(_ words: [String]) -> String? {
        guard let head = words.first, TaskActivityClassifier.isShell(head) else { return nil }
        var index = 1
        while index < words.count, words[index].hasPrefix("-") {
            if TaskActivityClassifier.isCommandFlag(words[index]) {
                return index + 1 < words.count ? words[index + 1] : nil
            }
            index += 1
        }
        return nil
    }

    /// The non-flag words, skipping the values of `valueFlags`.
    static func positionals(_ args: [String], valueFlags: Set<String> = []) -> [String] {
        var result: [String] = []
        var skipNext = false
        for arg in args {
            if skipNext { skipNext = false; continue }
            if arg.hasPrefix("-") {
                if valueFlags.contains(arg) { skipNext = true }
                continue
            }
            result.append(arg)
        }
        return result
    }

    /// Commands that set up a run and practically never fail (`cd app &&`).
    static func isSetupCommand(_ words: [String]) -> Bool {
        guard let head = words.first else { return true }
        return ["cd", "pushd", "popd", "export", "source", ".", "set", "unset", "ulimit",
                "true", "echo", "printf", "mkdir", "nvm", "ulimit"].contains((head as NSString).lastPathComponent)
    }

    /// Filters a test run is commonly piped through, which pass its output on.
    static func isPassThroughFilter(_ words: [String]) -> Bool {
        guard let head = words.first else { return false }
        return ["tail", "head", "tee", "cat", "xcpretty", "xcbeautify", "sed", "less", "more", "ts"]
            .contains((head as NSString).lastPathComponent)
    }

    private static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        let name = word[..<equals]
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber } && !(name.first?.isNumber ?? true)
    }
}
