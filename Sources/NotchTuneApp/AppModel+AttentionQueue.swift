import Foundation
import NotchTuneCore

/// Where a card sits among the sessions waiting on the user.
struct AttentionQueuePosition: Equatable {
    let index: Int
    let count: Int
}

/// Several agents can be blocked on the user at once, but the notch shows one
/// card. The rest wait here, in `SessionState`, longest wait first: nothing
/// replaces a card an agent is blocked on, and when a card goes the next
/// session takes its place.
extension AppModel {
    /// A click this soon after a card appeared was aimed at what was there
    /// before: cards swap in place, under the pointer.
    static let cardClickArmDelay: TimeInterval = 0.4

    /// Sessions blocked on a request answerable here, longest wait first. The
    /// tour's demo session runs its own script.
    var attentionQueue: [AgentSession] {
        state.sessions
            .filter { $0.hasPendingRequest && !$0.isDemoSession }
            .sorted { lhs, rhs in
                let (lhsStart, rhsStart) = (waitStart(of: lhs), waitStart(of: rhs))
                return lhsStart == rhsStart ? lhs.id < rhs.id : lhsStart < rhsStart
            }
    }

    private func waitStart(of session: AgentSession) -> Date {
        attentionStartedAt[session.id] ?? session.updatedAt
    }

    /// "1 of N" for the card on screen; nil when it's the only one.
    var attentionQueuePosition: AttentionQueuePosition? {
        let queue = attentionQueue
        guard queue.count > 1,
              let index = queue.firstIndex(where: { $0.id == overlay.presentedSurface.sessionID }) else {
            return nil
        }
        return AttentionQueuePosition(index: index, count: queue.count)
    }

    /// Who gets the next card: the longest wait the user hasn't already
    /// stepped past. A skipped request stays in the session list.
    var nextQueuedAttentionSessionID: String? {
        let onScreen = islandSurface.sessionID
        return attentionQueue.first { session in
            session.id != onScreen
                && session.pendingRequestID.map { !skippedAttentionRequestIDs.contains($0) } == true
        }?.id
    }

    /// The card went away unanswered. Don't bring it straight back, or Esc
    /// would only ever cycle through the same two cards.
    func skipAttentionRequest(of sessionID: String) {
        guard let session = state.session(id: sessionID),
              session.hasPendingRequest,
              let requestID = session.pendingRequestID else {
            return
        }
        let live = Set(attentionQueue.compactMap(\.pendingRequestID))
        skippedAttentionRequestIDs.formIntersection(live)
        skippedAttentionRequestIDs.insert(requestID)
    }

    /// The notch is free: a request that never got its card gets it now.
    func presentQueuedAttentionCardIfNeeded() {
        guard let sessionID = nextQueuedAttentionSessionID else { return }
        scheduleNotificationSurfacePresentationIfNeeded(
            .sessionList(actionableSessionID: sessionID),
            ingress: .bridge
        )
    }

    /// A card's buttons, bound to the request the card was drawn for.
    func approveFromCard(_ shown: AgentSession, action: ApprovalAction) {
        guard notificationCardAge() >= Self.cardClickArmDelay else { return }
        approvePermission(for: shown.id, requestID: shown.permissionRequest?.id, action: action)
    }

    func answerFromCard(_ shown: AgentSession, answer: QuestionPromptResponse) {
        guard notificationCardAge() >= Self.cardClickArmDelay else { return }
        answerQuestion(for: shown.id, requestID: shown.questionPrompt?.id, answer: answer)
    }
}

extension AgentSession {
    var pendingRequestID: UUID? {
        permissionRequest?.id ?? questionPrompt?.id
    }

    /// Whether `event` asks for what this session is already waiting on:
    /// some sources repeat a request (a Codex status change), each time as a
    /// fresh value. A different request is news even in the same phase.
    func isAlreadyWaiting(on event: AgentEvent) -> Bool {
        switch event {
        case let .permissionRequested(payload):
            permissionRequest?.asksTheSame(as: payload.request) == true
        case let .questionAsked(payload):
            questionPrompt?.title == payload.prompt.title
        default:
            false
        }
    }
}

private extension PermissionRequest {
    func asksTheSame(as other: PermissionRequest) -> Bool {
        title == other.title
            && summary == other.summary
            && affectedPath == other.affectedPath
            && toolName == other.toolName
            && toolUseID == other.toolUseID
            && commandPreview == other.commandPreview
    }
}
