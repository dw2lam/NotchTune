import Foundation
import NotchTuneCore

enum IslandSurface: Equatable {
    case sessionList(actionableSessionID: String? = nil)
    /// `AppModel.notice` on its own: a toast that opened the closed notch.
    case notice

    var sessionID: String? {
        switch self {
        case let .sessionList(actionableSessionID):
            actionableSessionID
        case .notice:
            nil
        }
    }

    var isNotificationCard: Bool {
        sessionID != nil || self == .notice
    }

    func autoDismissesWhenPresentedAsNotification(session: AgentSession?) -> Bool {
        if self == .notice { return true }
        guard sessionID != nil else { return false }
        return session?.phase == .completed
    }

    static func notificationSurface(for event: AgentEvent) -> IslandSurface? {
        switch event {
        case let .permissionRequested(payload):
            .sessionList(actionableSessionID: payload.sessionID)
        case let .questionAsked(payload):
            .sessionList(actionableSessionID: payload.sessionID)
        case let .sessionCompleted(payload):
            payload.isInterrupt == true ? nil : .sessionList(actionableSessionID: payload.sessionID)
        default:
            nil
        }
    }

    func matchesCurrentState(of session: AgentSession?) -> Bool {
        guard sessionID != nil else {
            return true
        }

        guard let session else {
            return false
        }

        switch session.phase {
        case .waitingForApproval:
            return session.permissionRequest != nil
        case .waitingForAnswer:
            return session.questionPrompt != nil
        case .completed:
            return true
        case .running:
            return false
        }
    }
}
