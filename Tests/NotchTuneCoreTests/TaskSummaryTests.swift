import Foundation
import Testing
@testable import NotchTuneCore

/// The finished-task summary: what a turn edited, ran and tested, worked out
/// from its own tool events. Payload shapes follow what the agents send —
/// Claude Code's `Edit`/`Write`/`Bash` with `PostToolUseFailure` for a failed
/// tool; Codex's `Bash` with an exec-style command and an exit code.
struct TaskActivityTrackerTests {
    private let start = Date(timeIntervalSince1970: 10_000)

    private func record(
        _ tracker: inout TaskActivityTracker,
        _ tool: String,
        _ input: CodexHookJSONValue?,
        response: CodexHookJSONValue? = nil,
        failed: Bool = false,
        id: String = "s"
    ) {
        tracker.recordToolUse(sessionID: id, toolName: tool, input: input, response: response, failed: failed, at: start)
    }

    private func edit(_ path: String) -> CodexHookJSONValue {
        .object(["file_path": .string(path), "old_string": .string("a"), "new_string": .string("b")])
    }

    private func bash(_ command: String) -> CodexHookJSONValue {
        .object(["command": .string(command), "description": .string("Run it")])
    }

    private let bashOK: CodexHookJSONValue = .object([
        "stdout": .string("All tests passed"), "stderr": .string(""), "interrupted": .boolean(false),
    ])

    @Test
    func claudeTurnCountsDistinctFilesTestsAndTime() throws {
        var tracker = TaskActivityTracker()
        tracker.beginTurn(sessionID: "s", at: start)
        record(&tracker, "Edit", edit("/repo/Sources/AppModel.swift"))
        record(&tracker, "Edit", edit("/repo/Sources/AppModel.swift"))
        record(&tracker, "Write", .object(["file_path": .string("/repo/Tests/NewTests.swift"), "content": .string("…")]))
        record(&tracker, "MultiEdit", .object(["file_path": .string("/repo/README.md"), "edits": .array([])]))
        record(&tracker, "Read", .object(["file_path": .string("/repo/Package.swift")]))
        record(&tracker, "Bash", bash("cd /repo && swift test"), response: bashOK)

        let summary = try #require(tracker.summary(sessionID: "s", finishedAt: start.addingTimeInterval(192)))
        #expect(summary.fileCount == 3)
        #expect(summary.fileNames == ["AppModel.swift", "NewTests.swift", "README.md"])
        #expect(summary.commandCount == 1)
        #expect(summary.tests == .passed)
        #expect(summary.duration == 192)
    }

    @Test
    func aFailedTestRunReadsAsFailedUntilARerunPasses() throws {
        var tracker = TaskActivityTracker()
        tracker.beginTurn(sessionID: "s", at: start)
        // Claude Code reports a non-zero exit as PostToolUseFailure.
        record(&tracker, "Bash", bash("npm test"), failed: true)
        #expect(tracker.summary(sessionID: "s", finishedAt: start)?.tests == .failed)

        record(&tracker, "Edit", edit("/repo/src/math.ts"))
        record(&tracker, "Bash", bash("npm test"), response: bashOK)
        #expect(tracker.summary(sessionID: "s", finishedAt: start)?.tests == .passed)
        #expect(tracker.summary(sessionID: "s", finishedAt: start)?.commandCount == 2)
    }

    @Test
    func aFailedEditDoesNotCount() {
        var tracker = TaskActivityTracker()
        tracker.beginTurn(sessionID: "s", at: start)
        record(&tracker, "Edit", edit("/repo/a.swift"), failed: true)
        #expect(tracker.summary(sessionID: "s", finishedAt: start) == nil)
    }

    @Test
    func aTurnThatOnlyTalkedHasNoSummary() {
        var tracker = TaskActivityTracker()
        tracker.beginTurn(sessionID: "s", at: start)
        record(&tracker, "Read", .object(["file_path": .string("/repo/a.swift")]))
        record(&tracker, "Grep", .object(["pattern": .string("TODO")]))
        #expect(tracker.summary(sessionID: "s", finishedAt: start.addingTimeInterval(30)) == nil)
    }

    @Test
    func aNewPromptStartsAFreshTurn() {
        var tracker = TaskActivityTracker()
        tracker.beginTurn(sessionID: "s", at: start)
        record(&tracker, "Edit", edit("/repo/a.swift"))
        #expect(tracker.summary(sessionID: "s", finishedAt: start)?.fileCount == 1)

        tracker.beginTurn(sessionID: "s", at: start.addingTimeInterval(60))
        #expect(tracker.summary(sessionID: "s", finishedAt: start.addingTimeInterval(90)) == nil)
        record(&tracker, "Bash", bash("ls"))
        let summary = tracker.summary(sessionID: "s", finishedAt: start.addingTimeInterval(90))
        #expect(summary?.fileCount == 0)
        #expect(summary?.commandCount == 1)
        #expect(summary?.duration == 30)
    }

