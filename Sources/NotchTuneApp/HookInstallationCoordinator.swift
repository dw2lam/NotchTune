import Foundation
import Observation
import NotchTuneCore

@MainActor
@Observable
final class HookInstallationCoordinator {
    @ObservationIgnored
    let intentStore: AgentIntentStore

    init(intentStore: AgentIntentStore = AgentIntentStore()) {
        self.intentStore = intentStore
    }

    var codexHookStatus: CodexHookInstallationStatus?
    var claudeHookStatus: ClaudeHookInstallationStatus?
    var qoderHookStatus: ClaudeHookInstallationStatus?
    var qwenCodeHookStatus: ClaudeHookInstallationStatus?
    var factoryHookStatus: ClaudeHookInstallationStatus?
    var codebuddyHookStatus: ClaudeHookInstallationStatus?
    var openCodePluginStatus: OpenCodePluginInstallationStatus?
    var cursorHookStatus: CursorHookInstallationStatus?
    var geminiHookStatus: GeminiHookInstallationStatus?
    var antigravityHookStatus: AntigravityHookInstallationStatus?
    var kimiHookStatus: KimiHookInstallationStatus?
    var claudeStatusLineStatus: ClaudeStatusLineInstallationStatus?
    var claudeUsageSnapshot: ClaudeUsageSnapshot?
    var codexUsageSnapshot: CodexUsageSnapshot?
    var geminiUsageSnapshot: GeminiUsageSnapshot?
    var hooksBinaryURL: URL?
    var isCodexSetupBusy = false
    var isClaudeHookSetupBusy = false
    var isQoderHookSetupBusy = false
    var isQwenCodeHookSetupBusy = false
    var isFactoryHookSetupBusy = false
    var isCodebuddyHookSetupBusy = false
    var isOpenCodeSetupBusy = false
    var isCursorHookSetupBusy = false
    var isGeminiHookSetupBusy = false
    var isAntigravityHookSetupBusy = false
    var isKimiHookSetupBusy = false
    var isClaudeUsageSetupBusy = false
    /// An install, repair or removal is running for some agent.
    var isAnyHookSetupBusy: Bool {
        isCodexSetupBusy || isClaudeHookSetupBusy || isQoderHookSetupBusy || isQwenCodeHookSetupBusy
            || isFactoryHookSetupBusy || isCodebuddyHookSetupBusy || isOpenCodeSetupBusy
            || isCursorHookSetupBusy || isGeminiHookSetupBusy || isAntigravityHookSetupBusy
            || isKimiHookSetupBusy
    }

    @ObservationIgnored
    var onStatusMessage: ((String) -> Void)?

    /// One plain sentence for the user; `AppModel` posts it as a notice.
    @ObservationIgnored
    var onFailure: ((String) -> Void)?

    /// The last install or uninstall failure per agent, shown on its Setup row
    /// until the next attempt.
    var setupFailures: [AgentIdentifier: String] = [:]

    /// Shared with `BridgeServer`, which records into it.
    nonisolated static let activityStore = HookActivityStore()

    /// Only a real launch may spawn an agent's own CLI; a harness capture
    /// never gets past `.notRun` on this.
    @ObservationIgnored
    var allowsAgentProbes = false

    @ObservationIgnored
    private let codexHookInstallationManager = CodexHookInstallationManager()

    /// Computed so it always reflects the latest `ClaudeConfigDirectory` setting.
    private var claudeHookInstallationManager: ClaudeHookInstallationManager {
        ClaudeHookInstallationManager()
    }

