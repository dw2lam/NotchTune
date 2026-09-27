import Foundation
import SwiftUI
import Testing
@testable import NotchTuneApp
import NotchTuneCore

struct IslandLiveActivityTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func session(
        _ id: String,
        phase: SessionPhase,
        tool: AgentTool = .codex,
        currentTool: String? = nil,
        command: String? = nil,
        reply: String? = nil
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(id)",
            tool: tool,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: phase.displayName,
            updatedAt: now.addingTimeInterval(-30),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: id,
                paneTitle: "codex ~/\(id)",
                workingDirectory: "/tmp/\(id)",
                terminalSessionID: "ghostty-\(id)"
            ),
            codexMetadata: CodexSessionMetadata(
                lastAssistantMessage: reply,
                currentTool: currentTool,
                currentCommandPreview: command
            )
        )
    }

    @Test
    func offModeNeverWidens() {
        let result = IslandLiveActivity.resolve(
            mode: .off,
            sessions: [session("a", phase: .waitingForApproval)],
            finishedPeekSessionID: nil,
            runningSince: [:],
            attentionSince: [:]
        )
        #expect(result == nil)
    }

    @Test
    func eventsModeIgnoresWorkingSessions() {
        let result = IslandLiveActivity.resolve(
            mode: .events,
            sessions: [session("a", phase: .running)],
            finishedPeekSessionID: nil,
            runningSince: [:],
            attentionSince: [:]
        )
        #expect(result == nil)
    }

    @Test
    func activeModeShowsTheWorkingSessionWithItsTimer() {
        let start = now.addingTimeInterval(-125)
        let result = IslandLiveActivity.resolve(
            mode: .active,
            sessions: [session("notch", phase: .running, currentTool: "apply_patch", command: "Sources/App/AppModel.swift")],
            finishedPeekSessionID: nil,
            runningSince: ["notch": start],
            attentionSince: [:]
        )
        #expect(result?.kind == .working)
        #expect(result?.title == "Codex · notch")
        #expect(result?.subtitle == "Editing AppModel.swift")
        #expect(result?.since == start)
        #expect(IslandLiveActivity.elapsedText(since: start, now: now) == "2:05")
    }

    @Test
    func waitingBeatsFinishedBeatsWorking() {
        let sessions = [
            session("run", phase: .running),
            session("done", phase: .completed, reply: "**All** tests pass"),
            session("ask", phase: .waitingForAnswer),
        ]
        let waiting = IslandLiveActivity.resolve(
            mode: .active, sessions: sessions, finishedPeekSessionID: "done",
            runningSince: [:], attentionSince: [:]
        )
        #expect(waiting?.kind == .needsAnswer)
        #expect(waiting?.otherCount == 1)

        let finished = IslandLiveActivity.resolve(
            mode: .active, sessions: Array(sessions.prefix(2)), finishedPeekSessionID: "done",
            runningSince: [:], attentionSince: [:]
        )
        #expect(finished?.kind == .finished)
        #expect(finished?.subtitle == "All tests pass")
        #expect(finished?.otherCount == 1)
    }

    @Test
    func finishedPeekRequiresTheSessionToStillBeCompleted() {
        let result = IslandLiveActivity.resolve(
            mode: .events,
            sessions: [session("a", phase: .running)],
            finishedPeekSessionID: "a",
            runningSince: [:],
            attentionSince: [:]
        )
        #expect(result == nil)
    }

    @Test
    func activityPhrasesReadNaturally() {
        let bash = session("x", phase: .running, command: "$ swift test --filter Foo")
        #expect(IslandLiveActivity.activityPhrase(tool: "exec_command", session: bash) == "Running swift test --filter Foo")
        #expect(IslandLiveActivity.activityPhrase(tool: "image_generation", session: bash) == "Generating an image")
        #expect(IslandLiveActivity.activityPhrase(tool: "Grep", session: bash) == "Searching the codebase")
    }

    @Test
    func wingWidthGrowsWithTextButStaysClamped() {
        let metrics = IslandChromeMetrics.regular
        var activity = IslandLiveActivity(
            kind: .working, sessionID: "a", tool: .codex,
            title: "Codex · a", subtitle: nil, since: now, otherCount: 0
        )
        let short = activity.wingWidth(metrics: metrics, maxWingWidth: 400)
        activity.subtitle = "Running a very long command that keeps going and going and going"
        let long = activity.wingWidth(metrics: metrics, maxWingWidth: 400)
        let clamped = activity.wingWidth(metrics: metrics, maxWingWidth: 120)

        #expect(short >= metrics.notchedClosedMinimumWingReserve)
        #expect(long > short)
        #expect(long <= IslandLiveActivity.maxWingWidth)
        #expect(clamped == 120)
    }
}

