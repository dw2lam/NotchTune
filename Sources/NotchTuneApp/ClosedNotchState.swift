import Foundation

/// What the closed notch shows. This is the one place that decides it:
/// the closed surface's size, position and the shape a close morphs to all
/// follow from this, so a new closed state is added here first.
///
/// The closed notch is one of these while the open panel is a separate
/// thing with its own content; `OverlayUICoordinator.presentedSurface` says
/// what that panel shows, including during a close.
enum ClosedNotchState: Equatable, Sendable {
    /// A track change, shown for a few seconds. Outranks everything.
    case musicNotification
    /// The music pill: agents idle, with music playing or just paused.
    case compactMusic
    /// Nothing to show: tucked behind the hardware notch.
    case hidden
    /// The widened pill: an agent working or waiting, with its activity.
    case liveActivity
    /// The standard pill: character and right slot.
    case pill

    static func resolve(
        showsMusicNotification: Bool,
        showsCompactMusic: Bool,
        collapsesBehindNotch: Bool,
        hasLiveActivity: Bool
    ) -> ClosedNotchState {
        if showsMusicNotification { return .musicNotification }
        if showsCompactMusic { return .compactMusic }
        if collapsesBehindNotch { return .hidden }
        return hasLiveActivity ? .liveActivity : .pill
    }

    var showsMusicSurface: Bool {
        self == .musicNotification || self == .compactMusic
    }

    /// A close lands straight on the surface at its own size, in one motion.
    /// Only with nothing to show does it tuck into the hardware notch.
    var closesIntoHardwareNotch: Bool {
        self == .hidden
    }
}
