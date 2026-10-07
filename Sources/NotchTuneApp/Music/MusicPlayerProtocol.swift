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
    /// Replay handle + cover URL of the current track. Only asked on a track
    /// change (never per poll); players without one return `nil`.
    func currentTrackIdentity() -> MusicTrackIdentity?
}

struct MusicTrackIdentity: Equatable, Sendable {
    var playbackURI: String
    var artworkURL: URL?
}

extension MusicPlayerProtocol {
    func currentTrackIdentity() -> MusicTrackIdentity? { nil }

    func sendNotification(title: String, message: String) {
        notificationSubject.send(MusicAlertItem(
            title: NSLocalizedString(title, comment: ""),
            message: message
        ))
    }
}
