import Combine
import Foundation
import Observation
import Sparkle

/// Small SwiftUI-facing wrapper around Sparkle's standard updater.
///
/// Sparkle owns the update UI and installation lifecycle. This object only
/// starts its schedule and exposes whether a manual check can currently run.
@MainActor
@Observable
final class UpdateChecker: NSObject {
    static let releasesURL = URL(string: "https://github.com/dw2lam/NotchTune/releases")!

    private(set) var canCheckForUpdates = false
    private(set) var hasUpdate = false
    private(set) var latestVersion: String?
    /// A check the user asked for is running (Sparkle shows its own window
    /// too); scheduled background checks don't set it.
    private(set) var isChecking = false
    /// When Sparkle last checked; nil before the first check and in
    /// development builds.
    private(set) var lastCheckDate: Date?

    @ObservationIgnored
    private var updaterController: SPUStandardUpdaterController!

    @ObservationIgnored
    private var cancellable: AnyCancellable?

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func startIfNeeded() {
        #if DEBUG
        // Never let a locally-built app replace itself with a published build.
        canCheckForUpdates = false
        applyHarnessState()
        return
        #else
        let updater = updaterController.updater
        updater.automaticallyChecksForUpdates = true
        updater.updateCheckInterval = 60 * 60
        updater.automaticallyDownloadsUpdates = false

        do {
            try updater.start()
        } catch {
            print("[UpdateChecker] Failed to start Sparkle: \(error)")
        }
        lastCheckDate = updater.lastUpdateCheckDate

        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
        #endif
    }

    func checkForUpdates() {
        if canCheckForUpdates { isChecking = true }
        updaterController.checkForUpdates(nil)
    }

    #if DEBUG
    /// Harness: `NOTCHTUNE_HARNESS_UPDATE_STATE=checking|available|current`
    /// shows that state in Settings without Sparkle (debug builds only).
    private func applyHarnessState() {
        guard let state = ProcessInfo.processInfo.environment["NOTCHTUNE_HARNESS_UPDATE_STATE"] else { return }
        canCheckForUpdates = true
        switch state {
        case "checking":
            isChecking = true
        case "available":
            hasUpdate = true
            latestVersion = "2.2.0"
        default:
            lastCheckDate = Date().addingTimeInterval(-5 * 60)
        }
    }
    #endif
}

extension UpdateChecker: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Set()
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.hasUpdate = true
            self.latestVersion = item.displayVersionString
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            self.hasUpdate = false
            self.latestVersion = nil
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        Task { @MainActor in
            self.isChecking = false
            // Sparkle wants this read on the main thread.
            self.lastCheckDate = self.updaterController.updater.lastUpdateCheckDate
        }
    }
}
