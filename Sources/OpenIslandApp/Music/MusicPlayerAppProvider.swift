import Foundation
import Combine

class MusicPlayerAppProvider {
    private var notificationSubject: PassthroughSubject<MusicAlertItem, Never>

    init(notificationSubject: PassthroughSubject<MusicAlertItem, Never>) {
        self.notificationSubject = notificationSubject
    }

    func getPlayerApp() -> any MusicPlayerProtocol {
        let raw = UserDefaults.standard.string(forKey: musicConnectedAppDefaultsKey) ?? "none"
        switch raw {
        case "spotify":
            return MusicSpotifyManager(notificationSubject: notificationSubject)
        case "appleMusic":
            return MusicAppleMusicManager(notificationSubject: notificationSubject)
        default:
            return MusicNoneManager(notificationSubject: notificationSubject)
        }
    }
}
