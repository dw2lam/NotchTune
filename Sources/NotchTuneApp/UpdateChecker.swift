import Combine
import CoreGraphics
import Foundation
import Observation
import Sparkle

/// What a restart would interrupt right now, as the rest of the app sees it.
struct UpdateRestartContext: Equatable, Sendable {
    /// Agents waiting on an approval or a question, whose prompts live in
    /// the notch.
    var agentsWaiting = 0
    var mirrorOpen = false
}

/// When a prepared update may restart NotchTune without being asked.
///
/// Sparkle runs no further update cycles while we hold a prepared update
/// (see `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)`), so
/// on a Mac that keeps NotchTune open for weeks, an ignored "Update" button
/// would hide every later release. Applying it after a while is what lets
/// the checks start again.
enum UpdateAutoInstall {
    /// Long enough that "Update" gets its chance first.
    static let readyDelay: TimeInterval = 24 * 60 * 60
    static let idleThreshold: TimeInterval = 5 * 60

    static func shouldInstall(
        readySince: Date?,
        now: Date,
        idleFor: TimeInterval,
        context: UpdateRestartContext,
        automaticDownloads: Bool
    ) -> Bool {
        guard automaticDownloads, let readySince else { return false }
        return now.timeIntervalSince(readySince) >= readyDelay
            && idleFor >= idleThreshold
            && context.agentsWaiting == 0
            && !context.mirrorOpen
    }
}

/// Small SwiftUI-facing wrapper around Sparkle's standard updater.
///
/// Updates arrive the way Figma's do: Sparkle downloads them in the
/// background (a small delta patch when the feed has one for this build),
/// prepares them, and holds them; NotchTune then offers "Restart to
/// Update" in the notch and in Settings, which swaps the app in place and
/// relaunches it with no installer window. Left alone, the update goes in
/// the next time NotchTune quits, or by itself once `UpdateAutoInstall`
/// says it's safe.
///
/// With automatic downloads off, Sparkle still checks but nothing else
/// happens until the user asks: Settings says a version is out, and its
/// button opens Sparkle's own update window.
@MainActor
@Observable
final class UpdateChecker: NSObject {
    static let releasesURL = URL(string: "https://github.com/dw2lam/NotchTune/releases")!
    private static let automaticDownloadsKey = "updates.automaticDownloads"
    /// Finer than `UpdateAutoInstall.idleThreshold` buys nothing: idle time
    /// only grows between ticks.
    private static let autoInstallCheckInterval: TimeInterval = 5 * 60

    private(set) var canCheckForUpdates = false
    private(set) var hasUpdate = false
    private(set) var latestVersion: String?
    /// A check the user asked for is running (Sparkle shows its own window
    /// too); scheduled background checks don't set it.
    private(set) var isChecking = false
    /// When Sparkle last checked; nil before the first check and in
    /// development builds. Sparkle stamps it whether or not the check
    /// worked — see `lastCheckFailed`.
    private(set) var lastCheckDate: Date?
    /// The last check couldn't complete (offline, the feed unreachable or
    /// malformed), so `lastCheckDate` doesn't mean "up to date".
    private(set) var lastCheckFailed = false
    /// Sparkle refused to run because NotchTune is on a disk image or still
    /// translocated: only moving the app fixes that, so a retry won't.
    private(set) var needsMoveToApplications = false
    /// An update is downloading in the background.
    private(set) var downloadingVersion: String?
    /// An update is downloaded and prepared: restarting installs it.
    private(set) var readyVersion: String?

    /// The Settings toggle. Off, Sparkle stops downloading on its own and a
    /// prepared update waits for the user.
    var automaticDownloadsEnabled: Bool {
        didSet {
            guard automaticDownloadsEnabled != oldValue else { return }
            defaults.set(automaticDownloadsEnabled, forKey: Self.automaticDownloadsKey)
            #if !DEBUG
            if hasStartedUpdater {
                updaterController.updater.automaticallyDownloadsUpdates = automaticDownloadsEnabled
            }
            #endif
        }
    }

