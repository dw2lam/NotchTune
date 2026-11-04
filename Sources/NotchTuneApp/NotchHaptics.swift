import AppKit
import SwiftUI

/// Trackpad haptics for the notch, off unless Settings → General turns
/// them on (`AppModel.hapticFeedbackEnabled` keeps `isEnabled` in sync).
/// A Force Touch trackpad only plays them while a finger rests on it, so
/// buttons fire theirs as they go down, not on release.
@MainActor
enum NotchHaptics {
    enum Feel: Equatable {
        /// A button inside the notch.
        case tap
        /// Snapping into place: switching tabs, the notch opening on hover.
        case detent
        /// Play, pause and skip: pulses that ease out, each further apart.
        case ripple
    }

    static var isEnabled = false

    /// Ripple pulses, as seconds after the first one. The gaps grow (45 →
    /// 60 → 80 ms) so the ripple eases out; it stays under 0.2 s so it has
    /// played before a finger usually leaves the trackpad.
    nonisolated static let rippleOffsets: [TimeInterval] = [0, 0.045, 0.105, 0.185]

    static func play(_ feel: Feel) {
        guard isEnabled else { return }
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch feel {
        case .tap:
            performer.perform(.generic, performanceTime: .now)
        case .detent:
            performer.perform(.alignment, performanceTime: .now)
        case .ripple:
            // Strongest first, then lighter pulses.
            let patterns: [NSHapticFeedbackManager.FeedbackPattern] = [.levelChange, .alignment, .generic, .generic]
            for (offset, pattern) in zip(rippleOffsets, patterns) {
                if offset == 0 {
                    performer.perform(pattern, performanceTime: .now)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + offset) {
                        guard isEnabled else { return }
                        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
                    }
                }
            }
        }
    }
}

extension View {
    /// Plays `feel` as a button goes down (pass the style's `isPressed`).
    func notchHapticOnPress(_ isPressed: Bool, _ feel: NotchHaptics.Feel? = .tap) -> some View {
        onChange(of: isPressed) { _, pressed in
            if pressed, let feel {
                NotchHaptics.play(feel)
            }
        }
    }
}