@MainActor
@Suite(.serialized)
struct IslandLiveActivityModelTests {
    init() {
        ["appearance.island.v8.notch.liveActivity", "appearance.island.v8.topBar.liveActivity"]
            .forEach(UserDefaults.standard.removeObject(forKey:))
    }

    @Test
    func colorByAgentTintsTheCharacterWithTheSessionsBrandColor() {
        let keys = ["appearance.island.v8.notch.colorByAgent", "appearance.island.v8.topBar.colorByAgent"]
        keys.forEach(UserDefaults.standard.removeObject(forKey:))
        defer { keys.forEach(UserDefaults.standard.removeObject(forKey:)) }

        let model = AppModel()
        var session = AgentSession(
            id: "s", title: "Codex · s", tool: .codex, origin: .live,
            attachmentState: .attached, phase: .running, summary: "Running", updatedAt: .now
        )
        session.isProcessAlive = true
        model.state = SessionState(sessions: [session])
        #expect(model.islandClosedGlyphTint == nil)

        for profile in IslandAppearanceDisplayProfile.allCases {
            model.updateAppearancePreferences(for: profile) { $0.colorByAgent = true }
        }
        #expect(model.islandClosedGlyphTint == Color(hex: AgentTool.codex.brandColorHex))
        #expect(AppModel().appearancePreferences(for: .notch).colorByAgent)
    }

    @Test
    func liveActivityModeDefaultsToActiveAndPersistsPerProfile() {
        let model = AppModel()
        #expect(model.appearancePreferences(for: .notch).liveActivity == .active)

        model.updateAppearancePreferences(for: .notch) { $0.liveActivity = .events }
        #expect(AppModel().appearancePreferences(for: .notch).liveActivity == .events)
        #expect(AppModel().appearancePreferences(for: .topBar).liveActivity == .active)
    }

    @Test
    func runningTimerRestartsOnlyWhenATurnStarts() {
        let model = AppModel()
        let t0 = Date(timeIntervalSince1970: 1_000)
        var session = AgentSession(
            id: "s", title: "Codex · s", tool: .codex, origin: .live,
            attachmentState: .attached, phase: .running, summary: "Running", updatedAt: t0
        )
        model.state = SessionState(sessions: [session])

        model.noteRunningTransition(sessionID: "s", from: .completed, at: t0)
        #expect(model.runningSince["s"] == t0)

        // Still running: a later tool event must not reset the turn timer.
        model.noteRunningTransition(sessionID: "s", from: .running, at: t0.addingTimeInterval(30))
        #expect(model.runningSince["s"] == t0)

        session.phase = .completed
        model.state = SessionState(sessions: [session])
        model.noteRunningTransition(sessionID: "s", from: .running, at: t0.addingTimeInterval(60))
        #expect(model.runningSince["s"] == nil)
    }

    @Test
    func finishedPeekIsSkippedWhenLiveActivityIsOff() {
        let model = AppModel()
        model.islandLiveActivityMode = .off
        model.beginFinishedPeek(for: "s")
        #expect(model.finishedPeekSessionID == nil)
        model.islandLiveActivityMode = .active
        model.beginFinishedPeek(for: "s")
        #expect(model.finishedPeekSessionID == "s")
    }
}
