import AppKit
import CoreGraphics
import Foundation
import NotchTuneCore

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason: Equatable {
    case click
    case hover
    case drag
    case notification
    case boot
}

enum TrackedEventIngress {
    case bridge
    case rollout
}

// MARK: - v6 island preferences

/// What the closed island renders in the right slot. Chosen in the
/// Personalization tab; the pill layout only varies by content width.
enum IslandRightSlot: String, CaseIterable, Identifiable, Sendable {
    case count   // "×N" badge
    case agents  // colored dot stack, one per active agent tool
    case none    // pill collapses — useful if you just want the bars

    var id: String { rawValue }
}

/// What the closed island renders in the center label (external displays
/// only — on MacBook the physical notch covers this space so we suppress
/// the label regardless).
enum IslandCenterLabel: String, CaseIterable, Identifiable, Sendable {
    case sessionName  // e.g. "open-island"
    case agentAction  // e.g. "Claude · editing"
    case off

    var id: String { rawValue }
}

// MARK: - v8 island preferences

enum IslandAppearanceDisplayProfile: String, CaseIterable, Identifiable, Sendable {
    case notch
    case topBar

    var id: String { rawValue }

    /// The other display's profile (the passenger zone when this one drives).
    var other: IslandAppearanceDisplayProfile {
        switch self {
        case .notch: .topBar
        case .topBar: .notch
        }
    }
}

/// How much room the closed island takes. `regular` is the shipped v6 pill;
/// `compact` trims the chrome (glyph, album art, paddings, wing reserve) so the
/// pill hugs the physical notch / menu bar instead of standing proud of it.
/// What a track change does to the closed notch.
enum MusicTrackNotificationOutcome: Equatable, Sendable {
    /// Leave the pill as it is.
    case ignore
    /// Show the new track on the music pill.
    case show
    /// Show it and pop the notch to draw the eye.
    case showAndPop

    static func resolve(
        trackChanged: Bool,
        fromSwipe: Bool,
        musicOwnsPill: Bool,
        notchClosed: Bool
    ) -> MusicTrackNotificationOutcome {
        if fromSwipe {
            // The user is looking at the pill and the arrows answered the
            // swipe: an agent pill stays put, a music pill just updates.
            return musicOwnsPill ? .show : .ignore
        }
        return trackChanged && notchClosed ? .showAndPop : .show
    }
}

struct MusicSkipFeedback: Equatable, Sendable {
    enum Direction: Sendable { case next, previous }

    let direction: Direction
    let id = UUID()

    /// How long the arrows ripple on the pill.
    nonisolated static let duration: TimeInterval = 1.1
}

/// How long the cursor has to rest on the closed notch before it opens.
enum HoverOpenMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case quick
    case normal
    case relaxed

    var id: String { rawValue }

    /// `nil` = hover never opens the notch (click still does).
    var delay: TimeInterval? {
        switch self {
        case .off: nil
        case .quick: 0.2
        case .normal: 0.4
        case .relaxed: 0.7
        }
    }
}

enum IslandDensity: String, CaseIterable, Identifiable, Sendable {
    case regular
    case compact

    var id: String { rawValue }
}

struct IslandAppearancePreferences: Equatable, Sendable {
    var rightSlot: IslandRightSlot = .count
    var centerLabel: IslandCenterLabel = .agentAction
    var character: IslandCharacter = .dino
    /// How much the character moves; Calm by default (the pill sits in
    /// peripheral vision for hours).
    var characterMotion: IslandCharacterMotion = .calm
    /// Tint the character with the active agent's brand color (Codex blue,
    /// Claude orange, …) instead of the paper ink.
    var colorByAgent: Bool = false
    /// Outward curve where the notch meets the top of the screen, closed and
    /// opened (the flared "ears" of a hardware notch).
    var topCurve: Bool = true
    var density: IslandDensity = .regular
    var liveActivity: IslandLiveActivityMode = .active
    var autoHideWhenInactive: Bool = false
    var usageDisplay: IslandUsageDisplay = .compact
    var sessionStateIndicator: IslandSessionStateIndicator = .animatedDot
    var sessionGroup: IslandSessionGroup = .none
    var sessionSort: IslandSessionSort = .attention
    var completedStaleThreshold: IslandCompletedStaleThreshold = .fiveMinutes

    /// These preferences with every shared choice taken from `source`, as
    /// Sync writes them. Only the external display's auto-hide stays put:
    /// it is the one choice Settings offers for a single display, so it
    /// never lands on the MacBook notch unseen. New fields sync by default.
    func syncing(from source: IslandAppearancePreferences) -> IslandAppearancePreferences {
        var synced = source
        synced.autoHideWhenInactive = autoHideWhenInactive
        return synced
    }
}

/// How much the closed-pill character moves. Raw values are persisted in the
/// appearance preferences: never rename one.
enum IslandCharacterMotion: String, CaseIterable, Identifiable, Sendable {
    /// Slow, in-place changes; long rests between blinks and glances.
    case calm
    /// Walk cycles, hops and sways.
    case lively
    /// One frame per state.
    case still

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: "Calm"
        case .lively: "Lively"
        case .still: "Still"
        }
    }
}

/// Raw values are persisted in the appearance preferences: never rename one.
enum IslandCharacter: String, CaseIterable, Identifiable, Sendable {
    case dino
    case ghost
    case crab
    case duck
    case claude
    case cat
    case robot
    case octopus
    case frog
    case slime

    var id: String { rawValue }
}

enum IslandUsageDisplay: String, CaseIterable, Identifiable, Sendable {
    case hidden
    case compact

    var id: String { rawValue }
}

enum IslandTab: String, CaseIterable, Identifiable, Sendable {
    case agents
    case music
    case myspace
    case reminders

    var id: String { rawValue }
}

enum IslandSessionStateIndicator: String, CaseIterable, Identifiable, Sendable {
    case animatedDot
    case bar
    case glyph
    case tint

    var id: String { rawValue }
}

enum IslandSessionGroup: String, CaseIterable, Identifiable, Sendable {
    case none
    case state
    case agent
    case project

    var id: String { rawValue }
}

enum IslandSessionSort: String, CaseIterable, Identifiable, Sendable {
    case attention
    case lastUpdate

    var id: String { rawValue }
}

enum IslandCompletedStaleThreshold: String, CaseIterable, Identifiable, Sendable {
    case twoMinutes
    case fiveMinutes
    case tenMinutes
    case twentyMinutes
    case never

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .twoMinutes:    return 2 * 60
        case .fiveMinutes:   return 5 * 60
        case .tenMinutes:    return 10 * 60
        case .twentyMinutes: return 20 * 60
        case .never:         return .infinity
        }
    }
}

struct IslandSessionSection: Identifiable {
    let id: String
    let title: String
    let sessions: [AgentSession]
}