    @Test
    func sessionsAreTrackedApartAndEndedSessionsAreForgotten() {
        var tracker = TaskActivityTracker()
        record(&tracker, "Edit", edit("/a.swift"), id: "one")
        record(&tracker, "Edit", edit("/b.swift"), id: "two")
        #expect(tracker.summary(sessionID: "one", finishedAt: start)?.fileNames == ["a.swift"])
        // Seen mid-turn (no prompt observed): no duration to report.
        #expect(tracker.summary(sessionID: "one", finishedAt: start)?.duration == nil)

        tracker.endSession("one")
        #expect(tracker.summary(sessionID: "one", finishedAt: start) == nil)
        #expect(tracker.summary(sessionID: "two", finishedAt: start)?.fileCount == 1)
    }

    @Test
    func codexExecCommandAndExitCodeAreRead() throws {
        var tracker = TaskActivityTracker()
        tracker.beginTurn(sessionID: "s", at: start)
        record(
            &tracker, "Bash",
            .object(["command": .array([.string("bash"), .string("-lc"), .string("cargo test --workspace")])]),
            response: .object(["exit_code": .number(101), "output": .string("test result: FAILED")])
        )
        #expect(tracker.summary(sessionID: "s", finishedAt: start)?.tests == .failed)

        record(&tracker, "shell", .object(["command": .string("pytest -q")]), response: .string("Exit code: 0\n12 passed"))
        #expect(tracker.summary(sessionID: "s", finishedAt: start)?.tests == .passed)
    }

    @Test
    func codexApplyPatchNamesItsFiles() throws {
        var tracker = TaskActivityTracker()
        tracker.beginTurn(sessionID: "s", at: start)
        let patch = """
        *** Begin Patch
        *** Update File: Sources/App/Model.swift
        @@
        -old
        +new
        *** Add File: Sources/App/New.swift
        +struct New {}
        *** Delete File: Sources/App/Old.swift
        *** End Patch
        """
        record(&tracker, "apply_patch", .object(["input": .string(patch)]))
        let summary = try #require(tracker.summary(sessionID: "s", finishedAt: start))
        #expect(summary.fileCount == 3)
        #expect(summary.fileNames == ["Model.swift", "New.swift", "Old.swift"])
    }

    @Test
    func anInterruptedOrSilentTestRunIsJustRan() {
        var tracker = TaskActivityTracker()
        tracker.beginTurn(sessionID: "s", at: start)
        record(&tracker, "Bash", bash("go test ./..."), response: .object(["interrupted": .boolean(true), "stdout": .string("")]))
        #expect(tracker.summary(sessionID: "s", finishedAt: start)?.tests == .ran)
    }

    @Test
    func fileNamesAreCappedButEveryFileCounts() throws {
        var tracker = TaskActivityTracker()
        tracker.beginTurn(sessionID: "s", at: start)
        for index in 0..<7 {
            record(&tracker, "Write", .object(["file_path": .string("/repo/f\(index).swift")]))
        }
        let summary = try #require(tracker.summary(sessionID: "s", finishedAt: start))
        #expect(summary.fileCount == 7)
        #expect(summary.fileNames.count == TaskActivityTracker.maxFileNames)
    }
}

struct TaskActivityClassifierTests {
    @Test
    func recognisesTestRunnersButNotMentionsOfThem() {
        for command in [
            "swift test --filter Foo", "cd app && npm test", "pnpm run test", "yarn test", "bun test",
            "pytest -q", "python3 -m pytest tests/", "go test ./...", "cargo test", "cargo nextest run",
            "xcodebuild -scheme App test", "npx vitest run", "npx jest", "./gradlew test", "mvn -q test",
            "make check", "bundle exec rspec", "dotnet test",
        ] {
            #expect(TaskActivityClassifier.isTestCommand(command), "\(command)")
        }
        for command in [
            "git commit -m \"run pytest in CI\"", "swift build", "npm install", "ls tests/",
            "echo 'go test later'", "cat test_output.txt", "grep -r testHelper .",
        ] {
            #expect(!TaskActivityClassifier.isTestCommand(command), "\(command)")
        }
    }

