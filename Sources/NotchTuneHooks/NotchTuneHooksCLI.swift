import Foundation
import NotchTuneCore

@main
struct NotchTuneHooksCLI {
    private static let interactiveClaudeHookTimeout: TimeInterval = 24 * 60 * 60
    private static let interactiveCodexHookTimeout =
        TimeInterval(CodexHookInstaller.managedInteractiveTimeout)

    private enum HookSource: String {
        case codex
        case claude
        case qoder
        case qwen
        case factory
        case droid
        case codebuddy
        case cursor
        case gemini
        case kimi
        case antigravity

        var isClaudeFormat: Bool {
            switch self {
            case .claude, .qoder, .qwen, .factory, .droid, .codebuddy, .kimi:
                return true
            case .codex, .cursor, .gemini, .antigravity:
                return false
            }
        }
    }

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        // Before the skip check and the stdin read: the doctor has no payload
        // to send and needs an answer even from a wrapped environment.
        if let nonce = value(of: "--doctor-ping", in: arguments) {
            exit(doctorPing(nonce: nonce))
        }

        var input = Data()
        var sourceString: String?

        do {
            // Allow wrappers to delegate one child process away from NotchTune without changing global hook installation.
            // Lets an external controller skip NotchTune hooks for this child process only, without touching the global install.
            if HookSkipConfiguration.shouldSkipHooks(environment: ProcessInfo.processInfo.environment) {
                return
            }

            input = FileHandle.standardInput.readDataToEndOfFile()
            guard !input.isEmpty else {
                return
            }

            sourceString = rawSourceString(arguments: arguments)
            guard let source = hookSource(arguments: arguments) else {
                logStderr("unsupported hook source: \(sourceString ?? "nil")")
                return
            }
            let decoder = JSONDecoder()
            let client = BridgeCommandClient(socketURL: BridgeSocketLocation.currentURL())

            switch source {
            case .codex:
                let payload = try decoder
                    .decode(CodexHookPayload.self, from: input)
                    .withRuntimeContext(environment: ProcessInfo.processInfo.environment)

                let timeout = payload.hookEventName == .permissionRequest
                    ? interactiveCodexHookTimeout
                    : 45

                guard let response = try? client.send(.processCodexHook(payload), timeout: timeout) else {
                    logStderr("bridge unavailable for codex hook (\(payload.hookEventName.rawValue))")
                    return
                }

                if let output = try CodexHookOutputEncoder.standardOutput(for: response) {
                    writeDirective(output)
                }
            case .claude, .qoder, .qwen, .factory, .droid, .codebuddy, .kimi:
                var payload = try decoder
                    .decode(ClaudeHookPayload.self, from: input)
                    .withRuntimeContext(environment: ProcessInfo.processInfo.environment)
                payload.hookSource = sourceString

                let timeout = payload.hookEventName == .permissionRequest
                    ? interactiveClaudeHookTimeout
                    : 45

                guard let response = try? client.send(.processClaudeHook(payload), timeout: timeout) else {
                    logStderr("bridge unavailable for claude hook (\(payload.hookEventName.rawValue))")
                    return
                }

                if let output = try ClaudeHookOutputEncoder.standardOutput(for: response) {
                    writeDirective(output)
                }
            case .cursor:
                let payload = try decoder.decode(CursorHookPayload.self, from: input)

                let timeout: TimeInterval = payload.isBlockingHook
                    ? Self.interactiveClaudeHookTimeout
                    : 45

                guard let response = try? client.send(.processCursorHook(payload), timeout: timeout) else {
                    return
                }

                if case let .cursorHookDirective(directive) = response {
                    let encoder = JSONEncoder()
                    writeDirective(try encoder.encode(directive))
                }
            case .gemini:
                let payload = try decoder
                    .decode(GeminiHookPayload.self, from: input)
                    .withRuntimeContext(environment: ProcessInfo.processInfo.environment)

                if let usage = payload.usage {
                    writeGeminiUsageCache(usage)
                } else if let details = payload.details,
                          case let .object(obj) = details,
                          let usage = obj["usage"] {
                    writeGeminiUsageCache(usage)
                }

                _ = try? client.send(.processGeminiHook(payload), timeout: 45)
            case .antigravity:
                // Antigravity ships its own (non-Claude) payload format and its
                // events (SessionStart/End, Before/AfterAgent, Notification) are
                // informational — none blocks the agent — so we fire-and-forget
                // like Gemini and emit no stdout directive.
                let payload = try decoder
                    .decode(AntigravityHookPayload.self, from: input)
                    .withRuntimeContext(environment: ProcessInfo.processInfo.environment)

                _ = try? client.send(.processAntigravityHook(payload), timeout: 45)
            }
        } catch {
            // Hooks should fail open so the CLI continues working even if the bridge is unavailable.
            logStderr("hook failed: \(error)")

            if error is DecodingError {
                HookDropLog().record(
                    source: sourceString ?? "codex",
                    event: HookDropLog.eventName(in: input),
                    field: HookDropLog.fieldPath(of: error)
                )
            }
        }
    }

    /// Answers the doctor's Test hook. Exit codes are the contract with
    /// `HookRoundTripTest`: 0 reached the app, 3 no bridge to talk to, 4 the
    /// bridge answered something else.
    private static func doctorPing(nonce: String) -> Int32 {
        let client = BridgeCommandClient(socketURL: BridgeSocketLocation.currentURL())
        guard let response = try? client.send(.doctorPing(nonce: nonce), timeout: 2) else {
            return 3
        }

        guard case .doctorPong(nonce) = response else {
            return 4
        }

        // The echo is the proof: a binary too old to know this flag also
        // exits 0, having found nothing on stdin.
        FileHandle.standardOutput.write(Data("\(nonce)\n".utf8))
        return 0
    }

    /// Claude Code reports a stdout that looks like JSON and isn't as a hook
    /// error, so what reaches an agent is valid JSON or nothing.
    private static func writeDirective(_ output: Data) {
        guard (try? JSONSerialization.jsonObject(with: output)) != nil else {
            logStderr("dropped a directive that wasn't valid JSON")
            return
        }

        FileHandle.standardOutput.write(output)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeGeminiUsageCache(_ usage: CodexHookJSONValue) {
        do {
            let data = try JSONEncoder().encode(usage)
            // Validate that it matches the GeminiUsageSnapshot format
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            _ = try decoder.decode(GeminiUsageSnapshot.self, from: data)
            
            // Re-encode to ensure clean JSON without extra fields
            try data.write(to: URL(fileURLWithPath: "/tmp/open-island-gemini-usage.json"), options: .atomic)
        } catch {
            // Ignore usage write errors
        }
    }

    private static func logStderr(_ message: String) {
        guard let data = "[NotchTuneHooks] \(message)\n".data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }

    private static func hookSource(arguments: [String]) -> HookSource? {
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--source", index + 1 < arguments.count {
                return HookSource(rawValue: arguments[index + 1])
            }

            index += 1
        }

        return .codex
    }

    private static func rawSourceString(arguments: [String]) -> String? {
        value(of: "--source", in: arguments)
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        var index = 0
        while index < arguments.count {
            if arguments[index] == flag, index + 1 < arguments.count {
                return arguments[index + 1]
            }

            index += 1
        }

        return nil
    }
}