    @ObservationIgnored
    private let qoderHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".qoder", isDirectory: true),
        hookSource: "qoder"
    )

    @ObservationIgnored
    private let qwenCodeHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".qwen", isDirectory: true),
        hookSource: "qwen"
    )

    @ObservationIgnored
    private let factoryHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".factory", isDirectory: true),
        hookSource: "factory"
    )

    @ObservationIgnored
    private let codebuddyHookInstallationManager = ClaudeHookInstallationManager(
        claudeDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codebuddy", isDirectory: true),
        hookSource: "codebuddy"
    )

    @ObservationIgnored
    private let openCodePluginInstallationManager = OpenCodePluginInstallationManager()

    @ObservationIgnored
    private let cursorHookInstallationManager = CursorHookInstallationManager()

    @ObservationIgnored
    private let geminiHookInstallationManager = GeminiHookInstallationManager()

    @ObservationIgnored
    private let antigravityHookInstallationManager = AntigravityHookInstallationManager()

    /// Computed: installing Kimi Code later moves its config directory.
    private var kimiHookInstallationManager: KimiHookInstallationManager {
        KimiHookInstallationManager()
    }

    /// Computed so it always reflects the latest `ClaudeConfigDirectory` setting.
    private var claudeStatusLineInstallationManager: ClaudeStatusLineInstallationManager {
        ClaudeStatusLineInstallationManager()
    }

    @ObservationIgnored
    private var claudeUsageMonitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var codexUsageMonitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var geminiUsageMonitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var relativeTimestampFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }

    // MARK: - Computed display properties

    var codexHooksInstalled: Bool {
        codexHookStatus?.managedHooksPresent == true
    }

    var claudeHooksInstalled: Bool {
        claudeHookStatus?.managedHooksPresent == true
    }

    var qoderHooksInstalled: Bool {
        qoderHookStatus?.managedHooksPresent == true
    }

    var qwenCodeHooksInstalled: Bool {
        qwenCodeHookStatus?.managedHooksPresent == true
    }

    var factoryHooksInstalled: Bool {
        factoryHookStatus?.managedHooksPresent == true
    }

    var codebuddyHooksInstalled: Bool {
        codebuddyHookStatus?.managedHooksPresent == true
    }

    var openCodePluginInstalled: Bool {
        openCodePluginStatus?.isInstalled == true
    }

    var cursorHooksInstalled: Bool {
        cursorHookStatus?.managedHooksPresent == true
    }

    var geminiHooksInstalled: Bool {
        geminiHookStatus?.managedHooksPresent == true
    }

    var antigravityHooksInstalled: Bool {
        antigravityHookStatus?.managedHooksPresent == true
    }

    var kimiHooksInstalled: Bool {
        kimiHookStatus?.managedHooksPresent == true
    }

    var claudeUsageInstalled: Bool {
        claudeStatusLineStatus?.managedStatusLineInstalled == true
    }

    var claudeHookStatusTitle: String {
        if claudeHooksInstalled {
            return "Claude hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Claude hooks not installed"
    }

    var claudeHookStatusSummary: String {
        guard let status = claudeHookStatus else {
            return "Reading \(ClaudeConfigDirectory.resolved().appendingPathComponent("settings.json").path)."
        }

        if claudeHooksInstalled {
            if status.hasClaudeIslandHooks {
                return "managed hooks present · claude-island hooks also detected"
            }
            return "managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Build NotchTuneHooks before installing."
        }

        if status.hasClaudeIslandHooks {
            return "claude-island hooks detected · managed hooks absent"
        }

        return "no managed Claude hooks"
    }

    var claudeUsageStatusTitle: String {
        guard let status = claudeStatusLineStatus else {
            return "Claude usage status unavailable"
        }

        if status.managedStatusLineInstalled {
            return "Claude usage bridge installed"
        }

        if status.managedStatusLineNeedsRepair {
            return "Claude usage bridge needs repair"
        }

        if status.hasConflictingStatusLine {
            return "Custom Claude status line detected"
        }

        return "Claude usage bridge not installed"
    }

    var claudeUsageStatusSummary: String {
        guard let status = claudeStatusLineStatus else {
            return "Reading \(ClaudeConfigDirectory.resolved().appendingPathComponent("settings.json").path)."
        }

        if status.managedStatusLineInstalled {
            if let summary = claudeUsageSummaryText {
                return "Caching rate limits from Claude Code · \(summary)"
            }
            return "Caching rate limits from Claude Code into \(status.cacheURL.path)."
        }

        if status.managedStatusLineNeedsRepair {
            return "NotchTune detected a missing managed Claude status line script and will repair it automatically."
        }

        if status.hasConflictingStatusLine {
            return "NotchTune will not overwrite an existing Claude status line automatically."
        }

        return "Install a managed Claude status line to cache 5h and 7d usage locally."
    }

    var claudeUsageSummaryText: String? {
        guard let snapshot = claudeUsageSnapshot else {
            return nil
        }

        var components: [String] = []
        if let fiveHour = snapshot.fiveHour {
            components.append("5h \(fiveHour.roundedUsedPercentage)%")
        }
        if let sevenDay = snapshot.sevenDay {
            components.append("7d \(sevenDay.roundedUsedPercentage)%")
        }
        if let cachedAt = snapshot.cachedAt {
            components.append("updated \(relativeTimestampFormatter.localizedString(for: cachedAt, relativeTo: .now))")
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    var codexUsageStatusTitle: String {
        if codexUsageSnapshot?.isEmpty == false {
            return "Codex rate limits detected"
        }

        return "Waiting for Codex rate limits"
    }

    var codexUsageStatusSummary: String {
        if let summary = codexUsageSummaryText {
            return "Reading the latest local rollout token_count snapshots · \(summary)"
        }

        return "Passively reading ~/.codex/sessions/**/rollout-*.jsonl and extracting token_count.rate_limits."
    }

    var codexUsageSummaryText: String? {
        guard let snapshot = codexUsageSnapshot else {
            return nil
        }

        var components = snapshot.windows.map { window in
            "\(window.label) \(window.roundedUsedPercentage)%"
        }

        if let planType = snapshot.planType {
            components.append("plan \(planType)")
        }

        if let capturedAt = snapshot.capturedAt {
            components.append("updated \(relativeTimestampFormatter.localizedString(for: capturedAt, relativeTo: .now))")
        }

        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    var openCodePluginStatusTitle: String {
        if openCodePluginInstalled {
            return "OpenCode plugin installed"
        }

        return "OpenCode plugin not installed"
    }

    var openCodePluginStatusSummary: String {
        guard let status = openCodePluginStatus else {
            return "Reading ~/.config/opencode state."
        }

        if status.isInstalled {
            return "managed plugin present in \(status.pluginsDirectory.path)"
        }

        return "no managed OpenCode plugin"
    }

    var cursorHookStatusTitle: String {
        if cursorHooksInstalled {
            return "Cursor hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Cursor hooks not installed"
    }

    var cursorHookStatusSummary: String {
        guard cursorHookStatus != nil else {
            return "Reading ~/.cursor/hooks.json."
        }

        if cursorHooksInstalled {
            return "managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Build NotchTuneHooks before installing."
        }

        return "no managed Cursor hooks"
    }

    var geminiHookStatusTitle: String {
        guard let status = geminiHookStatus else { return "Gemini hooks loading" }
        return status.managedHooksPresent ? "Gemini hooks installed" : "Gemini hooks not installed"
    }

    var geminiHookStatusSummary: String {
        guard let status = geminiHookStatus else {
            return "Reading ~/.gemini/settings.json."
        }

        if hooksBinaryURL == nil {
            return "Build NotchTuneHooks before installing."
        }

        return status.managedHooksPresent ? "managed hooks present" : "no managed Gemini hooks"
    }

    var kimiHookStatusTitle: String {
        if kimiHooksInstalled {
            return "Kimi hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Kimi hooks not installed"
    }

    var kimiHookStatusSummary: String {
        guard kimiHookStatus != nil else {
            return "Reading Kimi's config.toml."
        }

        if kimiHooksInstalled {
            return "managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Build NotchTuneHooks before installing."
        }

        return "no managed Kimi hooks"
    }

    var codexHookStatusTitle: String {
        if codexHooksInstalled {
            return "Codex hooks installed"
        }

        if hooksBinaryURL == nil {
            return "Hook binary not found"
        }

        return "Codex hooks not installed"
    }

    var codexHookStatusSummary: String {
        guard let status = codexHookStatus else {
            return "Reading ~/.codex state."
        }

        if codexHooksInstalled {
            let featureText = status.featureFlagEnabled ? "feature on" : "feature off"
            return "\(featureText) · managed hooks present"
        }

        if hooksBinaryURL == nil {
            return "Build NotchTuneHooks before installing."
        }

        return status.featureFlagEnabled ? "feature on · no managed hooks" : "feature off · no managed hooks"
    }

    // MARK: - Claude config directory

    /// Updates the custom Claude config directory, cleans up old hooks if present, and refreshes status.
    func updateClaudeConfigDirectory(to newDirectory: URL?) {
        let oldDirectory = ClaudeConfigDirectory.resolved()
        let oldHadHooks = claudeHookStatus?.managedHooksPresent == true

        ClaudeConfigDirectory.customDirectory = newDirectory

        // Refresh status from the new directory
        refreshClaudeHookStatus()
        refreshClaudeUsageState()

        let newPath = ClaudeConfigDirectory.resolved().path
        if oldHadHooks {
            let oldPath = oldDirectory.path
            if oldPath != newPath {
                onStatusMessage?("Claude config directory changed to \(newPath). Hooks in \(oldPath) were not removed — uninstall them manually if no longer needed.")
            }
        } else {
            onStatusMessage?("Claude config directory set to \(newPath).")
        }
    }

    // MARK: - Auto-update hooks binary

    /// Overwrites the installed hooks binary if the app bundle ships a newer version.
    /// Call once at startup after hooksBinaryURL is set.
    func updateHooksBinaryIfNeeded() {
        guard let sourceURL = hooksBinaryURL else { return }

        // Restore a deleted binary only if some agent's hooks point at it.
        let restoreIfMissing = !intentStore.installedAgents().isEmpty

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let source = sourceURL
                let updated = try await Task.detached(priority: .utility) {
                    try ManagedHooksBinary.updateIfNeeded(from: source, restoreIfMissing: restoreIfMissing)
                }.value
                if updated {
                    self.onStatusMessage?("Hooks binary updated to match the current app version.")
                    self.refreshCodexHookStatus()
                    self.refreshClaudeHookStatus()
                    self.refreshCursorHookStatus()
                    self.refreshGeminiHookStatus()
                    self.refreshAntigravityHookStatus()
                }
            } catch {
                self.onStatusMessage?("Failed to update hooks binary: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Health check & auto-repair

    var healthReports: [AgentIdentifier: HookHealthReport] = [:]
    var doctorReports: [IntegrationDiagnosis] = []
    var hookTestResults: [AgentIdentifier: HookRoundTripResult] = [:]
    var hookTestsRunning: Set<AgentIdentifier> = []

    /// Captures show a fixed doctor instead of this Mac's real one.
    @ObservationIgnored
    private var isShowingSampleDoctor = false

    /// Refreshes every agent's report. Reads only: nothing here repairs.
    func runHealthChecks() {
        Task { @MainActor [weak self] in
            await self?.examineHooks()
        }
    }

    private func examineHooks() async {
        guard !isShowingSampleDoctor else { return }

        let binaryURL = hooksBinaryURL
        let probesCodexTrust = allowsAgentProbes
        let intents = Dictionary(uniqueKeysWithValues: AgentIdentifier.hookAgents.map { ($0, intentStore.intent(for: $0)) })
        let present = Dictionary(uniqueKeysWithValues: AgentIdentifier.hookAgents.map { ($0, isHookInstalled($0)) })
        let lastEvents = Dictionary(uniqueKeysWithValues: AgentIdentifier.hookAgents.compactMap { agent in
            Self.activityStore.lastEvent(for: agent).map { (agent, $0) }
        })

        let result = await Task.detached(priority: .utility) {
            IntegrationDoctor.examine(
                hooksBinaryURL: binaryURL,
                hooksPresent: present,
                intents: intents,
                lastEvents: lastEvents,
                drops: HookDropLog().read(),
                probesCodexTrust: probesCodexTrust
            )
        }.value

        healthReports = result.reports
        doctorReports = result.diagnoses
    }

    func isHookInstalled(_ agent: AgentIdentifier) -> Bool {
        switch agent {
        case .claudeCode: claudeHooksInstalled
        case .codex: codexHooksInstalled
        case .cursor: cursorHooksInstalled
        case .qoder: qoderHooksInstalled
        case .qwenCode: qwenCodeHooksInstalled
        case .factory: factoryHooksInstalled
        case .codebuddy: codebuddyHooksInstalled
        case .openCode: openCodePluginInstalled
        case .gemini: geminiHooksInstalled
        case .kimi: kimiHooksInstalled
        case .antigravity: antigravityHooksInstalled
        case .claudeUsageBridge: claudeUsageInstalled
        }
    }

    func installHooks(for agent: AgentIdentifier) {
        switch agent {
        case .claudeCode: installClaudeHooks()
        case .codex: installCodexHooks()
        case .cursor: installCursorHooks()
        case .qoder: installQoderHooks()
        case .qwenCode: installQwenCodeHooks()
        case .factory: installFactoryHooks()
        case .codebuddy: installCodebuddyHooks()
        case .openCode: installOpenCodePlugin()
        case .gemini: installGeminiHooks()
        case .kimi: installKimiHooks()
        case .antigravity: installAntigravityHooks()
        case .claudeUsageBridge: installClaudeUsageBridge()
        }
    }

    /// Agents "Install All" may touch: the ones whose tool is on this Mac.
    /// Installing means creating config, and a folder for a tool the user
    /// doesn't have is clutter and a false "detected" later.
    var installAllAgents: [AgentIdentifier] {
        let detected = HookAgentCatalog.descriptors()
            .filter { HookAgentCatalog.isToolPresent($0) }
            .map(\.agent)
        return detected.contains(.claudeCode) ? detected + [.claudeUsageBridge] : detected
    }

    func installAllDetectedHooks() {
        for agent in installAllAgents where !isHookInstalled(agent) {
            installHooks(for: agent)
        }
    }

    /// The doctor's Test hook, off the main actor: it spawns the binary.
    func testHook(for agent: AgentIdentifier) {
        guard !hookTestsRunning.contains(agent),
              let descriptor = HookAgentCatalog.descriptors().first(where: { $0.agent == agent }) else {
            return
        }

        hookTestsRunning.insert(agent)
        hookTestResults[agent] = nil

        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                HookRoundTripTest.run(descriptor)
            }.value

            self?.hookTestsRunning.remove(agent)
            self?.hookTestResults[agent] = result
        }
    }

    /// Fixed reports for harness captures (`NOTCHTUNE_HARNESS_SAMPLE_DOCTOR=1`).
    func loadSampleDoctorReports() {
        isShowingSampleDoctor = true
        let now = Date.now

        func sample(
            _ agent: AgentIdentifier,
            _ name: String,
            _ status: IntegrationDiagnosis.Status,
            findings: [IntegrationDiagnosis.Finding] = [],
            fix: IntegrationDiagnosis.Fix? = nil,
            lastEvent: TimeInterval? = nil,
            dropped: Int = 0
        ) -> IntegrationDiagnosis {
            IntegrationDiagnosis(
                agent: agent,
                displayName: name,
                status: status,
                findings: findings,
                fix: fix,
                lastEventAt: lastEvent.map { now.addingTimeInterval(-$0) },
                droppedEvents: dropped,
                lastDroppedEvent: dropped > 0 ? "PostCompact" : nil,
                toolPresent: true
            )
        }

        doctorReports = [
            sample(.claudeCode, "Claude Code", .working, lastEvent: 90, dropped: 3),
            sample(.codex, "Codex", .needsRepair, findings: [.codexHooksNeedReview(count: 4)]),
            sample(.openCode, "OpenCode", .needsRepair, findings: [.pluginOutdated], fix: .reinstall, lastEvent: 86_400 * 3),
            sample(.cursor, "Cursor", .noEventsYet),
            sample(.gemini, "Gemini CLI", .notInstalled),
        ]
        hookTestResults[.claudeCode] = .passed
        hookTestResults[.cursor] = HookRoundTripResult(failedStep: .bridge, failure: .bridgeUnreachable)
        setupFailures[.kimi] = "NotchTune couldn't install Kimi CLI hooks. config.toml is not UTF-8 text, so it was left untouched."
    }

    /// Re-installs what's broken, for the agents the user asked NotchTune to
    /// manage and no others. Returns true if any repairs were attempted.
    @discardableResult
    func repairHooksIfNeeded() async -> Bool {
        await examineHooks()

        let agents = HookRepairPolicy.agentsToRepair(
            reports: healthReports,
            intent: intentStore.intent(for:),
            hooksBinaryAvailable: hooksBinaryURL != nil
        )

        guard !agents.isEmpty else {
            return false
        }

        for agent in agents {
            let issues = healthReports[agent]?.repairableIssues.map(\.description).joined(separator: "; ") ?? ""
            onStatusMessage?("Repairing \(agent.rawValue) hooks: \(issues)")
            installHooks(for: agent)
        }

        try? await Task.sleep(for: .milliseconds(500))
        await examineHooks()

        let remaining = agents.reduce(0) { $0 + (healthReports[$1]?.errors.count ?? 0) }
        onStatusMessage?(remaining == 0
            ? "Hook repair completed successfully."
            : "Hook repair finished with \(remaining) remaining issue(s).")
        return true
    }

    // MARK: - Failures

    /// A failed setup reaches the user twice: a notice now, and a line on the
    /// agent's row for whoever opens Setup later.
    private func reportSetupFailure(_ agent: AgentIdentifier, _ message: String) {
        setupFailures[agent] = message
        onStatusMessage?(message)
        onFailure?(message)
    }

    private func failureMessage(_ name: String, removing: Bool, _ error: any Error) -> String {
        let action = removing ? "remove" : "install"
        return "NotchTune couldn't \(action) \(name) hooks. \(error.localizedDescription)"
    }

    private static let missingBinaryMessage = "The NotchTuneHooks helper is missing, so hooks can't be installed. Reinstall NotchTune to restore it."

    // MARK: - Refresh

    func refreshCodexHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.codexHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.codexHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Codex hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshClaudeHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.claudeHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.claudeHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Claude hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshCCForkHookStatuses() {
        refreshCCForkHookStatus(manager: qoderHookInstallationManager, name: "Qoder") { [weak self] in self?.qoderHookStatus = $0 }
        refreshCCForkHookStatus(manager: qwenCodeHookInstallationManager, name: "Qwen Code") { [weak self] in self?.qwenCodeHookStatus = $0 }
        refreshCCForkHookStatus(manager: factoryHookInstallationManager, name: "Factory") { [weak self] in self?.factoryHookStatus = $0 }
        refreshCCForkHookStatus(manager: codebuddyHookInstallationManager, name: "CodeBuddy") { [weak self] in self?.codebuddyHookStatus = $0 }
    }

    private func refreshCCForkHookStatus(
        manager: ClaudeHookInstallationManager,
        name: String,
        apply: @MainActor @escaping (ClaudeHookInstallationStatus) -> Void
    ) {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try manager.status(hooksBinaryURL: self.hooksBinaryURL)
                apply(status)
            } catch {
                self.onStatusMessage?("Failed to read \(name) hook status: \(error.localizedDescription)")
            }
        }
    }

    /// Awaitable versions of refresh for use in startup flow to avoid race conditions.
    func refreshAllHookStatusAndWait() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.claudeHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.claudeHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Claude hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.codexHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.codexHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Codex hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.openCodePluginInstallationManager.status()
                    self.openCodePluginStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read OpenCode plugin status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let usageState = try self.readClaudeUsageState(
                        repairManagedBridgeIfNeeded: self.intentStore.intent(for: .claudeUsageBridge) == .installed
                    )
                    self.claudeStatusLineStatus = usageState.status
                    self.claudeUsageSnapshot = usageState.snapshot
                } catch {
                    self.onStatusMessage?("Failed to read Claude usage state: \(error.localizedDescription)")
                }
            }

            // CC fork agents
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                for (manager, name, apply) in [
                    (self.qoderHookInstallationManager, "Qoder", { [weak self] (s: ClaudeHookInstallationStatus) in self?.qoderHookStatus = s }),
                    (self.qwenCodeHookInstallationManager, "Qwen Code", { [weak self] (s: ClaudeHookInstallationStatus) in self?.qwenCodeHookStatus = s }),
                    (self.factoryHookInstallationManager, "Factory", { [weak self] (s: ClaudeHookInstallationStatus) in self?.factoryHookStatus = s }),
                    (self.codebuddyHookInstallationManager, "CodeBuddy", { [weak self] (s: ClaudeHookInstallationStatus) in self?.codebuddyHookStatus = s }),
                ] {
                    do {
                        let status = try manager.status(hooksBinaryURL: self.hooksBinaryURL)
                        apply(status)
                    } catch {
                        self.onStatusMessage?("Failed to read \(name) hook status: \(error.localizedDescription)")
                    }
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.geminiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.geminiHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Gemini hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.antigravityHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.antigravityHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Antigravity hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let status = try self.kimiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                    self.kimiHookStatus = status
                } catch {
                    self.onStatusMessage?("Failed to read Kimi hook status: \(error.localizedDescription)")
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                self.refreshGeminiUsageState()
            }
        }
    }

    func refreshOpenCodePluginStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.openCodePluginInstallationManager.status()
                self.openCodePluginStatus = status
            } catch {
                self.onStatusMessage?("Failed to read OpenCode plugin status: \(error.localizedDescription)")
            }
        }
    }

    func refreshCursorHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.cursorHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.cursorHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Cursor hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshGeminiHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.geminiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.geminiHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Gemini hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshAntigravityHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.antigravityHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.antigravityHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Antigravity hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshKimiHookStatus() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let status = try self.kimiHookInstallationManager.status(hooksBinaryURL: self.hooksBinaryURL)
                self.kimiHookStatus = status
            } catch {
                self.onStatusMessage?("Failed to read Kimi hook status: \(error.localizedDescription)")
            }
        }
    }

    func refreshClaudeUsageState() {
        let manager = claudeStatusLineInstallationManager
        let mayRepairBridge = intentStore.intent(for: .claudeUsageBridge) == .installed
        Task { [weak self] in
            guard let self else { return }

            do {
                let usageState = try await Task.detached(priority: .utility) {
                    var status = try manager.status()
                    var repairedManagedBridge = false
                    if status.managedStatusLineNeedsRepair, mayRepairBridge {
                        status = try manager.install()
                        repairedManagedBridge = true
                    }
                    let snapshot = try ClaudeUsageLoader.load()
                    return (status: status, snapshot: snapshot, repairedManagedBridge: repairedManagedBridge)
                }.value
                // @Observable does not diff — only write on real change so an
                // unchanged snapshot never re-renders usage readouts.
                if self.claudeStatusLineStatus != usageState.status {
                    self.claudeStatusLineStatus = usageState.status
                }
                if self.claudeUsageSnapshot != usageState.snapshot {
                    self.claudeUsageSnapshot = usageState.snapshot
                }
                if usageState.repairedManagedBridge {
                    self.onStatusMessage?("Recovered the Claude usage bridge after repairing a missing managed script.")
                }
            } catch {
                self.onStatusMessage?("Failed to read Claude usage state: \(error.localizedDescription)")
            }
        }
    }

    func refreshCodexUsageState() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    try CodexUsageLoader.load()
                }.value
                if self.codexUsageSnapshot != snapshot {
                    self.codexUsageSnapshot = snapshot
                }
            } catch {
                self.onStatusMessage?("Failed to read Codex usage state: \(error.localizedDescription)")
            }
        }
    }

    func refreshGeminiUsageState() {
        Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    try GeminiUsageLoader.load()
                }.value
                if self.geminiUsageSnapshot != snapshot {
                    self.geminiUsageSnapshot = snapshot
                }
            } catch {
                self.onStatusMessage?("Failed to read Gemini usage state: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Intent-aware helpers

    /// Reports whether the startup flow should auto-install hooks for the
    /// given agent.
    ///
    /// Post-onboarding, the only case that triggers auto-install is
    /// `.installed && !present` — i.e. the user asked for this hook in the
    /// past but it is currently missing (fresh machine, config wiped,
    /// upgraded binary path, etc). This is a repair, not a surprise
    /// install. `.untouched` and `.uninstalled` both return false;
    /// untouched agents are surfaced to the user via the first-run
    /// onboarding window and the empty-state banner instead.
    func shouldAutoInstall(_ agent: AgentIdentifier) -> Bool {
        guard intentStore.intent(for: agent) == .installed else {
            return false
        }

        switch agent {
        case .claudeCode: return !claudeHooksInstalled
        case .codex: return !codexHooksInstalled
        case .cursor: return !cursorHooksInstalled
        case .qoder: return !qoderHooksInstalled
        case .qwenCode: return !qwenCodeHooksInstalled
        case .factory: return !factoryHooksInstalled
        case .codebuddy: return !codebuddyHooksInstalled
        case .openCode: return !openCodePluginInstalled
        case .gemini: return !geminiHooksInstalled
        case .kimi: return !kimiHooksInstalled
        case .antigravity: return !antigravityHooksInstalled
        case .claudeUsageBridge: return !claudeUsageInstalled
        }
    }

    // MARK: - Intent store migration

    /// Reconciles the persisted intent store with the hook status currently
    /// observed on disk. Must be called only after
    /// `refreshAllHookStatusAndWait()` has returned, otherwise every agent
    /// will be recorded as `.untouched` and legacy users will have their
    /// installed hooks silently forgotten.
    func migrateIntentStoreIfNeeded() {
        intentStore.migrateFromLegacyStateIfNeeded { [self] agent in
            switch agent {
            case .claudeCode: return claudeHooksInstalled
            case .codex: return codexHooksInstalled
            case .cursor: return cursorHooksInstalled
            case .qoder: return qoderHooksInstalled
            case .qwenCode: return qwenCodeHooksInstalled
            case .factory: return factoryHooksInstalled
            case .codebuddy: return codebuddyHooksInstalled
            case .openCode: return openCodePluginInstalled
            case .gemini: return geminiHooksInstalled
            case .kimi: return kimiHooksInstalled
            case .antigravity: return antigravityHooksInstalled
            case .claudeUsageBridge: return claudeUsageInstalled
            }
        }
    }

    // MARK: - Install / uninstall

    func installCodexHooks() {
        guard let hooksBinaryURL else {
            reportSetupFailure(.codex, Self.missingBinaryMessage)
            return
        }

        updateCodexHooks(userMessage: "Installing Codex hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallCodexHooks() {
        updateCodexHooks(userMessage: "Removing Codex hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installClaudeHooks() {
        guard let hooksBinaryURL else {
            reportSetupFailure(.claudeCode, Self.missingBinaryMessage)
            return
        }

        updateClaudeHooks(userMessage: "Installing Claude hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallClaudeHooks() {
        updateClaudeHooks(userMessage: "Removing Claude hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installQoderHooks() {
        updateCCForkHooks(manager: qoderHookInstallationManager, name: "Qoder", agent: .qoder, isBusySetter: { [weak self] in self?.isQoderHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qoderHookStatus = $0 }, install: true)
    }

    func uninstallQoderHooks() {
        updateCCForkHooks(manager: qoderHookInstallationManager, name: "Qoder", agent: .qoder, isBusySetter: { [weak self] in self?.isQoderHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qoderHookStatus = $0 }, install: false)
    }

    func installQwenCodeHooks() {
        updateCCForkHooks(manager: qwenCodeHookInstallationManager, name: "Qwen Code", agent: .qwenCode, isBusySetter: { [weak self] in self?.isQwenCodeHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qwenCodeHookStatus = $0 }, install: true)
    }

    func uninstallQwenCodeHooks() {
        updateCCForkHooks(manager: qwenCodeHookInstallationManager, name: "Qwen Code", agent: .qwenCode, isBusySetter: { [weak self] in self?.isQwenCodeHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.qwenCodeHookStatus = $0 }, install: false)
    }

    func installFactoryHooks() {
        updateCCForkHooks(manager: factoryHookInstallationManager, name: "Factory", agent: .factory, isBusySetter: { [weak self] in self?.isFactoryHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.factoryHookStatus = $0 }, install: true)
    }

    func uninstallFactoryHooks() {
        updateCCForkHooks(manager: factoryHookInstallationManager, name: "Factory", agent: .factory, isBusySetter: { [weak self] in self?.isFactoryHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.factoryHookStatus = $0 }, install: false)
    }

    func installCodebuddyHooks() {
        updateCCForkHooks(manager: codebuddyHookInstallationManager, name: "CodeBuddy", agent: .codebuddy, isBusySetter: { [weak self] in self?.isCodebuddyHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.codebuddyHookStatus = $0 }, install: true)
    }

    func uninstallCodebuddyHooks() {
        updateCCForkHooks(manager: codebuddyHookInstallationManager, name: "CodeBuddy", agent: .codebuddy, isBusySetter: { [weak self] in self?.isCodebuddyHookSetupBusy = $0 }, statusSetter: { [weak self] in self?.codebuddyHookStatus = $0 }, install: false)
    }

    private func updateCCForkHooks(
        manager: ClaudeHookInstallationManager,
        name: String,
        agent: AgentIdentifier,
        isBusySetter: @MainActor @escaping (Bool) -> Void,
        statusSetter: @MainActor @escaping (ClaudeHookInstallationStatus) -> Void,
        install: Bool
    ) {
        let binaryURL = hooksBinaryURL
        guard !install || binaryURL != nil else {
            reportSetupFailure(agent, Self.missingBinaryMessage)
            return
        }

        isBusySetter(true)
        setupFailures[agent] = nil
        onStatusMessage?(install ? "Installing \(name) hooks." : "Removing \(name) hooks.")

        Task { [weak self] in
            guard let self else { return }

            defer { isBusySetter(false) }

            do {
                let status = if let binaryURL, install {
                    try manager.install(hooksBinaryURL: binaryURL)
                } else {
                    try manager.uninstall()
                }
                statusSetter(status)
                self.intentStore.setIntent(install ? .installed : .uninstalled, for: agent)
                if status.managedHooksPresent {
                    self.onStatusMessage?("\(name) hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("\(name) hooks are not installed.")
                }
            } catch {
                self.reportSetupFailure(agent, self.failureMessage(name, removing: !install, error))
            }
        }
    }

    func installOpenCodePlugin() {
        guard let pluginData = loadBundledOpenCodePlugin() else {
            reportSetupFailure(.openCode, "The OpenCode plugin is missing from this copy of NotchTune. Reinstall NotchTune to restore it.")
            return
        }

        isOpenCodeSetupBusy = true
        setupFailures[.openCode] = nil
        onStatusMessage?("Installing OpenCode plugin.")

        Task { [weak self] in
            guard let self else { return }

            defer { self.isOpenCodeSetupBusy = false }

            do {
                let status = try self.openCodePluginInstallationManager.install(pluginSourceData: pluginData)
                self.openCodePluginStatus = status
                self.intentStore.setIntent(.installed, for: .openCode)
                if status.isInstalled {
                    self.onStatusMessage?("OpenCode plugin is installed. Restart OpenCode to activate.")
                } else {
                    self.onStatusMessage?("OpenCode plugin installation incomplete.")
                }
            } catch {
                self.reportSetupFailure(.openCode, self.failureMessage("OpenCode", removing: false, error))
            }
        }
    }

    func uninstallOpenCodePlugin() {
        isOpenCodeSetupBusy = true
        setupFailures[.openCode] = nil
        onStatusMessage?("Removing OpenCode plugin.")

        Task { [weak self] in
            guard let self else { return }

            defer { self.isOpenCodeSetupBusy = false }

            do {
                let status = try self.openCodePluginInstallationManager.uninstall()
                self.openCodePluginStatus = status
                self.intentStore.setIntent(.uninstalled, for: .openCode)
                if let problem = status.configCleanupProblem {
                    self.reportSetupFailure(.openCode, "The OpenCode plugin was removed, but one step needs you. \(problem)")
                } else {
                    self.onStatusMessage?("OpenCode plugin removed.")
                }
            } catch {
                self.reportSetupFailure(.openCode, self.failureMessage("OpenCode", removing: true, error))
            }
        }
    }

    func installCursorHooks() {
        guard let hooksBinaryURL else {
            reportSetupFailure(.cursor, Self.missingBinaryMessage)
            return
        }

        updateCursorHooks(userMessage: "Installing Cursor hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallCursorHooks() {
        updateCursorHooks(userMessage: "Removing Cursor hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installGeminiHooks() {
        guard let hooksBinaryURL else {
            reportSetupFailure(.gemini, Self.missingBinaryMessage)
            return
        }

        updateGeminiHooks(userMessage: "Installing Gemini hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallGeminiHooks() {
        updateGeminiHooks(userMessage: "Removing Gemini hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installAntigravityHooks() {
        guard let hooksBinaryURL else {
            reportSetupFailure(.antigravity, Self.missingBinaryMessage)
            return
        }

        updateAntigravityHooks(userMessage: "Installing Antigravity hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallAntigravityHooks() {
        updateAntigravityHooks(userMessage: "Removing Antigravity hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installKimiHooks() {
        guard let hooksBinaryURL else {
            reportSetupFailure(.kimi, Self.missingBinaryMessage)
            return
        }

        updateKimiHooks(userMessage: "Installing Kimi hooks.", intent: .installed) { manager in
            try manager.install(hooksBinaryURL: hooksBinaryURL)
        }
    }

    func uninstallKimiHooks() {
        updateKimiHooks(userMessage: "Removing Kimi hooks.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    func installClaudeUsageBridge() {
        updateClaudeUsageBridge(userMessage: "Installing Claude usage bridge.", intent: .installed) { manager in
            do {
                return try manager.install()
            } catch ClaudeStatusLineInstallationError.existingStatusLineConflict {
                // User already has a custom statusLine (e.g. claude-hud). Install as a
                // wrapper so their script keeps running and we still get rate_limits.
                return try manager.installAsWrapper()
            }
        }
    }

    func uninstallClaudeUsageBridge() {
        updateClaudeUsageBridge(userMessage: "Removing Claude usage bridge.", intent: .uninstalled) { manager in
            try manager.uninstall()
        }
    }

    // MARK: - Monitoring

    func startClaudeUsageMonitoringIfNeeded() {
        guard claudeUsageMonitorTask == nil else { return }

        claudeUsageMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.refreshClaudeUsageState()
                // Usage windows move slowly; 20s keeps readouts fresh at a
                // quarter of the file-IO + status checks of the old 5s loop.
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    func startCodexUsageMonitoringIfNeeded() {
        guard codexUsageMonitorTask == nil else { return }

        codexUsageMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.refreshCodexUsageState()
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    func startGeminiUsageMonitoringIfNeeded() {
        guard geminiUsageMonitorTask == nil else { return }

        geminiUsageMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.refreshGeminiUsageState()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: - Internal: readClaudeUsageState

    nonisolated func readClaudeUsageState(
        repairManagedBridgeIfNeeded: Bool
    ) throws -> (
        status: ClaudeStatusLineInstallationStatus,
        snapshot: ClaudeUsageSnapshot?,
        repairedManagedBridge: Bool
    ) {
        let manager = ClaudeStatusLineInstallationManager()
        var status = try manager.status()
        var repairedManagedBridge = false

        if repairManagedBridgeIfNeeded && status.managedStatusLineNeedsRepair {
            status = try manager.install()
            repairedManagedBridge = true
        }

        let snapshot = try ClaudeUsageLoader.load()
        return (status, snapshot, repairedManagedBridge)
    }

    // MARK: - Private helpers

    private func updateCodexHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping @Sendable (CodexHookInstallationManager) throws -> CodexHookInstallationStatus
    ) {
        isCodexSetupBusy = true
        setupFailures[.codex] = nil
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isCodexSetupBusy = false }

            do {
                // Off the main actor: installing asks the `codex` CLI which
                // feature flag it wants, and that can take seconds.
                let manager = self.codexHookInstallationManager
                let status = try await Task.detached(priority: .userInitiated) {
                    try operation(manager)
                }.value
                self.codexHookStatus = status
                self.intentStore.setIntent(intent, for: .codex)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Codex hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Codex hooks are not installed.")
                }
            } catch {
                self.reportSetupFailure(.codex, self.failureMessage("Codex", removing: intent == .uninstalled, error))
            }
        }
    }

    private func updateClaudeHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (ClaudeHookInstallationManager) throws -> ClaudeHookInstallationStatus
    ) {
        isClaudeHookSetupBusy = true
        setupFailures[.claudeCode] = nil
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isClaudeHookSetupBusy = false }

            do {
                let status = try operation(self.claudeHookInstallationManager)
                self.claudeHookStatus = status
                self.intentStore.setIntent(intent, for: .claudeCode)
                if status.managedHooksPresent {
                    self.onStatusMessage?(status.hasClaudeIslandHooks
                        ? "Claude hooks are installed. claude-island hooks are also still present."
                        : "Claude hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Claude hooks are not installed.")
                }
            } catch {
                self.reportSetupFailure(.claudeCode, self.failureMessage("Claude Code", removing: intent == .uninstalled, error))
            }
        }
    }

    private func updateCursorHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (CursorHookInstallationManager) throws -> CursorHookInstallationStatus
    ) {
        isCursorHookSetupBusy = true
        setupFailures[.cursor] = nil
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isCursorHookSetupBusy = false }

            do {
                let status = try operation(self.cursorHookInstallationManager)
                self.cursorHookStatus = status
                self.intentStore.setIntent(intent, for: .cursor)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Cursor hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Cursor hooks are not installed.")
                }
            } catch {
                self.reportSetupFailure(.cursor, self.failureMessage("Cursor", removing: intent == .uninstalled, error))
            }
        }
    }

    private func updateGeminiHooks(
        userMessage: String,
        intent: AgentHookIntent,
        action: @escaping (GeminiHookInstallationManager) throws -> GeminiHookInstallationStatus
    ) {
        isGeminiHookSetupBusy = true
        setupFailures[.gemini] = nil
        onStatusMessage?(userMessage)

        let manager = geminiHookInstallationManager
        Task { [weak self] in
            guard let self else { return }

            defer { self.isGeminiHookSetupBusy = false }

            do {
                let status = try action(manager)
                self.geminiHookStatus = status
                self.intentStore.setIntent(intent, for: .gemini)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Gemini hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Gemini hooks are not installed.")
                }
            } catch {
                self.reportSetupFailure(.gemini, self.failureMessage("Gemini", removing: intent == .uninstalled, error))
            }
        }
    }

    private func updateAntigravityHooks(
        userMessage: String,
        intent: AgentHookIntent,
        action: @escaping (AntigravityHookInstallationManager) throws -> AntigravityHookInstallationStatus
    ) {
        isAntigravityHookSetupBusy = true
        setupFailures[.antigravity] = nil
        onStatusMessage?(userMessage)

        let manager = antigravityHookInstallationManager
        Task { [weak self] in
            guard let self else { return }

            defer { self.isAntigravityHookSetupBusy = false }

            do {
                let status = try action(manager)
                self.antigravityHookStatus = status
                self.intentStore.setIntent(intent, for: .antigravity)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Antigravity hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Antigravity hooks are not installed.")
                }
            } catch {
                self.reportSetupFailure(.antigravity, self.failureMessage("Antigravity", removing: intent == .uninstalled, error))
            }
        }
    }

    private func updateKimiHooks(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (KimiHookInstallationManager) throws -> KimiHookInstallationStatus
    ) {
        isKimiHookSetupBusy = true
        setupFailures[.kimi] = nil
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isKimiHookSetupBusy = false }

            do {
                let status = try operation(self.kimiHookInstallationManager)
                self.kimiHookStatus = status
                self.intentStore.setIntent(intent, for: .kimi)
                if status.managedHooksPresent {
                    self.onStatusMessage?("Kimi hooks are installed and ready.")
                } else {
                    self.onStatusMessage?("Kimi hooks are not installed.")
                }
            } catch {
                self.reportSetupFailure(.kimi, self.failureMessage("Kimi", removing: intent == .uninstalled, error))
            }
        }
    }

    private func updateClaudeUsageBridge(
        userMessage: String,
        intent: AgentHookIntent,
        operation: @escaping (ClaudeStatusLineInstallationManager) throws -> ClaudeStatusLineInstallationStatus
    ) {
        isClaudeUsageSetupBusy = true
        setupFailures[.claudeUsageBridge] = nil
        onStatusMessage?(userMessage)

        Task { [weak self] in
            guard let self else { return }

            defer { self.isClaudeUsageSetupBusy = false }

            do {
                let status = try operation(self.claudeStatusLineInstallationManager)
                self.claudeStatusLineStatus = status
                self.claudeUsageSnapshot = try ClaudeUsageLoader.load()
                self.intentStore.setIntent(intent, for: .claudeUsageBridge)
                if status.managedStatusLineInstalled {
                    if status.managedStatusLineIsWrapper {
                        self.onStatusMessage?("Claude usage bridge installed in wrapper mode — your existing statusLine is preserved. Start a Claude Code turn to refresh cached rate limits.")
                    } else {
                        self.onStatusMessage?("Claude usage bridge is installed. Start a Claude Code turn to refresh cached rate limits.")
                    }
                } else {
                    self.onStatusMessage?("Claude usage bridge is not installed.")
                }
            } catch {
                let action = intent == .uninstalled ? "remove" : "install"
                self.reportSetupFailure(.claudeUsageBridge, "NotchTune couldn't \(action) the Claude usage bridge. \(error.localizedDescription)")
            }
        }
    }

    private func loadBundledOpenCodePlugin() -> Data? {
        // Use appResources which searches both Contents/Resources/ and .app root
        if let url = Bundle.appResources.url(forResource: "notchtune-opencode", withExtension: "js") {
            return try? Data(contentsOf: url)
        }

        // Fallback: Bundle.main for Xcode builds
        if let url = Bundle.main.url(forResource: "notchtune-opencode", withExtension: "js") {
            return try? Data(contentsOf: url)
        }

        return nil
    }
}
