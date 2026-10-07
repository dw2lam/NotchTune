import Foundation
import Combine

class MusicPlayerAppProvider {
    private var notificationSubject: PassthroughSubject<MusicAlertItem, Never>
    private let harness: MusicHarnessOverride?

    init(
        notificationSubject: PassthroughSubject<MusicAlertItem, Never>,
        harness: MusicHarnessOverride? = nil
    ) {
        self.notificationSubject = notificationSubject
        self.harness = harness
    }

    func getPlayerApp() -> any MusicPlayerProtocol {
        if let harness {
            return MusicHarnessPlayer(override: harness, notificationSubject: notificationSubject)
        }
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
