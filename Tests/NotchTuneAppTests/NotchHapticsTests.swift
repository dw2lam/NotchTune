import Foundation
import Testing
@testable import NotchTuneApp

struct NotchHapticsTests {
    @Test
    func theRippleSwellsToAPeakAndSettles() {
        let offsets = HapticFeel.ripple.pulses.map(\.offset)
        #expect(offsets.first == 0)
        #expect(offsets == offsets.sorted())
        // Spread out over a beat, not a sharp burst, and still brief.
        #expect((offsets.last ?? 0) >= 0.4)
        #expect((offsets.last ?? 0) < 0.7)
        // Up to the firmest pulse, then down to the faintest.
        let strengths = HapticFeel.ripple.pulses.map(\.strength.rawValue)
        let peak = strengths.firstIndex(of: strengths.max()!)!
        #expect(peak > 0 && peak < strengths.count - 1)
        #expect(Array(strengths[...peak]) == strengths[...peak].sorted())
        #expect(Array(strengths[peak...]) == strengths[peak...].sorted(by: >))
        #expect(strengths.last == strengths.min())
    }

    @Test
    func offPlaysNothingAndEveryOtherFeelPlaysSomething() {
        #expect(HapticFeel.off.pulses.isEmpty)
        for feel in HapticFeel.allCases where feel != .off {
            #expect(!feel.pulses.isEmpty)
        }
    }

    @Test
    func everyEventHasADefaultFeel() {
        let settings = HapticSettings()
        for event in HapticEvent.allCases {
            #expect(settings.feel(for: event) != .off)
        }
        #expect(settings.feel(for: .playback) == .ripple)
        #expect(settings.feel(for: .agentFinished) == .nudge)
    }

    @Test
    func feelsSurviveARoundTripAndIgnoreUnknownEntries() {
        var settings = HapticSettings()
        settings.feels[.buttons] = .off
        settings.feels[.tabs] = .bump
        var stored = settings.stored
        stored["someFutureEvent"] = "ripple"
        stored["playback"] = "notAFeel"
        let restored = HapticSettings(stored: stored)
        #expect(restored.feel(for: .buttons) == .off)
        #expect(restored.feel(for: .tabs) == .bump)
        #expect(restored.feel(for: .playback) == .ripple)
    }

    @Test @MainActor
    func hapticsFollowTheSetting() {
        // AppModel saves to the standard defaults: put them back after.
        let defaults = UserDefaults.standard
        let savedEnabled = defaults.object(forKey: "app.hapticFeedbackEnabled")
        let savedFeels = defaults.object(forKey: "app.hapticFeels")
        defer {
            defaults.set(savedEnabled, forKey: "app.hapticFeedbackEnabled")
            defaults.set(savedFeels, forKey: "app.hapticFeels")
            NotchHaptics.isEnabled = false
            NotchHaptics.settings = HapticSettings()
        }
        let model = AppModel()
        model.hapticFeedbackEnabled = true
        #expect(NotchHaptics.isEnabled)
        model.hapticSettings.feels[.tabs] = .bump
        #expect(NotchHaptics.settings.feel(for: .tabs) == .bump)
        model.hapticFeedbackEnabled = false
        #expect(!NotchHaptics.isEnabled)
    }
}
