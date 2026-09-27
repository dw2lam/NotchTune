import Foundation
import NotchTuneCore

/// Keyboard control of the auto-expanded notification cards (approval,
/// question, completion toast). `OverlayPanelController` turns key events
/// into `NotificationCardKeyCommand`s; this routes them through the same
/// model methods the card buttons call.
extension AppModel {
    /// The card the keyboard acts on, or `nil` when no notification card is
    /// on screen (browsing the session list, closed pill, music tab…).
    var keyboardNotificationCard: (session: AgentSession, kind: NotificationCardKind)? {
        guard notchStatus == .opened,
              notchOpenReason == .notification,
              islandActiveTab == .agents,
              let session = activeIslandCardSession,
              let kind = NotificationCardKind(
                  session: session,
                  replyAvailable: TerminalTextSender.canReply(to: session, enabled: completionReplyEnabled)
              ) else {
            return nil
        }
        return (session, kind)
    }

    /// Seconds the current notification card has been on screen.
    func notificationCardAge(now: Date = .now) -> TimeInterval {
        guard let shownAt = notificationCardShownAt else { return .infinity }
        return now.timeIntervalSince(shownAt)
    }

    /// Performs `command` on the card on screen. Returns `false` when the
    /// command does not apply (no card, or the card changed underneath), so
    /// the caller can let the key through.
    @discardableResult
    func performNotificationCardKeyCommand(_ command: NotificationCardKeyCommand) -> Bool {
        guard let (session, kind) = keyboardNotificationCard else {
            return false
        }

        switch (command, kind) {
        case (.dismiss, _):
            overlay.dismissNotificationCard()

        case (.allowOnce, .approval):
            approvePermission(for: session.id, action: .allowOnce)
        case (.deny, .approval):
            approvePermission(for: session.id, action: .deny)
        case (.alwaysAllow, .approval(supportsAlwaysAllow: true)):
            guard let toolName = session.permissionRequest?.toolName else { return false }
            approvePermission(for: session.id, action: .alwaysAllow(toolName: toolName))

        case (.pickOption, .question), (.submit, .question):
            // Selections live in the question view; it applies the pick (or
            // submits only when its Submit button is enabled).
            NotificationCardKeyCommandBus.post(command, sessionID: session.id)

        case (.jump, .completion):
            jumpToSession(session)
        case (.openReply, .completion(hasReply: true)):
            NotificationCardKeyCommandBus.post(command, sessionID: session.id)
        case (.previous, .completion):
            rotateCompletionToast(forward: false)
        case (.next, .completion):
            rotateCompletionToast(forward: true)

        default:
            return false
        }
        return true
    }
}
