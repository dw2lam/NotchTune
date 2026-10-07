import Foundation
import Testing
@testable import NotchTuneCore

/// Subagents must keep their Claude Code session live — including background
/// agents (`run_in_background`) that keep working after the main turn's Stop.
/// Payload shapes mirror what Claude Code actually sends: subagent tool hooks
/// carry the PARENT's session_id plus `agent_id` / `agent_type`; a background
/// `Agent` call returns at once with `status: async_launched`; `SubagentStop`
/// carries `background_tasks`.
struct ClaudeSubagentLivenessTests {
    @Test
    func backgroundAgentKeepsSessionLiveAfterStopAndCompletesWhenItFinishes() async throws {
        let rig = try await BridgeRig()
        defer { rig.tearDown() }
        let id = "liveness-background"

        try rig.send(.userPromptSubmit, id, prompt: "Investigate in the background")
        try rig.send(
            .postToolUse, id,
            toolName: "Agent",
            toolInput: .object(["description": .string("Probe"), "subagent_type": .string("Explore")]),
            toolResponse: .object([
                "status": .string("async_launched"),
                "agentId": .string("bg-1"),
                "description": .string("Probe"),
            ])
        )
        try rig.send(.stop, id, lastAssistantMessage: "Launched a background agent.")

        var session = try await rig.session(id) { $0.phase == .running && $0.claudeMetadata?.activeSubagents.count == 1 }
        #expect(session.phase == .running)
        #expect(session.claudeMetadata?.activeSubagents.first?.agentID == "bg-1")
        #expect(session.claudeMetadata?.activeSubagents.first?.isBackground == true)
        #expect(await !rig.hasCompletion(id))

        // The background agent works: the parent mirrors its tool and stays live.
        try rig.send(.preToolUse, id, agentID: "bg-1", agentType: "Explore",
                     toolName: "Bash", toolInput: .object(["command": .string("swift test")]))
        session = try await rig.session(id) { $0.claudeMetadata?.currentTool == "Bash" }
        #expect(session.phase == .running)
        #expect(await !rig.hasCompletion(id))

        // It finishes: the held completion is delivered with the main turn's summary.
        try rig.send(.subagentStop, id, agentID: "bg-1", agentType: "Explore",
                     backgroundTasks: [ClaudeBackgroundTask(id: "bg-1", type: "subagent", status: "running")])
        session = try await rig.session(id) { $0.phase == .completed }
        #expect(session.summary == "Launched a background agent.")
        #expect(session.claudeMetadata?.activeSubagents.isEmpty == true)
    }

    @Test
    func foregroundSubagentIsTrackedDuringTheTurnAndClearedAtStop() async throws {
        let rig = try await BridgeRig()
        defer { rig.tearDown() }
        let id = "liveness-foreground"

        try rig.send(.userPromptSubmit, id, prompt: "Use a subagent")
        try rig.send(.preToolUse, id, agentID: "fg-1", agentType: "general-purpose",
                     toolName: "Read", toolInput: .object(["file_path": .string("/tmp/a.swift")]))
        var session = try await rig.session(id) { $0.claudeMetadata?.activeSubagents.count == 1 }
        #expect(session.phase == .running)
        #expect(session.claudeMetadata?.activeSubagents.first?.isBackground == nil)

        // Foreground subagents can't outlive the turn.
        try rig.send(.stop, id, lastAssistantMessage: "Done.")
        session = try await rig.session(id) { $0.phase == .completed }
        #expect(session.summary == "Done.")
        #expect(session.claudeMetadata?.activeSubagents.isEmpty == true)
    }

    @Test
    func stopListingRunningBackgroundTasksDefersTheCompletion() async throws {
        let rig = try await BridgeRig()
        defer { rig.tearDown() }
        let id = "liveness-background-tasks"

        try rig.send(.userPromptSubmit, id, prompt: "Go")
        try rig.send(.stop, id, lastAssistantMessage: "Waiting on agents.",
                     backgroundTasks: [
                        ClaudeBackgroundTask(id: "bg-a", type: "subagent", status: "running", agentType: "Explore"),
                        ClaudeBackgroundTask(id: "sh-1", type: "shell", status: "running"),
                     ])
        var session = try await rig.session(id) { $0.claudeMetadata?.activeSubagents.count == 1 }
        #expect(session.phase == .running)
        // Background shells (dev servers etc.) don't keep a session live.
        #expect(session.claudeMetadata?.activeSubagents.map(\.agentID) == ["bg-a"])

        try rig.send(.subagentStop, id, agentID: "bg-a", agentType: "Explore",
                     backgroundTasks: [ClaudeBackgroundTask(id: "sh-1", type: "shell", status: "running")])
        session = try await rig.session(id) { $0.phase == .completed }
        #expect(session.summary == "Waiting on agents.")
    }