    @Test
    func readsEditPathsAcrossAgentSpellings() {
        #expect(TaskActivityClassifier.editedPaths(toolName: "NotebookEdit", input: .object(["notebook_path": .string("/n.ipynb")])) == ["/n.ipynb"])
        #expect(TaskActivityClassifier.editedPaths(toolName: "write_file", input: .object(["path": .string("/g.py")])) == ["/g.py"])
        #expect(TaskActivityClassifier.editedPaths(toolName: "replace", input: .object(["file_path": .string("/r.go")])) == ["/r.go"])
        #expect(TaskActivityClassifier.editedPaths(toolName: "Read", input: .object(["file_path": .string("/x")])).isEmpty)
    }

    @Test
    func readsExitCodesFromCommonShapes() {
        #expect(TaskActivityClassifier.commandSucceeded(response: .object(["exitCode": .number(0)]), failed: false) == true)
        #expect(TaskActivityClassifier.commandSucceeded(response: .object(["metadata": .object(["exit_code": .number(2)])]), failed: false) == false)
        #expect(TaskActivityClassifier.commandSucceeded(response: .string("Process exited with code 1"), failed: false) == false)
        #expect(TaskActivityClassifier.commandSucceeded(response: .string("ok"), failed: false) == nil)
        #expect(TaskActivityClassifier.commandSucceeded(response: nil, failed: true) == false)
    }
}

struct TaskSummaryStateTests {
    private let now = Date(timeIntervalSince1970: 20_000)
    private let summary = TaskSummary(fileCount: 2, fileNames: ["a.swift", "b.swift"], commandCount: 1, tests: .passed, duration: 90)

    private func startedState() -> SessionState {
        var state = SessionState()
        state.apply(.sessionStarted(SessionStarted(sessionID: "s", title: "Claude", tool: .claudeCode, summary: "", timestamp: now)))
        return state
    }

    @Test
    func completionStoresTheSummaryAndANewTurnClearsIt() {
        var state = startedState()
        state.apply(.sessionCompleted(SessionCompleted(sessionID: "s", summary: "Done.", timestamp: now, taskSummary: summary)))
        #expect(state.session(id: "s")?.taskSummary == summary)

        // A bare completion (the session ending) keeps it.
        state.apply(.sessionCompleted(SessionCompleted(sessionID: "s", summary: "Ended.", timestamp: now, isSessionEnd: true)))
        #expect(state.session(id: "s")?.taskSummary == summary)

        state.apply(.activityUpdated(SessionActivityUpdated(sessionID: "s", summary: "Prompt: next", phase: .running, timestamp: now)))
        #expect(state.session(id: "s")?.taskSummary == nil)
    }

    @Test
    func theSummarySurvivesASessionRoundTrip() throws {
        var state = startedState()
        state.apply(.sessionCompleted(SessionCompleted(sessionID: "s", summary: "Done.", timestamp: now, taskSummary: summary)))
        let session = try #require(state.session(id: "s"))
        let decoded = try JSONDecoder().decode(AgentSession.self, from: JSONEncoder().encode(session))
        #expect(decoded.taskSummary == summary)

        // Sessions persisted before summaries existed still decode.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as! [String: Any]
        legacy.removeValue(forKey: "taskSummary")
        let old = try JSONDecoder().decode(AgentSession.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.taskSummary == nil)
    }
}

/// End to end through a live bridge: hook payloads in, the completion's
/// summary out.
struct TaskSummaryBridgeTests {
    @Test
    func claudeStopCarriesWhatTheTurnDid() async throws {
        let rig = try await SummaryRig()
        defer { rig.tearDown() }
        let id = "summary-claude"

        try rig.claude(.userPromptSubmit, id, prompt: "Fix the bug and run the tests")
        try rig.claude(.postToolUse, id, toolName: "Edit",
                       toolInput: .object(["file_path": .string("/repo/Sources/Bug.swift"), "old_string": .string("a"), "new_string": .string("b")]),
                       toolResponse: .object(["filePath": .string("/repo/Sources/Bug.swift")]))
        // A subagent's edit is the turn's work too.
        try rig.claude(.postToolUse, id, agentID: "sub-1", toolName: "Write",
                       toolInput: .object(["file_path": .string("/repo/Tests/BugTests.swift"), "content": .string("…")]))
        try rig.claude(.postToolUseFailure, id, toolName: "Bash",
                       toolInput: .object(["command": .string("swift test")]))
        try rig.claude(.postToolUse, id, toolName: "Bash",
                       toolInput: .object(["command": .string("swift test")]),
                       toolResponse: .object(["stdout": .string("Test run passed"), "stderr": .string(""), "interrupted": .boolean(false)]))
        try rig.claude(.stop, id, lastAssistantMessage: "Fixed it; tests pass.")

        let session = try await rig.session(id) { $0.phase == .completed }
        let summary = try #require(session.taskSummary)
        #expect(summary.fileCount == 2)
        #expect(summary.fileNames == ["Bug.swift", "BugTests.swift"])
        #expect(summary.commandCount == 2)
        #expect(summary.tests == .passed)
        #expect(summary.duration != nil)

        // The next prompt clears it until that turn finishes.
        try rig.claude(.userPromptSubmit, id, prompt: "Thanks, explain the fix")
        let next = try await rig.session(id) { $0.phase == .running }
        #expect(next.taskSummary == nil)
        try rig.claude(.stop, id, lastAssistantMessage: "It was an off-by-one.")
        let talked = try await rig.session(id) { $0.phase == .completed && $0.summary == "It was an off-by-one." }
        #expect(talked.taskSummary == nil)
    }

