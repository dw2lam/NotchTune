import Foundation
import Testing
@testable import NotchTuneCore

/// Agents ship new fields and values between our releases. An event should
/// only be lost when it has no event name or session to attach to.
struct HookPayloadLeniencyTests {
    private let decoder = JSONDecoder()

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    // Each optional field gets every wrong type a fuzzer would try.
    private var hostileValues: [Any] {
        [NSNull(), 42, true, "surprise", ["nested": ["deep": 1]], [1, "two", ["three": 3]]]
    }

    private func expectSurvives<Payload: Decodable>(
        _ type: Payload.Type,
        base: [String: Any],
        fields: [String],
        required: Set<String>
    ) throws {
        for field in fields where !required.contains(field) {
            for value in hostileValues {
                var payload = base
                payload[field] = value
                #expect(throws: Never.self, "\(field) = \(value)") {
                    _ = try decoder.decode(type, from: json(payload))
                }
            }
        }
    }

    private let claudeFields = [
        "cwd", "transcript_path", "hook_source", "permission_mode", "agent_id", "agent_type", "model",
        "source", "tool_name", "tool_input", "tool_use_id", "tool_response", "permission_suggestions",
        "prompt", "message", "title", "notification_type", "subtype", "stop_hook_active",
        "last_assistant_message", "error", "error_details", "is_interrupt", "agent_transcript_path",
        "background_tasks", "terminal_app", "terminal_session_id", "terminal_tty", "terminal_title",
        "warp_pane_uuid", "remote",
    ]

    private let codexFields = [
        "cwd", "model", "permission_mode", "terminal_app", "terminal_session_id", "terminal_tty",
        "terminal_title", "warp_pane_uuid", "transcript_path", "source", "turn_id", "tool_name",
        "tool_use_id", "tool_input", "tool_response", "prompt", "stop_hook_active", "last_assistant_message",
    ]

    private let geminiFields = [
        "cwd", "transcript_path", "timestamp", "prompt", "prompt_response", "source", "reason",
        "notification_type", "message", "usage", "details", "stop_hook_active", "terminal_app",
        "terminal_session_id", "terminal_tty", "terminal_title",
    ]

    @Test
    func claudeSurvivesUnexpectedValuesInEveryOptionalField() throws {
        try expectSurvives(
            ClaudeHookPayload.self,
            base: ["hook_event_name": "PreToolUse", "session_id": "s", "cwd": "/tmp"],
            fields: claudeFields,
            required: []
        )
    }

    @Test
    func codexSurvivesUnexpectedValuesInEveryOptionalField() throws {
        try expectSurvives(
            CodexHookPayload.self,
            base: ["hook_event_name": "Stop", "session_id": "s", "cwd": "/tmp"],
            fields: codexFields,
            required: []
        )
    }

    @Test
    func geminiSurvivesUnexpectedValuesInEveryOptionalField() throws {
        try expectSurvives(
            GeminiHookPayload.self,
            base: ["hook_event_name": "BeforeAgent", "session_id": "s", "cwd": "/tmp"],
            fields: geminiFields,
            required: []
        )
    }

    @Test
    func unknownEventNamesDecodeAndKeepTheirName() throws {
        let claude = try decoder.decode(ClaudeHookPayload.self, from: json([
            "hook_event_name": "PostCompact", "session_id": "s", "cwd": "/tmp",
        ]))
        #expect(claude.hookEventName == .unknown("PostCompact"))
        #expect(claude.hookEventName.rawValue == "PostCompact")

        let codex = try decoder.decode(CodexHookPayload.self, from: json([
            "hook_event_name": "PreModelRequest", "session_id": "s", "cwd": "/tmp",
        ]))
        #expect(codex.hookEventName == .unknown("PreModelRequest"))

        let gemini = try decoder.decode(GeminiHookPayload.self, from: json([
            "hook_event_name": "AfterTool", "session_id": "s", "cwd": "/tmp",
        ]))
        #expect(gemini.hookEventName == .unknown("AfterTool"))

        let antigravity = try decoder.decode(AntigravityHookPayload.self, from: json([
            "hook_event_name": "PreInvocation", "session_id": "s", "cwd": "/tmp",
        ]))
        #expect(antigravity.hookEventName == .unknown("PreInvocation"))

        let cursor = try decoder.decode(CursorHookPayload.self, from: json([
            "hook_event_name": "afterAgentThought", "conversation_id": "c",
        ]))
        #expect(cursor.hookEventName == .unknown("afterAgentThought"))
    }

    @Test
    func knownValuesStillDecodeToTheirCases() throws {
        let claude = try decoder.decode(ClaudeHookPayload.self, from: json([
            "hook_event_name": "SessionStart", "session_id": "s", "cwd": "/tmp",
            "source": "fork", "permission_mode": "plan",
        ]))
        #expect(claude.hookEventName == .sessionStart)
        #expect(claude.source == .fork)
        #expect(claude.permissionMode == .plan)
    }

    @Test
    func codexDecodesWithoutModelOrPermissionMode() throws {
        let payload = try decoder.decode(CodexHookPayload.self, from: json([
            "hook_event_name": "Stop", "session_id": "s", "cwd": "/tmp",
        ]))
        #expect(payload.model == nil)
        #expect(payload.permissionMode == nil)
    }

    @Test
    func unknownModesAreKept() throws {
        let codex = try decoder.decode(CodexHookPayload.self, from: json([
            "hook_event_name": "Stop", "session_id": "s", "cwd": "/tmp", "permission_mode": "yolo",
        ]))
        #expect(codex.permissionMode == .unknown("yolo"))

        let claude = try decoder.decode(ClaudeHookPayload.self, from: json([
            "hook_event_name": "Stop", "session_id": "s", "cwd": "/tmp",
            "permission_mode": "delegate", "source": "teleport",
        ]))
        #expect(claude.permissionMode == .unknown("delegate"))
        #expect(claude.source == .unknown("teleport"))
    }

    @Test
    func unknownValuesSurviveTheBridgeRoundTrip() throws {
        var payload = ClaudeHookPayload(cwd: "/tmp", hookEventName: .unknown("PostCompact"), sessionID: "s")
        payload.permissionMode = .unknown("delegate")

        let line = try BridgeCodec.encodeLine(.command(.processClaudeHook(payload)))
        var buffer = line
        let envelopes = try BridgeCodec.decodeLines(from: &buffer)
        #expect(envelopes == [.command(.processClaudeHook(payload))])
    }

    @Test
    func oneUnfamiliarPermissionSuggestionKeepsTheRest() throws {
        let payload = try decoder.decode(ClaudeHookPayload.self, from: json([
            "hook_event_name": "PermissionRequest", "session_id": "s", "cwd": "/tmp",
            "permission_suggestions": [
                ["type": "somethingNew", "destination": "elsewhere"],
                ["type": "setMode", "mode": "plan", "destination": "session"],
            ],
        ]))
        #expect(payload.permissionSuggestions?.count == 1)
    }

    @Test
    func anEventWithoutASessionStillFails() {
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(ClaudeHookPayload.self, from: json(["hook_event_name": "Stop"]))
        }
    }

    @Test
    func newNotificationTypesAreJustText() throws {
        let payload = try decoder.decode(ClaudeHookPayload.self, from: json([
            "hook_event_name": "Notification", "session_id": "s", "cwd": "/tmp",
            "notification_type": "agent_needs_input", "message": "Waiting on you",
        ]))
        #expect(payload.notificationType == "agent_needs_input")
        #expect(!payload.isIdleNotification)
    }

    @Test
    func directivesAreAlwaysValidJSON() throws {
        let output = try #require(try ClaudeHookOutputEncoder.standardOutput(
            for: .claudeHookDirective(.permissionRequest(.deny(message: "quote \" and \n newline", interrupt: false)))
        ))
        #expect((try? JSONSerialization.jsonObject(with: output)) != nil)
    }
}
