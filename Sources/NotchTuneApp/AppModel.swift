import AppKit
import Foundation
import Observation
import NotchTuneCore
import SwiftUI

extension Notification.Name {
    /// Posted by `AppModel.showOnboarding()` to ask `SettingsView` to
    /// switch to the Setup tab. Lets the empty-state CTAs deliver the
    /// user to the right place without `SettingsView`'s `@State` having
    /// to leak into `AppModel`.
    static let notchTuneSelectSetupTab = Notification.Name("notchTuneSelectSetupTab")
}

@MainActor
@Observable
final class AppModel {
    private static let soundMutedDefaultsKey = "overlay.sound.muted"
    private static let showDockIconDefaultsKey = "app.showDockIcon"
    private static let hapticFeedbackEnabledDefaultsKey = "app.hapticFeedbackEnabled"
    private static let islandRightSlotDefaultsKey = "appearance.island.v6.rightSlot"
    private static let islandCenterLabelDefaultsKey = "appearance.island.v6.centerLabel"
    private static let showCodexUsageDefaultsKey = "app.showCodexUsage"
    private static let completionReplyEnabledDefaultsKey = "feature.completionReply.enabled"
    private static let suppressFrontmostNotificationsDefaultsKey = "app.suppressFrontmostNotifications"
    private static let legacyIslandSessionStateIndicatorDefaultsKey = "appearance.island.v8.stateIndicator"
    private static let legacyIslandSessionGroupDefaultsKey = "appearance.island.v8.sessionGroup"
    private static let legacyIslandSessionSortDefaultsKey = "appearance.island.v8.sessionSort"
    private static let legacyCompletedStaleThresholdDefaultsKey = "appearance.island.v8.completedStaleThreshold"
    private static let appearanceProfileSettingsDefaultsKey = "appearance.island.v8.settingsProfile"
    private static let glassEnabledKey = "appearance.glass.enabled"
    private static let glassStyleKey = "appearance.glass.style"
    private static let glassTintRedKey = "appearance.glass.tint.r"
    private static let glassTintGreenKey = "appearance.glass.tint.g"
    private static let glassTintBlueKey = "appearance.glass.tint.b"
    private static let glassTintStrengthKey = "appearance.glass.tint.strength"
    private static let glassOpenViewKey = "appearance.glass.openView"
    private static let glassClosedScopeKey = "appearance.glass.closedScope"
    private static let nudgeEnabledKey = "feature.nudge.enabled"
    private static let nudgeThresholdKey = "feature.nudge.threshold"

    private static let syntheticClaudeSessionPrefix = "claude-process:"
    private static let liveSessionStalenessWindow: TimeInterval = 15 * 60
    private static let jumpOverlayDismissLeadTime: Duration = .milliseconds(20)
    private static let agentsGridObservedSequenceLimit = 512
    static let hoverOpenDelay: TimeInterval = 0.15

    struct AcceptanceStep: Identifiable {
        let id: String
        let title: String
        let detail: String
        let isComplete: Bool
    }

    let lang = LanguageManager.shared

    var state = SessionState() {
        didSet {
            _cachedSessionBuckets = nil
            pruneAgentsGridObservationTicketsIfNeeded()
            bridgeServer.updateStateSnapshot(state)
        }
    }
    @ObservationIgnored private var _cachedSessionBuckets: (primary: [AgentSession], overflow: [AgentSession])?

    /// Monotonic ticket assigned the first time a session ID shows up in the
    /// closed-island's right-slot surfaced set. Drives the grid's display
    /// order: newly-surfaced sessions always land at the end, and a session
    /// that briefly leaves (e.g. attachment flip) keeps its old slot when it
    /// returns. Persists for the process lifetime; session IDs are UUIDs so
    /// accumulation over time is bounded in practice.
    @ObservationIgnored private var _agentsGridObservedSequence: [String: Int] = [:]
    @ObservationIgnored private var _agentsGridNextTicket: Int = 0
    var selectedSessionID: String?
    var islandActiveTab: IslandTab = .agents {
        didSet {
            if islandActiveTab != oldValue {
                DispatchQueue.main.async { [weak self] in
                    self?.refreshOverlayPlacementIfVisible()
                }
            }
        }
    }
    let hooks = HookInstallationCoordinator()
    let overlay = OverlayUICoordinator()
    let tour = OnboardingTourController()
    let discovery = SessionDiscoveryCoordinator()
    let monitoring = ProcessMonitoringCoordinator()
    let codexAppServer = CodexAppServerCoordinator()
    let playerManager = MusicPlayerManager()
    let myspaceStore = MyspaceStore()
    let updateChecker = UpdateChecker()

    var notchStatus: NotchStatus {
        get { overlay.notchStatus }
        set { overlay.notchStatus = newValue }
    }
    var notchOpenReason: NotchOpenReason? {
        get { overlay.notchOpenReason }
        set { overlay.notchOpenReason = newValue }
    }
    var islandSurface: IslandSurface {
        get { overlay.islandSurface }
        set { overlay.islandSurface = newValue }
    }
    var isOverlayVisible: Bool { overlay.isOverlayVisible }
    var isOverlayCloseTransitionPending: Bool { overlay.isCloseTransitionPending }
    var isCodexSetupBusy: Bool { hooks.isCodexSetupBusy }
    var isClaudeHookSetupBusy: Bool { hooks.isClaudeHookSetupBusy }
    var isClaudeUsageSetupBusy: Bool { hooks.isClaudeUsageSetupBusy }
    var codexHookStatus: CodexHookInstallationStatus? { hooks.codexHookStatus }
    var claudeHookStatus: ClaudeHookInstallationStatus? { hooks.claudeHookStatus }
    var claudeStatusLineStatus: ClaudeStatusLineInstallationStatus? { hooks.claudeStatusLineStatus }
    var claudeUsageSnapshot: ClaudeUsageSnapshot? { hooks.claudeUsageSnapshot }
    var codexUsageSnapshot: CodexUsageSnapshot? { hooks.codexUsageSnapshot }
    var geminiUsageSnapshot: GeminiUsageSnapshot? { hooks.geminiUsageSnapshot }
    var hooksBinaryURL: URL? { hooks.hooksBinaryURL }
    var codexHooksInstalled: Bool { hooks.codexHooksInstalled }
    var claudeHooksInstalled: Bool { hooks.claudeHooksInstalled }
    var qoderHooksInstalled: Bool { hooks.qoderHooksInstalled }
    var qwenCodeHooksInstalled: Bool { hooks.qwenCodeHooksInstalled }
    var factoryHooksInstalled: Bool { hooks.factoryHooksInstalled }
    var codebuddyHooksInstalled: Bool { hooks.codebuddyHooksInstalled }
    var qoderHookStatus: ClaudeHookInstallationStatus? { hooks.qoderHookStatus }
    var qwenCodeHookStatus: ClaudeHookInstallationStatus? { hooks.qwenCodeHookStatus }
    var factoryHookStatus: ClaudeHookInstallationStatus? { hooks.factoryHookStatus }
    var codebuddyHookStatus: ClaudeHookInstallationStatus? { hooks.codebuddyHookStatus }
    var isQoderHookSetupBusy: Bool { hooks.isQoderHookSetupBusy }
    var isQwenCodeHookSetupBusy: Bool { hooks.isQwenCodeHookSetupBusy }
    var isFactoryHookSetupBusy: Bool { hooks.isFactoryHookSetupBusy }
    var isCodebuddyHookSetupBusy: Bool { hooks.isCodebuddyHookSetupBusy }
    var openCodePluginInstalled: Bool { hooks.openCodePluginInstalled }
    var claudeUsageInstalled: Bool { hooks.claudeUsageInstalled }
    var claudeHookStatusTitle: String { hooks.claudeHookStatusTitle }
    var claudeHookStatusSummary: String { hooks.claudeHookStatusSummary }
    var claudeUsageStatusTitle: String { hooks.claudeUsageStatusTitle }
    var claudeUsageStatusSummary: String { hooks.claudeUsageStatusSummary }
    var claudeUsageSummaryText: String? { hooks.claudeUsageSummaryText }
    var codexUsageStatusTitle: String { hooks.codexUsageStatusTitle }
    var codexUsageStatusSummary: String { hooks.codexUsageStatusSummary }
    var codexUsageSummaryText: String? { hooks.codexUsageSummaryText }
    var openCodePluginStatus: OpenCodePluginInstallationStatus? { hooks.openCodePluginStatus }
    var isOpenCodeSetupBusy: Bool { hooks.isOpenCodeSetupBusy }
    var openCodePluginStatusTitle: String { hooks.openCodePluginStatusTitle }
    var openCodePluginStatusSummary: String { hooks.openCodePluginStatusSummary }
    var claudeHealthReport: HookHealthReport? { hooks.claudeHealthReport }
    var codexHealthReport: HookHealthReport? { hooks.codexHealthReport }
    var cursorHooksInstalled: Bool { hooks.cursorHooksInstalled }
    var isCursorHookSetupBusy: Bool { hooks.isCursorHookSetupBusy }
    var cursorHookStatus: CursorHookInstallationStatus? { hooks.cursorHookStatus }
    var cursorHookStatusTitle: String { hooks.cursorHookStatusTitle }
    var cursorHookStatusSummary: String { hooks.cursorHookStatusSummary }
    var geminiHooksInstalled: Bool { hooks.geminiHooksInstalled }
    var isGeminiHookSetupBusy: Bool { hooks.isGeminiHookSetupBusy }
    var geminiHookStatus: GeminiHookInstallationStatus? { hooks.geminiHookStatus }
    var antigravityHooksInstalled: Bool { hooks.antigravityHooksInstalled }
    var isAntigravityHookSetupBusy: Bool { hooks.isAntigravityHookSetupBusy }
    var antigravityHookStatus: AntigravityHookInstallationStatus? { hooks.antigravityHookStatus }
    var geminiHookStatusTitle: String { hooks.geminiHookStatusTitle }
    var geminiHookStatusSummary: String { hooks.geminiHookStatusSummary }
    var kimiHooksInstalled: Bool { hooks.kimiHooksInstalled }
    var isKimiHookSetupBusy: Bool { hooks.isKimiHookSetupBusy }
    var kimiHookStatus: KimiHookInstallationStatus? { hooks.kimiHookStatus }
    var kimiHookStatusTitle: String { hooks.kimiHookStatusTitle }
    var kimiHookStatusSummary: String { hooks.kimiHookStatusSummary }
    var codexHookStatusTitle: String { hooks.codexHookStatusTitle }
    var codexHookStatusSummary: String { hooks.codexHookStatusSummary }

    /// Mirrors `AgentIntentStore.firstLaunchCompleted`. Onboarding sets this
    /// to true after the user completes (or explicitly skips) the flow;
    /// legacy migration also flips it for users upgrading with existing
    /// hooks.
    var firstLaunchCompleted: Bool {
        get { hooks.intentStore.firstLaunchCompleted }
        set { hooks.intentStore.firstLaunchCompleted = newValue }
    }

    /// Mirrors `AgentIntentStore.onboardingWizardStage` (monotonic resume point).
    var onboardingWizardStage: Int {
        get { hooks.intentStore.onboardingWizardStage }
        set { hooks.intentStore.onboardingWizardStage = newValue }
    }

    /// Mirrors `AgentIntentStore.onboardingTourOutcome`.
    var onboardingTourOutcome: AgentIntentStore.OnboardingTourOutcome? {
        get { hooks.intentStore.onboardingTourOutcome }
        set { hooks.intentStore.onboardingTourOutcome = newValue }
    }

