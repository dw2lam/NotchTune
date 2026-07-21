import Foundation
import Testing
@testable import NotchTuneCore

/// Pins the per-request timeout for `CodexAppServerClient`. Without it,
/// a wedged codex app-server (no disconnect, no reply) would suspend
/// the caller's `Task` and pin a `CheckedThrowingContinuation` plus
/// every byte its closure captured for the lifetime of the process.
struct CodexAppServerTimeoutTests {
    @Test
    func sendRequestThrowsTimeoutWhenAppServerNeverReplies() async {
        let client = CodexAppServerClient()
        client.requestTimeoutSeconds = 0.1

        // Discard pipe stands in for a real codex stdin — writes
        // succeed (empty 64 KB kernel buffer absorbs them) but
        // nothing on the read side ever produces a reply.
        let pipe = Pipe()
        client.stdin = pipe.fileHandleForWriting

        let start = Date()

        await #expect(throws: CodexAppServerError.self) {
            _ = try await client.listLoadedThreads()
        }

        // Should fail fast — within a small multiple of the
        // configured timeout, not hang on the global test timeout.
        #expect(Date().timeIntervalSince(start) < 1.0)
    }

    @Test
    func sendRequestSurfacesTimeoutErrorCase() async throws {
        let client = CodexAppServerClient()
        client.requestTimeoutSeconds = 0.1

        let pipe = Pipe()
        client.stdin = pipe.fileHandleForWriting

        do {
            _ = try await client.listLoadedThreads()
            Issue.record("Expected CodexAppServerError.timeout, got nothing")
        } catch let error as CodexAppServerError {
            switch error {
            case .timeout:
                break  // expected
            default:
                Issue.record("Expected .timeout, got \(error)")
            }
        } catch {
            Issue.record("Expected CodexAppServerError, got \(type(of: error))")
        }
    }
}
