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
    case blob
    case poo
    // Italian brainrot and friends.
    case johnPork
    case tungTung
    case tralalero
    case bombardiro
    case ballerina
    case chimpanzini
    case lirili
    case patapim

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
    case mirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agents: "Agents"
        case .music: "Music"
        case .myspace: "Myspace"
        case .reminders: "Reminders"
        case .mirror: "Mirror"
        }
    }

    var systemImage: String {
        switch self {
        case .agents: "terminal"
        case .music: "music.note"
        case .myspace: "square.grid.2x2"
        case .reminders: "bell"
        case .mirror: "camera"
        }
    }

    /// The saved tab order, made whole: unknown names are dropped, repeats
    /// keep their first place, and a tab added since it was saved goes last.
    static func order(stored: [String]) -> [IslandTab] {
        var order: [IslandTab] = []
        for tab in stored.compactMap(IslandTab.init(rawValue:)) where !order.contains(tab) {
            order.append(tab)
        }
        return order + allCases.filter { !order.contains($0) }
    }

    /// `tab` takes `target`'s place, the way a dragged item does.
    static func order(_ order: [IslandTab], moving tab: IslandTab, onto target: IslandTab) -> [IslandTab] {
        guard let from = order.firstIndex(of: tab), let to = order.firstIndex(of: target) else { return order }
        var result = order
        result.remove(at: from)
        result.insert(tab, at: to)
        return result
    }

    /// `tab` moved by `offset` places, stopping at the ends.
    static func order(_ order: [IslandTab], moving tab: IslandTab, by offset: Int) -> [IslandTab] {
        guard let from = order.firstIndex(of: tab) else { return order }
        let to = min(max(from + offset, 0), order.count - 1)
        return Self.order(order, moving: tab, onto: order[to])
    }
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
