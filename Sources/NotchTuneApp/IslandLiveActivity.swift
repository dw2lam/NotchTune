import AppKit
import Foundation
import NotchTuneCore

/// When the closed pill widens into a "live activity" that carries text.
enum IslandLiveActivityMode: String, CaseIterable, Identifiable, Sendable {
    /// Never widen; the pill only shows the glyph and right slot.
    case off
    /// Widen only when an agent needs you, and briefly when one finishes.
    case events
    /// Also widen while an agent is working (task + elapsed timer).
    case active

    var id: String { rawValue }
}

/// What the widened closed pill shows. Pure value so the resolver and the wing
/// math are unit-testable without a view.
struct IslandLiveActivity: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case working
        case needsApproval
        case needsAnswer
        case finished
    }

    var kind: Kind
    var sessionID: String
    var tool: AgentTool
    /// First line: "Codex · open-island".
    var title: String
    /// Second line: what the agent is doing / needs / said.
    var subtitle: String?
    /// Start of the timer shown on the right wing (working / waiting).
    var since: Date?
    /// Other live sessions beyond this one ("+2").
    var otherCount: Int
    /// Album-art chip on the right wing (music playing while an agent works).
    var showsMusicChip: Bool = false

    /// Width the music chip adds to the right wing (art + gap).
    nonisolated static let musicChipWidth: CGFloat = 21

    /// Seconds a finished peek stays on the pill before it tucks back.
    nonisolated static let finishedPeekDuration: TimeInterval = 4

    // MARK: Resolve

    /// Picks what the pill should say. Priority: a session that needs you,
    /// then a fresh finish peek, then (in `.active` mode) the working session.
    static func resolve(
        mode: IslandLiveActivityMode,
        sessions: [AgentSession],
        finishedPeekSessionID: String?,
        runningSince: [String: Date],
        attentionSince: [String: Date]
    ) -> IslandLiveActivity? {
        guard mode != .off else { return nil }

        let waiting = sessions.first { $0.phase.requiresAttention }
        let finished = finishedPeekSessionID.flatMap { id in
            sessions.first { $0.id == id && $0.phase == .completed }
        }
        let working = mode == .active ? sessions.first { $0.phase == .running } : nil

        guard let session = waiting ?? finished ?? working else { return nil }

        let liveCount = sessions.filter { $0.phase == .running || $0.phase.requiresAttention }.count
        let others = max(0, liveCount - (session.phase == .completed ? 0 : 1))

        switch session.phase {
        case .waitingForApproval:
            return IslandLiveActivity(
                kind: .needsApproval,
                sessionID: session.id,
                tool: session.tool,
                title: "\(session.tool.displayName) needs approval",
                subtitle: firstNonEmpty(
                    session.currentCommandPreviewText.map { $0.hasPrefix("$ ") ? String($0.dropFirst(2)) : $0 },
                    session.permissionRequest?.affectedPath,
                    session.permissionRequest?.summary,
                    session.permissionRequest?.title
                ),
                since: attentionSince[session.id] ?? session.updatedAt,
                otherCount: others
            )
        case .waitingForAnswer:
            return IslandLiveActivity(
                kind: .needsAnswer,
                sessionID: session.id,
                tool: session.tool,
                title: "\(session.tool.displayName) has a question",
                subtitle: firstNonEmpty(session.questionPrompt?.title),
                since: attentionSince[session.id] ?? session.updatedAt,
                otherCount: others
            )
        case .completed:
            return IslandLiveActivity(
                kind: .finished,
                sessionID: session.id,
                tool: session.tool,
                title: "\(session.tool.displayName) finished",
                subtitle: firstNonEmpty(
                    session.completionAssistantMessageText.map(CompletionPreviewText.plain),
                    workspaceName(of: session)
                ),
                since: nil,
                otherCount: others
            )
        case .running:
            return IslandLiveActivity(
                kind: .working,
                sessionID: session.id,
                tool: session.tool,
                title: "\(session.tool.displayName) · \(workspaceName(of: session))",
                subtitle: firstNonEmpty(
                    session.currentToolName.map { activityPhrase(tool: $0, session: session) },
                    subagentsPhrase(session),
                    session.latestUserPromptText
                ),
                since: runningSince[session.id] ?? session.updatedAt,
                otherCount: others
            )
        }
    }

    private static func workspaceName(of session: AgentSession) -> String {
        let name = session.spotlightWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? session.tool.displayName : name
    }

    /// "Explore agent working" / "3 agents working" while Claude subagents run
    /// (e.g. background agents after the main turn ended).
    static func subagentsPhrase(_ session: AgentSession) -> String? {
        let active = session.claudeMetadata?.activeSubagents ?? []
        switch active.count {
        case 0: return nil
        case 1: return "\(active[0].agentType.map { "\($0) agent" } ?? "Subagent") working"
        default: return "\(active.count) agents working"
        }
    }

    /// "Editing AppModel.swift", "Running swift test", or the raw tool name.
    static func activityPhrase(tool: String, session: AgentSession) -> String {
        let preview = session.currentCommandPreviewText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        switch tool {
        case "Bash", "exec_command", "shell", "run_shell_command":
            if let preview, !preview.isEmpty {
                return "Running \(preview.hasPrefix("$ ") ? String(preview.dropFirst(2)) : preview)"
            }
            return "Running a command"
        case "Edit", "MultiEdit", "Write", "apply_patch", "write_file", "replace":
            if let file = preview.flatMap(lastPathComponent), !file.isEmpty {
                return "Editing \(file)"
            }
            return "Editing files"
        case "Read", "read_file", "View":
            if let file = preview.flatMap(lastPathComponent), !file.isEmpty {
                return "Reading \(file)"
            }
            return "Reading files"
        case "Grep", "Glob", "search", "grep_search", "glob":
            return "Searching the codebase"
        case "WebFetch", "WebSearch", "web_search", "google_web_search":
            return "Browsing the web"
        case "Task", "Agent", "spawn_agent":
            return "Running a subagent"
        case "image_gen", "image_generation", "generate_image":
            return "Generating an image"
        case "view_image":
            return "Looking at an image"
        case "tool_search":
            return "Searching"
        case "context_compaction":
            return "Compacting context"
        case "update_plan", "TodoWrite", "ExitPlanMode":
            return "Updating the plan"
        case "write_stdin":
            return "Typing into a command"
        default:
            return AgentSession.currentToolDisplayName(for: tool)
        }
    }

    private static func lastPathComponent(_ text: String) -> String? {
        let token = text
            .split(whereSeparator: { $0 == " " || $0 == "\"" || $0 == "'" })
            .first { $0.contains("/") || $0.contains(".") }
        guard let token else { return nil }
        return (String(token) as NSString).lastPathComponent
    }

    private static func firstNonEmpty(_ candidates: String?...) -> String? {
        for candidate in candidates {
            let trimmed = candidate?
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    // MARK: Layout

    /// Left wing (glyph + two-line text) — grows with the text, clamped.
    func leftWingWidth(metrics: IslandChromeMetrics, maxWingWidth: CGFloat) -> CGFloat {
        let titleWidth = Self.textWidth(title, font: metrics.notificationTitleNSFont.withWeight(.semibold))
        let subtitleWidth = subtitle.map { Self.textWidth($0, font: metrics.notificationArtistNSFont) } ?? 0
        let text = min(Self.maxTextWidth, max(titleWidth, subtitleWidth))
        let needed = ceil(
            metrics.notchedClosedHorizontalPadding
                + metrics.closedGlyphSize
                + metrics.notchedClosedContentGap
                + text
                + metrics.notchedClosedContentGap
        )
        return clampWing(needed, metrics: metrics, maxWingWidth: maxWingWidth)
    }

    /// Right wing (timer / check / +N) — only as wide as its content.
    func rightWingWidth(metrics: IslandChromeMetrics, maxWingWidth: CGFloat) -> CGFloat {
        let needed = ceil(metrics.notchedClosedContentGap + trailingWidth + metrics.notchedClosedHorizontalPadding)
        return clampWing(needed, metrics: metrics, maxWingWidth: maxWingWidth)
    }

    /// The wider of the two wings (used where one number is enough).
    func wingWidth(metrics: IslandChromeMetrics, maxWingWidth: CGFloat) -> CGFloat {
        max(
            leftWingWidth(metrics: metrics, maxWingWidth: maxWingWidth),
            rightWingWidth(metrics: metrics, maxWingWidth: maxWingWidth)
        )
    }

    private func clampWing(_ needed: CGFloat, metrics: IslandChromeMetrics, maxWingWidth: CGFloat) -> CGFloat {
        let floor = metrics.notchedClosedMinimumWingReserve
        let cap = max(floor, min(Self.maxWingWidth, maxWingWidth))
        return min(max(needed, floor), cap)
    }

    /// Widest the two-line text block may get before it truncates. Keeps the
    /// widened pill "a bit wider", not panel-wide.
    nonisolated static let maxTextWidth: CGFloat = 150

    /// Hard cap on one MacBook wing, whatever the text.
    nonisolated static let maxWingWidth: CGFloat = 196

    /// Widest the single-line external pill may get.
    nonisolated static let maxExternalWidth: CGFloat = 420

    /// Outer width of the single-line external (menu-bar) pill.
    func externalPillWidth(metrics: IslandChromeMetrics, height: CGFloat, minWidth: CGFloat) -> CGFloat {
        let titleW = Self.textWidth(title, font: metrics.notificationTitleNSFont)
        let subtitleW = subtitle.map { Self.textWidth("  " + $0, font: metrics.notificationArtistNSFont) } ?? 0
        let textW = min(Self.maxTextWidth * 1.8, titleW + subtitleW)
        let intrinsic = height + metrics.closedGlyphSize + 8 + textW + 6 + trailingWidth
        return min(max(minWidth, ceil(intrinsic)), Self.maxExternalWidth)
    }

    /// Room reserved on the right wing for the timer / status mark.
    var trailingWidth: CGFloat {
        let chip = showsMusicChip ? Self.musicChipWidth : 0
        switch kind {
        case .working, .needsApproval, .needsAnswer:
            return (otherCount > 0 ? 64 : 40) + chip
        case .finished:
            return (otherCount > 0 ? 44 : 20) + chip
        }
    }

    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// "0:42", "12:05", "1:03:10".
    static func elapsedText(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

private extension NSFont {
    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: weight],
        ])
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
