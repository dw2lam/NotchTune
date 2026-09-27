import AppKit
import Testing
@testable import NotchTuneApp

@MainActor
struct MyspaceClipboardTests {
    private func scratchPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("notchtune.test.\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    @Test
    func copiesReminderTextVerbatim() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }

        let text = "Call the dentist\n  re: Tuesday 3pm"
        #expect(MyspaceClipboard.copy(text, to: pasteboard))
        #expect(pasteboard.string(forType: .string) == text)
    }

    @Test
    func blankTextLeavesTheClipboardAlone() {
        let pasteboard = scratchPasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("keep me", forType: .string)

        #expect(!MyspaceClipboard.copy("  \n ", to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "keep me")
    }
}
