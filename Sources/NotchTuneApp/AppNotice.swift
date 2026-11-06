import Foundation

/// A failure or a blocked permission the user needs to hear about.
/// `lastActionMessage` is a log line for the harness; a notice is what
/// reaches the screen, so anything that fails after the user asked for it
/// posts one (`AppModel.post`).
struct AppNotice: Equatable, Identifiable, Sendable {
    enum Action: Equatable, Sendable {
        /// Opens that pane of System Settings → Privacy & Security.
        case openPrivacyPane(PrivacyPane)
        /// Opens NotchTune's Settings on the Setup tab.
        case openSetup
    }

    /// The anchors of `x-apple.systempreferences:com.apple.preference.security`.
    enum PrivacyPane: String, Sendable {
        case accessibility = "Privacy_Accessibility"
        case automation = "Privacy_Automation"
        case calendars = "Privacy_Calendars"
        case camera = "Privacy_Camera"
    }

    let id: UUID
    /// One plain sentence: what went wrong, for this user, right now.
    var message: String
    var actionTitle: String?
    var action: Action?

    init(message: String, actionTitle: String? = nil, action: Action? = nil) {
        id = UUID()
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    /// The same message posted again shouldn't restart the banner.
    func isSameProblem(as other: AppNotice) -> Bool {
        message == other.message && action == other.action
    }
}
