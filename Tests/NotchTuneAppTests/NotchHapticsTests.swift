import Foundation
import Testing
@testable import NotchTuneApp

struct NotchHapticsTests {
    @Test
    func theRippleEasesOut() {
        let offsets = NotchHaptics.rippleOffsets
        #expect(offsets.first == 0)
        let gaps = zip(offsets.dropFirst(), offsets).map { $0 - $1 }
        #expect(gaps.count >= 2)
        // Each pulse comes later than the last gap: an ease-out.
        for (earlier, later) in zip(gaps, gaps.dropFirst()) {
            #expect(later > earlier)
        }
    }

    @Test
    func theRippleEndsWhileAFingerIsStillOnTheTrackpad() {
        #expect((NotchHaptics.rippleOffsets.last ?? 0) < 0.2)
    }

    @Test @MainActor
    func hapticsFollowTheSetting() {
        let model = AppModel()
        model.hapticFeedbackEnabled = true
        #expect(NotchHaptics.isEnabled)
        model.hapticFeedbackEnabled = false
        #expect(!NotchHaptics.isEnabled)
    }
}