    @Test
    func lateEventFromAStoppedSubagentDoesNotReopenTheSession() async throws {
        let rig = try await BridgeRig()
        defer { rig.tearDown() }
        let id = "liveness-late"

        try rig.send(.userPromptSubmit, id, prompt: "Go")
        try rig.send(.preToolUse, id, agentID: "fg-2", agentType: "Explore",
                     toolName: "Grep", toolInput: .object(["pattern": .string("x")]))
        try rig.send(.subagentStop, id, agentID: "fg-2", agentType: "Explore")
        try rig.send(.stop, id, lastAssistantMessage: "All done.")
        _ = try await rig.session(id) { $0.phase == .completed }

        // A straggling PostToolUse from the stopped subagent.
        try rig.send(.postToolUse, id, agentID: "fg-2", agentType: "Explore", toolName: "Grep")
        try await Task.sleep(for: .milliseconds(150))
        let session = try await rig.session(id) { _ in true }
        #expect(session.phase == .completed)
        #expect(session.summary == "All done.")
    }

    @Test
    func backgroundTasksDecodesLenientlyAndNeverBreaksTheHook() throws {
        let good = #"{"cwd":"/tmp","hook_event_name":"SubagentStop","session_id":"s","agent_id":"a","background_tasks":[{"id":"a","type":"subagent","status":"running","agent_type":"Explore","extra":{"x":1}},{"id":"b","type":"shell","status":"running","command":"npm run dev"}]}"#
        let decoded = try JSONDecoder().decode(ClaudeHookPayload.self, from: Data(good.utf8))
        #expect(decoded.backgroundTasks?.count == 2)
        #expect(decoded.backgroundTasks?.first?.isRunningSubagent == true)
        #expect(decoded.backgroundTasks?.last?.isRunningSubagent == false)

        // An unexpected shape is "unknown", not "nothing running", and the
        // rest of the payload still decodes.
        let odd = #"{"cwd":"/tmp","hook_event_name":"Stop","session_id":"s","background_tasks":{"count":2}}"#
        let decodedOdd = try JSONDecoder().decode(ClaudeHookPayload.self, from: Data(odd.utf8))
        #expect(decodedOdd.hookEventName == .stop)
        #expect(decodedOdd.backgroundTasks == nil)
    }
}

// MARK: - Rig

private final class BridgeRig: @unchecked Sendable {
    let socketURL = BridgeSocketLocation.uniqueTestURL()
    let server: BridgeServer
    let observer: LocalBridgeClient
    let collector = LivenessEventCollector()
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

    func send(
        _ event: ClaudeHookEventName,
        _ sessionID: String,
        agentID: String? = nil,
        agentType: String? = nil,
        toolName: String? = nil,
        toolInput: ClaudeHookJSONValue? = nil,
        toolResponse: ClaudeHookJSONValue? = nil,
        prompt: String? = nil,
        lastAssistantMessage: String? = nil,
        backgroundTasks: [ClaudeBackgroundTask]? = nil
    ) throws {
        _ = try BridgeCommandClient(socketURL: socketURL).send(
            .processClaudeHook(
                ClaudeHookPayload(
                    cwd: "/tmp/liveness",
                    hookEventName: event,
                    sessionID: sessionID,
                    transcriptPath: "/tmp/\(sessionID).jsonl",
                    agentID: agentID,
                    agentType: agentType,
                    toolName: toolName,
                    toolInput: toolInput,
                    toolResponse: toolResponse,
                    prompt: prompt,
                    lastAssistantMessage: lastAssistantMessage,
                    backgroundTasks: backgroundTasks
                )
            )
        )
    }

    /// Replays the observed events and waits until `predicate` holds.
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

    func hasCompletion(_ id: String) async -> Bool {
        await collector.snapshot().contains { event in
            if case let .sessionCompleted(payload) = event { return payload.sessionID == id }
            return false
        }
    }
}

private actor LivenessEventCollector {
    private var events: [AgentEvent] = []
    func append(_ event: AgentEvent) { events.append(event) }
    func snapshot() -> [AgentEvent] { events }
}
