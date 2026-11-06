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
        /// Opens System Settings → Notifications.
        case openNotificationSettings
        /// Starts the local bridge again.
        case retryBridge
    }

    /// The anchors of `x-apple.systempreferences:com.apple.preference.security`.
    enum PrivacyPane: String, Sendable {
        case accessibility = "Privacy_Accessibility"
        case automation = "Privacy_Automation"
        case calendars = "Privacy_Calendars"
        case camera = "Privacy_Camera"

        var settingsURL: URL? {
            URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")
        }
    }

    /// How long a notice stays on screen. One with an action outlives this:
    /// its toast still folds away, but the banner waits in the open panel
    /// until the user acts on it or dismisses it.
    static let displayDuration: TimeInterval = 8

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

    /// A notice with nothing to do about it goes away once it has been seen.
    var clearsOnceSeen: Bool {
        action == nil
    }
}

/// How a notice reaches the user, given what the notch is doing.
enum AppNoticeDelivery: Equatable, Sendable {
    /// Not now: it follows when the notch is free (see `resolve`).
    case wait
    /// The panel is open, so the banner in it is enough.
    case banner
    /// The notch is closed: open it passively, as a toast of just the notice.
    case toast

    static func resolve(
        status: NotchStatus,
        openReason: NotchOpenReason?,
        surface: IslandSurface,
        isClosing: Bool,
        isFullscreen: Bool
    ) -> AppNoticeDelivery {
        // Hidden for a full-screen app there is nothing to show it on, and
        // opening under a close would pull the morph back open halfway.
        if isFullscreen || isClosing { return .wait }
        guard status == .opened else { return .toast }
        // An agent's card and a file drag keep the notch to themselves.
        if openReason == .drag { return .wait }
        if openReason == .notification, surface.sessionID != nil { return .wait }
        return .banner
    }
}
