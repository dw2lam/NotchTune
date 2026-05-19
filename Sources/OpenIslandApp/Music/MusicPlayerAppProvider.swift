import Foundation
import Combine

class MusicPlayerAppProvider {
    private var notificationSubject: PassthroughSubject<MusicAlertItem, Never>

    init(notificationSubject: PassthroughSubject<MusicAlertItem, Never>) {
        self.notificationSubject = notificationSubject
    }

    func getPlayerApp() -> any MusicPlayerProtocol {
        let raw = UserDefaults.standard.string(forKey: musicConnectedAppDefaultsKey) ?? "appleMusic"
        if raw == "spotify" {
            return MusicSpotifyManager(notificationSubject: notificationSubject)
        }
        return MusicAppleMusicManager(notificationSubject: notificationSubject)
    }
}