    /// True if at least one managed hook is currently present on disk.
    /// Drives the "configure agents" empty-state prompts in the island and
    /// the settings window.
    var hasAnyInstalledAgent: Bool {
        hooks.claudeHooksInstalled
            || hooks.codexHooksInstalled
            || hooks.cursorHooksInstalled
            || hooks.qoderHooksInstalled
            || hooks.qwenCodeHooksInstalled
            || hooks.factoryHooksInstalled
            || hooks.codebuddyHooksInstalled
            || hooks.openCodePluginInstalled
            || hooks.geminiHooksInstalled
            || hooks.kimiHooksInstalled
    }
    func refreshCodexHookStatus() { hooks.refreshCodexHookStatus() }
    func refreshClaudeHookStatus() { hooks.refreshClaudeHookStatus() }
    func refreshOpenCodePluginStatus() { hooks.refreshOpenCodePluginStatus() }
    func refreshCursorHookStatus() { hooks.refreshCursorHookStatus() }
    func refreshClaudeUsageState() { hooks.refreshClaudeUsageState() }
    func refreshCodexUsageState() { hooks.refreshCodexUsageState() }
    func installCodexHooks() { hooks.installCodexHooks() }
    func uninstallCodexHooks() { hooks.uninstallCodexHooks() }
    func installClaudeHooks() { hooks.installClaudeHooks() }
    func uninstallClaudeHooks() { hooks.uninstallClaudeHooks() }
    func installQoderHooks() { hooks.installQoderHooks() }
    func uninstallQoderHooks() { hooks.uninstallQoderHooks() }
    func installQwenCodeHooks() { hooks.installQwenCodeHooks() }
    func uninstallQwenCodeHooks() { hooks.uninstallQwenCodeHooks() }
    func installFactoryHooks() { hooks.installFactoryHooks() }
    func uninstallFactoryHooks() { hooks.uninstallFactoryHooks() }
    func installCodebuddyHooks() { hooks.installCodebuddyHooks() }
    func uninstallCodebuddyHooks() { hooks.uninstallCodebuddyHooks() }
    func refreshCCForkHookStatuses() { hooks.refreshCCForkHookStatuses() }
    func installOpenCodePlugin() { hooks.installOpenCodePlugin() }
    func uninstallOpenCodePlugin() { hooks.uninstallOpenCodePlugin() }
    func installCursorHooks() { hooks.installCursorHooks() }
    func uninstallCursorHooks() { hooks.uninstallCursorHooks() }
    func installGeminiHooks() { hooks.installGeminiHooks() }
    func uninstallGeminiHooks() { hooks.uninstallGeminiHooks() }
    func installAntigravityHooks() { hooks.installAntigravityHooks() }
    func uninstallAntigravityHooks() { hooks.uninstallAntigravityHooks() }
    func refreshKimiHookStatus() { hooks.refreshKimiHookStatus() }
    func installKimiHooks() { hooks.installKimiHooks() }
    func uninstallKimiHooks() { hooks.uninstallKimiHooks() }
    func installClaudeUsageBridge() { hooks.installClaudeUsageBridge() }
    func uninstallClaudeUsageBridge() { hooks.uninstallClaudeUsageBridge() }
    func updateClaudeConfigDirectory(to newDirectory: URL?) { hooks.updateClaudeConfigDirectory(to: newDirectory) }
    func runHealthChecks() { hooks.runHealthChecks() }
    func repairHooks() {
        Task { @MainActor in
            await hooks.repairHooksIfNeeded()
        }
    }
    var isBridgeReady = false
    var lastActionMessage = "Waiting for agent hook events..." {
        didSet {
            guard lastActionMessage != oldValue else {
                return
            }

            harnessRuntimeMonitor?.recordLog(lastActionMessage)
        }
    }
    var isResolvingInitialLiveSessions: Bool {
        get { monitoring.isResolvingInitialLiveSessions }
        set { monitoring.isResolvingInitialLiveSessions = newValue }
    }
    var overlayDisplayOptions: [OverlayDisplayOption] {
        get { overlay.overlayDisplayOptions }
        set { overlay.overlayDisplayOptions = newValue }
    }
    var overlayPlacementDiagnostics: OverlayPlacementDiagnostics? {
        get { overlay.overlayPlacementDiagnostics }
        set { overlay.overlayPlacementDiagnostics = newValue }
    }
    var showDockIcon: Bool = false {
        didSet {
            guard hasFinishedInit, showDockIcon != oldValue else { return }
            UserDefaults.standard.set(showDockIcon, forKey: Self.showDockIconDefaultsKey)
            NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
            if !showDockIcon {
                // macOS does not immediately refresh the Dock when switching to
                // .accessory at runtime. Briefly activating another app forces
                // the Dock to drop the icon.
                NSApp.hide(nil)
                DispatchQueue.main.async {
                    NSApp.unhide(nil)
                }
            }
        }
    }
    var hapticFeedbackEnabled: Bool = false {
        didSet {
            guard hasFinishedInit, hapticFeedbackEnabled != oldValue else { return }
            UserDefaults.standard.set(hapticFeedbackEnabled, forKey: Self.hapticFeedbackEnabledDefaultsKey)
        }
    }
    var showCodexUsage: Bool = false {
        didSet {
            guard hasFinishedInit, showCodexUsage != oldValue else { return }
            UserDefaults.standard.set(showCodexUsage, forKey: Self.showCodexUsageDefaultsKey)
        }
    }
    var completionReplyEnabled: Bool = false {
        didSet {
            guard hasFinishedInit, completionReplyEnabled != oldValue else { return }
            UserDefaults.standard.set(completionReplyEnabled, forKey: Self.completionReplyEnabledDefaultsKey)
            refreshOverlayPlacementIfVisible()
        }
    }
    var suppressFrontmostNotifications: Bool = true {
        didSet {
            guard hasFinishedInit, suppressFrontmostNotifications != oldValue else { return }
            UserDefaults.standard.set(suppressFrontmostNotifications, forKey: Self.suppressFrontmostNotificationsDefaultsKey)
        }
    }
    var launchAtLoginEnabled: Bool = false {
        didSet {
            guard !isApplyingLaunchAtLogin, hasFinishedInit, launchAtLoginEnabled != oldValue else { return }
            do {
                try LaunchAtLoginService.shared.setEnabled(launchAtLoginEnabled)
            } catch {
                isApplyingLaunchAtLogin = true
                launchAtLoginEnabled = oldValue
                isApplyingLaunchAtLogin = false
                presentLaunchAtLoginError(error)
            }
        }
    }
    private func presentLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = lang.t("settings.general.launchAtLogin")
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
    @ObservationIgnored
    private var isApplyingLaunchAtLogin = false

    /// Configurable Liquid Glass appearance for the island surfaces. Persisted
    /// globally; see `LiquidGlassSettings`.
    var glassSettings = LiquidGlassSettings() {
        didSet {
            guard glassSettings != oldValue else { return }
            persistGlassSettings(glassSettings)
        }
    }

    /// Idle-session nudge configuration; persisted. See `NudgeSettings`.
    var nudgeSettings = NudgeSettings() {
        didSet {
            guard nudgeSettings != oldValue else { return }
            persistNudgeSettings(nudgeSettings)
            if nudgeSettings.isEnabled && !oldValue.isEnabled {
                armNudgesForWaitingSessions()
            } else if !nudgeSettings.isEnabled {
                cancelAllNudges()
            }
        }
    }

    /// Per-session pending nudge timers, keyed by session id.
    @ObservationIgnored private var nudgeTimers: [String: Task<Void, Never>] = [:]

    /// Per-session debounce that settles an Antigravity session to idle once its
    /// tool-call hooks stop arriving. Antigravity emits only `PreToolUse` /
    /// `PostToolUse` hooks (no turn- or session-end event), so without this the
    /// notch could never tell "actively working" from "done". Keyed by session id.
    @ObservationIgnored private var antigravitySettleTimers: [String: Task<Void, Never>] = [:]

    /// Coalesces bump-worthy agent events (approvals, questions, completions)
    /// so a burst of Codex turns yields one notch open + sound, not five.
    /// Pure logic lives in `NotificationCoalescer`; the settle timers it asks
    /// for live here, keyed by notification group.
    @ObservationIgnored private var notificationCoalescer = NotificationCoalescer()
    @ObservationIgnored private var completionSettleTimers: [NotificationGroupKey: Task<Void, Never>] = [:]

    /// Windows for notification coalescing. Settable so tests can shrink the
    /// settle window; a future settings round can back this with defaults.
    var notificationCoalescingPolicy: NotificationCoalescingPolicy {
        get { notificationCoalescer.policy }
        set {
            notificationCoalescer.policy = newValue
            notificationCoalescer.reset()
            cancelAllCompletionSettleTimers()
        }
    }

    /// Bumped to fire a one-shot character jump when an idle session is nudged.
    var nudgeTrigger: UUID?

    /// A file drag is hovering NEAR the closed notch (approach zone). The pill
    /// grows slightly to hint it can catch the file; it does not open until the
    /// drag reaches the notch itself.
    var isFileDragHintReady = false

    /// When each waiting session entered its attention phase, anchored so the
    /// "Waiting Xm Ys" display doesn't reset if `updatedAt` bumps mid-wait.
    var attentionStartedAt: [String: Date] = [:]

    var isSoundMuted = false {
        didSet {
            guard isSoundMuted != oldValue else {
                return
            }

            UserDefaults.standard.set(isSoundMuted, forKey: Self.soundMutedDefaultsKey)
            lastActionMessage = isSoundMuted
                ? "Island sound notifications muted."
                : "Island sound notifications enabled."
        }
    }
    var selectedSoundName: String = NotificationSoundService.defaultSoundName {
        didSet {
            guard selectedSoundName != oldValue else { return }
            NotificationSoundService.selectedSoundName = selectedSoundName
        }
    }
    var selectedNudgeSoundName: String = NotificationSoundService.defaultSoundName(for: .nudge) {
        didSet {
            guard selectedNudgeSoundName != oldValue else { return }
            NotificationSoundService.setSelectedSoundName(selectedNudgeSoundName, for: .nudge)
        }
    }
    var overlayDisplaySelectionID: String {
        get { overlay.overlayDisplaySelectionID }
        set { overlay.overlayDisplaySelectionID = newValue }
    }

    // MARK: - Appearance

    var appearanceSettingsProfile: IslandAppearanceDisplayProfile = .topBar {
        didSet {
            guard appearanceSettingsProfile != oldValue else { return }
            UserDefaults.standard.set(appearanceSettingsProfile.rawValue, forKey: Self.appearanceProfileSettingsDefaultsKey)
        }
    }

    private var notchAppearancePreferences = IslandAppearancePreferences() {
        didSet {
            guard notchAppearancePreferences != oldValue else { return }
            persistAppearancePreferences(notchAppearancePreferences, for: .notch)
            if activeAppearanceProfile == .notch { appearancePreferencesDidChange(oldValue: oldValue, newValue: notchAppearancePreferences) }
        }
    }

    private var topBarAppearancePreferences = IslandAppearancePreferences() {
        didSet {
            guard topBarAppearancePreferences != oldValue else { return }
            persistAppearancePreferences(topBarAppearancePreferences, for: .topBar)
            if activeAppearanceProfile == .topBar { appearancePreferencesDidChange(oldValue: oldValue, newValue: topBarAppearancePreferences) }
        }
    }

    /// Runtime profile selected from current overlay placement. External
    /// displays use the top-bar presentation; built-in notch displays keep
    /// notch-aware geometry and their own persisted appearance choices.
    var activeAppearanceProfile: IslandAppearanceDisplayProfile {
        overlayPlacementDiagnostics?.mode == .notch ? .notch : .topBar
    }

