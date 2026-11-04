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
        #expect(settings.feel(for: .playPause) == .ripple)
        #expect(settings.feel(for: .skip) == .flick)
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
        #expect(restored.feel(for: .playPause) == .ripple)
    }

    @Test
    func eachKindOfButtonHasItsOwnCharacter() {
        let settings = HapticSettings()
        #expect(settings.feel(for: .confirm) == .rise)
        #expect(settings.feel(for: .decline) == .knock)
        #expect(settings.feel(for: .jump) == .swoosh)

        func strengths(_ feel: HapticFeel) -> [Int] { feel.pulses.map(\.strength.rawValue) }
        // Yes climbs, no stays level, a jump climbs through three steps.
        #expect(strengths(.rise) == strengths(.rise).sorted() && strengths(.rise).first != strengths(.rise).last)
        #expect(Set(strengths(.knock)).count == 1 && strengths(.knock).count == 2)
        #expect(strengths(.swoosh) == strengths(.swoosh).sorted() && strengths(.swoosh).count == 3)

        // No two kinds of action share a multi-pulse feel.
        let signature = [HapticEvent.playPause, .skip, .confirm, .decline, .jump, .agentFinished].map { settings.feel(for: $0) }
        #expect(Set(signature).count == signature.count)
    }

    @Test
    func aFeelPickedForPlaybackCarriesOverToPlayAndPause() {
        let restored = HapticSettings(stored: ["playback": "bump"])
        #expect(restored.feel(for: .playPause) == .bump)
        #expect(restored.feel(for: .skip) == .flick)
    }

    @Test
    func playbackHapticsFollowTheHierarchy() {
        // The sum of each pulse's strength, the double hit counted twice.
        func weight(_ feel: HapticFeel) -> Int {
            feel.pulses.reduce(0) { $0 + $1.strength.rawValue * $1.strength.repeats }
        }
        let settings = HapticSettings()
        let playPause = weight(settings.feel(for: .playPause))
        let skip = weight(settings.feel(for: .skip))
        let button = weight(settings.feel(for: .buttons))
        #expect(playPause > skip)
        #expect(skip > button)
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
