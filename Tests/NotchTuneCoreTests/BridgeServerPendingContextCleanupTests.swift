import Foundation
import Testing
@testable import NotchTuneCore

/// Pins the cleanup contract for `BridgeServer.dropPendingClaudeContexts`.
/// Without it, `pendingClaudeToolContexts` / `pendingTaskCreations` /
/// `pendingAgentDescriptions` accumulated forever whenever a Claude
/// session ended (Stop / StopFailure / SessionEnd) without the matching
/// postToolUse / subagentStart — pinning entire `toolInput` JSON trees
/// (full file contents for Edit / Write) in memory until app restart.
struct BridgeServerPendingContextCleanupTests {
    @Test
    func stopDropsOrphanedPreToolUseContext() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let sessionID = "claude-session-leak-1"
        let bigInput: ClaudeHookJSONValue = .object([
            "file_path": .string("/tmp/x.swift"),
            "old_string": .string(String(repeating: "a", count: 10_000)),
            "new_string": .string(String(repeating: "b", count: 10_000)),
        ])

        let preToolPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .preToolUse,
            sessionID: sessionID,
            toolName: "Edit",
            toolInput: bigInput,
            toolUseID: "tool-use-edit-1"
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(preToolPayload))

        #expect(server.pendingClaudeStateSnapshotForTests().toolContextCount == 1)

        let stopPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .stop,
            sessionID: sessionID
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(stopPayload))

        let snapshot = server.pendingClaudeStateSnapshotForTests()
        #expect(snapshot.toolContextCount == 0)
        #expect(snapshot.totalCount == 0)
    }

    @Test
    func stopFailureDropsOrphanedAgentDescription() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let sessionID = "claude-session-leak-2"
        let agentInput: ClaudeHookJSONValue = .object([
            "description": .string("audit memory leaks across the bridge"),
            "subagent_type": .string("general-purpose"),
            "prompt": .string("..."),
        ])

        let preToolPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .preToolUse,
            sessionID: sessionID,
            toolName: "Agent",
            toolInput: agentInput,
            toolUseID: "tool-use-agent-1"
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(preToolPayload))

        let before = server.pendingClaudeStateSnapshotForTests()
        #expect(before.agentDescriptionCount == 1)
        #expect(before.toolContextCount == 1)

        let stopFailurePayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .stopFailure,
            sessionID: sessionID,
            error: "agent crashed"
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(stopFailurePayload))

        let snapshot = server.pendingClaudeStateSnapshotForTests()
        #expect(snapshot.agentDescriptionCount == 0)
        #expect(snapshot.toolContextCount == 0)
    }

    @Test
    func sessionEndDropsOrphanedTaskCreation() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let sessionID = "claude-session-leak-3"
        let taskInput: ClaudeHookJSONValue = .object([
            "subject": .string("Write the report"),
            "description": .string("Finish before the demo."),
        ])

        let preToolPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .preToolUse,
            sessionID: sessionID,
            toolName: "TaskCreate",
            toolInput: taskInput,
            toolUseID: "tool-use-task-1"
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(preToolPayload))

        #expect(server.pendingClaudeStateSnapshotForTests().taskCreationCount == 1)

        let sessionEndPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionEnd,
            sessionID: sessionID
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(sessionEndPayload))

        #expect(server.pendingClaudeStateSnapshotForTests().taskCreationCount == 0)
    }

    @Test
    func stopOfOneSessionLeavesOtherSessionsUntouched() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let toolInputA: ClaudeHookJSONValue = .object(["command": .string("ls -la")])
        let toolInputB: ClaudeHookJSONValue = .object(["command": .string("pwd")])

        let preA = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .preToolUse,
            sessionID: "session-A",
            toolName: "Bash",
            toolInput: toolInputA,
            toolUseID: "use-A"
        )
        let preB = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .preToolUse,
            sessionID: "session-B",
            toolName: "Bash",
            toolInput: toolInputB,
            toolUseID: "use-B"
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(preA))
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(preB))

        #expect(server.pendingClaudeStateSnapshotForTests().toolContextCount == 2)

        let stopA = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .stop,
            sessionID: "session-A"
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(stopA))

        // session-B's tool context must still be there — the cleanup is
        // strictly per-session; otherwise a parallel turn on a sibling
        // session would lose its in-flight state.
        #expect(server.pendingClaudeStateSnapshotForTests().toolContextCount == 1)
    }

    @Test
    func normalPreToolUseThenPostToolUseLeavesNoLeftover() throws {
        // Regression guard: the leak fix must not change normal pairing
        // semantics. After a matching postToolUse the entry should be
        // gone via the existing line-701 path — we should not depend
        // on .stop to reach zero.
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let sessionID = "claude-session-paired"
        let toolInput: ClaudeHookJSONValue = .object(["command": .string("echo hi")])

        let preToolPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .preToolUse,
            sessionID: sessionID,
            toolName: "Bash",
            toolInput: toolInput,
            toolUseID: "use-paired"
        )
        let postToolPayload = ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .postToolUse,
            sessionID: sessionID,
            toolName: "Bash",
            toolInput: toolInput,
            toolUseID: "use-paired"
        )
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(preToolPayload))
        _ = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(postToolPayload))

        #expect(server.pendingClaudeStateSnapshotForTests().toolContextCount == 0)
    }
}
