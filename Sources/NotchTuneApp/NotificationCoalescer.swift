import Foundation
import NotchTuneCore

// MARK: - Policy (tunables in one place so they can become settings later)

/// Windows that shape how agent notification "bumps" (notch open + sound)
/// are coalesced. Kept together so a future settings pane can expose them.
struct NotificationCoalescingPolicy: Equatable, Sendable {
    /// Trailing debounce for completions. A completion is held this long;
    /// if the session (or any sibling in its group) goes back to running
    /// before the window elapses, the pending bump is cancelled.
    var completionSettleSeconds: TimeInterval = 1.5

    /// After a full bump for a group, further completions in that group
    /// within this window are downgraded to `.subtle`.
    var groupCooldownSeconds: TimeInterval = 20

    /// At most one full completion bump across all groups per this interval;
    /// excess completions become `.subtle`.
    var globalMinimumIntervalSeconds: TimeInterval = 3

    static let `default` = NotificationCoalescingPolicy()
}

// MARK: - Decision

/// What the presentation layer should do with a bump-worthy event.
enum NotificationBumpDecision: Equatable, Sendable {
    /// Full bump: open the notification surface and play the sound.
    case present
    /// Flash only (`completionFlashSessionID`); no open, no sound.
    case subtle
    /// Nothing visible.
    case suppress
}

// MARK: - Grouping

/// Sessions coalesce by (agent tool, workspace). Sibling Codex threads in the
/// same cwd share a group so one logical task yields one bump.
struct NotificationGroupKey: Hashable, Sendable {
    var tool: AgentTool
    var workspace: String

    init(tool: AgentTool, workspace: String) {
        self.tool = tool
        self.workspace = workspace
    }

    init(session: AgentSession) {
        self.init(
            tool: session.tool,
            workspace: Self.workspaceIdentity(for: session)
        )
    }

    private static func workspaceIdentity(for session: AgentSession) -> String {
        if let cwd = session.jumpTarget?.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cwd.isEmpty {
            let standardized = URL(fileURLWithPath: cwd).standardizedFileURL.path
            return standardized.count > 1 && standardized.hasSuffix("/")
                ? String(standardized.dropLast())
                : standardized
        }
        if let name = session.jumpTarget?.workspaceName.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "workspace:\(name)"
        }
        // No workspace known: the session is its own group.
        return "session:\(session.id)"
    }
}

// MARK: - Coalescer

/// Pure decision logic for agent notification bumps. `AppModel` owns one,
/// feeds it events with explicit timestamps, and arms the settle timers it
/// asks for; the coalescer never touches timers or UI itself, which keeps it
/// unit-testable with a fake clock.
///
/// Rules:
/// - Completions are held for `completionSettleSeconds` (trailing debounce).
///   Holding a newer completion in the same group supersedes the older one.
///   Any running/attention signal in the group cancels the hold.
/// - After a full bump for a group, completions in that group within
///   `groupCooldownSeconds` are `.subtle`.
/// - Completions are additionally rate-limited to one full bump per
///   `globalMinimumIntervalSeconds` across all groups; excess is `.subtle`.
/// - A first pending approval/question for a session always `.present`s
///   (never downgraded); a repeat of the same pending request is `.suppress`.
/// - A session already on screen as the current notification card is
///   `.suppress`ed so it does not re-open or replay the sound.
struct NotificationCoalescer: Sendable {
    struct PendingCompletion: Equatable, Sendable {
        var payload: SessionCompleted
        var deadline: Date
    }

    var policy: NotificationCoalescingPolicy

    private(set) var pendingCompletions: [NotificationGroupKey: PendingCompletion] = [:]
    private var lastPresentedByGroup: [NotificationGroupKey: Date] = [:]
    private var lastPresentedAt: Date?

    init(policy: NotificationCoalescingPolicy = .default) {
        self.policy = policy
    }

    // MARK: Completions