    var islandRightSlot: IslandRightSlot {
        get { appearancePreferences(for: activeAppearanceProfile).rightSlot }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.rightSlot = newValue } }
    }

    var islandCenterLabel: IslandCenterLabel {
        get { appearancePreferences(for: activeAppearanceProfile).centerLabel }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.centerLabel = newValue } }
    }

    var islandCharacter: IslandCharacter {
        get { appearancePreferences(for: activeAppearanceProfile).character }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.character = newValue } }
    }

    /// Closed-island density for the active display profile. The harness can
    /// pin it per run (`NOTCHTUNE_HARNESS_ISLAND_DENSITY`) without touching the
    /// persisted preference.
    var islandDensity: IslandDensity {
        get { islandDensityHarnessOverride ?? appearancePreferences(for: activeAppearanceProfile).density }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.density = newValue } }
    }

    @ObservationIgnored
    var islandDensityHarnessOverride: IslandDensity?

    // MARK: - Live activity (widened closed pill)

    /// When the closed pill widens to carry text, for the active display profile.
    var islandLiveActivityMode: IslandLiveActivityMode {
        get { appearancePreferences(for: activeAppearanceProfile).liveActivity }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.liveActivity = newValue } }
    }

    /// When each session most recently went from not-running to running, so
    /// the working pill's timer counts the current turn, not the session.
    private(set) var runningSince: [String: Date] = [:]

    /// Session whose "finished" peek is on the pill right now, if any.
    private(set) var finishedPeekSessionID: String?

    /// What the closed pill should say, or nil to stay narrow.
    var islandLiveActivity: IslandLiveActivity? {
        IslandLiveActivity.resolve(
            mode: islandLiveActivityMode,
            sessions: surfacedSessions,
            finishedPeekSessionID: finishedPeekSessionID,
            runningSince: runningSince,
            attentionSince: attentionStartedAt
        )
    }

    /// Width the view actually drew for the closed pill; the controller uses it
    /// so the hover / click area follows the widened live-activity pill.
    @ObservationIgnored
    var measuredClosedSurfaceWidth: CGFloat = 0

    func noteRunningTransition(sessionID: String, from priorPhase: SessionPhase?, at date: Date = .now) {
        let phase = state.session(id: sessionID)?.phase
        if phase == .running {
            if priorPhase != .running || runningSince[sessionID] == nil {
                runningSince[sessionID] = date
            }
        } else if phase != nil {
            runningSince[sessionID] = nil
        }
    }

    /// Shows "<Agent> finished" on the pill for a few seconds and makes the
    /// character hop. Replaces any earlier peek.
    func beginFinishedPeek(for sessionID: String) {
        guard islandLiveActivityMode != .off else { return }
        finishedPeekSessionID = sessionID
        nudgeTrigger = UUID()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(IslandLiveActivity.finishedPeekDuration))
            guard let self, self.finishedPeekSessionID == sessionID else { return }
            self.finishedPeekSessionID = nil
        }
    }

    var islandUsageDisplay: IslandUsageDisplay {
        get { appearancePreferences(for: activeAppearanceProfile).usageDisplay }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.usageDisplay = newValue } }
    }

    var islandSessionStateIndicator: IslandSessionStateIndicator {
        get { appearancePreferences(for: activeAppearanceProfile).sessionStateIndicator }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.sessionStateIndicator = newValue } }
    }

    var islandSessionGroup: IslandSessionGroup {
        get { appearancePreferences(for: activeAppearanceProfile).sessionGroup }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.sessionGroup = newValue } }
    }

    var islandSessionSort: IslandSessionSort {
        get { appearancePreferences(for: activeAppearanceProfile).sessionSort }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.sessionSort = newValue } }
    }

    var completedStaleThreshold: IslandCompletedStaleThreshold {
        get { appearancePreferences(for: activeAppearanceProfile).completedStaleThreshold }
        set { updateAppearancePreferences(for: activeAppearanceProfile) { $0.completedStaleThreshold = newValue } }
    }

    @ObservationIgnored
    var openSettingsWindow: (() -> Void)?

    @ObservationIgnored
    var openOnboardingWindow: (() -> Void)?

    @ObservationIgnored
    private var hasFinishedInit = false

    func appearancePreferences(for profile: IslandAppearanceDisplayProfile) -> IslandAppearancePreferences {
        switch profile {
        case .notch: notchAppearancePreferences
        case .topBar: topBarAppearancePreferences
        }
    }

    func updateAppearancePreferences(
        for profile: IslandAppearanceDisplayProfile,
        _ update: (inout IslandAppearancePreferences) -> Void
    ) {
        switch profile {
        case .notch:
            update(&notchAppearancePreferences)
        case .topBar:
            update(&topBarAppearancePreferences)
        }
    }

    private func appearancePreferencesDidChange(
        oldValue: IslandAppearancePreferences,
        newValue: IslandAppearancePreferences
    ) {
        if oldValue.sessionGroup != newValue.sessionGroup ||
            oldValue.sessionSort != newValue.sessionSort ||
            oldValue.completedStaleThreshold != newValue.completedStaleThreshold {
            _cachedSessionBuckets = nil
        }
        refreshOverlayPlacementIfVisible()
    }

    private func persistAppearancePreferences(
        _ preferences: IslandAppearancePreferences,
        for profile: IslandAppearanceDisplayProfile
    ) {
        let defaults = UserDefaults.standard
        defaults.set(preferences.rightSlot.rawValue, forKey: Self.appearanceDefaultsKey(profile, "rightSlot"))
        defaults.set(preferences.centerLabel.rawValue, forKey: Self.appearanceDefaultsKey(profile, "centerLabel"))
        defaults.set(preferences.character.rawValue, forKey: Self.appearanceDefaultsKey(profile, "character"))
        defaults.set(preferences.colorByAgent, forKey: Self.appearanceDefaultsKey(profile, "colorByAgent"))
        defaults.set(preferences.density.rawValue, forKey: Self.appearanceDefaultsKey(profile, "density"))
        defaults.set(preferences.liveActivity.rawValue, forKey: Self.appearanceDefaultsKey(profile, "liveActivity"))
        defaults.set(preferences.autoHideWhenInactive, forKey: Self.appearanceDefaultsKey(profile, "autoHideWhenInactive"))
        defaults.set(preferences.usageDisplay.rawValue, forKey: Self.appearanceDefaultsKey(profile, "usageDisplay"))
        defaults.set(preferences.sessionStateIndicator.rawValue, forKey: Self.appearanceDefaultsKey(profile, "stateIndicator"))
        defaults.set(preferences.sessionGroup.rawValue, forKey: Self.appearanceDefaultsKey(profile, "sessionGroup"))
        defaults.set(preferences.sessionSort.rawValue, forKey: Self.appearanceDefaultsKey(profile, "sessionSort"))
        defaults.set(preferences.completedStaleThreshold.rawValue, forKey: Self.appearanceDefaultsKey(profile, "completedStaleThreshold"))
    }

    // MARK: - Watch Notification

    private static let watchNotificationEnabledKey = "watch.notification.enabled"

    var watchNotificationEnabled: Bool = false {
        didSet {
            guard watchNotificationEnabled != oldValue else { return }
            UserDefaults.standard.set(watchNotificationEnabled, forKey: Self.watchNotificationEnabledKey)
            if watchNotificationEnabled {
                startWatchRelay()
            } else {
                stopWatchRelay()
            }
        }
    }

    @ObservationIgnored
    private(set) var watchRelay: WatchNotificationRelay?

    /// Current pairing code for display in the settings UI.
    var watchPairingCode: String {
        watchRelay?.endpoint.currentCode() ?? "----"
    }

    /// Number of currently connected iPhone SSE clients.
    var watchConnectedDevices: Int {
        // Placeholder — endpoint doesn't expose count yet
        0
    }

    private func startWatchRelay() {
        guard watchRelay == nil else { return }
        let relay = WatchNotificationRelay()
        setupWatchRelayCallbacks(relay)
        relay.start()
        self.watchRelay = relay
    }

    /// Wire up resolution callbacks so Watch/iPhone actions flow back to the bridge.
    private func setupWatchRelayCallbacks(_ relay: WatchNotificationRelay) {
        relay.onResolvePermission = { [weak self] sessionID, approved in
            Task { @MainActor [weak self] in
                self?.approvePermission(for: sessionID, approved: approved)
            }
        }

        relay.onAnswerQuestion = { [weak self] sessionID, answer in
            Task { @MainActor [weak self] in
                self?.answerQuestion(
                    for: sessionID,
                    answer: QuestionPromptResponse(answer: answer)
                )
            }
        }

        relay.endpoint.activeSessionCountProvider = { [weak self] in
            // Safe to call from any queue — reads a snapshot count.
            guard let self else { return 0 }
            return MainActor.assumeIsolated {
                self.state.sessions.count
            }
        }
    }

    private func stopWatchRelay() {
        watchRelay?.stop()
        watchRelay = nil
    }

    var ignoresPointerExitDuringHarness = false
    var disablesOverlayEventMonitoringDuringHarness = false

    @ObservationIgnored
    private var bridgeTask: Task<Void, Never>?

    @ObservationIgnored
    private var bridgeReconnectTask: Task<Void, Never>?

    @ObservationIgnored
    private var hasStarted = false

    @ObservationIgnored
    private let bridgeServer = BridgeServer()

    @ObservationIgnored
    private var bridgeClient = LocalBridgeClient()

    @ObservationIgnored
    private let terminalJumpAction: @Sendable (JumpTarget) throws -> String

    @ObservationIgnored
    private let isNotificationSessionAlreadyFrontmost: @Sendable (AgentSession) async -> Bool

    @ObservationIgnored
    private let frontmostBundleIdentifierProvider: @Sendable () -> String?


    @ObservationIgnored
    var harnessRuntimeMonitor: HarnessRuntimeMonitor? {
        didSet {
            overlay.harnessRuntimeMonitor = harnessRuntimeMonitor
        }
    }


    @ObservationIgnored
    private var jumpTask: Task<Void, Never>?

    @ObservationIgnored
    private var notificationPresentationTask: Task<Void, Never>?

    private static func appearanceDefaultsKey(_ profile: IslandAppearanceDisplayProfile, _ name: String) -> String {
        "appearance.island.v8.\(profile.rawValue).\(name)"
    }

    private static func loadAppearancePreferences(for profile: IslandAppearanceDisplayProfile) -> IslandAppearancePreferences {
        let defaults = UserDefaults.standard
        return IslandAppearancePreferences(
            rightSlot: IslandRightSlot(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "rightSlot"))
                    ?? defaults.string(forKey: islandRightSlotDefaultsKey)
                    ?? ""
            ) ?? .count,
            centerLabel: IslandCenterLabel(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "centerLabel"))
                    ?? defaults.string(forKey: islandCenterLabelDefaultsKey)
                    ?? ""
            ) ?? .agentAction,
            character: IslandCharacter(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "character"))
                    ?? ""
            ) ?? .dino,
            colorByAgent: defaults.bool(forKey: appearanceDefaultsKey(profile, "colorByAgent")),
            density: IslandDensity(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "density"))
                    ?? ""
            ) ?? .regular,
            liveActivity: IslandLiveActivityMode(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "liveActivity"))
                    ?? ""
            ) ?? .active,
            autoHideWhenInactive: defaults.bool(forKey: appearanceDefaultsKey(profile, "autoHideWhenInactive")),
            usageDisplay: IslandUsageDisplay(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "usageDisplay"))
                    ?? ""
            ) ?? .compact,
            sessionStateIndicator: IslandSessionStateIndicator(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "stateIndicator"))
                    ?? defaults.string(forKey: legacyIslandSessionStateIndicatorDefaultsKey)
                    ?? ""
            ) ?? .animatedDot,
            sessionGroup: IslandSessionGroup(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "sessionGroup"))
                    ?? defaults.string(forKey: legacyIslandSessionGroupDefaultsKey)
                    ?? ""
            ) ?? .none,
            sessionSort: IslandSessionSort(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "sessionSort"))
                    ?? defaults.string(forKey: legacyIslandSessionSortDefaultsKey)
                    ?? ""
            ) ?? .attention,
            completedStaleThreshold: IslandCompletedStaleThreshold(
                rawValue: defaults.string(forKey: appearanceDefaultsKey(profile, "completedStaleThreshold"))
                    ?? defaults.string(forKey: legacyCompletedStaleThresholdDefaultsKey)
                    ?? ""
            ) ?? .fiveMinutes
        )
    }

    private func persistGlassSettings(_ s: LiquidGlassSettings) {
        let d = UserDefaults.standard
        d.set(s.isEnabled, forKey: Self.glassEnabledKey)
        d.set(s.style.rawValue, forKey: Self.glassStyleKey)
        d.set(s.tintRed, forKey: Self.glassTintRedKey)
        d.set(s.tintGreen, forKey: Self.glassTintGreenKey)
        d.set(s.tintBlue, forKey: Self.glassTintBlueKey)
        d.set(s.tintStrength, forKey: Self.glassTintStrengthKey)
        d.set(s.openView, forKey: Self.glassOpenViewKey)
        d.set(s.closedScope.rawValue, forKey: Self.glassClosedScopeKey)
    }

    private static func loadGlassSettings() -> LiquidGlassSettings {
        let d = UserDefaults.standard
        var s = LiquidGlassSettings()
        if d.object(forKey: glassEnabledKey) != nil { s.isEnabled = d.bool(forKey: glassEnabledKey) }
        if let raw = d.string(forKey: glassStyleKey), let style = GlassStyle(rawValue: raw) { s.style = style }
        if d.object(forKey: glassTintRedKey) != nil { s.tintRed = d.double(forKey: glassTintRedKey) }
        if d.object(forKey: glassTintGreenKey) != nil { s.tintGreen = d.double(forKey: glassTintGreenKey) }
        if d.object(forKey: glassTintBlueKey) != nil { s.tintBlue = d.double(forKey: glassTintBlueKey) }
        if d.object(forKey: glassTintStrengthKey) != nil { s.tintStrength = d.double(forKey: glassTintStrengthKey) }
        if d.object(forKey: glassOpenViewKey) != nil { s.openView = d.bool(forKey: glassOpenViewKey) }
        if let raw = d.string(forKey: glassClosedScopeKey), let scope = GlassClosedScope(rawValue: raw) {
            s.closedScope = scope
        }
        return s
    }

    private func persistNudgeSettings(_ s: NudgeSettings) {
        let d = UserDefaults.standard
        d.set(s.isEnabled, forKey: Self.nudgeEnabledKey)
        d.set(s.threshold.rawValue, forKey: Self.nudgeThresholdKey)
    }

    private static func loadNudgeSettings() -> NudgeSettings {
        let d = UserDefaults.standard
        var s = NudgeSettings()
        if d.object(forKey: nudgeEnabledKey) != nil { s.isEnabled = d.bool(forKey: nudgeEnabledKey) }
        if let raw = d.string(forKey: nudgeThresholdKey), let t = IdleNudgeThreshold(rawValue: raw) {
            s.threshold = t
        }
        return s
    }

    // MARK: - Idle-session nudge

    /// How long to wait before re-checking when a nudge is held back because the
    /// user is currently looking at the terminal that owns the waiting session.
    /// Bounds how late the nudge lands after they finally look away.
    private static let nudgeFocusRecheckSeconds: TimeInterval = 15

    /// Antigravity emits only per-tool-call hooks (`PreToolUse` / `PostToolUse`)
    /// and never a turn- or session-end event. We keep its session `.running`
    /// while those hooks keep arriving and settle it to idle after this much
    /// silence. Long enough to bridge a model-thinking gap between tools, short
    /// enough that the notch stops reading "active" promptly once agy finishes.
    private static let antigravityActivitySettleSeconds: TimeInterval = 8

    /// (Re)arm the Antigravity idle-settle debounce. Each running tool event
    /// pushes the deadline out; when it finally fires we emit a synthetic
    /// completion so the session stops reading as actively working.
    private func armAntigravitySettleTimer(for sessionID: String) {
        antigravitySettleTimers[sessionID]?.cancel()
        antigravitySettleTimers[sessionID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.antigravityActivitySettleSeconds))
            guard let self, !Task.isCancelled else { return }
            self.antigravitySettleTimers[sessionID] = nil
            guard let session = self.state.session(id: sessionID),
                  session.tool == .antigravity,
                  session.phase == .running else { return }
            self.applyTrackedEvent(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: sessionID,
                        summary: session.summary,
                        phase: .completed,
                        timestamp: Date()
                    )
                )
            )
        }
    }

    private func cancelAntigravitySettleTimer(for sessionID: String) {
        antigravitySettleTimers[sessionID]?.cancel()
        antigravitySettleTimers[sessionID] = nil
    }

    /// Arm a one-shot nudge for a session that just entered an attention phase.
    /// Fires after the configured threshold if the session is still waiting.
    func scheduleIdleNudgeIfNeeded(for sessionID: String) {
        nudgeTimers[sessionID]?.cancel()
        // Anchor the wait-start once (the displayed "Waiting Xm Ys" must not
        // reset if updatedAt bumps mid-wait). Preserved across re-arms.
        if attentionStartedAt[sessionID] == nil {
            attentionStartedAt[sessionID] = state.session(id: sessionID)?.updatedAt ?? Date()
        }
        armNudgeTimer(for: sessionID, after: nudgeSettings.threshold.seconds)
    }

    private func armNudgeTimer(for sessionID: String, after seconds: TimeInterval) {
        nudgeTimers[sessionID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }

            @MainActor func stillWaiting() -> Bool {
                self.nudgeSettings.isEnabled
                    && self.state.session(id: sessionID)?.phase.requiresAttention == true
            }
            guard stillWaiting(), let session = self.state.session(id: sessionID) else {
                self.nudgeTimers[sessionID] = nil
                return
            }

            // Mirror the dock-bounce condition: a terminal only bounces when
            // it's in the background. If the user is actively looking at the
            // terminal that owns this session, hold the nudge and re-check
            // shortly so it still lands once they look away.
            let focused = await self.isOwningTerminalFocused(session)
            // The focus probe can await (AppleScript); bail if we were replaced
            // or the session resolved meanwhile, without clobbering a newer timer.
            guard !Task.isCancelled else { return }
            guard stillWaiting() else {
                self.nudgeTimers[sessionID] = nil
                return
            }
            if focused {
                self.armNudgeTimer(for: sessionID, after: Self.nudgeFocusRecheckSeconds)
                return
            }
            self.nudgeTimers[sessionID] = nil
            self.fireSessionNudge(for: sessionID)
        }
    }

    /// Whether the user is currently looking at the terminal that owns this
    /// session — used to hold back the idle nudge (don't pester about something
    /// already on screen).
    private func isOwningTerminalFocused(_ session: AgentSession) async -> Bool {
        // Pane/tab precision where the probe supports it (Ghostty, Terminal,
        // iTerm): a focused background tab of the same app correctly reads as
        // not-focused for this session.
        if await isNotificationSessionAlreadyFrontmost(session) {
            return true
        }
        // App-level fallback for terminals the probe can't introspect (Warp,
        // VS Code, Cursor, JetBrains, …): if that app is frontmost, treat the
        // session as on-screen. Skip when the frontmost app IS pane-
        // introspectable — there the probe already gave an authoritative answer
        // and a background tab of the same app must still nudge.
        guard let frontmost = frontmostBundleIdentifierProvider(),
              !ForegroundTerminalSessionProbe.paneIntrospectableBundleIDs.contains(frontmost),
              let terminalApp = session.jumpTarget?.terminalApp else {
            return false
        }
        return TerminalJumpService.bundleIdentifiers(forTerminalAppName: terminalApp).contains(frontmost)
    }

    private func fireSessionNudge(for sessionID: String) {
        NotificationSoundService.play(type: .nudge, isMuted: isSoundMuted)
        nudgeTrigger = UUID()
    }

    /// Arm nudges for every session already waiting — used when the feature is
    /// turned on mid-wait (otherwise only fresh events would arm).
    private func armNudgesForWaitingSessions() {
        for session in state.sessions where session.phase.requiresAttention {
            scheduleIdleNudgeIfNeeded(for: session.id)
        }
    }

    /// Cancel and clear all pending nudge state (feature disabled).
    private func cancelAllNudges() {
        for task in nudgeTimers.values { task.cancel() }
        nudgeTimers.removeAll()
        attentionStartedAt.removeAll()
    }

    /// Cancel pending nudges for sessions that are no longer waiting (the user
    /// responded, the session completed, or it was removed). Called from every
    /// resolution path so a resolved session never nudges.
    private func reconcileNudgeTimers() {
        guard !nudgeTimers.isEmpty || !attentionStartedAt.isEmpty else { return }
        for id in Array(nudgeTimers.keys) where state.session(id: id)?.phase.requiresAttention != true {
            nudgeTimers[id]?.cancel()
            nudgeTimers[id] = nil
        }
        for id in Array(attentionStartedAt.keys) where state.session(id: id)?.phase.requiresAttention != true {
            attentionStartedAt[id] = nil
        }
    }

    init(
        terminalJumpAction: @escaping @Sendable (JumpTarget) throws -> String = { target in
            try TerminalJumpService().jump(to: target)
        },
        isNotificationSessionAlreadyFrontmost: @escaping @Sendable (AgentSession) async -> Bool = { session in
            await ForegroundTerminalSessionProbe().matches(session: session)
        },
        frontmostBundleIdentifierProvider: @escaping @Sendable () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        self.terminalJumpAction = terminalJumpAction
        self.isNotificationSessionAlreadyFrontmost = isNotificationSessionAlreadyFrontmost
        self.frontmostBundleIdentifierProvider = frontmostBundleIdentifierProvider
        UserDefaults.standard.register(defaults: [
            Self.showDockIconDefaultsKey: true,
            Self.hapticFeedbackEnabledDefaultsKey: false,
            Self.completionReplyEnabledDefaultsKey: false,
            Self.suppressFrontmostNotificationsDefaultsKey: true,
        ])
        isSoundMuted = UserDefaults.standard.bool(forKey: Self.soundMutedDefaultsKey)
        selectedSoundName = NotificationSoundService.selectedSoundName
        showDockIcon = UserDefaults.standard.bool(forKey: Self.showDockIconDefaultsKey)
        hapticFeedbackEnabled = UserDefaults.standard.bool(forKey: Self.hapticFeedbackEnabledDefaultsKey)
        suppressFrontmostNotifications = UserDefaults.standard.bool(forKey: Self.suppressFrontmostNotificationsDefaultsKey)
        if UserDefaults.standard.object(forKey: Self.showCodexUsageDefaultsKey) != nil {
            showCodexUsage = UserDefaults.standard.bool(forKey: Self.showCodexUsageDefaultsKey)
        } else {
            showCodexUsage = FileManager.default.fileExists(
                atPath: CodexRolloutDiscovery.defaultRootURL.path
            )
        }
        completionReplyEnabled = UserDefaults.standard.bool(forKey: Self.completionReplyEnabledDefaultsKey)
        launchAtLoginEnabled = LaunchAtLoginService.shared.isEnabled
        appearanceSettingsProfile = IslandAppearanceDisplayProfile(
            rawValue: UserDefaults.standard.string(forKey: Self.appearanceProfileSettingsDefaultsKey) ?? ""
        ) ?? .topBar
        notchAppearancePreferences = Self.loadAppearancePreferences(for: .notch)
        topBarAppearancePreferences = Self.loadAppearancePreferences(for: .topBar)
        glassSettings = Self.loadGlassSettings()
        nudgeSettings = Self.loadNudgeSettings()
        selectedNudgeSoundName = NotificationSoundService.selectedSoundName(for: .nudge)
        watchNotificationEnabled = UserDefaults.standard.bool(forKey: Self.watchNotificationEnabledKey)
        if watchNotificationEnabled {
            startWatchRelay()
        }

        playerManager.onTrackChange = { [weak self] track in
            guard let self else { return }
            self.presentMusicTrackNotification(track: track)
        }

        playerManager.onAlbumArtUpdated = { [weak self] track in
            guard let self else { return }
            self.refreshMusicNotificationAlbumArtIfNeeded(from: track)
        }

        playerManager.onPlaybackStateChange = { [weak self] _ in
            guard let self else { return }
            self.reconcileCompactMusicView()
        }

        overlay.appModel = self
        overlay.startFullscreenPolling()
        overlay.restoreDisplayPreference()
        overlay.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }
        overlay.activeIslandCardSessionAccessor = { [weak self] in
            self?.activeIslandCardSession
        }
        overlay.nextUnseenCompletionAccessor = { [weak self] in
            self?.nextUnseenCompletedSessionID
        }
        overlay.onNotificationSurfaceShown = { [weak self] sessionID in
            self?.notificationCardShownAt = Date()
            self?.markCompletionToastShown(for: sessionID)
        }
        overlay.isSoundMutedAccessor = { [weak self] in
            self?.isSoundMuted ?? false
        }
        overlay.ignoresPointerExitAccessor = { [weak self] in
            self?.ignoresPointerExitDuringHarness ?? false
        }

        hooks.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }

        discovery.syntheticClaudeSessionPrefix = Self.syntheticClaudeSessionPrefix
        discovery.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }
        discovery.stateAccessor = { [weak self] in self?.state ?? SessionState() }
        discovery.stateUpdater = { [weak self] in self?.state = $0 }
        discovery.onStateChanged = { [weak self] in
            self?.synchronizeSelection()
            self?.refreshOverlayPlacementIfVisible()
            self?.reconcileCompactMusicView()
        }

        discovery.codexRolloutWatcher.eventHandler = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.applyTrackedEvent(
                    event,
                    updateLastActionMessage: false,
                    ingress: .rollout
                )
            }
        }

        codexAppServer.onEvent = { [weak self] event in
            self?.applyTrackedEvent(event, ingress: .bridge)
        }
        codexAppServer.onStatusMessage = { [weak self] message in
            self?.lastActionMessage = message
        }
        codexAppServer.isSessionTracked = { [weak self] id in
            self?.state.session(id: id) != nil
        }

        monitoring.syntheticClaudeSessionPrefix = Self.syntheticClaudeSessionPrefix
        monitoring.stateAccessor = { [weak self] in self?.state ?? SessionState() }
        monitoring.stateUpdater = { [weak self] in self?.state = $0 }
        monitoring.onSessionsReconciled = { [weak self] in
            self?.synchronizeSelection()
            self?.refreshOverlayPlacementIfVisible()
            self?.reconcileCompactMusicView()
        }
        monitoring.onPersistenceNeeded = { [weak self] in
            self?.discovery.scheduleCodexSessionPersistence()
            self?.discovery.scheduleClaudeSessionPersistence()
            self?.discovery.scheduleOpenCodeSessionPersistence()
            self?.discovery.scheduleCursorSessionPersistence()
        }
        monitoring.onCodexAppRunningChanged = { [weak self] isRunning in
            guard let self else { return }
            if isRunning {
                self.codexAppServer.ensureConnected()
            } else {
                self.codexAppServer.disconnect()
            }
        }
        refreshOverlayDisplayConfiguration()
        hasFinishedInit = true
        reconcileCompactMusicView()
        overlay.refreshFullscreenState()
    }

    var isMouseInsideClosedArea: Bool = false {
        didSet {
            if isMouseInsideClosedArea != oldValue {
                // Trigger re-render for peek behavior
            }
        }
    }

    /// Sessions are present but none are running or waiting on the user.
    var agentsAreIdle: Bool {
        surfacedSessions.isEmpty || surfacedSessions.allSatisfy {
            $0.phase != .running && !$0.phase.requiresAttention
        }
    }

    var isMusicPlaybackActive: Bool {
        playerManager.isMusicEnabled
            && playerManager.isRunning
            && playerManager.isPlaying
            && !playerManager.track.isEmpty()
    }

    /// Closed-notch music pill while agents are idle and music is playing.
    var shouldShowCompactMusicView: Bool {
        notchStatus != .opened && agentsAreIdle && isMusicPlaybackActive
    }

    var isIslandInactive: Bool {
        agentsAreIdle && !shouldShowCompactMusicView
    }

    /// Collapse the closed notch when nothing needs the surface: no running or
    /// attention sessions, no active music playback (paused is fine), and no
    /// transient track notification. Peek-on-hover still reveals the pill.
    var shouldHideClosedNotch: Bool {
        notchStatus != .opened
            && musicNotificationTrack == nil
            && !isMusicPlaybackActive
            && agentsAreIdle
    }

    var shouldAutoHideIsland: Bool {
        appearancePreferences(for: activeAppearanceProfile).autoHideWhenInactive && isIslandInactive
    }

    /// True when the closed pill should slide off-screen (empty state or user pref).
    var shouldCollapseClosedNotch: Bool {
        isOverlayDisplayFullscreen || shouldHideClosedNotch || shouldAutoHideIsland
    }

    var isPeeking: Bool {
        shouldCollapseClosedNotch && isMouseInsideClosedArea
    }

    /// True when the overlay's target display is in a native fullscreen space.
    var isOverlayDisplayFullscreen: Bool = false

    func notePointerInsideClosedArea() {
        isMouseInsideClosedArea = true
    }

    func notePointerExitedClosedArea() {
        isMouseInsideClosedArea = false
    }

    var sessions: [AgentSession] {
        state.sessions
    }

    var allSessions: [AgentSession] {
        state.sessions
    }

    /// Measured by SwiftUI GeometryReader in notification mode. Used by panel controller for sizing.
    /// Uses a tolerance of 2pt to avoid infinite layout loops caused by floating-point jitter
    /// in GeometryReader measurements across consecutive layout passes.
    var measuredNotificationContentHeight: CGFloat = 0 {
        didSet {
            let delta = abs(measuredNotificationContentHeight - oldValue)
            if delta >= 2, measuredNotificationContentHeight > 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.overlay.refreshOverlayPlacementIfVisible()
                }
            }
        }
    }

    /// Measured by SwiftUI GeometryReader in Agents tab.
    var measuredAgentsContentHeight: CGFloat = 0 {
        didSet {
            let delta = abs(measuredAgentsContentHeight - oldValue)
            if delta >= 2, measuredAgentsContentHeight > 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.overlay.refreshOverlayPlacementIfVisible()
                }
            }
        }
    }

    /// Measured by SwiftUI from Myspace's natural content height.
    var measuredMyspaceContentHeight: CGFloat = 0 {
        didSet {
            let delta = abs(measuredMyspaceContentHeight - oldValue)
            if delta >= 2, measuredMyspaceContentHeight > 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.overlay.refreshOverlayPlacementIfVisible()
                }
            }
        }
    }

    /// Measured by SwiftUI from the Reminders tab's natural content height.
    var measuredRemindersContentHeight: CGFloat = 0 {
        didSet {
            let delta = abs(measuredRemindersContentHeight - oldValue)
            if delta >= 2, measuredRemindersContentHeight > 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.overlay.refreshOverlayPlacementIfVisible()
                }
            }
        }
    }

    var completionFlashSessionID: String?

    /// When the current notification card appeared (open or rotate). Keyboard
    /// control uses it to keep a bare Return from approving a card the user
    /// has not had time to read.
    @ObservationIgnored var notificationCardShownAt: Date?

    var musicNotificationTrack: PlayerTrack?

    var surfacedSessions: [AgentSession] {
        sessionBuckets.primary
    }

    var recentSessions: [AgentSession] {
        sessionBuckets.overflow
    }

    var islandListSessions: [AgentSession] {
        islandSessionSections.flatMap(\.sessions)
    }

    var islandSessionSections: [IslandSessionSection] {
        let sessions = sortIslandSessions(surfacedSessions)
        switch islandSessionGroup {
        case .none:
            return [
                IslandSessionSection(
                    id: "all",
                    title: "island.section.sessions",
                    sessions: sessions
                )
            ]
        case .state:
            return stateGroupedSections(for: sessions)
        case .agent:
            return AgentTool.allCases.compactMap { tool in
                let list = sessions.filter { $0.tool == tool }
                guard !list.isEmpty else { return nil }
                return IslandSessionSection(id: "agent-\(tool.rawValue)", title: tool.displayName, sessions: list)
            }
        case .project:
            let names = Set(sessions.map(projectGroupName(for:))).sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
            return names.compactMap { name in
                let list = sessions.filter { projectGroupName(for: $0) == name }
                guard !list.isEmpty else { return nil }
                return IslandSessionSection(id: "project-\(name)", title: name, sessions: list)
            }
        }
    }

    var recentSessionCount: Int {
        recentSessions.count
    }

    var liveSessionCount: Int {
        surfacedSessions.count
    }

    var liveAttentionCount: Int {
        surfacedSessions.filter { $0.phase.requiresAttention }.count
    }

    var liveRunningCount: Int {
        surfacedSessions.filter { $0.phase == .running }.count
    }

    private func sortIslandSessions(_ sessions: [AgentSession]) -> [AgentSession] {
        switch islandSessionSort {
        case .attention:
            return sessions
        case .lastUpdate:
            return sessions.sorted { lhs, rhs in
                if lhs.islandActivityDate == rhs.islandActivityDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.islandActivityDate > rhs.islandActivityDate
            }
        }
    }

    private func stateGroupedSections(for sessions: [AgentSession]) -> [IslandSessionSection] {
        let definitions: [(id: String, title: String, include: (AgentSession) -> Bool)] = [
            ("approval", "island.section.needsApproval", { $0.phase == .waitingForApproval }),
            ("answer", "island.section.needsAnswer", { $0.phase == .waitingForAnswer }),
            ("running", "island.section.inProgress", { $0.phase == .running }),
            ("done", "island.section.justDone", { [completedStaleThreshold] session in
                session.phase == .completed
                    && !session.isStaleCompletedForIsland(at: .now, threshold: completedStaleThreshold.seconds)
            }),
            ("idle", "island.section.idle", { [completedStaleThreshold] session in
                session.phase == .completed
                    && session.isStaleCompletedForIsland(at: .now, threshold: completedStaleThreshold.seconds)
            }),
        ]

        return definitions.compactMap { definition in
            let list = sessions.filter(definition.include)
            guard !list.isEmpty else { return nil }
            return IslandSessionSection(id: "state-\(definition.id)", title: definition.title, sessions: list)
        }
    }

    private func projectGroupName(for session: AgentSession) -> String {
        if let workspace = session.jumpTarget?.workspaceName.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspace.isEmpty {
            return workspace
        }

        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return session.tool.displayName }

        let pieces = title.split(separator: "·", maxSplits: 1).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return pieces.last?.isEmpty == false ? pieces.last! : title
    }

    // MARK: - v6 closed-island derivation

    /// The aggregate UnifiedBars state for the closed island. Waiting beats
    /// running; everything else is idle. Completed sessions are absorbed
    /// directly into idle so the pill never stops on a tick glyph.
    var islandClosedMode: UnifiedBars.Mode {
        let sessions = surfacedSessions
        if sessions.contains(where: { $0.phase.requiresAttention }) { return .waiting }
        if sessions.contains(where: { $0.phase == .running })       { return .running }
        return .idle
    }

    /// The character's tint when "Color by agent" is on: the brand color of
    /// the agent the pill is about (live activity first, then the spotlight
    /// session). `nil` keeps the paper ink.
    var islandClosedGlyphTint: Color? {
        guard appearancePreferences(for: activeAppearanceProfile).colorByAgent else { return nil }
        let session = islandLiveActivity.flatMap { state.session(id: $0.sessionID) }
            ?? islandClosedSpotlight
        guard let session else { return nil }
        return Color(hex: session.tool.brandColorHex)
    }

    /// The spotlight session powering the center label (if any). Attention
    /// sessions first, then the most recent running one, then whatever's
    /// first.
    var islandClosedSpotlight: AgentSession? {
        surfacedSessions.first(where: { $0.phase.requiresAttention })
            ?? surfacedSessions.first(where: { $0.phase == .running })
            ?? surfacedSessions.first
    }

    /// Text to show in the closed island's center label. Respects the
    /// `islandCenterLabel` user preference.
    func islandClosedLabel() -> String? {
        guard islandCenterLabel != .off,
              let session = islandClosedSpotlight else { return nil }

        switch islandCenterLabel {
        case .off:
            return nil
        case .sessionName:
            let workspace = session.jumpTarget?.workspaceName ?? ""
            if !workspace.isEmpty { return workspace }
            return session.title.isEmpty ? session.tool.displayName : session.title
        case .agentAction:
            let action = session.displayCurrentToolName
            if let action, !action.isEmpty {
                return "\(session.tool.displayName) · \(action)"
            }
            return session.tool.displayName
        }
    }

    /// Right-slot payload derived from the user's `islandRightSlot`
    /// preference and current live state. Returns nil when the preference
    /// is `.none` or there's nothing meaningful to show.
    func islandClosedRightSlotContent() -> IslandRightSlotContent? {
        let sessions = surfacedSessions
        switch islandRightSlot {
        case .none:
            return nil
        case .count:
            let n = sessions.count
            guard n > 0 else { return nil }
            return .count(n)
        case .agents:
            // Display order = order-of-first-observation-in-the-island. A
            // session that later flips visibility (e.g. attachment churn,
            // completed↔running) keeps its existing slot instead of being
            // reshuffled by session.firstSeenAt, which tracks the historical
            // event time and can be older than visible peers. Bulk-observing
            // N sessions at once (e.g. at app launch) breaks the tie by
            // session.firstSeenAt so historical order is preserved.
            stampAgentsGridObservationTickets(for: sessions)
            let ordered = sessions.sorted { a, b in
                let ta = _agentsGridObservedSequence[a.id] ?? .max
                let tb = _agentsGridObservedSequence[b.id] ?? .max
                if ta != tb { return ta < tb }
                return a.id < b.id
            }
            var cells: [AgentGridCell] = []
            if ordered.count <= 9 {
                cells = ordered.map(Self.agentsGridCell(for:))
            } else {
                cells = ordered.prefix(7).map(Self.agentsGridCell(for:))
                cells.append(.overflow(ordered.count - 7))
            }
            return cells.isEmpty ? nil : .agents(cells)
        }
    }

    private func stampAgentsGridObservationTickets(for sessions: [AgentSession]) {
        let newcomers = sessions.filter { _agentsGridObservedSequence[$0.id] == nil }
        guard !newcomers.isEmpty else { return }
        let orderedNewcomers = newcomers.sorted { a, b in
            if a.firstSeenAt != b.firstSeenAt { return a.firstSeenAt < b.firstSeenAt }
            return a.id < b.id
        }
        for session in orderedNewcomers {
            _agentsGridObservedSequence[session.id] = _agentsGridNextTicket
            _agentsGridNextTicket += 1
        }
    }

    private func pruneAgentsGridObservationTicketsIfNeeded() {
        guard _agentsGridObservedSequence.count > Self.agentsGridObservedSequenceLimit else {
            return
        }

        let liveIDs = Set(state.sessions.map(\.id))
        let retainedHistoricalCapacity = max(Self.agentsGridObservedSequenceLimit - liveIDs.count, 0)
        let retainedHistoricalIDs = _agentsGridObservedSequence
            .filter { !liveIDs.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(retainedHistoricalCapacity)
            .map(\.key)
        let retainedIDs = liveIDs.union(retainedHistoricalIDs)
        _agentsGridObservedSequence = _agentsGridObservedSequence.filter {
            retainedIDs.contains($0.key)
        }
    }

    private static func agentsGridCell(for session: AgentSession) -> AgentGridCell {
        let color = Color(hex: session.tool.brandColorHex) ?? .gray
        let state: AgentGridCellState
        if session.phase.requiresAttention {
            state = .waiting
        } else if session.phase == .running {
            state = .running
        } else {
            state = .idle
        }
        return .session(color: color, state: state)
    }

    var shouldShowSessionBootstrapPlaceholder: Bool {
        isResolvingInitialLiveSessions
            && liveSessionCount == 0
            && state.sessions.contains(where: \.isTrackedLiveSession)
    }

    var focusedSession: AgentSession? {
        state.session(id: selectedSessionID) ?? surfacedSessions.first ?? state.activeActionableSession ?? state.sessions.first
    }

    var activeIslandCardSession: AgentSession? {
        guard let sessionID = islandSurface.sessionID else {
            return nil
        }

        return state.session(id: sessionID)
    }

    var hasAnySession: Bool {
        !sessions.isEmpty
    }

    var hasCodexSession: Bool {
        sessions.contains(where: { $0.tool == .codex })
    }

    var hasJumpableSession: Bool {
        sessions.contains(where: { $0.jumpTarget != nil })
    }

    var acceptanceSteps: [AcceptanceStep] {
        [
            AcceptanceStep(
                id: "bridge",
                title: "Bridge ready",
                detail: "The app must own the local socket and register as a bridge observer.",
                isComplete: isBridgeReady
            ),
            AcceptanceStep(
                id: "hooks",
                title: "Codex hooks installed",
                detail: "Managed `hooks.json` entries should be present in `~/.codex`.",
                isComplete: hooks.codexHooksInstalled
            ),
            AcceptanceStep(
                id: "overlay",
                title: "Island visible",
                detail: "Show the overlay at least once so the notch/top-bar surface is visible.",
                isComplete: isOverlayVisible
            ),
            AcceptanceStep(
                id: "session",
                title: "A Codex session is observed",
                detail: "Start Codex in Terminal and wait for the first session row to appear.",
                isComplete: hasCodexSession
            ),
            AcceptanceStep(
                id: "jump",
                title: "Jump target captured",
                detail: "At least one session should include terminal jump metadata.",
                isComplete: hasJumpableSession
            ),
        ]
    }

    var acceptanceCompletedCount: Int {
        acceptanceSteps.filter(\.isComplete).count
    }

    var isReadyForFirstAcceptance: Bool {
        acceptanceSteps.prefix(3).allSatisfy(\.isComplete)
    }

    var hasPassedAcceptanceFlow: Bool {
        acceptanceSteps.allSatisfy(\.isComplete)
    }

    var acceptanceStatusTitle: String {
        if hasPassedAcceptanceFlow {
            return "v0.1 acceptance passed"
        }

        if isReadyForFirstAcceptance {
            return "Ready for v0.1 acceptance"
        }

        return "v0.1 acceptance not ready"
    }

    var acceptanceStatusSummary: String {
        if hasPassedAcceptanceFlow {
            return "The current build has completed the first-run checklist end to end."
        }

        if isReadyForFirstAcceptance {
            return "You can start your first acceptance run now. Launch Codex in Terminal and walk the last two steps."
        }

        return "Finish the setup steps in the left column, then start Codex from Terminal."
    }

    func startIfNeeded(
        startBridge: Bool = true,
        shouldPerformBootAnimation: Bool = true,
        loadRuntimeState: Bool = true
    ) {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        if loadRuntimeState {
            isResolvingInitialLiveSessions = true

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let payload = self.discovery.loadStartupDiscoveryPayload()
                await MainActor.run {
                    self.applyStartupDiscoveryPayload(payload)
                }
            }

            // These are already async or lightweight — safe to start immediately.
            hooks.refreshCodexHookStatus()
            hooks.refreshClaudeHookStatus()
            hooks.refreshCCForkHookStatuses()
            hooks.refreshOpenCodePluginStatus()
            hooks.refreshCursorHookStatus()
            hooks.refreshClaudeUsageState()
            hooks.refreshGeminiUsageState()
            hooks.startClaudeUsageMonitoringIfNeeded()
            hooks.startGeminiUsageMonitoringIfNeeded()
            if showCodexUsage {
                hooks.refreshCodexUsageState()
                hooks.startCodexUsageMonitoringIfNeeded()
            }
        } else {
            isResolvingInitialLiveSessions = false
        }
        refreshOverlayDisplayConfiguration()
        ensureOverlayPanel()
        if shouldPerformBootAnimation {
            performBootAnimation()
        }

        guard startBridge else {
            isBridgeReady = false
            lastActionMessage = loadRuntimeState
                ? "Harness mode active. Bridge startup skipped."
                : "Deterministic harness mode active. Runtime discovery and bridge startup skipped."
            harnessRuntimeMonitor?.recordMilestone("bridgeSkipped", message: lastActionMessage)
            return
        }

        do {
            try bridgeServer.start()
            connectBridgeObserver()
        } catch {
            isBridgeReady = false
            lastActionMessage = "Failed to start local bridge: \(error.localizedDescription)"
            harnessRuntimeMonitor?.recordMilestone("bridgeStartFailed", message: lastActionMessage)
        }
    }

    // MARK: - Bridge observer connection

    private static let bridgeReconnectDelay: Duration = .seconds(2)
    private static let bridgeMaxReconnectDelay: Duration = .seconds(30)

    private func connectBridgeObserver() {
        bridgeTask?.cancel()
        bridgeReconnectTask?.cancel()

        // Explicitly disconnect the old client so its DispatchSource is
        // cancelled deterministically rather than relying on dealloc timing.
        bridgeClient.disconnect()

        // Create a fresh client for each connection attempt so we don't
        // have to worry about stale file-descriptor state.
        let client = LocalBridgeClient()
        bridgeClient = client

        let stream: AsyncThrowingStream<AgentEvent, Error>
        do {
            stream = try client.connect()
        } catch {
            isBridgeReady = false
            lastActionMessage = "Failed to connect bridge observer: \(error.localizedDescription)"
            scheduleBridgeReconnect()
            return
        }

        // A single task handles both registration and event consumption so
        // there is no untracked task that could race with a reconnect.
        bridgeTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await client.send(.registerClient(role: .observer))
                self.isBridgeReady = true
                self.lastActionMessage = "Bridge ready. Waiting for Claude and Codex hook events."
                self.harnessRuntimeMonitor?.recordMilestone("bridgeReady", message: self.lastActionMessage)
            } catch {
                guard !Task.isCancelled else { return }
                self.isBridgeReady = false
                self.lastActionMessage = "Failed to register bridge observer: \(error.localizedDescription)"
                self.harnessRuntimeMonitor?.recordMilestone(
                    "bridgeRegistrationFailed",
                    message: self.lastActionMessage
                )
                self.scheduleBridgeReconnect()
                return
            }

            do {
                for try await event in stream {
                    self.applyTrackedEvent(event)
                }
            } catch {}

            // Stream ended (server closed our connection or transient error).
            // Mark as disconnected and schedule reconnection.
            guard !Task.isCancelled else { return }
            self.isBridgeReady = false
            self.lastActionMessage = "Bridge observer disconnected. Reconnecting…"
            self.harnessRuntimeMonitor?.recordMilestone("bridgeDisconnected", message: self.lastActionMessage)
            self.scheduleBridgeReconnect()
        }
    }

    private func scheduleBridgeReconnect() {
        bridgeReconnectTask?.cancel()
        bridgeReconnectTask = Task { [weak self] in
            var delay = Self.bridgeReconnectDelay
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                self.connectBridgeObserver()
                // If we're now connected, stop retrying.
                if self.isBridgeReady { return }
                delay = min(delay * 2, Self.bridgeMaxReconnectDelay)
            }
        }
    }

    func select(sessionID: String) {
        selectedSessionID = sessionID
    }

    // MARK: - Overlay forwarding

    func toggleOverlay() { overlay.toggleOverlay() }
    func notchOpen(reason: NotchOpenReason, surface: IslandSurface = .sessionList()) { overlay.notchOpen(reason: reason, surface: surface) }
    func notchClose() { overlay.notchClose() }

    // MARK: - Onboarding live appearance preview

    /// Opens the REAL island (pinned) so the personalize step previews glass,
    /// tint, and character changes on the actual notch instead of a mock.
    func beginAppearanceLivePreview() {
        overlay.keepsIslandOpenForPreview = true
        if notchStatus != .opened {
            notchOpen(reason: .click)
        }
    }

    func endAppearanceLivePreview() {
        guard overlay.keepsIslandOpenForPreview else { return }
        overlay.keepsIslandOpenForPreview = false
        if notchStatus == .opened {
            notchClose()
        }
    }

    // MARK: - Onboarding tour

    /// Starts (or restarts) the guided notch tour. The island closes first so
    /// the tour always begins from the hover-to-open step.
    func startOnboardingTour() {
        if notchStatus == .opened {
            notchClose()
        }
        islandActiveTab = .agents
        tour.start(model: self)
    }

    /// Seeds the tour's fake approval session. Additive — real (restored or
    /// live) sessions are untouched, and `.demo` origin is excluded from every
    /// registry persistence path, so nothing survives a quit.
    func insertTourDemoSession() {
        let now = Date()
        let demo = AgentSession(
            id: OnboardingTourController.demoSessionID,
            title: "Claude Code · demo",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Allow Claude Code to edit Welcome.swift?",
            updatedAt: now,
            permissionRequest: PermissionRequest(
                title: "Approve file edit",
                summary: "Allow Claude Code to edit Welcome.swift?",
                affectedPath: "Sources/Welcome.swift",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                initialUserPrompt: "Show me around NotchTune.",
                lastUserPrompt: "Polish the welcome screen copy.",
                lastAssistantMessage: "Ready to edit Welcome.swift — needs your approval.",
                currentTool: "Edit",
                currentToolInputPreview: "Sources/Welcome.swift"
            )
        )
        state.insertSession(demo)
        selectedSessionID = demo.id
    }

    func removeTourDemoSession() {
        let removed = state.removeSessions(where: \.isDemoSession)
        if removed, selectedSessionID == OnboardingTourController.demoSessionID {
            selectedSessionID = nil
            synchronizeSelection()
        }
    }

    /// Rewrites the demo session into a small completed win after the user
    /// resolves its approval.
    func completeTourDemoSession() {
        guard var demo = state.session(id: OnboardingTourController.demoSessionID) else { return }
        demo.phase = .completed
        demo.permissionRequest = nil
        demo.summary = "Approvals resolved right from the notch — just like that."
        demo.updatedAt = Date()
        state.insertSession(demo)
    }
    func notchPop() { overlay.notchPop() }
    func presentMusicTrackNotification(track: PlayerTrack) {
        overlay.presentMusicTrackNotification(track: track)
    }

    func reconcileCompactMusicView() {
        guard hasFinishedInit else { return }
        overlay.reconcileCompactMusicView()
    }

    func refreshMusicNotificationAlbumArtIfNeeded(from track: PlayerTrack) {
        guard let notificationTrack = musicNotificationTrack,
              notificationTrack.matchesMetadata(track) else {
            return
        }
        var updated = notificationTrack
        updated.albumArt = track.albumArt
        updated.nsAlbumArt = track.nsAlbumArt
        updated.avgAlbumColor = track.avgAlbumColor
        withAnimation(V6ClosedMusicSurfaceMetrics.morphAnimation) {
            musicNotificationTrack = updated
        }
    }
    func performBootAnimation() { overlay.performBootAnimation() }
    func ensureOverlayPanel() { overlay.ensureOverlayPanel() }
    func showOverlay() { overlay.showOverlay() }
    func hideOverlay() { overlay.hideOverlay() }
    func expandNotificationToSessionList(clearExpansion: Bool = false) {
        overlay.expandNotificationToSessionList(clearExpansion: clearExpansion)
    }

    // MARK: - Completion toast rotation

    /// Completion timestamps the toast has already shown, keyed by session.
    /// A later completion (newer activity date) counts as unseen again.
    private(set) var completionToastShownAt: [String: Date] = [:]

    func markCompletionToastShown(for sessionID: String) {
        guard let session = state.session(id: sessionID), session.phase == .completed else {
            return
        }
        completionToastShownAt[sessionID] = session.islandActivityDate
    }

    /// Recently finished sessions, newest first, that the toast can rotate
    /// through. Stale completions (past the appearance threshold) drop out.
    var completionToastRing: [AgentSession] {
        let now = Date.now
        return allSessions
            .filter { session in
                session.phase == .completed
                    && !session.isStaleCompletedForIsland(at: now, threshold: completedStaleThreshold.seconds)
            }
            .sorted { $0.islandActivityDate > $1.islandActivityDate }
    }

    var completionToastQueuePosition: CompletionToastQueuePosition? {
        guard let currentID = islandSurface.sessionID else { return nil }
        let ring = completionToastRing
        guard ring.count > 1, let index = ring.firstIndex(where: { $0.id == currentID }) else {
            return nil
        }
        return CompletionToastQueuePosition(index: index, count: ring.count)
    }

    /// The next completed session the toast has not shown yet (or has shown
    /// only for an older completion), excluding the one on screen.
    var nextUnseenCompletedSessionID: String? {
        let currentID = islandSurface.sessionID
        return completionToastRing.first { session in
            guard session.id != currentID else { return false }
            guard let shownAt = completionToastShownAt[session.id] else { return true }
            return session.islandActivityDate > shownAt
        }?.id
    }

    func rotateCompletionToast(forward: Bool) {
        guard let currentID = islandSurface.sessionID else { return }
        let ring = completionToastRing
        guard ring.count > 1, let index = ring.firstIndex(where: { $0.id == currentID }) else {
            return
        }
        let nextIndex = (index + (forward ? 1 : ring.count - 1)) % ring.count
        overlay.rotateNotificationSurface(to: ring[nextIndex].id)
    }
    func refreshOverlayDisplayConfiguration() { overlay.refreshOverlayDisplayConfiguration() }
    func refreshOverlayPlacement() { overlay.refreshOverlayPlacement() }
    private func refreshOverlayPlacementIfVisible() { overlay.refreshOverlayPlacementIfVisible() }
    func notePointerInsideIslandSurface() { overlay.notePointerInsideIslandSurface() }
    func handlePointerExitedIslandSurface() { overlay.handlePointerExitedIslandSurface() }
    private func presentNotificationSurface(_ surface: IslandSurface) { overlay.presentNotificationSurface(surface) }
    private func reconcileIslandSurfaceAfterStateChange() { overlay.reconcileIslandSurfaceAfterStateChange() }
    private func dismissNotificationSurfaceIfPresent(for sessionID: String) { overlay.dismissNotificationSurfaceIfPresent(for: sessionID) }
    private func dismissOverlayForJump() { overlay.dismissOverlayForJump() }

    var shouldAutoCollapseOnMouseLeave: Bool { overlay.shouldAutoCollapseOnMouseLeave }
    var autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry: Bool { overlay.autoCollapseOnMouseLeaveRequiresPriorSurfaceEntry }
    var showsNotificationCard: Bool { overlay.showsNotificationCard }
    var shouldDeferTimedNotificationAutoCollapse: Bool { overlay.shouldDeferTimedNotificationAutoCollapse }
    var hasPendingNotificationAutoCollapse: Bool { overlay.hasPendingNotificationAutoCollapse }

    /// Harness-only: fixed usage numbers so captures show the header cycler.
    func seedHarnessSampleUsage() {
        let now = Date.now
        hooks.claudeUsageSnapshot = ClaudeUsageSnapshot(
            fiveHour: ClaudeUsageWindow(usedPercentage: 12, resetsAt: now.addingTimeInterval(3 * 3_600)),
            sevenDay: ClaudeUsageWindow(usedPercentage: 83, resetsAt: now.addingTimeInterval(29 * 3_600)),
            modelWeekly: [
                ClaudeModelUsageWindow(model: "fable", window: ClaudeUsageWindow(usedPercentage: 32, resetsAt: now.addingTimeInterval(29 * 3_600)))
            ]
        )
        hooks.codexUsageSnapshot = CodexUsageSnapshot(
            sourceFilePath: "harness",
            capturedAt: now,
            windows: [
                CodexUsageWindow(key: "primary", label: "5h", usedPercentage: 41, leftPercentage: 59, windowMinutes: 300, resetsAt: now.addingTimeInterval(7_200)),
                CodexUsageWindow(key: "secondary", label: "7d", usedPercentage: 22, leftPercentage: 78, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(86_400 * 4)),
            ]
        )
        showCodexUsage = true
    }

    func loadDebugSnapshot(
        _ snapshot: IslandDebugSnapshot,
        presentOverlay: Bool = false,
        autoCollapseNotificationCards: Bool = false
    ) {
        state = SessionState(sessions: snapshot.sessions)
        selectedSessionID = snapshot.selectedSessionID ?? snapshot.sessions.first?.id
        lastActionMessage = "Loaded debug scenario: \(snapshot.title)."
        harnessRuntimeMonitor?.recordMilestone("scenarioLoaded", message: snapshot.title)

        overlay.applyOverlayState(from: snapshot, presentOverlay: presentOverlay, autoCollapseNotificationCards: autoCollapseNotificationCards)
    }

    func showSettings() {
        if let opener = openSettingsWindow {
            opener()
        } else {
            // First-launch fallback: SwiftUI's `openWindow` closure is registered
            // by `SettingsWindowContent.onAppear`, which doesn't fire until the
            // settings window renders the first time. Send the standard
            // `showSettingsWindow:` responder action (macOS 13+) so it fires
            // the `CommandGroup(.appSettings)` button that opens the window.
            NSApp.sendAction(NSSelectorFromString("showSettingsWindow:"), to: nil, from: nil)
        }
        if let window = NSApp.windows.first(where: { $0.title == "NotchTune Settings" }) {
            window.orderFrontRegardless()
            window.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func showOnboarding() {
        if let opener = openOnboardingWindow {
            opener()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showSettings()
            NotificationCenter.default.post(name: .notchTuneSelectSetupTab, object: nil)
        }
    }

    func toggleSoundMuted() {
        isSoundMuted.toggle()
    }

    func approveFocusedPermission(_ approved: Bool) {
        guard let session = focusedSession else {
            return
        }

        send(
            .resolvePermission(sessionID: session.id, resolution: permissionResolution(for: approved)),
            userMessage: approved
                ? "Approving permission for \(session.title)."
                : "Denying permission for \(session.title)."
        )
    }

    func answerFocusedQuestion(_ answer: String) {
        guard let session = focusedSession else {
            return
        }

        send(
            .answerQuestion(sessionID: session.id, response: QuestionPromptResponse(answer: answer)),
            userMessage: "Sending answer \"\(answer)\" for \(session.title)."
        )
    }

    func jumpToFocusedSession() {
        jump(to: focusedSession?.jumpTarget)
    }

    func jumpToSession(_ session: AgentSession) {
        guard let jumpTarget = session.jumpTarget,
              jumpTarget.terminalApp.lowercased() != "unknown" else {
            lastActionMessage = "Cannot jump: terminal app is unknown."
            return
        }
        jump(to: jumpTarget)
    }

    private func jump(to jumpTarget: JumpTarget?) {
        guard let jumpTarget else {
            lastActionMessage = "No jump target is available yet."
            return
        }

        let shouldDelayForDismissAnimation = isOverlayVisible
        let jumpAction = terminalJumpAction

        dismissOverlayForJump()
        jumpTask?.cancel()
        jumpTask = Task { [weak self] in
            if shouldDelayForDismissAnimation {
                try? await Task.sleep(for: Self.jumpOverlayDismissLeadTime)
            }

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try jumpAction(jumpTarget)
                }.value

                guard !Task.isCancelled else {
                    return
                }

                self?.lastActionMessage = result
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self?.lastActionMessage = "Jump failed: \(error.localizedDescription)"
            }
        }
    }

    func approvePermission(for sessionID: String, approved: Bool) {
        guard let session = state.session(id: sessionID) else {
            return
        }

        let resolution = permissionResolution(for: approved)
        dismissNotificationSurfaceIfPresent(for: sessionID)
        state.resolvePermission(sessionID: session.id, resolution: resolution)
        reconcileNudgeTimers()
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        // The onboarding tour's demo session has no live agent behind it —
        // resolve locally only, never over the bridge.
        guard !session.isDemoSession else { return }

        send(
            .resolvePermission(sessionID: session.id, resolution: resolution),
            userMessage: approved
                ? "Approving permission for \(session.title)."
                : "Denying permission for \(session.title)."
        )
    }

    func approvePermission(for sessionID: String, action: ApprovalAction) {
        guard let session = state.session(id: sessionID) else {
            return
        }

        let resolution: PermissionResolution
        let message: String

        switch action {
        case .deny:
            resolution = .deny(message: "Permission denied in NotchTune.", interrupt: false)
            message = "Denying permission for \(session.title)."
        case .allowOnce:
            resolution = .allowOnce()
            message = "Approving permission for \(session.title)."
        case let .allowWithUpdates(updates):
            resolution = .allowOnce(updatedPermissions: updates)
            message = "Always allowing for \(session.title)."
        }

        dismissNotificationSurfaceIfPresent(for: sessionID)
        state.resolvePermission(sessionID: session.id, resolution: resolution)
        reconcileNudgeTimers()
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        // Demo sessions resolve locally only (see approvePermission(for:approved:)).
        guard !session.isDemoSession else { return }

        send(
            .resolvePermission(sessionID: session.id, resolution: resolution),
            userMessage: message
        )
    }

    func dismissSession(_ sessionID: String) {
        state.dismissSession(id: sessionID)
        dismissNotificationSurfaceIfPresent(for: sessionID)
        reconcileNudgeTimers()
        synchronizeSelection()
    }

    func answerQuestion(for sessionID: String, answer: QuestionPromptResponse) {
        guard let session = state.session(id: sessionID) else {
            return
        }

        dismissNotificationSurfaceIfPresent(for: sessionID)
        state.answerQuestion(sessionID: session.id, response: answer)
        reconcileNudgeTimers()
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        send(
            .answerQuestion(sessionID: session.id, response: answer),
            userMessage: "Sending answer for \(session.title)."
        )
    }

    func replyToSession(_ session: AgentSession, text: String) {
        dismissNotificationSurfaceIfPresent(for: session.id)
        synchronizeSelection()
        refreshOverlayPlacementIfVisible()

        lastActionMessage = "Sending reply to \(session.title)…"

        Task { [weak self] in
            let success = await Task.detached(priority: .userInitiated) {
                TerminalTextSender.send(text, to: session)
            }.value

            self?.lastActionMessage = success
                ? "Sent reply to \(session.title)."
                : "Failed to send reply to \(session.title)."
        }
    }


    private func send(_ command: BridgeCommand, userMessage: String) {
        lastActionMessage = userMessage

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await self.bridgeClient.send(command)
            } catch {
                self.lastActionMessage = "Failed to send bridge command: \(error.localizedDescription)"
            }
        }
    }

    private func permissionResolution(for approved: Bool) -> PermissionResolution {
        if approved {
            return .allowOnce()
        }

        return .deny(message: "Permission denied in NotchTune.", interrupt: false)
    }

    func applyTrackedEvent(
        _ event: AgentEvent,
        updateLastActionMessage: Bool = true,
        ingress: TrackedEventIngress = .bridge
    ) {
        // Snapshot whether this session was already completed before applying
        // the event. Used to suppress duplicate/stale completion notifications
        // (e.g. rollout watcher re-discovering an old completion on startup,
        // or producing a duplicate sessionCompleted that races with the bridge).
        let wasAlreadyCompleted: Bool = {
            guard case let .sessionCompleted(payload) = event else { return false }
            return state.session(id: payload.sessionID)?.phase == .completed
        }()

        // Phase before the event lands, so a repeated approval/question for a
        // session that is already waiting in that phase can be told apart
        // from a fresh request (see `NotificationCoalescer.decideRequest`).
        let priorPhase: SessionPhase? = event.sessionID.flatMap { state.session(id: $0)?.phase }

        // Guard: don't let rollout events downgrade a session from completed
        // back to running. The bridge's sessionCompleted is authoritative; the
        // rollout watcher may have read the JSONL before task_complete was
        // flushed, producing a stale activityUpdated(phase: .running).
        if ingress == .rollout,
           case let .activityUpdated(payload) = event,
           payload.phase == .running,
           state.session(id: payload.sessionID)?.phase == .completed {
            return
        }

        state.apply(event)
        if let sessionID = event.sessionID {
            noteRunningTransition(sessionID: sessionID, from: priorPhase)
        }
        reconcileIslandSurfaceAfterStateChange()

        // Arm an idle nudge when a session enters an attention phase.
        if nudgeSettings.isEnabled {
            switch event {
            case let .permissionRequested(p): scheduleIdleNudgeIfNeeded(for: p.sessionID)
            case let .questionAsked(p): scheduleIdleNudgeIfNeeded(for: p.sessionID)
            default: break
            }
        }

        // Antigravity only emits per-tool-call hooks with no turn/session end,
        // so keep its session "active" while tool events arrive and settle it to
        // idle after a quiet gap (see armAntigravitySettleTimer).
        if case let .activityUpdated(p) = event,
           p.phase == .running,
           state.session(id: p.sessionID)?.tool == .antigravity {
            armAntigravitySettleTimer(for: p.sessionID)
        } else if case let .sessionCompleted(p) = event {
            cancelAntigravitySettleTimer(for: p.sessionID)
        }

        // The pill flash is the "subtle" completion signal: immediate, silent,
        // and shown for every fresh completion. Whether the notch also opens
        // (with sound) is decided by the coalescer below, after the settle
        // window, through the single presentation path — so completions honour
        // `suppressFrontmostNotifications` like approvals and questions do.
        if case let .sessionCompleted(payload) = event, !wasAlreadyCompleted, payload.isInterrupt != true, payload.isSessionEnd != true {
            completionFlashSessionID = payload.sessionID

            // Clear the flash after a delay
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if completionFlashSessionID == payload.sessionID {
                    completionFlashSessionID = nil
                }
            }
        }

        if ingress == .bridge {
            monitoring.markSessionAttached(for: event)
            monitoring.markSessionProcessAlive(for: event)
        }
        synchronizeSelection()
        discovery.refreshCodexRolloutTracking()
        refreshOverlayPlacementIfVisible()
        discovery.scheduleCodexSessionPersistence()
        discovery.scheduleClaudeSessionPersistence()
        discovery.scheduleOpenCodeSessionPersistence()
        discovery.scheduleCursorSessionPersistence()

        // Push events to the Watch/iPhone via the relay. Bump-worthy events
        // (approvals, questions, completions) go through the coalescer
        // instead so the watch doesn't buzz once per Codex sub-turn either.
        if let relay = watchRelay, !event.isCoalescedNotificationEvent(wasAlreadyCompleted: wasAlreadyCompleted) {
            relay.notifyEvent(event, session: event.sessionID.flatMap { state.session(id: $0) })
        }

        if updateLastActionMessage {
            lastActionMessage = describe(event)
        }

        coalesceNotification(
            for: event,
            priorPhase: priorPhase,
            wasAlreadyCompleted: wasAlreadyCompleted,
            ingress: ingress
        )

        // Tear down nudges for sessions that left their attention phase.
        reconcileNudgeTimers()
    }

    // MARK: - Notification coalescing

    /// Routes a freshly applied event through `NotificationCoalescer` and acts
    /// on its decision: `.present` opens the notification surface (via the
    /// single, frontmost-aware presentation path) and pushes to the watch
    /// relay; `.subtle` leaves only the pill flash; `.suppress` does nothing.
    /// Completions are held for the settle window first; any running or
    /// attention signal in the same group cancels the hold.
    private func coalesceNotification(
        for event: AgentEvent,
        priorPhase: SessionPhase?,
        wasAlreadyCompleted: Bool,
        ingress: TrackedEventIngress
    ) {
        guard let sessionID = event.sessionID,
              let session = state.session(id: sessionID) else {
            return
        }
        let group = NotificationGroupKey(session: session)
        let now = Date()

        switch event {
        case let .sessionCompleted(payload):
            guard !wasAlreadyCompleted,
                  payload.isInterrupt != true,
                  payload.isSessionEnd != true,
                  ingress == .bridge || !isResolvingInitialLiveSessions else {
                if payload.isInterrupt == true {
                    // The user stopped the agent themselves — they're present.
                    cancelPendingCompletion(in: group)
                }
                return
            }
            notificationCoalescer.holdCompletion(payload, group: group, now: now)
            armCompletionSettleTimer(for: group, ingress: ingress)

        case .permissionRequested, .questionAsked:
            // The session is asking for the user; whatever sibling completion
            // was pending is not the end of the task.
            cancelPendingCompletion(in: group)

            let surface = IslandSurface.sessionList(actionableSessionID: sessionID)
            let decision = notificationCoalescer.decideRequest(
                group: group,
                isRepeatOfPendingRequest: priorPhase == session.phase,
                isAlreadyPresented: isNotificationSurfaceCurrentlyPresented(surface),
                now: now
            )
            guard decision == .present else { return }
            watchRelay?.notifyEvent(event, session: session)
            scheduleNotificationSurfacePresentationIfNeeded(surface, ingress: ingress)

        default:
            // Any signal that leaves the session active again (a new prompt,
            // a tool call, a sibling thread starting) means the group's task
            // is still going: drop the pending completion bump.
            if session.phase == .running || session.phase.requiresAttention {
                cancelPendingCompletion(in: group)
            }
        }
    }

    private func armCompletionSettleTimer(for group: NotificationGroupKey, ingress: TrackedEventIngress) {
        completionSettleTimers[group]?.cancel()
        let settleSeconds = notificationCoalescer.policy.completionSettleSeconds
        completionSettleTimers[group] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(settleSeconds))
            guard let self, !Task.isCancelled else { return }
            self.completionSettleTimers[group] = nil
            self.settleCompletion(in: group, ingress: ingress)
        }
    }

    private func settleCompletion(in group: NotificationGroupKey, ingress: TrackedEventIngress) {
        let pendingSessionID = notificationCoalescer.pendingCompletion(in: group)?.payload.sessionID
        let surface = IslandSurface.sessionList(actionableSessionID: pendingSessionID)
        guard let settled = notificationCoalescer.settleCompletion(
            in: group,
            isAlreadyPresented: isNotificationSurfaceCurrentlyPresented(surface),
            now: Date()
        ) else {
            return
        }

        // The session may have moved on during the settle window (e.g. a
        // late running signal that raced the timer); only a session that is
        // still completed gets surfaced.
        guard let session = state.session(id: settled.payload.sessionID),
              session.phase == .completed else {
            return
        }

        if settled.decision != .suppress {
            beginFinishedPeek(for: settled.payload.sessionID)
        }

        switch settled.decision {
        case .present:
            watchRelay?.notifyEvent(.sessionCompleted(settled.payload), session: session)
            scheduleNotificationSurfacePresentationIfNeeded(surface, ingress: ingress)
        case .subtle:
            // The pill flash already ran when the completion arrived. Re-arm
            // it so the settled completion still gets its silent cue.
            showSubtleCompletion(sessionID: settled.payload.sessionID, bounce: false)
        case .suppress:
            break
        }
    }

    /// The `.subtle` completion cue: a silent pill flash, plus a `notchPop()`
    /// bounce when the completion was downgraded because its terminal is
    /// frontmost (see `NotificationCoalescer.decisionForFrontmostSession`).
    private func showSubtleCompletion(sessionID: String, bounce: Bool) {
        completionFlashSessionID = sessionID
        if bounce {
            notchPop()
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.completionFlashSessionID == sessionID else { return }
            self.completionFlashSessionID = nil
        }
    }

    private func cancelPendingCompletion(in group: NotificationGroupKey) {
        notificationCoalescer.cancelPendingCompletion(in: group)
        completionSettleTimers[group]?.cancel()
        completionSettleTimers[group] = nil
    }

    private func cancelAllCompletionSettleTimers() {
        completionSettleTimers.values.forEach { $0.cancel() }
        completionSettleTimers.removeAll()
    }

    /// True when `surface` is what the notch is showing right now as a
    /// notification card, in which case re-presenting would only replay the
    /// sound and restart the open animation.
    private func isNotificationSurfaceCurrentlyPresented(_ surface: IslandSurface) -> Bool {
        notchStatus == .opened
            && notchOpenReason == .notification
            && surface.isNotificationCard
            && islandSurface == surface
    }

    /// Test-only view of the coalescer's pending completions.
    func pendingCompletionSessionIDsForTests() -> [String] {
        notificationCoalescer.pendingCompletions.values.map(\.payload.sessionID).sorted()
    }

    private func scheduleNotificationSurfacePresentationIfNeeded(
        _ surface: IslandSurface,
        ingress: TrackedEventIngress
    ) {
        guard notificationSurfaceIsEligibleForPresentation(surface, ingress: ingress),
              let sessionID = surface.sessionID,
              let session = state.session(id: sessionID) else {
            return
        }

        guard suppressFrontmostNotifications else {
            presentNotificationSurface(surface)
            return
        }

        notificationPresentationTask?.cancel()
        notificationPresentationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            // Tab-precise for Ghostty / Terminal / iTerm, app-level for Warp,
            // IDEs and anything else the probe can't see into.
            let isFrontmost = await self.isOwningTerminalFocused(session)
            guard !Task.isCancelled,
                  self.notificationSurfaceIsEligibleForPresentation(surface, ingress: ingress) else {
                return
            }

            guard isFrontmost else {
                self.presentNotificationSurface(surface)
                return
            }

            // Focus-aware: the user is already in this session's terminal.
            let isCompletion = self.state.session(id: sessionID)?.phase == .completed
            switch NotificationCoalescer.decisionForFrontmostSession(isCompletion: isCompletion) {
            case .subtle:
                self.showSubtleCompletion(sessionID: sessionID, bounce: true)
            case .present:
                self.presentNotificationSurface(surface)
            case .suppress:
                break
            }
        }
    }

    private func notificationSurfaceIsEligibleForPresentation(
        _ surface: IslandSurface,
        ingress: TrackedEventIngress
    ) -> Bool {
        guard let sessionID = surface.sessionID,
              let session = state.session(id: sessionID) else {
            return false
        }

        return (ingress == .bridge || !isResolvingInitialLiveSessions)
            && (notchStatus == .closed || notchOpenReason == .notification)
            && !isNotificationSurfaceCurrentlyPresented(surface)
            && !overlay.shouldPreserveCurrentNotificationSurface(against: surface)
            && surface.matchesCurrentState(of: session)
    }

    private func synchronizeSelection() {
        let surfacedIDs = Set(surfacedSessions.map(\.id))

        if let activeAction = state.activeActionableSession {
            selectedSessionID = activeAction.id
            return
        }

        guard let selectedSessionID,
              surfacedIDs.contains(selectedSessionID),
              state.session(id: selectedSessionID) != nil else {
            self.selectedSessionID = surfacedSessions.first?.id ?? state.sessions.first?.id
            return
        }
    }

    /// Applies startup discovery results on the main thread after background I/O completes.
    private func applyStartupDiscoveryPayload(_ payload: SessionDiscoveryCoordinator.StartupDiscoveryPayload) {
        discovery.applyStartupDiscoveryPayload(payload)

        // Apply hooks binary URL and update the installed copy if the app ships a newer version.
        hooks.hooksBinaryURL = payload.hooksBinaryURL
        hooks.updateHooksBinaryIfNeeded()

        // Auto-install missing hooks and usage bridge, then run health checks.
        if payload.hooksBinaryURL != nil {
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Wait for all status reads to complete before checking install state.
                await self.hooks.refreshAllHookStatusAndWait()

                // Reconcile persisted intent with what is actually on disk. For
                // legacy users this records existing hooks as `.installed` and
                // marks first-launch as complete so onboarding does not appear
                // on upgrade. Must run after status reads and before any
                // install decision.
                self.hooks.migrateIntentStoreIfNeeded()

                if !self.firstLaunchCompleted {
                    self.showOnboarding()
                }

                // Install only hooks the user has not explicitly opted out of.
                // `shouldAutoInstall` skips `.uninstalled` agents and agents
                // whose hooks are already present — it is the single checkpoint
                // that fixes #324.
                if self.hooks.shouldAutoInstall(.claudeCode) { self.installClaudeHooks() }
                if self.hooks.shouldAutoInstall(.codex) { self.installCodexHooks() }
                if self.hooks.shouldAutoInstall(.qoder) { self.installQoderHooks() }
                if self.hooks.shouldAutoInstall(.qwenCode) { self.installQwenCodeHooks() }
                if self.hooks.shouldAutoInstall(.factory) { self.installFactoryHooks() }
                if self.hooks.shouldAutoInstall(.codebuddy) { self.installCodebuddyHooks() }
                if self.hooks.shouldAutoInstall(.openCode) { self.installOpenCodePlugin() }
                if self.hooks.shouldAutoInstall(.cursor) { self.installCursorHooks() }
                if self.hooks.shouldAutoInstall(.gemini) { self.installGeminiHooks() }
                if self.hooks.shouldAutoInstall(.antigravity) { self.installAntigravityHooks() }
                if self.hooks.shouldAutoInstall(.kimi) { self.installKimiHooks() }
                if self.hooks.shouldAutoInstall(.claudeUsageBridge) { self.installClaudeUsageBridge() }

                // Run health checks after install to detect stale paths, conflicts, etc.
                try? await Task.sleep(for: .milliseconds(500))
                await self.hooks.repairHooksIfNeeded()
            }
        }

        // Reconcile attachments and start monitoring (requires sessions to be loaded).
        monitoring.reconcileSessionAttachments()
        monitoring.startMonitoringIfNeeded()
    }


    private var sessionBuckets: (primary: [AgentSession], overflow: [AgentSession]) {
        if let cached = _cachedSessionBuckets {
            return cached
        }
        let result = computeSessionBuckets()
        _cachedSessionBuckets = result
        return result
    }

    private func computeSessionBuckets() -> (primary: [AgentSession], overflow: [AgentSession]) {
        let now = Date.now
        let rankedSessions = state.sessions.sorted { lhs, rhs in
            let lhsScore = displayPriority(for: lhs, now: now)
            let rhsScore = displayPriority(for: rhs, now: now)

            if lhsScore == rhsScore {
                if lhs.islandActivityDate == rhs.islandActivityDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }

                return lhs.islandActivityDate > rhs.islandActivityDate
            }

            return lhsScore > rhsScore
        }

        var primary: [AgentSession] = []
        var claimedLiveAttachmentKeys: Set<String> = []

        for session in rankedSessions where session.isVisibleInIsland {
            guard !session.isSubagentSession else { continue }

            if let liveAttachmentKey = monitoring.liveAttachmentKey(for: session) {
                guard claimedLiveAttachmentKeys.insert(liveAttachmentKey).inserted else {
                    continue
                }
            }

            primary.append(session)
        }

        let primaryIDs = Set(primary.map(\.id))
        let overflow = rankedSessions.filter { !primaryIDs.contains($0.id) && !$0.isSubagentSession }
        return (primary, overflow)
    }

    private func displayPriority(for session: AgentSession, now: Date) -> Int {
        var score = 0

        let presence = session.islandPresence(at: now)

        if session.isProcessAlive {
            score += presence == .inactive ? 3_000 : 12_000
        } else if session.isDemoSession || session.phase.requiresAttention {
            score += 6_000
        }

        if session.phase.requiresAttention {
            score += 10_000
        }

        if session.currentToolName?.isEmpty == false {
            score += 6_000
        }

        if session.jumpTarget != nil {
            score += 4_000
        }

        switch session.phase {
        case .running:
            score += 2_000
        case .waitingForApproval:
            score += 1_500
        case .waitingForAnswer:
            score += 1_200
        case .completed:
            score += 600
        }

        if session.isStaleCompletedForIsland(at: now, threshold: completedStaleThreshold.seconds) {
            score -= 900
        }

        let age = now.timeIntervalSince(session.islandActivityDate)
        switch age {
        case ..<120:
            score += 500
        case ..<900:
            score += 250
        case ..<3_600:
            score += 120
        case ..<21_600:
            score += 40
        default:
            break
        }

        return score
    }

    private func describe(_ event: AgentEvent) -> String {
        switch event {
        case let .sessionStarted(payload):
            return "Session started: \(payload.title)"
        case let .activityUpdated(payload):
            return payload.summary
        case let .permissionRequested(payload):
            return payload.request.summary
        case let .questionAsked(payload):
            return payload.prompt.title
        case let .sessionCompleted(payload):
            return payload.summary
        case let .jumpTargetUpdated(payload):
            return "Jump target updated to \(payload.jumpTarget.terminalApp)."
        case let .sessionMetadataUpdated(payload):
            if let currentTool = payload.codexMetadata.currentTool {
                return "Codex is running \(currentTool)."
            }

            return payload.codexMetadata.lastAssistantMessage ?? "Codex session metadata updated."
        case let .claudeSessionMetadataUpdated(payload):
            if let currentTool = payload.claudeMetadata.currentTool {
                return "Claude is running \(currentTool)."
            }

            return payload.claudeMetadata.lastAssistantMessage ?? "Claude session metadata updated."
        case let .geminiSessionMetadataUpdated(payload):
            return payload.geminiMetadata.lastAssistantMessage ?? "Gemini session metadata updated."
        case let .antigravitySessionMetadataUpdated(payload):
            if let currentTool = payload.antigravityMetadata.currentTool {
                return "Antigravity is running \(currentTool)."
            }

            return payload.antigravityMetadata.lastAssistantMessage ?? "Antigravity session metadata updated."
        case let .openCodeSessionMetadataUpdated(payload):
            if let currentTool = payload.openCodeMetadata.currentTool {
                return "OpenCode is running \(currentTool)."
            }

            return payload.openCodeMetadata.lastAssistantMessage ?? "OpenCode session metadata updated."
        case let .cursorSessionMetadataUpdated(payload):
            if let currentTool = payload.cursorMetadata.currentTool {
                return "Cursor is running \(currentTool)."
            }

            return payload.cursorMetadata.lastAssistantMessage ?? "Cursor session metadata updated."
        case let .jumpTargetSynchronized(payload):
            return "Jump target synchronized to \(payload.jumpTarget.terminalApp)."
        case let .actionableStateResolved(payload):
            return "Actionable state resolved for session \(payload.sessionID)."
        }
    }

    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

}

