import AppKit
import NotchTuneCore
import SwiftUI
import UserNotifications

@MainActor
final class NotchTuneAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let harnessLaunchConfiguration = HarnessLaunchConfiguration()
    private let launchedAt = Date()
    private lazy var harnessRuntimeMonitor = HarnessRuntimeMonitor(launchedAt: launchedAt)

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Headless harness: hide SwiftUI's scene windows (the Settings scene
        // auto-opens at launch) before they ever draw on the user's screen.
        guard HarnessHeadless.isActive else { return }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { HarnessHeadless.parkAppWindows() }
        }
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            MainActor.assumeIsolated { HarnessHeadless.parkAppWindows() }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // UNUserNotificationCenter throws (bundleProxyForCurrentProcess is nil)
        // when the binary runs unbundled, e.g. `swift run` in the harness.
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            model.myspaceStore.restorePendingReminders()
        }
        model.updateChecker.startIfNeeded()
        ProcessInfo.processInfo.disableAutomaticTermination(
            "NotchTune should remain active while monitoring local agent sessions."
        )
        ProcessInfo.processInfo.disableSuddenTermination()
        NSApp.setActivationPolicy(model.showDockIcon ? .regular : .accessory)
        harnessRuntimeMonitor.recordMilestone("applicationDidFinishLaunching")

        DispatchQueue.main.async { [self] in
            harnessRuntimeMonitor.recordMilestone("bootstrapStarted")
            model.harnessRuntimeMonitor = harnessRuntimeMonitor
            harnessRuntimeMonitor.recordLog(model.lastActionMessage)

            model.ignoresPointerExitDuringHarness = harnessLaunchConfiguration.scenario != nil
            model.disablesOverlayEventMonitoringDuringHarness = harnessLaunchConfiguration.scenario != nil
            model.islandDensityHarnessOverride = harnessLaunchConfiguration.islandDensity
            model.startIfNeeded(
                startBridge: harnessLaunchConfiguration.shouldStartBridge,
                shouldPerformBootAnimation: harnessLaunchConfiguration.shouldPerformBootAnimation,
                loadRuntimeState: harnessLaunchConfiguration.scenario == nil
            )
            harnessRuntimeMonitor.recordMilestone("modelStarted")

            if harnessLaunchConfiguration.seedsSampleUsage {
                model.seedHarnessSampleUsage()
            }
            // `NOTCHTUNE_HARNESS_SETTINGS_TAB=<SettingsTab>` opens Settings on
            // that pane; `NOTCHTUNE_HARNESS_ONBOARDING_STEP=<0-6>` opens the
            // onboarding wizard on that step (Settings first: it registers
            // the window openers). The recorder then captures those windows.
            let env = ProcessInfo.processInfo.environment
            if HarnessHeadless.isActive,
               env["NOTCHTUNE_HARNESS_SETTINGS_TAB"] != nil || env["NOTCHTUNE_HARNESS_ONBOARDING_STEP"] != nil {
                // Headless: host the same views in windows born below the
                // desktop, so nothing ever appears on the user's screen.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [model] in
                    if let tab = env["NOTCHTUNE_HARNESS_SETTINGS_TAB"] {
                        // `NOTCHTUNE_HARNESS_SETTINGS_WIDTH=<pt>` sizes the window
                        // (e.g. 780, its minimum) to catch panes that overflow;
                        // `_HEIGHT=<pt>` shows a long pane whole.
                        let width = env["NOTCHTUNE_HARNESS_SETTINGS_WIDTH"].flatMap(Double.init) ?? 860
                        let height = env["NOTCHTUNE_HARNESS_SETTINGS_HEIGHT"].flatMap(Double.init) ?? 640
                        let window = HarnessHeadless.openHiddenWindow(
                            id: "harness-settings", title: "NotchTune Settings",
                            size: NSSize(width: width, height: height),
                            rootView: SettingsView(model: model)
                        )
                        if let backdrop = env["NOTCHTUNE_HARNESS_SETTINGS_BACKDROP"] {
                            HarnessHeadless.openBackdrop(behind: window, imagePath: backdrop)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(name: .notchTuneSelectSettingsTab, object: tab)
                        }
                    }
                    if let raw = env["NOTCHTUNE_HARNESS_ONBOARDING_STEP"], let index = Int(raw) {
                        // `NOTCHTUNE_HARNESS_ONBOARDING_HEIGHT=<pt>` shows a long
                        // step whole (the wizard's own window scrolls).
                        let height = env["NOTCHTUNE_HARNESS_ONBOARDING_HEIGHT"].flatMap(Double.init) ?? 610
                        let window = HarnessHeadless.openHiddenWindow(
                            id: "harness-onboarding", title: "Welcome to NotchTune",
                            size: NSSize(width: 760, height: height),
                            rootView: OnboardingView(model: model)
                        )
                        // `NOTCHTUNE_HARNESS_ONBOARDING_BACKDROP=<image>`: the
                        // wizard over a test wallpaper (`onboarding-desktop.png`).
                        if let backdrop = env["NOTCHTUNE_HARNESS_ONBOARDING_BACKDROP"] {
                            HarnessHeadless.openBackdrop(behind: window, imagePath: backdrop)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(name: .notchTuneSelectOnboardingStep, object: index)
                        }
                    }
                }
            } else if env["NOTCHTUNE_HARNESS_SETTINGS_TAB"] != nil || env["NOTCHTUNE_HARNESS_ONBOARDING_STEP"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [model] in
                    model.showSettings()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let tab = env["NOTCHTUNE_HARNESS_SETTINGS_TAB"] {
                            NotificationCenter.default.post(name: .notchTuneSelectSettingsTab, object: tab)
                        }
                        if let raw = env["NOTCHTUNE_HARNESS_ONBOARDING_STEP"], let index = Int(raw) {
                            model.showOnboarding()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                NotificationCenter.default.post(name: .notchTuneSelectOnboardingStep, object: index)
                            }
                        }
                    }
                }
            }

            // `NOTCHTUNE_HARNESS_SKIP_FEEDBACK=next|previous`: fire the swipe
            // arrows just before the capture.
            if let skip = ProcessInfo.processInfo.environment["NOTCHTUNE_HARNESS_SKIP_FEEDBACK"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [model] in
                    model.showMusicSkipFeedback(skip == "previous" ? .previous : .next)
                }
            }
            // `NOTCHTUNE_HARNESS_MUSIC_TOGGLE_AT=<seconds>`: flip the Music tab
            // between controls and library then (to capture the cross-fade).
            if let raw = ProcessInfo.processInfo.environment["NOTCHTUNE_HARNESS_MUSIC_TOGGLE_AT"],
               let delay = TimeInterval(raw) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    NotificationCenter.default.post(name: .notchTuneHarnessToggleMusicLibrary, object: nil)
                }
            }
            // `NOTCHTUNE_HARNESS_TRACK_NOTIFICATION=1`: present the track-change
            // notification a skip produces, just after the skip arrows.
            if ProcessInfo.processInfo.environment["NOTCHTUNE_HARNESS_TRACK_NOTIFICATION"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [model] in
                    model.presentMusicTrackNotification(track: model.playerManager.track)
                }
            }
            if harnessLaunchConfiguration.seedsSampleTrack {
                model.harnessMusicTintArt = AppModel.harnessSampleAlbumArt()
            }

            if let scenario = harnessLaunchConfiguration.scenario {
                model.loadDebugSnapshot(
                    scenario.snapshot(),
                    presentOverlay: harnessLaunchConfiguration.presentOverlay
                )
                if let tab = harnessLaunchConfiguration.tab {
                    model.islandActiveTab = tab
                }
                if scenario == .closedFinished, let id = model.selectedSessionID {
                    model.beginFinishedPeek(for: id)
                }
            }

            // Hide all windows on launch — settings opens on demand only.
            // Harness scenarios keep the overlay panel they just presented,
            // otherwise the capture finds no visible window to snapshot.
            if harnessLaunchConfiguration.scenario == nil {
                NotchTuneAppDelegate.hideAllAppWindows()
            }

            harnessRuntimeMonitor.recordMilestone("bootstrapCompleted")

            if let captureDelay = harnessLaunchConfiguration.captureDelay,
               harnessLaunchConfiguration.artifactDirectoryURL != nil {
                harnessRuntimeMonitor.recordMilestone(
                    "captureScheduled",
                    message: String(format: "%.3fs", captureDelay)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay) { [self] in
                    harnessRuntimeMonitor.recordMilestone("captureStarted")
                    try? HarnessArtifactRecorder.record(
                        configuration: harnessLaunchConfiguration,
                        model: model,
                        launchedAt: launchedAt,
                        runtimeMonitor: harnessRuntimeMonitor
                    )
                    if let directoryURL = harnessLaunchConfiguration.artifactDirectoryURL {
                        HarnessHeadless.parkAppWindows()
                        HarnessArtifactRecorder.recordAppWindows(to: directoryURL)
                    }
                    if let directoryURL = harnessLaunchConfiguration.artifactDirectoryURL {
                        switch ProcessInfo.processInfo.environment["NOTCHTUNE_HARNESS_FILMSTRIP"] {
                        case "1":
                            HarnessArtifactRecorder.recordFilmstrip(model: model, directoryURL: directoryURL)
                        case "music":
                            HarnessArtifactRecorder.recordMusicFadeFilmstrip(model: model, directoryURL: directoryURL)
                        case let mode? where mode.hasPrefix("settings:"):
                            HarnessArtifactRecorder.recordSettingsSwitchFilmstrip(
                                to: String(mode.dropFirst("settings:".count)),
                                directoryURL: directoryURL
                            )
                        default:
                            break
                        }
                    }
                }
            }

            if let autoExitAfter = harnessLaunchConfiguration.autoExitAfter {
                harnessRuntimeMonitor.recordMilestone(
                    "autoExitScheduled",
                    message: String(format: "%.3fs", autoExitAfter)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + autoExitAfter) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private static func hideAllAppWindows() {
        for window in NSApp.windows {
            window.orderOut(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showSettings()
        return false
    }
}

extension NotchTuneAppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier.hasPrefix(
            MyspaceReminderService.notificationPrefix
        ) else { return }

        await MainActor.run {
            model.islandActiveTab = .reminders
            model.notchOpen(reason: .click)
        }
    }
}

