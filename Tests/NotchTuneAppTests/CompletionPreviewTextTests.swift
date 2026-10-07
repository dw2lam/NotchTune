import Testing
@testable import NotchTuneApp
import NotchTuneCore

struct CompletionPreviewTextTests {
    @Test
    func stripsHeadingsListsAndEmphasis() {
        let markdown = """
        ## Summary

        - **Fixed** the `media strip` layout
        - Added *tests*

        1. First
        2. Second
        """
        #expect(
            CompletionPreviewText.plain(markdown)
                == "Summary Fixed the media strip layout Added tests First Second"
        )
    }

    @Test
    func keepsCodeContentButDropsFencesAndLinks() {
        let markdown = """
        Run this:

        ```bash
        swift build
        ```

        See [the docs](https://example.com) and ![diagram](x.png).
        """
        #expect(
            CompletionPreviewText.plain(markdown)
                == "Run this: swift build See the docs and diagram."
        )
    }

    @Test
    func flattensTablesAndQuotes() {
        let markdown = """
        > note
        | a | b |
        |---|---|
        | 1 | 2 |
        """
        #expect(CompletionPreviewText.plain(markdown) == "note a · b 1 · 2")
    }

    @Test
    func leavesSnakeCaseAndMathAlone() {
        #expect(CompletionPreviewText.plain("set max_width to 2 * 3") == "set max_width to 2 * 3")
    }

    @Test
    func emptyInputStaysEmpty() {
        #expect(CompletionPreviewText.plain("  \n\n ") == "")
    }
}

struct NotificationSurfaceMetricsTests {
    @Test
    func completionBudgetIsOneFifthOfTheScreenIncludingTheNotch() {
        // 982pt MacBook Pro display, 32pt notch strip.
        let budget = NotificationSurfaceMetrics.maxContentHeight(
            screenHeight: 982,
            notchHeight: 32,
            phase: .completed
        )
        #expect(budget == 164, "budget was \(budget)")
    }

    @Test
    func interactiveCardsGetALargerBudget() {
        let completion = NotificationSurfaceMetrics.maxContentHeight(screenHeight: 1000, notchHeight: 24, phase: .completed)
        let approval = NotificationSurfaceMetrics.maxContentHeight(screenHeight: 1000, notchHeight: 24, phase: .waitingForApproval)
        let question = NotificationSurfaceMetrics.maxContentHeight(screenHeight: 1000, notchHeight: 24, phase: .waitingForAnswer)
        #expect(completion == 176)
        #expect(approval == 396)
        #expect(question == 396)
    }

    @Test
    func budgetNeverCollapsesBelowAUsableFloor() {
        #expect(NotificationSurfaceMetrics.maxContentHeight(screenHeight: 300, notchHeight: 40, phase: .completed) == 72)
    }
}

struct CompletionPreviewTextBoundTests {
    /// A multi-kilobyte reply, as agents routinely send.
    private static let longReply: String = (1...400)
        .map { "- **Step \($0)**: updated `File\($0).swift` and [the docs](https://example.com/\($0))" }
        .joined(separator: "\n")

    @Test
    func flattensOnlyTheHeadOfALongReply() {
        // Previews show a line or three, yet this runs from view bodies (the
        // finished live-activity subtitle resolves it many times per render),
        // so the work must not grow with the reply.
        let preview = CompletionPreviewText.plain(Self.longReply)
        #expect(preview.count <= 2_000)
        #expect(preview.hasPrefix("Step 1: updated File1.swift and the docs Step 2:"))
    }

    @Test
    func cutsALongReplyOnALineBoundary() {
        let preview = CompletionPreviewText.plain(Self.longReply)
        // The last step kept is whole: no half-stripped link or code span.
        #expect(preview.hasSuffix("and the docs"))
        #expect(!preview.contains("]("))
        #expect(!preview.contains("`"))
    }
}