    /// What a restart would interrupt; AppModel fills this in.
    @ObservationIgnored
    var restartContext: @MainActor () -> UpdateRestartContext = { UpdateRestartContext() }

    /// Asks before restarting over waiting agents; AppModel fills this in.
    @ObservationIgnored
    var confirmRestartWithAgentsWaiting: @MainActor () -> Bool = { true }

    /// Sparkle's handler that installs the prepared update and relaunches.
    @ObservationIgnored
    private var installReadyUpdate: (() -> Void)?

    /// When `readyVersion` was set: `UpdateAutoInstall` counts from here.
    @ObservationIgnored
    private var readySince: Date?

    /// Runs only while an update is prepared.
    @ObservationIgnored
    private var autoInstallTimer: Timer?

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private var hasStartedUpdater = false

    @ObservationIgnored
    private var updaterController: SPUStandardUpdaterController!

    @ObservationIgnored
    private var cancellable: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticDownloadsEnabled = defaults.object(forKey: Self.automaticDownloadsKey) as? Bool ?? true
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    func startIfNeeded() {
        #if DEBUG
        // Never let a locally-built app replace itself with a published build.
        canCheckForUpdates = false
        applyHarnessState()
        return
        #else
        // A packaged build under test (package-app.sh's smoke run) stays
        // away from the feed.
        guard !HarnessHeadless.isActive else { return }
        let updater = updaterController.updater
        // Set rather than left to Sparkle, which would ask for permission
        // with a window of its own on the second launch.
        updater.automaticallyChecksForUpdates = true
        updater.updateCheckInterval = 60 * 60
        // Download and prepare in the background; we offer the restart.
        updater.automaticallyDownloadsUpdates = automaticDownloadsEnabled

        do {
            try updater.start()
            hasStartedUpdater = true
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

    /// A check the user asked for. It runs like a scheduled one: anything
    /// new downloads quietly and turns into "Restart to Update", with no
    /// Sparkle window. An update that's already been found and is waiting
    /// on the user opens that window instead, since nothing else can take it.
    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        if hasUpdate {
            updaterController.updater.checkForUpdates()
            return
        }
        isChecking = true
        updaterController.updater.checkForUpdatesInBackground()
    }

    /// The user asked to install the prepared update and relaunch NotchTune.
    func installAndRelaunch() {
        guard installReadyUpdate != nil else { return }
        if restartContext().agentsWaiting > 0, !confirmRestartWithAgentsWaiting() { return }
        installReadyUpdate?()
    }

    func updateBecameReady(version: String, install: @escaping () -> Void) {
        installReadyUpdate = install
        readyVersion = version
        readySince = .now
        autoInstallTimer?.invalidate()
        let timer = Timer(timeInterval: Self.autoInstallCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.installIfSafe() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        autoInstallTimer = timer
    }

    /// Sparkle's cycle ended without installing, so what it prepared and the
    /// handler it gave us are gone: a dead "Update" button would do nothing.
    func clearReadyUpdate() {
        installReadyUpdate = nil
        readyVersion = nil
        readySince = nil
        autoInstallTimer?.invalidate()
        autoInstallTimer = nil
    }

    private func installIfSafe() {
        let anyInput = CGEventType(rawValue: ~0)!
        guard UpdateAutoInstall.shouldInstall(
            readySince: readySince,
            now: .now,
            idleFor: CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput),
            context: restartContext(),
            automaticDownloads: automaticDownloadsEnabled
        ) else { return }
        autoInstallTimer?.invalidate()
        autoInstallTimer = nil
        installReadyUpdate?()
    }

    #if DEBUG
    /// Harness: `NOTCHTUNE_HARNESS_UPDATE_STATE=checking|available|failed|move|current`
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
        case "downloading":
            hasUpdate = true
            latestVersion = "2.2.0"
            downloadingVersion = "2.2.0"
        case "ready":
            hasUpdate = true
            latestVersion = "2.2.0"
            readyVersion = "2.2.0"
        case "failed":
            lastCheckFailed = true
            lastCheckDate = Date().addingTimeInterval(-5 * 60)
        case "move":
            lastCheckFailed = true
            needsMoveToApplications = true
        default:
            lastCheckDate = Date().addingTimeInterval(-5 * 60)
        }
    }
    #endif

    /// Whether a finished update cycle's error means the check itself
    /// failed. Sparkle reports "no update found" and "the user cancelled
    /// the install" as errors too; neither is a failed check.
    nonisolated static func isFailedCheck(_ error: (any Error)?) -> Bool {
        guard let error else { return false }
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else { return true }
        return ![Int(SUError.noUpdateError.rawValue), Int(SUError.installationCanceledError.rawValue)].contains(nsError.code)
    }

    /// Whether Sparkle refused because of where NotchTune is running from: a
    /// disk image, or a quarantined copy macOS translocated out of Downloads.
    nonisolated static func isWrongLocation(_ error: (any Error)?) -> Bool {
        guard let error else { return false }
        let nsError = error as NSError
        return nsError.domain == SUSparkleErrorDomain
            && [Int(SUError.runningFromDiskImageError.rawValue), Int(SUError.runningTranslocated.rawValue)].contains(nsError.code)
    }
}

