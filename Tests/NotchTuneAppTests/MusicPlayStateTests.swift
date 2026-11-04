import Foundation
import Testing
@testable import NotchTuneApp

/// Play/pause shows the new state at once; a poll that still reads the old
/// one mustn't flip the icon back.
@MainActor
struct MusicPlayStateTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func pending(_ isPlaying: Bool, in seconds: TimeInterval) -> MusicPlayerManager.PendingPlayState {
        .init(isPlaying: isPlaying, until: now.addingTimeInterval(seconds))
    }

    @Test
    func aStalePollRightAfterPausingIsIgnored() {
        // Paused by hand (isPlaying now false); the player still says playing.
        let result = MusicPlayerManager.resolvePolledPlayState(
            polled: true, current: false, pending: pending(false, in: 1), now: now
        )
        #expect(result.isPlaying == false)
        #expect(result.pending != nil)
    }

    @Test
    func thePlayerAgreeingEndsTheWait() {
        let result = MusicPlayerManager.resolvePolledPlayState(
            polled: false, current: false, pending: pending(false, in: 1), now: now
        )
        #expect(result.isPlaying == false)
        #expect(result.pending == nil)
    }

    @Test
    func afterTheWindowThePlayerIsBelieved() {
        // The command never took (player closed, say): show what's real.
        let result = MusicPlayerManager.resolvePolledPlayState(
            polled: true, current: false, pending: pending(false, in: -0.1), now: now
        )
        #expect(result.isPlaying == true)
        #expect(result.pending == nil)
    }

    @Test
    func withoutAToggleEveryPollIsTaken() {
        let result = MusicPlayerManager.resolvePolledPlayState(
            polled: true, current: false, pending: nil, now: now
        )
        #expect(result.isPlaying == true)
    }
}
