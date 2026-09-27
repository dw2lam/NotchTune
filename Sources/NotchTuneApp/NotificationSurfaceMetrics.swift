import CoreGraphics
import Foundation
import NotchTuneCore

/// Geometry + timing budget for the auto-expanded notification surfaces
/// (completion toast, approval card, question card).
///
/// The completion toast is deliberately small: a finished agent should read as
/// a passing notification hanging off the notch, never a full transcript that
/// takes over the screen. Interactive cards (approval / question) get a larger
/// budget because they carry controls, but they still never exceed roughly
/// two fifths of the display and scroll internally past that.
enum NotificationSurfaceMetrics {
    /// Maximum share of the screen height (notch strip included) a completion
    /// toast may occupy.
    nonisolated static let completionScreenFraction: CGFloat = 0.2

    /// Maximum share of the screen height an approval / question card may occupy.
    nonisolated static let interactiveScreenFraction: CGFloat = 0.42

    /// Width of the notification surface. Narrower than the browsing panel so
    /// the toast reads as an island rather than a dashboard.
    nonisolated static let panelWidth: CGFloat = 520

    /// How long a completion toast stays before it rotates to the next unseen
    /// completion or collapses.
    nonisolated static let completionToastDuration: TimeInterval = 6

    /// Number of message lines the toast previews before truncating.
    nonisolated static let previewLineLimit = 3

    nonisolated static func screenFraction(for phase: SessionPhase?) -> CGFloat {
        switch phase {
        case .completed, .running, nil:
            completionScreenFraction
        case .waitingForApproval, .waitingForAnswer:
            interactiveScreenFraction
        }
    }

    /// Content height budget (everything below the notch strip) for a
    /// notification surface on a screen of `screenHeight` points.
    nonisolated static func maxContentHeight(
        screenHeight: CGFloat,
        notchHeight: CGFloat,
        phase: SessionPhase?
    ) -> CGFloat {
        let budget = (screenHeight * screenFraction(for: phase)).rounded(.down) - notchHeight
        return max(72, budget)
    }
}