extension UpdateChecker: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Set()
    }

    // The check is over once Sparkle knows the answer, even while its own
    // update window stays open (the cycle only finishes when that closes).
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.hasUpdate = true
            self.latestVersion = item.displayVersionString
            self.isChecking = false
            self.lastCheckFailed = false
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.downloadingVersion = version
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        Task { @MainActor in
            self.downloadingVersion = nil
            self.isChecking = false
            self.lastCheckFailed = true
        }
    }

    /// The update is downloaded and prepared. Taking it over (returning
    /// true) keeps Sparkle's own window away: NotchTune shows "Restart to
    /// Update" and runs `immediateInstallHandler` when the user picks it, or
    /// when `UpdateAutoInstall` says so. Sparkle still installs on quit.
    ///
    /// Taking it over also leaves Sparkle's session open, so no later cycle
    /// runs until this one installs. Returning false wouldn't help: it
    /// withdraws the handler, and the next cycle only resumes this same
    /// prepared update (`SPUUpdater._checkForUpdatesInBackground` sees the
    /// installer running and never reads the feed) in Sparkle's window.
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        let version = item.displayVersionString
        nonisolated(unsafe) let install = immediateInstallHandler
        Task { @MainActor in
            self.updateBecameReady(version: version, install: install)
            self.downloadingVersion = nil
            self.isChecking = false
            self.lastCheckFailed = false
        }
        return true
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            self.hasUpdate = false
            self.latestVersion = nil
            self.isChecking = false
            self.lastCheckFailed = false
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let failed = Self.isFailedCheck(error)
        let wrongLocation = Self.isWrongLocation(error)
        Task { @MainActor in
            self.isChecking = false
            if failed { self.lastCheckFailed = true }
            if wrongLocation { self.needsMoveToApplications = true }
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        let failed = Self.isFailedCheck(error)
        let wrongLocation = Self.isWrongLocation(error)
        Task { @MainActor in
            self.isChecking = false
            self.lastCheckFailed = failed
            self.needsMoveToApplications = wrongLocation
            self.downloadingVersion = nil
            self.clearReadyUpdate()
            // Sparkle wants this read on the main thread.
            self.lastCheckDate = self.updaterController.updater.lastUpdateCheckDate
        }
    }
}

// Scheduled updates Sparkle can't take silently stay out of the user's way:
// automatic downloads off, or one it won't download alone. Settings shows
// them (`hasUpdate`), and `checkForUpdates()` brings up Sparkle's window.
extension UpdateChecker: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    /// Sparkle requires this once it's told not to show the update;
    /// `updater(_:didFindValidUpdate:)` already recorded it.
    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {}
}