    @Test
    func codexStopCarriesItsTestRun() async throws {
        let rig = try await SummaryRig()
        defer { rig.tearDown() }
        let id = "summary-codex"

        try rig.codex(#"{"hook_event_name":"SessionStart","source":"startup"}"#, id)
        try rig.codex(#"{"hook_event_name":"UserPromptSubmit","prompt":"run the tests"}"#, id)
        try rig.codex(#"""
        {"hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"call_1",
         "tool_input":{"command":"pnpm test"},
         "tool_response":{"exit_code":1,"output":"1 failing"}}
        """#, id)
        try rig.codex(#"{"hook_event_name":"Stop","last_assistant_message":"One test fails."}"#, id)

        let session = try await rig.session(id) { $0.phase == .completed }
        #expect(session.taskSummary?.tests == .failed)
        #expect(session.taskSummary?.commandCount == 1)
        #expect(session.taskSummary?.fileCount == 0)
    }
}

private final class SummaryRig: @unchecked Sendable {
    let socketURL = BridgeSocketLocation.uniqueTestURL()
    let server: BridgeServer
    let observer: LocalBridgeClient
    let collector = SummaryEventCollector()
    private var collection: Task<Void, Never>?

    init() async throws {
        server = BridgeServer(socketURL: socketURL)
        try server.start()
        observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        let collector = self.collector
        collection = Task {
            do {
                for try await event in stream { await collector.append(event) }
            } catch {}
        }
        try await observer.send(.registerClient(role: .observer))
    }

    func tearDown() {
        collection?.cancel()
        observer.disconnect()
        server.stop()
    }

    func claude(
        _ event: ClaudeHookEventName,
        _ sessionID: String,
        agentID: String? = nil,
        toolName: String? = nil,
        toolInput: ClaudeHookJSONValue? = nil,
        toolResponse: ClaudeHookJSONValue? = nil,
        prompt: String? = nil,
        lastAssistantMessage: String? = nil
    ) throws {
        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processClaudeHook(
                ClaudeHookPayload(
                    cwd: "/repo",
                    hookEventName: event,
                    sessionID: sessionID,
                    transcriptPath: "/tmp/\(sessionID).jsonl",
                    agentID: agentID,
                    toolName: toolName,
                    toolInput: toolInput,
                    toolResponse: toolResponse,
                    prompt: prompt,
                    lastAssistantMessage: lastAssistantMessage
                )
            )
        )
    }

    /// A Codex hook as Codex writes it: `fields` merged into the common keys.
    func codex(_ fields: String, _ sessionID: String) throws {
        var object = try JSONSerialization.jsonObject(with: Data(fields.utf8)) as! [String: Any]
        object["session_id"] = sessionID
        object["cwd"] = "/repo"
        object["model"] = "gpt-5"
        object["permission_mode"] = "default"
        object["transcript_path"] = "/tmp/\(sessionID)-rollout.jsonl"
        let payload = try JSONDecoder().decode(CodexHookPayload.self, from: JSONSerialization.data(withJSONObject: object))
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processCodexHook(payload))
    }

    func session(_ id: String, until predicate: (AgentSession) -> Bool) async throws -> AgentSession {
        var last: AgentSession?
        for _ in 0..<200 {
            var state = SessionState()
            for event in await collector.snapshot() { state.apply(event) }
            if let session = state.session(id: id) {
                last = session
                if predicate(session) { return session }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try #require(last)
    }
}

private actor SummaryEventCollector {
    private var events: [AgentEvent] = []
    func append(_ event: AgentEvent) { events.append(event) }
    func snapshot() -> [AgentEvent] { events }
}
