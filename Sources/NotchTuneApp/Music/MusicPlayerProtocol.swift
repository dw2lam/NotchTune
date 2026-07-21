import Foundation
import Combine
import AppKit
import SwiftUI

protocol MusicPlayerProtocol {
    var notificationSubject: PassthroughSubject<MusicAlertItem, Never> { get set }

    var appName: String { get }
    var appPath: URL { get }
    var appNotification: String { get }
    var bundleId: String { get }
    var defaultAlbumArt: NSImage { get }

    var playerPosition: Double? { get }
    var isPlaying: Bool { get }
    var volume: CGFloat { get }
    var isLikeAuthorized: Bool { get }
    var shuffleIsOn: Bool { get }
    var shuffleContextEnabled: Bool { get }
    var repeatContextEnabled: Bool { get }
    var playbackSeekerEnabled: Bool { get }

    func getTrackInfo() -> PlayerTrack
    func getAlbumArt(completion: @escaping @Sendable (MusicFetchedAlbumArt?) -> Void)
    func playPause()
    func previousTrack()
    func nextTrack()
    func toggleLoveTrack() -> Bool
    func setShuffle(shuffleIsOn: Bool) -> Bool
    func setRepeat(repeatIsOn: Bool) -> Bool
    func getCurrentSeekerPosition() -> Double
    func seekTrack(seekerPosition: CGFloat)
    func setVolume(volume: Int)
    func isRunning() -> Bool
}

extension MusicPlayerProtocol {
    func sendNotification(title: String, message: String) {
        notificationSubject.send(MusicAlertItem(
            title: NSLocalizedString(title, comment: ""),
            message: message
        ))
    }
}
