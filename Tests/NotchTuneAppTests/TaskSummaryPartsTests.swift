import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

/// How a finished turn's summary reads on the completion card, in a done
/// session row and on the closed pill's finished peek.
// The height estimates measure text with AppKit, which must start up on the
// main thread: off it, the first measurement deadlocks the test run.
@MainActor
struct TaskSummaryPartsTests {
    private func texts(_ summary: TaskSummary?) -> [String]? {
        TaskSummaryParts(summary: summary)?.parts.map(\.text)
    }

    @Test
    func editsTestsAndTimeReadAsOneLine() throws {
        let parts = try #require(TaskSummaryParts(summary: TaskSummary(
            fileCount: 4,
            fileNames: ["AppModel.swift", "IslandPanelView.swift", "Strings.swift"],
            commandCount: 6,
            tests: .passed,
            duration: 192
        )))
        #expect(parts.parts.map(\.text) == ["Edited 4 files", "Tests passed", "3m 12s"])
        #expect(parts.compactText == "Edited 4 files · Tests passed · 3m 12s")
        #expect(parts.parts.first?.help == "AppModel.swift, IslandPanelView.swift, Strings.swift and 1 more")
        #expect(parts.parts[1].tone == .positive)
    }

    @Test
    func oneFileIsNamedAndFailuresStandOut() throws {
        let parts = try #require(TaskSummaryParts(summary: TaskSummary(
            fileCount: 1, fileNames: ["Bug.swift"], commandCount: 2, tests: .failed, duration: 42
        )))
        #expect(parts.parts.map(\.text) == ["Edited Bug.swift", "Tests failed", "42s"])
        #expect(parts.parts[1].tone == .negative)
    }

    @Test
    func commandsShowOnlyWhenNothingMoreTellingHappened() {
        #expect(texts(TaskSummary(commandCount: 1)) == ["Ran 1 command"])
        #expect(texts(TaskSummary(commandCount: 3, duration: 0.4)) == ["Ran 3 commands"])
        #expect(texts(TaskSummary(fileCount: 2, fileNames: ["a", "b"], commandCount: 3)) == ["Edited 2 files"])
        #expect(texts(TaskSummary(commandCount: 2, tests: .ran)) == ["Ran tests"])
    }

    @Test
    func aTurnThatOnlyTalkedShowsNothing() {
        #expect(TaskSummaryParts(summary: nil) == nil)
        #expect(TaskSummaryParts(summary: TaskSummary(duration: 30)) == nil)
    }

    @Test
    func durationsReadCompactly() {
        #expect(TaskSummaryParts.durationText(0.3) == nil)
        #expect(TaskSummaryParts.durationText(59) == "59s")
        #expect(TaskSummaryParts.durationText(180) == "3m")
        #expect(TaskSummaryParts.durationText(3_905) == "1h 5m")
        #expect(TaskSummaryParts.durationText(7_200) == "2h")
    }

    @Test
    func theFinishedPeekLeadsWithTheSummary() {
        var session = AgentSession(
            id: "done",
            title: "Claude · repo",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Done.",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            claudeMetadata: ClaudeSessionMetadata(lastAssistantMessage: "I fixed the off-by-one in the parser.")
        )
        let resolve = {
            IslandLiveActivity.resolve(
                mode: .events, sessions: [session], finishedPeekSessionID: "done",
                runningSince: [:], attentionSince: [:]
            )
        }
        #expect(resolve()?.subtitle == "I fixed the off-by-one in the parser.")

        session.taskSummary = TaskSummary(fileCount: 2, fileNames: ["a", "b"], tests: .passed, duration: 75)
        #expect(resolve()?.subtitle == "Edited 2 files · Tests passed · 1m 15s")
    }

    // MARK: Height estimates (the panel opens at its final size)

    private func finished(reply: String, summary: TaskSummary?) -> AgentSession {
        var session = AgentSession(
            id: "done",
            title: "Codex · repo",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: reply,
            updatedAt: Date(timeIntervalSince1970: 10_000)
        )
        session.taskSummary = summary
        return session
    }

    private let summary = TaskSummary(fileCount: 2, fileNames: ["a.swift", "b.swift"], tests: .passed, duration: 75)

    @Test
    func theToastEstimateMakesRoomForTheSummaryRow() {
        let bare = CompletionToastView.estimatedHeight(for: finished(reply: "Done, one line.", summary: nil), contentWidth: 560, hasPrompt: true)
        let withSummary = CompletionToastView.estimatedHeight(for: finished(reply: "Done, one line.", summary: summary), contentWidth: 560, hasPrompt: true)
        // TaskSummaryLine (14pt) + the card's 6pt row spacing.
        #expect(withSummary - bare == 20)

        // A long reply gives up its last line to the summary, as the view does.
        let long = String(repeating: "A long reply that wraps across many lines of the card. ", count: 12)
        let longBare = CompletionToastView.estimatedHeight(for: finished(reply: long, summary: nil), contentWidth: 560, hasPrompt: true)
        let longWithSummary = CompletionToastView.estimatedHeight(for: finished(reply: long, summary: summary), contentWidth: 560, hasPrompt: true)
        #expect(longWithSummary - longBare < 20)
        #expect(CompletionToastView.previewLineLimit(hasSummary: true) == NotificationSurfaceMetrics.previewLineLimit - 1)
    }

    @Test
    func aDoneRowEstimateCountsItsSummaryLine() {
        let date = Date(timeIntervalSince1970: 10_005)
        let bare = finished(reply: "Done.", summary: nil).estimatedIslandRowHeight(at: date)
        let withSummary = finished(reply: "Done.", summary: summary).estimatedIslandRowHeight(at: date)
        #expect(withSummary - bare == 18)
    }
}
