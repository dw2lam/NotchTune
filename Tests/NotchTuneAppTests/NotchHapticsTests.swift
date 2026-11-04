import Foundation
import Testing
@testable import NotchTuneApp

struct NotchHapticsTests {
    @Test
    func theRippleEasesOut() {
        let offsets = HapticFeel.ripple.pulses.map(\.offset)
        #expect(offsets.first == 0)
        let gaps = zip(offsets.dropFirst(), offsets).map { $0 - $1 }
        #expect(gaps.count >= 2)
        // Each gap is longer than the last: an ease-out.
        for (earlier, later) in zip(gaps, gaps.dropFirst()) {
            #expect(later > earlier)
        }
        // Over before a finger usually leaves the trackpad.
        #expect((offsets.last ?? 0) < 0.2)
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
        let model = AppModel()
        model.hapticFeedbackEnabled = true
        #expect(NotchHaptics.isEnabled)
        model.hapticSettings.feels[.tabs] = .bump
        #expect(NotchHaptics.settings.feel(for: .tabs) == .bump)
        model.hapticFeedbackEnabled = false
        #expect(!NotchHaptics.isEnabled)
    }
}
