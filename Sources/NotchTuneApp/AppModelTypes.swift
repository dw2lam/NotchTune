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
}

/// How much room the closed island takes. `regular` is the shipped v6 pill;
/// `compact` trims the chrome (glyph, album art, paddings, wing reserve) so the
/// pill hugs the physical notch / menu bar instead of standing proud of it.
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
}

enum IslandCharacter: String, CaseIterable, Identifiable, Sendable {
    case dino
    case ghost
    case crab
    case duck
    case claude

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
