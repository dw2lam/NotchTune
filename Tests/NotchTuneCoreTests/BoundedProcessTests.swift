import Foundation
import Testing
@testable import NotchTuneCore

struct BoundedProcessTests {
    @Test
    func aChildThatNeverExitsIsKilledAtTheDeadline() {
        let start = Date()
        let output = BoundedProcess.run(executablePath: "/bin/sleep", arguments: ["30"], deadline: 0.2)
        #expect(output == nil)
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test
    func inputToAChildThatAlreadyExitedDoesNotKillUs() {
        // Far past the pipe buffer, to a child that never reads it. Without
        // the guard the write raises SIGPIPE and the test run dies here.
        let output = BoundedProcess.run(
            executablePath: "/usr/bin/true",
            arguments: [],
            deadline: 5,
            input: Data(repeating: 0x61, count: 1_000_000)
        )
        #expect(output?.status == 0)
    }

    @Test
    func aThrowingRunTellsATimeoutFromALaunchFailure() {
        #expect(throws: BoundedProcess.Failure.timedOut) {
            try BoundedProcess.runThrowing(executablePath: "/bin/sleep", arguments: ["30"], deadline: 0.1)
        }
        #expect(throws: (any Error).self) {
            try BoundedProcess.runThrowing(executablePath: "/no/such/helper", arguments: [], deadline: 1)
        }
    }

    @Test
    func standardErrorComesBackWhenAskedFor() throws {
        let output = try BoundedProcess.runThrowing(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo oops >&2"],
            deadline: 5,
            capturesStandardError: true
        )
        #expect(String(decoding: output.stderr, as: UTF8.self) == "oops\n")
    }

    @Test
    func aFastChildReturnsItsOutput() {
        let output = BoundedProcess.run(executablePath: "/bin/echo", arguments: ["hello"], deadline: 3)
        #expect(output?.status == 0)
        #expect(output?.text == "hello\n")
    }

    @Test
    func outputLargerThanThePipeBufferDoesNotDeadlock() {
        let output = BoundedProcess.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "yes hook | head -c 300000"],
            deadline: 5
        )
        #expect(output?.stdout.count == 300_000)
    }

    @Test
    func inputReachesTheChild() {
        let output = BoundedProcess.run(
            executablePath: "/bin/cat",
            arguments: [],
            deadline: 3,
            input: Data("payload".utf8)
        )
        #expect(output?.text == "payload")
    }

    @Test
    func aMissingExecutableIsNoAnswer() {
        #expect(BoundedProcess.run(executablePath: "/no/such/tool", arguments: [], deadline: 1) == nil)
    }

    @Test
    func ttyComesFromTheNearestAncestorThatHasOne() {
        // Claude Code's hooks: shell and hook have no terminal, Claude does.
        let tree: [pid_t: (parent: pid_t, tty: String?)] = [
            300: (200, nil),
            200: (100, nil),
            100: (1, "/dev/ttys004"),
        ]
        #expect(HookTerminalProbe.ancestorTTY(startingAt: 300) { tree[$0] } == "/dev/ttys004")
    }

    @Test
    func noAncestorWithATTYIsNil() {
        let tree: [pid_t: (parent: pid_t, tty: String?)] = [300: (1, nil)]
        #expect(HookTerminalProbe.ancestorTTY(startingAt: 300) { tree[$0] } == nil)
        #expect(HookTerminalProbe.ancestorTTY(startingAt: 999) { tree[$0] } == nil)
    }

    @Test
    func locatorRunsOnlyWhereTheUserIsSureToBeInTheTerminal() {
        var locatorCalls = 0
        let locate: (String) -> (sessionID: String?, tty: String?, title: String?) = { _ in
            locatorCalls += 1
            return (nil, "/dev/ttys001", "title")
        }

        func enrich(_ event: ClaudeHookEventName) -> ClaudeHookPayload {
            ClaudeHookPayload(cwd: "/tmp", hookEventName: event, sessionID: "s")
                .withRuntimeContext(
                    environment: ["TERM_PROGRAM": "Apple_Terminal"],
                    currentTTYProvider: { nil },
                    terminalLocatorProvider: locate
                )
        }

        _ = enrich(.preToolUse)
        _ = enrich(.postToolUse)
        _ = enrich(.notification)
        #expect(locatorCalls == 0)

        #expect(enrich(.sessionStart).terminalTTY == "/dev/ttys001")
        _ = enrich(.userPromptSubmit)
        #expect(locatorCalls == 2)
    }
}
