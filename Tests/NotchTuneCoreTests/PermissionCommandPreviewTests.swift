import Foundation
import Testing
@testable import NotchTuneCore

/// The approval card shows what will run, not a flattened first line of it.
struct PermissionCommandPreviewTests {
    @Test
    func keepsLineBreaksAndTheWholeCommand() throws {
        let command = "cd /tmp &&\n  rm -rf build\n"
        let preview = try #require(PermissionCommandPreview(command))

        #expect(preview.text == "cd /tmp &&\n  rm -rf build")
        #expect(!preview.isTruncated)
    }

    @Test
    func aCommandAtTheCapIsNotTruncated() throws {
        let preview = try #require(PermissionCommandPreview(String(repeating: "a", count: 600)))

        #expect(preview.text.count == 600)
        #expect(!preview.isTruncated)
    }

    @Test
    func aCommandPastTheCapSaysSo() throws {
        let preview = try #require(PermissionCommandPreview(String(repeating: "a", count: 601)))

        #expect(preview.text.count == 600)
        #expect(preview.isTruncated)
    }

    @Test
    func nothingToShowIsNoPreview() {
        #expect(PermissionCommandPreview(nil) == nil)
        #expect(PermissionCommandPreview(" \n ") == nil)
    }

    @Test
    func recognisesTheCommandRepeatedAsTheAffectedPath() throws {
        let preview = try #require(PermissionCommandPreview("git commit\n  -m hello && git push"))

        #expect(preview.repeats("git commit -m hello && git push"))
        #expect(preview.repeats("git commit -m hel…"))
        #expect(!preview.repeats("/tmp/repo"))
    }

    @Test
    func claudePayloadCarriesTheFullCommand() throws {
        let long = String(repeating: "x", count: 300) + "\nrm -rf ~/important"
        let payload = ClaudeHookPayload(
            cwd: "/tmp",
            hookEventName: .permissionRequest,
            sessionID: "s",
            toolName: "Bash",
            toolInput: .object(["command": .string(long), "description": .string("clean up")])
        )

        let preview = try #require(payload.permissionCommandPreview)
        #expect(preview.text == long)
        #expect((payload.toolInputPreview?.count ?? 0) <= 110)
    }

    @Test
    func aDecodedRequestFromAnOlderPayloadHasNoPreview() throws {
        let json = #"{"id":"6B29FC40-CA47-1067-B31D-00DD010662DA","title":"t","summary":"s","affectedPath":"p","primaryActionTitle":"Allow","secondaryActionTitle":"Deny","suggestedUpdates":[],"requiresTerminalApproval":false}"#
        let request = try JSONDecoder().decode(PermissionRequest.self, from: Data(json.utf8))

        #expect(request.commandPreview == nil)
    }
}
