import AppKit
import SwiftUI

/// Where the notch plays a haptic. Each one picks its own feel in
/// Settings → Personalization → Haptics.
enum HapticEvent: String, CaseIterable, Identifiable, Sendable {
    /// A button inside the open notch.
    case buttons
    /// Switching tabs.
    case tabs
    /// Play, pause, previous and next (buttons, the closed pill's cover, the
    /// two-finger skip swipe).
    case playback
    /// The notch opening on hover.
    case hoverOpen
    /// An agent finishing its task.
    case agentFinished

    var id: String { rawValue }
}

/// How a haptic feels. A Force Touch trackpad has three built-in pulses
/// (`.generic`, `.alignment`, `.levelChange`); ripple and nudge are timed
/// sequences of them.
enum HapticFeel: String, CaseIterable, Identifiable, Sendable {
    case off
    /// The lightest single pulse.
    case tap
    /// A detent, like snapping into place.
    case click
    /// The firmest single pulse.
    case bump
    /// Strong first, then lighter pulses that ease out.
    case ripple
    /// Two soft pulses: a gentle "hey".
    case nudge

    var id: String { rawValue }

    /// Pulses as (seconds after the first, pattern).
    var pulses: [(offset: TimeInterval, pattern: NSHapticFeedbackManager.FeedbackPattern)] {
        switch self {
        case .off: []
        case .tap: [(0, .generic)]
        case .click: [(0, .alignment)]
        case .bump: [(0, .levelChange)]
        case .ripple: zip(Self.rippleOffsets, [.levelChange, .alignment, .generic, .generic]).map { ($0, $1) }
        case .nudge: [(0, .generic), (0.12, .generic)]
        }
    }

    /// The gaps grow (45 → 60 → 80 ms) so the ripple eases out; it stays
    /// under 0.2 s so it has played before a finger usually leaves the
    /// trackpad.
    static let rippleOffsets: [TimeInterval] = [0, 0.045, 0.105, 0.185]
}

struct HapticSettings: Equatable, Sendable {
    static let defaultFeels: [HapticEvent: HapticFeel] = [
        .buttons: .tap,
        .tabs: .click,
        .playback: .ripple,
        .hoverOpen: .click,
        .agentFinished: .nudge,
    ]

    var feels: [HapticEvent: HapticFeel] = Self.defaultFeels

    func feel(for event: HapticEvent) -> HapticFeel {
        feels[event] ?? Self.defaultFeels[event] ?? .off
    }

    /// Persisted as `[event: feel]` raw values; unknown entries are dropped.
    init(feels: [HapticEvent: HapticFeel] = Self.defaultFeels) {
        self.feels = feels
    }

    init(stored: [String: String]) {
        var feels = Self.defaultFeels
        for (key, value) in stored {
            if let event = HapticEvent(rawValue: key), let feel = HapticFeel(rawValue: value) {
                feels[event] = feel
            }
        }
        self.feels = feels
    }

    var stored: [String: String] {
        Dictionary(uniqueKeysWithValues: feels.map { ($0.key.rawValue, $0.value.rawValue) })
    }
}

/// Trackpad haptics for the notch, off unless Settings turns them on
/// (`AppModel` keeps `isEnabled` and `settings` in sync). A Force Touch
/// trackpad only plays them while a finger rests on it, so buttons fire
/// theirs as they go down, not on release.
@MainActor
enum NotchHaptics {
    static var isEnabled = false
    static var settings = HapticSettings()

    static func play(_ event: HapticEvent) {
        guard isEnabled else { return }
        perform(settings.feel(for: event))
    }

    /// Plays `feel` regardless of the settings: the preview when picking one.
    static func perform(_ feel: HapticFeel) {
        for pulse in feel.pulses {
            if pulse.offset == 0 {
                NSHapticFeedbackManager.defaultPerformer.perform(pulse.pattern, performanceTime: .now)
            } else {
                let pattern = pulse.pattern
                DispatchQueue.main.asyncAfter(deadline: .now() + pulse.offset) {
                    NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
                }
            }
        }
    }
}

extension View {
    /// Plays `event`'s haptic as a button goes down (pass the style's
    /// `isPressed`).
    func notchHapticOnPress(_ isPressed: Bool, _ event: HapticEvent = .buttons) -> some View {
        onChange(of: isPressed) { _, pressed in
            if pressed {
                NotchHaptics.play(event)
            }
        }
    }
}