/// Entry point wrapper: legacy-install migration must complete before SwiftUI
/// instantiates the delegate (whose AppModel/MyspaceStore touch the support
/// directory and UserDefaults during init).
@main
enum NotchTuneMain {
    static func main() {
        LegacyInstallMigration.run()
        NotchTuneApp.main()
    }
}

struct NotchTuneApp: App {
    @NSApplicationDelegateAdaptor(NotchTuneAppDelegate.self)
    private var appDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("NotchTune Settings", id: "settings") {
            SettingsWindowContent(model: appDelegate.model)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 860, height: 640)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openWindow(id: "settings")
                    appDelegate.model.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("Welcome to NotchTune", id: "onboarding") {
            OnboardingView(model: appDelegate.model)
        }
        .windowResizability(.contentSize)
        // Sit low on screen so the real notch stays visible above the wizard —
        // the personalize step and the guided tour both preview up there.
        .defaultPosition(UnitPoint(x: 0.5, y: 0.82))
    }
}

/// Refreshes the `openWindow` registration each time the settings
/// window opens, keeping the closure current after window recreation.
private struct SettingsWindowContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsView(model: model)
            .onAppear {
                model.openSettingsWindow = { [openWindow] in
                    openWindow(id: "settings")
                }
                model.openOnboardingWindow = { [openWindow] in
                    openWindow(id: "onboarding")
                }
            }
    }
}