// MARK: - Hex color helpers

extension String {
    var normalizedHexColorString: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard raw.count == 6, raw.allSatisfy(\.isHexDigit) else { return "#6E9FFF" }
        return "#\(raw.uppercased())"
    }
}

extension Color {
    init?(hex: String) {
        let raw = String(hex.normalizedHexColorString.dropFirst())
        guard let value = Int(raw, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self = Color(red: red, green: green, blue: blue)
    }

    var opaqueHexString: String? {
        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - AgentEvent helpers for notification coalescing

private extension AgentEvent {
    var sessionID: String? {
        switch self {
        case let .sessionStarted(p): p.sessionID
        case let .activityUpdated(p): p.sessionID
        case let .permissionRequested(p): p.sessionID
        case let .questionAsked(p): p.sessionID
        case let .sessionCompleted(p): p.sessionID
        case let .jumpTargetUpdated(p): p.sessionID
        case let .sessionMetadataUpdated(p): p.sessionID
        case let .claudeSessionMetadataUpdated(p): p.sessionID
        case let .geminiSessionMetadataUpdated(p): p.sessionID
        case let .antigravitySessionMetadataUpdated(p): p.sessionID
        case let .openCodeSessionMetadataUpdated(p): p.sessionID
        case let .cursorSessionMetadataUpdated(p): p.sessionID
        case let .jumpTargetSynchronized(p): p.sessionID
        case let .actionableStateResolved(p): p.sessionID
        }
    }

    /// Events whose watch-relay push is gated by the coalescer's decision
    /// rather than sent straight through: approvals, questions, and fresh
    /// (non-interrupt, non-session-end) completions.
    func isCoalescedNotificationEvent(wasAlreadyCompleted: Bool) -> Bool {
        switch self {
        case .permissionRequested, .questionAsked:
            true
        case let .sessionCompleted(p):
            !wasAlreadyCompleted && p.isInterrupt != true && p.isSessionEnd != true
        default:
            false
        }
    }
}
