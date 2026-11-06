import Dispatch
import Foundation
import Testing
@testable import NotchTuneCore

/// Parallel tool calls in one Claude session each block their own hook. Every
/// hook must get an answer, and a tool call finishing must only settle its
/// own request.
struct BridgeServerParallelApprovalTests {
    private let sessionID = "claude-parallel"

    private struct Harness {
        let socketURL: URL
        let server: BridgeServer
        let observer: LocalBridgeClient
        let stream: AsyncThrowingStream<AgentEvent, Error>

        func hook(_ payload: ClaudeHookPayload, timeout: TimeInterval = 10) async throws -> BridgeResponse? {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    do {
                        let response = try BridgeCommandClient(socketURL: socketURL)
                            .send(.processClaudeHook(payload), timeout: timeout)
                        continuation.resume(returning: response)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        func tearDown() {
            observer.disconnect()
            server.stop()
        }
    }

    private func makeHarness() async throws -> Harness {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        try await observer.send(.registerClient(role: .observer))
        return Harness(socketURL: socketURL, server: server, observer: observer, stream: stream)
    }

    private func permission(_ command: String, toolUseID: String? = nil) -> ClaudeHookPayload {
        ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .permissionRequest,
            sessionID: sessionID,
            toolName: "Bash",
            toolInput: .object(["command": .string(command)]),
            toolUseID: toolUseID
        )
    }

    private func finished(_ command: String, toolUseID: String?, event: ClaudeHookEventName = .postToolUse) -> ClaudeHookPayload {
        ClaudeHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: event,
            sessionID: sessionID,
            toolName: "Bash",
            toolInput: .object(["command": .string(command)]),
            toolUseID: toolUseID
        )
    }

    private func nextRequest(
        _ iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator
    ) async throws -> PermissionRequest {
        for _ in 0..<12 {
            if case let .permissionRequested(payload)? = try await iterator.next() {
                return payload.request
            }
        }
        throw BridgeTransportError.notConnected
    }

    private func isAllow(_ response: BridgeResponse?) -> Bool {
        if case .claudeHookDirective(.permissionRequest(.allow))? = response { return true }
        return false
    }

    private func isDeny(_ response: BridgeResponse?) -> Bool {
        if case .claudeHookDirective(.permissionRequest(.deny))? = response { return true }
        return false
    }

