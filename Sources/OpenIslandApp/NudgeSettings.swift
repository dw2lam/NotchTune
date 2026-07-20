import Foundation

/// How long a session may sit waiting for the user before the island nudges.
enum IdleNudgeThreshold: String, CaseIterable, Identifiable, Sendable {
    case thirtySeconds
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case tenMinutes

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .thirtySeconds: return 30
        case .oneMinute:     return 60
        case .twoMinutes:    return 2 * 60
        case .fiveMinutes:   return 5 * 60
        case .tenMinutes:    return 10 * 60
        }
    }

    var displayName: String {
        switch self {
        case .thirtySeconds: return "30 seconds"
        case .oneMinute:     return "1 minute"
        case .twoMinutes:    return "2 minutes"
        case .fiveMinutes:   return "5 minutes"
        case .tenMinutes:    return "10 minutes"
        }
    }
}

/// User-configurable "idle session nudge": when an agent session sits waiting
/// for the user past `threshold` without a response, the closed-pill character
/// jumps and a selectable nudge sound plays (once per waiting episode).
///
/// The nudge sound itself lives in `NotificationSoundService` (slot `.nudge`),
/// so it shares the system + custom sound lists with notifications. Persisted by
/// `AppModel`, mirroring `LiquidGlassSettings`.
struct NudgeSettings: Equatable, Sendable {
    var isEnabled: Bool = false
    var threshold: IdleNudgeThreshold = .twoMinutes
}