    /// Hold a completion for its group. Returns the deadline the caller
    /// should arm a settle timer for. A newer completion in the same group
    /// supersedes any pending one (trailing debounce).
    @discardableResult
    mutating func holdCompletion(
        _ payload: SessionCompleted,
        group: NotificationGroupKey,
        now: Date
    ) -> Date {
        let deadline = now.addingTimeInterval(policy.completionSettleSeconds)
        pendingCompletions[group] = PendingCompletion(payload: payload, deadline: deadline)
        return deadline
    }

    /// A session in `group` is active again (running or waiting on the
    /// user): whatever completion was pending was not really the end of the
    /// task. Returns the cancelled payload, if any, so the caller can tear
    /// down its timer.
    @discardableResult
    mutating func cancelPendingCompletion(in group: NotificationGroupKey) -> SessionCompleted? {
        pendingCompletions.removeValue(forKey: group)?.payload
    }

    func pendingCompletion(in group: NotificationGroupKey) -> PendingCompletion? {
        pendingCompletions[group]
    }

    /// The settle timer for `group` fired. Pops the pending completion and
    /// decides how to surface it. Returns `nil` when nothing is pending (it
    /// was cancelled by a running signal). A `.present` decision records the
    /// bump for cooldown / rate-limit purposes.
    mutating func settleCompletion(
        in group: NotificationGroupKey,
        isAlreadyPresented: Bool,
        now: Date
    ) -> (payload: SessionCompleted, decision: NotificationBumpDecision)? {
        guard let pending = pendingCompletions.removeValue(forKey: group) else {
            return nil
        }

        if isAlreadyPresented {
            return (pending.payload, .suppress)
        }

        if isWithinGroupCooldown(group, now: now) || isWithinGlobalRateLimit(now: now) {
            return (pending.payload, .subtle)
        }

        recordPresentation(group: group, now: now)
        return (pending.payload, .present)
    }

    // MARK: Approvals / questions

    /// Decide an approval or question request.
    /// - `isRepeatOfPendingRequest`: the session was already waiting in the
    ///   same phase before this event (e.g. the Codex app-server re-emitting
    ///   `waitingOnApproval` on every status change).
    /// - `isAlreadyPresented`: the session is the current notification card.
    /// A first request is never downgraded; a `.present` decision records
    /// the bump for cooldown / rate-limit purposes.
    mutating func decideRequest(
        group: NotificationGroupKey,
        isRepeatOfPendingRequest: Bool,
        isAlreadyPresented: Bool,
        now: Date
    ) -> NotificationBumpDecision {
        if isRepeatOfPendingRequest || isAlreadyPresented {
            return .suppress
        }

        recordPresentation(group: group, now: now)
        return .present
    }

    // MARK: Focus-aware downgrade

    /// What a bump that would `.present` becomes when the session's own
    /// terminal / IDE is already frontmost (and the user has
    /// `suppressFrontmostNotifications` on). A completion bounces the pill
    /// (`.subtle`: pop + flash) instead of opening the toast — the user is
    /// looking at the result already. Approvals and questions keep the
    /// setting's contract and stay out of the way (`.suppress`): the agent's
    /// own prompt is on screen in front of them.
    static func decisionForFrontmostSession(isCompletion: Bool) -> NotificationBumpDecision {
        isCompletion ? .subtle : .suppress
    }

    // MARK: Bookkeeping

    private func isWithinGroupCooldown(_ group: NotificationGroupKey, now: Date) -> Bool {
        guard let last = lastPresentedByGroup[group] else { return false }
        return now.timeIntervalSince(last) < policy.groupCooldownSeconds
    }

    private func isWithinGlobalRateLimit(now: Date) -> Bool {
        guard let last = lastPresentedAt else { return false }
        return now.timeIntervalSince(last) < policy.globalMinimumIntervalSeconds
    }

    private mutating func recordPresentation(group: NotificationGroupKey, now: Date) {
        lastPresentedByGroup[group] = now
        lastPresentedAt = now
    }

    /// Drop everything (used when the policy changes).
    mutating func reset() {
        pendingCompletions.removeAll()
        lastPresentedByGroup.removeAll()
        lastPresentedAt = nil
    }
}