    @Test
    func aSecondParallelRequestWaitsItsTurnAndBothHooksGetAnAnswer() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }
        var events = harness.stream.makeAsyncIterator()

        async let first = harness.hook(permission("npm test", toolUseID: "t1"))
        let shownFirst = try await nextRequest(&events)
        #expect(shownFirst.commandPreview?.text == "npm test")

        async let second = harness.hook(permission("rm -rf build", toolUseID: "t2"))
        // Let the second hook land behind the first.
        try await Task.sleep(for: .milliseconds(100))

        try await harness.observer.send(.resolvePermission(
            sessionID: sessionID,
            resolution: .allowOnce(),
            requestID: shownFirst.id
        ))
        #expect(isAllow(try await first))

        let shownSecond = try await nextRequest(&events)
        #expect(shownSecond.commandPreview?.text == "rm -rf build")

        try await harness.observer.send(.resolvePermission(
            sessionID: sessionID,
            resolution: .deny(),
            requestID: shownSecond.id
        ))
        #expect(isDeny(try await second))
    }

    @Test
    func anotherToolCallFinishingLeavesThePendingApprovalAlone() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }
        var events = harness.stream.makeAsyncIterator()

        async let waiting = harness.hook(permission("npm test", toolUseID: "t1"))
        let request = try await nextRequest(&events)

        _ = try await harness.hook(finished("ls", toolUseID: "t9"))
        _ = try await harness.hook(finished("cat x", toolUseID: "t8", event: .postToolUseFailure))
        _ = try await harness.hook(finished("pwd", toolUseID: "t7", event: .permissionDenied))

        try await harness.observer.send(.resolvePermission(
            sessionID: sessionID,
            resolution: .allowOnce(),
            requestID: request.id
        ))
        #expect(isAllow(try await waiting))
    }

    @Test
    func aRequestWithoutAToolUseIDMatchesByItsInput() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }
        var events = harness.stream.makeAsyncIterator()

        async let first = harness.hook(permission("npm test"), timeout: 0.5)
        _ = try await nextRequest(&events)
        async let second = harness.hook(permission("rm -rf build"))
        try await Task.sleep(for: .milliseconds(100))

        // The first call went ahead in the terminal: the second takes over.
        _ = try await harness.hook(finished("npm test", toolUseID: "t1"))
        let shown = try await nextRequest(&events)
        #expect(shown.commandPreview?.text == "rm -rf build")

        try await harness.observer.send(.resolvePermission(sessionID: sessionID, resolution: .allowOnce()))
        #expect(isAllow(try await second))
        _ = try? await first
    }

    @Test
    func aHookThatDisconnectsHandsOverToTheNextRequest() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }
        var events = harness.stream.makeAsyncIterator()

        async let first = harness.hook(permission("npm test", toolUseID: "t1"), timeout: 0.3)
        _ = try await nextRequest(&events)
        async let second = harness.hook(permission("rm -rf build", toolUseID: "t2"))

        _ = try? await first
        let shown = try await nextRequest(&events)
        #expect(shown.commandPreview?.text == "rm -rf build")

        try await harness.observer.send(.resolvePermission(sessionID: sessionID, resolution: .allowOnce()))
        #expect(isAllow(try await second))
    }

    @Test
    func anAnswerForARequestThatIsGoneTouchesNothing() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }
        var events = harness.stream.makeAsyncIterator()

        async let waiting = harness.hook(permission("rm -rf build", toolUseID: "t1"))
        let request = try await nextRequest(&events)

        try await harness.observer.send(.resolvePermission(
            sessionID: sessionID,
            resolution: .allowOnce(),
            requestID: UUID()
        ))
        try await Task.sleep(for: .milliseconds(100))

        try await harness.observer.send(.resolvePermission(
            sessionID: sessionID,
            resolution: .deny(),
            requestID: request.id
        ))
        #expect(isDeny(try await waiting))
    }

    @Test
    func theEndOfTheTurnClearsEveryWaitingRequest() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }
        var events = harness.stream.makeAsyncIterator()

        async let first = harness.hook(permission("npm test", toolUseID: "t1"), timeout: 0.5)
        _ = try await nextRequest(&events)
        async let second = harness.hook(permission("ls", toolUseID: "t2"), timeout: 0.5)
        try await Task.sleep(for: .milliseconds(100))

        _ = try await harness.hook(ClaudeHookPayload(cwd: "/tmp/worktree", hookEventName: .stop, sessionID: sessionID))

        var sawResolved = false
        for _ in 0..<12 where !sawResolved {
            if case .actionableStateResolved? = try await events.next() {
                sawResolved = true
            }
        }
        #expect(sawResolved)
        _ = try? await first
        _ = try? await second
    }

    @Test
    func commandsCarryTheirRequestIDOverTheWireAndOlderOnesDecode() throws {
        let id = UUID()
        let commands: [BridgeCommand] = [
            .resolvePermission(sessionID: "s", resolution: .allowOnce(), requestID: id),
            .answerQuestion(sessionID: "s", response: QuestionPromptResponse(answer: "a"), requestID: id),
        ]
        for command in commands {
            let data = try JSONEncoder().encode(command)
            #expect(try JSONDecoder().decode(BridgeCommand.self, from: data) == command)
        }

        let withoutID = BridgeCommand.resolvePermission(sessionID: "s", resolution: .deny())
        let data = try JSONEncoder().encode(withoutID)
        #expect(!String(decoding: data, as: UTF8.self).contains("requestID"))
        #expect(try JSONDecoder().decode(BridgeCommand.self, from: data) == withoutID)
    }
}
