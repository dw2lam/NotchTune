import AppKit
import IOKit
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

/// One trackpad pulse.
enum HapticStrength: Sendable {
    case light
    case medium
    case strong

    /// MultitouchSupport actuation IDs (the ones HapticKey and friends use;
    /// 3 is the faintest, 6 the firmest). 3 was too faint to notice through
    /// a resting finger, so the scale starts at 4.
    var actuationID: Int32 {
        switch self {
        case .light: 4
        case .medium: 6
        case .strong: 6
        }
    }

    /// Strong is the firmest pulse played twice, back to back, for more
    /// body than any single actuation has.
    var repeats: Int {
        self == .strong ? 2 : 1
    }

    /// The closest AppKit pattern, for the fallback.
    var pattern: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .light: .generic
        case .medium: .alignment
        case .strong: .levelChange
        }
    }
}

/// How a haptic feels: a single pulse, or a timed sequence of them.
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

    /// Pulses as (seconds after the first, strength).
    var pulses: [(offset: TimeInterval, strength: HapticStrength)] {
        switch self {
        case .off: []
        case .tap: [(0, .light)]
        case .click: [(0, .medium)]
        case .bump: [(0, .strong)]
        case .ripple: zip(Self.rippleOffsets, [.strong, .strong, .medium, .medium, .light]).map { ($0, $1) }
        case .nudge: [(0, .light), (0.12, .light)]
        }
    }

    /// Five pulses whose gaps grow (70 → 80 → 90 → 100 ms) so the ripple
    /// rolls out and eases off over about a third of a second, instead of
    /// one quick, sharp burst.
    static let rippleOffsets: [TimeInterval] = [0, 0.07, 0.15, 0.24, 0.34]
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
/// (`AppModel` keeps `isEnabled` and `settings` in sync). Buttons fire
/// theirs as they go down, while the finger is still on the trackpad.
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
                fire(pulse.strength)
            } else {
                let strength = pulse.strength
                DispatchQueue.main.asyncAfter(deadline: .now() + pulse.offset) {
                    fire(strength)
                }
            }
        }
    }

    /// AppKit's haptics only play for the active app, and NotchTune never is
    /// (the notch is a non-activating panel), so they were silent. The
    /// trackpad's actuator plays for any app; AppKit stays as the fallback
    /// where there is no built-in Force Touch trackpad to drive.
    private static func fire(_ strength: HapticStrength) {
        if TrackpadActuator.shared?.actuate(strength.actuationID) == true {
            for repeatIndex in 1..<strength.repeats {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.014 * Double(repeatIndex)) {
                    _ = TrackpadActuator.shared?.actuate(strength.actuationID)
                }
            }
            return
        }
        NSHapticFeedbackManager.defaultPerformer.perform(strength.pattern, performanceTime: .now)
    }
}

/// The Force Touch trackpad's actuator, through the MultitouchSupport
/// framework (private, loaded at run time; `nil` when it or a trackpad with
/// an actuator isn't there).
@MainActor
final class TrackpadActuator {
    private typealias CreateFn = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias OpenFn = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuateFn = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32
    private typealias CloseFn = @convention(c) (CFTypeRef) -> Int32

    static let shared: TrackpadActuator? = TrackpadActuator()

    private let create: CreateFn
    private let open: OpenFn
    private let actuateFn: ActuateFn
    private let close: CloseFn
    private var actuator: CFTypeRef?
    /// When the last search for an actuator came up empty. A Mac without a
    /// Force Touch trackpad shouldn't scan the IORegistry on every pulse.
    private var lastFailedOpen: Date?
    private static let retryInterval: TimeInterval = 10

    private init?() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW
        ),
            let create = dlsym(handle, "MTActuatorCreateFromDeviceID"),
            let open = dlsym(handle, "MTActuatorOpen"),
            let actuate = dlsym(handle, "MTActuatorActuate"),
            let close = dlsym(handle, "MTActuatorClose") else {
            return nil
        }
        self.create = unsafeBitCast(create, to: CreateFn.self)
        self.open = unsafeBitCast(open, to: OpenFn.self)
        self.actuateFn = unsafeBitCast(actuate, to: ActuateFn.self)
        self.close = unsafeBitCast(close, to: CloseFn.self)
    }

    /// A trackpad with an actuator is connected and opens.
    var isAvailable: Bool {
        openIfNeeded() != nil
    }

    /// `true` when the pulse played.
    func actuate(_ actuationID: Int32) -> Bool {
        guard let actuator = openIfNeeded() else { return false }
        if actuateFn(actuator, actuationID, 0, 0, 0) == 0 {
            return true
        }
        // The trackpad went away (sleep, a reconnect): close this handle and
        // reopen next time.
        _ = close(actuator)
        self.actuator = nil
        return false
    }

    private func openIfNeeded() -> CFTypeRef? {
        if let actuator { return actuator }
        if let lastFailedOpen, Date().timeIntervalSince(lastFailedOpen) < Self.retryInterval {
            return nil
        }
        actuator = openActuator()
        lastFailedOpen = actuator == nil ? Date() : nil
        return actuator
    }

    private func openActuator() -> CFTypeRef? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let supported = IORegistryEntryCreateCFProperty(
                service, "ActuationSupported" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? Bool
            guard supported == true,
                  let id = IORegistryEntryCreateCFProperty(
                      service, "Multitouch ID" as CFString, kCFAllocatorDefault, 0
                  )?.takeRetainedValue() as? NSNumber,
                  let actuator = create(id.uint64Value)?.takeRetainedValue(),
                  open(actuator) == 0 else { continue }
            return actuator
        }
        return nil
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
