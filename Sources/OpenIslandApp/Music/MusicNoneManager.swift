import Foundation
import Combine
import AppKit
import SwiftUI

final class MusicNoneManager: MusicPlayerProtocol {
    var notificationSubject: PassthroughSubject<MusicAlertItem, Never>

    init(notificationSubject: PassthroughSubject<MusicAlertItem, Never>) {
        self.notificationSubject = notificationSubject
    }

    var appName: String { "None" }
    var appPath: URL { URL(fileURLWithPath: "/Applications") }
    var appNotification: String { "" }
    var bundleId: String { "" }
    var defaultAlbumArt: NSImage { NSImage() }

    var playerPosition: Double? { nil }
    var isPlaying: Bool { false }
    var volume: CGFloat { 50 }
    var isLikeAuthorized: Bool { false }
    var shuffleIsOn: Bool { false }
    var shuffleContextEnabled: Bool { false }
    var repeatContextEnabled: Bool { false }
    var playbackSeekerEnabled: Bool { false }

    func getTrackInfo() -> PlayerTrack { PlayerTrack() }
    func getAlbumArt(completion: @escaping @Sendable (MusicFetchedAlbumArt?) -> Void) { completion(nil) }
    func playPause() {}
    func previousTrack() {}
    func nextTrack() {}
    func toggleLoveTrack() -> Bool { false }
    func setShuffle(shuffleIsOn: Bool) -> Bool { false }
    func setRepeat(repeatIsOn: Bool) -> Bool { false }
    func getCurrentSeekerPosition() -> Double { 0 }
    func seekTrack(seekerPosition: CGFloat) {}
    func setVolume(volume: Int) {}
    func isRunning() -> Bool { false }
}
