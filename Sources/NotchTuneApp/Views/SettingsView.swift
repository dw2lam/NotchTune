import SwiftUI
import AppKit
import NotchTuneCore
import UniformTypeIdentifiers

// MARK: - Settings tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case setup
    case display
    case sound
    case music
    case appearance
    case updates
    case about

    var id: String { rawValue }

    func label(_ lang: LanguageManager) -> String {
        switch self {
        case .general:    lang.t("settings.tab.general")
        case .setup:      lang.t("settings.tab.setup")
        case .appearance: lang.t("settings.tab.appearance")
        case .display:    lang.t("settings.tab.display")
        case .sound:      lang.t("settings.tab.sound")
        case .music:      "Music"
        case .updates:    lang.t("settings.tab.updates")
        case .about:      lang.t("settings.tab.about")
        }
    }

    /// White glyph drawn on the colored tile, System Settings style.
    var icon: String {
        switch self {
        case .general:    "gearshape.fill"
        case .setup:      "puzzlepiece.extension.fill"
        case .appearance: "paintpalette.fill"
        case .display:    "display"
        case .sound:      "speaker.wave.3.fill"
        case .music:      "music.note"
        case .updates:    "arrow.triangle.2.circlepath"
        case .about:      "info"
        }
    }

    var iconColor: Color {
        switch self {
        case .general:    .gray
        case .setup:      .orange
        case .appearance: .indigo
        case .display:    .blue
        case .sound:      .red
        case .music:      .pink
        case .updates:    .gray
        case .about:      .blue
        }
    }

    var section: SettingsSection {
        switch self {
        case .general, .setup, .display, .sound, .music, .appearance: .system
        case .updates, .about:                                                 .app
        }
    }
}

enum SettingsSection: String, CaseIterable {
    case system
    case app

    var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0.section == self }
    }
}

/// The small colored rounded-square icon System Settings puts in front of
/// every sidebar row.
struct SettingsSidebarIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color.gradient)
            )
    }
}

// MARK: - Root settings view

struct SettingsView: View {
    var model: AppModel
    @State private var selectedTab: SettingsTab = .general

    private var lang: LanguageManager { model.lang }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(215)
        } detail: {
            detailView
        }
        .frame(minWidth: 715, idealWidth: 740, maxWidth: 780, minHeight: 480, idealHeight: 620)
        .onReceive(NotificationCenter.default.publisher(for: .notchTuneSelectSetupTab)) { _ in
            selectedTab = .setup
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchTuneSelectSettingsTab)) { note in
            if let raw = note.object as? String, let tab = SettingsTab(rawValue: raw) {
                selectedTab = tab
            }
        }
    }

    // MARK: Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedTab) {
            // Groups are separated by spacing only, like System Settings —
            // no header text that would repeat the panes' own titles.
            ForEach(SettingsSection.allCases, id: \.self) { section in
                Section {
                    ForEach(section.tabs) { tab in
                        Label {
                            Text(tab.label(lang))
                        } icon: {
                            SettingsSidebarIcon(systemName: tab.icon, color: tab.iconColor)
                        }
                        .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsPane(model: model)
        case .setup:
            SetupSettingsPane(model: model)
        case .appearance:
            AppearanceSettingsPane(model: model)
        case .display:
            DisplaySettingsPane(model: model)
        case .sound:
            SoundSettingsPane(model: model)
        case .music:
            MusicSettingsPane(model: model)
        case .updates:
            UpdateSettingsPane(model: model)
        case .about:
            AboutSettingsPane(model: model)
        }
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section {
                Toggle(lang.t("settings.general.launchAtLogin"), isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.launchAtLoginEnabled = $0 }
                ))

                Picker(lang.t("settings.general.monitor"), selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )) {
                    Text(lang.t("settings.general.automatic")).tag(OverlayDisplayOption.automaticID)
                    ForEach(model.overlayDisplayOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }

            Section(lang.t("settings.general.behavior")) {
                Toggle(lang.t("settings.general.hideDockIcon"), isOn: Binding(
                    get: { !model.showDockIcon },
                    set: { model.showDockIcon = !$0 }
                ))
                Toggle(lang.t("settings.general.hapticFeedback"), isOn: Binding(
                    get: { model.hapticFeedbackEnabled },
                    set: { model.hapticFeedbackEnabled = $0 }
                ))
                Toggle(lang.t("settings.general.completionReply"), isOn: Binding(
                    get: { model.completionReplyEnabled },
                    set: { model.completionReplyEnabled = $0 }
                ))
                Picker(selection: Binding(
                    get: { model.hoverOpenMode },
                    set: { model.hoverOpenMode = $0 }
                )) {
                    ForEach(HoverOpenMode.allCases) { mode in
                        Text(lang.t("settings.general.hoverOpen.\(mode.rawValue)")).tag(mode)
                    }
                } label: {
                    Text(lang.t("settings.general.hoverOpen"))
                    Text(lang.t("settings.general.hoverOpen.note"))
                }
                Toggle(isOn: Binding(
                    get: { model.suppressFrontmostNotifications },
                    set: { model.suppressFrontmostNotifications = $0 }
                )) {
                    Text(lang.t("settings.general.suppressFrontmostNotifications"))
                    Text(lang.t("settings.general.suppressFrontmostNotifications.note"))
                }
            }

            Section(lang.t("settings.general.gettingStarted")) {
                LabeledContent {
                    Button(lang.t("settings.general.open")) {
                        model.showOnboarding()
                    }
                } label: {
                    Text(lang.t("settings.general.setupAssistant"))
                    Text(lang.t("settings.general.setupAssistant.note"))
                }

                LabeledContent {
                    if model.tour.isActive {
                        Button(lang.t("settings.general.tour.end")) {
                            model.tour.skip()
                        }
                    } else {
                        Button(model.onboardingTourOutcome == nil
                            ? lang.t("settings.general.tour.start")
                            : lang.t("settings.general.tour.replay")
                        ) {
                            model.startOnboardingTour()
                        }
                        .disabled(model.isOverlayDisplayFullscreen)
                    }
                } label: {
                    Text(lang.t("settings.general.tour"))
                    Text(lang.t("settings.general.tour.note"))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.general"))
    }
}

// MARK: - Display

struct DisplaySettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section {
                Picker(lang.t("settings.display.position"), selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )) {
                    Text(lang.t("settings.general.automatic")).tag(OverlayDisplayOption.automaticID)
                    ForEach(model.overlayDisplayOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            } header: {
                Text(lang.t("settings.display.monitor"))
            } footer: {
                Text(lang.t("settings.display.position.footer"))
                    .settingsFooterStyle()
            }

            if let diag = model.overlay.overlayPlacementDiagnostics {
                Section(lang.t("settings.display.diagnostics")) {
                    LabeledContent(lang.t("settings.display.currentScreen"), value: diag.targetScreenName)
                    LabeledContent(lang.t("settings.display.layoutMode"), value: diag.modeDescription)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.display"))
    }
}

// MARK: - Sound

struct SoundSettingsPane: View {
    var model: AppModel
    @State private var customSounds: [String] = []

    private var lang: LanguageManager { model.lang }

    private var availableSounds: [String] {
        NotificationSoundService.availableSounds()
    }

    var body: some View {
        Form {
            Section(lang.t("settings.sound.notifications")) {
                Toggle(lang.t("settings.sound.mute"), isOn: Binding(
                    get: { model.isSoundMuted },
                    set: { _ in model.toggleSoundMuted() }
                ))

                soundPickerRow(
                    title: lang.t("settings.sound.selectSound"),
                    selection: Binding(
                        get: { model.selectedSoundName },
                        set: { model.selectedSoundName = $0; NotificationSoundService.play($0) }
                    ),
                    previewHelp: lang.t("settings.sound.preview")
                ) {
                    NotificationSoundService.play(model.selectedSoundName)
                }
            }

            Section {
                if customSounds.isEmpty {
                    Text(lang.t("settings.sound.noCustomSounds"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customSounds, id: \.self) { filename in
                        LabeledContent(cleanFilename(filename)) {
                            HStack(spacing: 12) {
                                Button {
                                    NotificationSoundService.play(filename)
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .buttonStyle(.borderless)
                                .help(lang.t("settings.sound.preview"))

                                Button(role: .destructive) {
                                    deleteSound(filename)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help(lang.t("settings.sound.delete"))
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button(lang.t("settings.sound.addCustomSound"), action: selectCustomSoundFile)
                }
            } header: {
                Text(lang.t("settings.sound.customSounds"))
            } footer: {
                Text(lang.t("settings.sound.customSounds.footer"))
                    .settingsFooterStyle()
            }

            nudgeSection
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.sound"))
        .onAppear {
            loadCustomSounds()
        }
    }

    /// A menu of every system + custom sound with a trailing preview button.
    /// Choosing a sound plays it, like System Settings' alert-sound menu.
    @ViewBuilder
    private func soundPickerRow(
        title: String,
        selection: Binding<String>,
        previewHelp: String,
        preview: @escaping () -> Void
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Picker(title, selection: selection) {
                    Section(lang.t("settings.sound.systemSounds")) {
                        ForEach(availableSounds, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    if !customSounds.isEmpty {
                        Section(lang.t("settings.sound.customSounds")) {
                            ForEach(customSounds, id: \.self) { filename in
                                Text(cleanFilename(filename)).tag(filename)
                            }
                        }
                    }
                }
                .labelsHidden()
                .fixedSize()

                Button(action: preview) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help(previewHelp)
            }
        }
    }

    @ViewBuilder
    private var nudgeSection: some View {
        Section {
            Toggle("Nudge me about sessions I haven't answered", isOn: Binding(
                get: { model.nudgeSettings.isEnabled },
                set: { model.nudgeSettings.isEnabled = $0 }
            ))

            Picker("Nudge after", selection: Binding(
                get: { model.nudgeSettings.threshold },
                set: { model.nudgeSettings.threshold = $0 }
            )) {
                ForEach(IdleNudgeThreshold.allCases) { threshold in
                    Text(threshold.displayName).tag(threshold)
                }
            }
            .disabled(!model.nudgeSettings.isEnabled)

            soundPickerRow(
                title: "Nudge sound",
                selection: Binding(
                    get: { model.selectedNudgeSoundName },
                    set: { model.selectedNudgeSoundName = $0; NotificationSoundService.play($0) }
                ),
                previewHelp: "Preview nudge sound"
            ) {
                NotificationSoundService.play(model.selectedNudgeSoundName)
            }
            .disabled(!model.nudgeSettings.isEnabled)
        } header: {
            Text("Idle Session Nudge")
        } footer: {
            Text("When a session waits for you longer than the chosen time, the island's character jumps once and the nudge sound plays. The nudge sound shares the custom sounds added above.")
                .settingsFooterStyle()
        }
    }

    private func cleanFilename(_ filename: String) -> String {
        return (filename as NSString).deletingPathExtension
    }

    private func loadCustomSounds() {
        customSounds = NotificationSoundService.availableCustomSounds()
    }

    private func selectCustomSoundFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = lang.t("settings.sound.chooseCustomSound")
        openPanel.allowedContentTypes = [.audio, .quickTimeMovie]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true

        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let filename = try NotificationSoundService.addCustomSound(from: url)
                loadCustomSounds()
                model.selectedSoundName = filename
                NotificationSoundService.play(filename)
            } catch {
                print("Failed to copy custom sound: \(error)")
            }
        }
    }

    private func deleteSound(_ filename: String) {
        do {
            try NotificationSoundService.deleteCustomSound(filename)
            loadCustomSounds()
            if model.selectedSoundName == filename {
                model.selectedSoundName = NotificationSoundService.defaultSoundName
            }
            if model.selectedNudgeSoundName == filename {
                model.selectedNudgeSoundName = NotificationSoundService.defaultSoundName(for: .nudge)
            }
        } catch {
            print("Failed to delete custom sound: \(error)")
        }
    }
}

// MARK: - Updates

struct UpdateSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        Form {
            Section(lang.t("settings.updates.softwareUpdate")) {
                LabeledContent(
                    lang.t("settings.updates.currentVersion"),
                    value: currentVersion
                )
                LabeledContent(
                    lang.t("settings.updates.build"),
                    value: currentBuild
                )

                if model.updateChecker.hasUpdate,
                   let latestVersion = model.updateChecker.latestVersion {
                    LabeledContent(
                        lang.t("settings.updates.availableVersion"),
                        value: latestVersion
                    )
                }
            }

            Section {
                LabeledContent {
                    Button(lang.t("settings.updates.checkNow")) {
                        model.updateChecker.checkForUpdates()
                    }
                    .disabled(!model.updateChecker.canCheckForUpdates)
                } label: {
                    Text(lang.t("settings.updates.checkRow"))
                    Text(lang.t("settings.updates.automaticDetail"))
                }

                LabeledContent {
                    Button(lang.t("settings.updates.releaseNotes")) {
                        NSWorkspace.shared.open(UpdateChecker.releasesURL)
                    }
                } label: {
                    Text(lang.t("settings.updates.releaseNotesRow"))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.updates"))
    }
}

// MARK: - About & Credits

struct AboutSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    private var versionLine: String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return lang.t("settings.about.version", version)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)

                    Text(lang.t("app.name"))
                        .font(.title2.weight(.semibold))

                    Text(lang.t("app.description"))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let versionLine {
                        Text(versionLine)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Text("Originally Open Island")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Credits") {
                creditLinkRow(
                    title: "View NotchTune source",
                    subtitle: "Open source on GitHub",
                    url: "https://github.com/dw2lam/NotchTune"
                )

                creditLinkRow(
                    title: "Forked from Open Vibe Island",
                    subtitle: "Octane0411/open-vibe-island",
                    url: "https://github.com/Octane0411/open-vibe-island"
                )

                creditLinkRow(
                    title: "Music foundation from Tuneful",
                    subtitle: "martinfekete10/Tuneful",
                    url: "https://github.com/martinfekete10/Tuneful"
                )

                creditLinkRow(
                    title: "Created by David",
                    subtitle: "dw2lam",
                    url: "https://github.com/dw2lam"
                )
            }

            Section {
                LabeledContent {
                    Button(lang.t("settings.about.quit"), role: .destructive) {
                        model.quitApplication()
                    }
                    .accessibilityIdentifier("settings.about.quitApp")
                } label: {
                    Text(lang.t("settings.about.quitApp"))
                    Text(lang.t("settings.about.quitApp.note"))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.about"))
    }

    /// A credit row that opens its page in the browser: title + secondary
    /// line on the left, a trailing "open externally" arrow.
    private func creditLinkRow(
        title: String,
        subtitle: String,
        url: String
    ) -> some View {
        Link(destination: URL(string: url)!) {
            LabeledContent {
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(.secondary)
            } label: {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Setup

struct SetupSettingsPane: View {
    var model: AppModel

    @State private var confirmingUninstallClaude = false
    @State private var confirmingUninstallCodex = false
    @State private var confirmingUninstallOpenCode = false
    @State private var confirmingUninstallQoder = false
    @State private var confirmingUninstallQwenCode = false
    @State private var confirmingUninstallFactory = false
    @State private var confirmingUninstallCodebuddy = false
    @State private var confirmingUninstallCursor = false
    @State private var confirmingUninstallGemini = false
    @State private var confirmingUninstallAntigravity = false
    @State private var confirmingUninstallKimi = false
    @State private var confirmingUninstallClaudeUsage = false

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            if !model.hasAnyInstalledAgent {
                emptyStateBanner
            }

            Section {
                hookRow(
                    name: "Claude Code",
                    installed: model.claudeHooksInstalled,
                    busy: model.isClaudeHookSetupBusy,
                    configLocationURL: model.claudeHookStatus?.settingsURL,
                    installAction: { model.installClaudeHooks() },
                    uninstallAction: { confirmingUninstallClaude = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallClaude) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallClaudeHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.claude"))
                }

                hookRow(
                    name: "Codex",
                    installed: model.codexHooksInstalled,
                    busy: model.isCodexSetupBusy,
                    configLocationURL: codexHookConfigURL,
                    installAction: { model.installCodexHooks() },
                    uninstallAction: { confirmingUninstallCodex = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCodex) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCodexHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.codex"))
                }

                hookRow(
                    name: "OpenCode",
                    installed: model.openCodePluginInstalled,
                    busy: model.isOpenCodeSetupBusy,
                    requiresBinary: false,
                    configLocationURL: model.openCodePluginStatus?.configURL,
                    installAction: { model.installOpenCodePlugin() },
                    uninstallAction: { confirmingUninstallOpenCode = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallOpenCode) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallOpenCodePlugin()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove the NotchTune plugin from ~/.config/opencode/plugins/.")
                }

                hookRow(
                    name: "Qoder",
                    installed: model.qoderHooksInstalled,
                    busy: model.isQoderHookSetupBusy,
                    configLocationURL: model.qoderHookStatus?.settingsURL,
                    installAction: { model.installQoderHooks() },
                    uninstallAction: { confirmingUninstallQoder = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallQoder) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallQoderHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove NotchTune hooks from ~/.qoder/settings.json.")
                }

                hookRow(
                    name: "Qwen Code",
                    installed: model.qwenCodeHooksInstalled,
                    busy: model.isQwenCodeHookSetupBusy,
                    configLocationURL: model.qwenCodeHookStatus?.settingsURL,
                    installAction: { model.installQwenCodeHooks() },
                    uninstallAction: { confirmingUninstallQwenCode = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallQwenCode) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallQwenCodeHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove NotchTune hooks from ~/.qwen/settings.json.")
                }

                hookRow(
                    name: "Factory",
                    installed: model.factoryHooksInstalled,
                    busy: model.isFactoryHookSetupBusy,
                    configLocationURL: model.factoryHookStatus?.settingsURL,
                    installAction: { model.installFactoryHooks() },
                    uninstallAction: { confirmingUninstallFactory = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallFactory) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallFactoryHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove NotchTune hooks from ~/.factory/settings.json.")
                }

                hookRow(
                    name: "CodeBuddy",
                    installed: model.codebuddyHooksInstalled,
                    busy: model.isCodebuddyHookSetupBusy,
                    configLocationURL: model.codebuddyHookStatus?.settingsURL,
                    installAction: { model.installCodebuddyHooks() },
                    uninstallAction: { confirmingUninstallCodebuddy = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCodebuddy) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCodebuddyHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove NotchTune hooks from ~/.codebuddy/settings.json.")
                }

                hookRow(
                    name: "Cursor",
                    installed: model.cursorHooksInstalled,
                    busy: model.isCursorHookSetupBusy,
                    requiresBinary: true,
                    configLocationURL: model.cursorHookStatus?.hooksURL,
                    installAction: { model.installCursorHooks() },
                    uninstallAction: { confirmingUninstallCursor = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCursor) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCursorHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove the NotchTune hooks from ~/.cursor/hooks.json.")
                }

                hookRow(
                    name: "Gemini CLI",
                    installed: model.geminiHooksInstalled,
                    busy: model.isGeminiHookSetupBusy,
                    configLocationURL: geminiHookConfigURL,
                    installAction: { model.installGeminiHooks() },
                    uninstallAction: { confirmingUninstallGemini = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallGemini) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallGeminiHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove NotchTune hooks from ~/.gemini/settings.json.")
                }

                hookRow(
                    name: "Antigravity",
                    installed: model.antigravityHooksInstalled,
                    busy: model.isAntigravityHookSetupBusy,
                    configLocationURL: antigravityHookConfigURL,
                    installAction: { model.installAntigravityHooks() },
                    uninstallAction: { confirmingUninstallAntigravity = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallAntigravity) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallAntigravityHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove NotchTune hooks from ~/.gemini/config/hooks.json.")
                }

                hookRow(
                    name: "Kimi CLI",
                    installed: model.kimiHooksInstalled,
                    busy: model.isKimiHookSetupBusy,
                    configLocationURL: model.kimiHookStatus?.configURL,
                    installAction: { model.installKimiHooks() },
                    uninstallAction: { confirmingUninstallKimi = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallKimi) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallKimiHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove NotchTune hooks from ~/.kimi/config.toml.")
                }

                HStack {
                    Spacer()
                    Button(lang.t("setup.installAll")) {
                        if !model.claudeHooksInstalled { model.installClaudeHooks() }
                        if !model.codexHooksInstalled { model.installCodexHooks() }
                        if !model.openCodePluginInstalled { model.installOpenCodePlugin() }
                        if !model.qoderHooksInstalled { model.installQoderHooks() }
                        if !model.qwenCodeHooksInstalled { model.installQwenCodeHooks() }
                        if !model.factoryHooksInstalled { model.installFactoryHooks() }
                        if !model.codebuddyHooksInstalled { model.installCodebuddyHooks() }
                        if !model.cursorHooksInstalled { model.installCursorHooks() }
                        if !model.geminiHooksInstalled { model.installGeminiHooks() }
                        if !model.antigravityHooksInstalled { model.installAntigravityHooks() }
                        if !model.kimiHooksInstalled { model.installKimiHooks() }
                        if !model.claudeUsageInstalled { model.installClaudeUsageBridge() }
                    }
                    .disabled(model.hooksBinaryURL == nil || allReady)
                }
            } header: {
                Text(lang.t("setup.section.hooks"))
            } footer: {
                Text(lang.t("setup.section.hooks.footer"))
                    .settingsFooterStyle()
            }

            Section {
                LabeledContent {
                    if model.claudeUsageInstalled {
                        HStack(spacing: 10) {
                            statusBadge(lang.t("setup.usageBridgeReady"))
                            Button(lang.t("settings.general.uninstall")) {
                                confirmingUninstallClaudeUsage = true
                            }
                        }
                    } else if model.isClaudeUsageSetupBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(lang.t("settings.general.install")) {
                            model.installClaudeUsageBridge()
                        }
                    }
                } label: {
                    Text(lang.t("setup.usageBridge"))
                    Text(lang.t("setup.usageBridgeDesc"))
                }
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallClaudeUsage) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallClaudeUsageBridge()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.claudeUsage"))
                }

                Toggle(lang.t("settings.general.showCodexUsage"), isOn: Binding(
                    get: { model.showCodexUsage },
                    set: { model.showCodexUsage = $0 }
                ))
            } header: {
                Text(lang.t("setup.section.usage"))
            } footer: {
                Text(lang.t("setup.section.usage.footer"))
                    .settingsFooterStyle()
            }

            claudeConfigDirectorySection

            Section(lang.t("setup.section.permissions")) {
                LabeledContent {
                    Button(lang.t("setup.permissions.open")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } label: {
                    Text(lang.t("setup.permissionsTitle"))
                    Text(lang.t("setup.permissionsDesc"))
                }
            }

            hookDiagnosticsSection

            RemoteConnectionSection(model: model)
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.setup"))
    }

    @ViewBuilder
    private var claudeConfigDirectorySection: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    if ClaudeConfigDirectory.customDirectory != nil {
                        Button(lang.t("setup.claudeConfigDir.reset")) {
                            model.updateClaudeConfigDirectory(to: nil)
                        }
                    }
                    Button(lang.t("setup.claudeConfigDir.choose")) {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        panel.showsHiddenFiles = true
                        panel.prompt = lang.t("setup.claudeConfigDir.choose")
                        if panel.runModal() == .OK, let url = panel.url {
                            model.updateClaudeConfigDirectory(to: url)
                        }
                    }
                }
            } label: {
                Text(lang.t("setup.claudeConfigDir.title"))
                Text(ClaudeConfigDirectory.resolved().path)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } header: {
            Text(lang.t("setup.claudeConfigDir.section"))
        } footer: {
            Text(lang.t("setup.claudeConfigDir.footer"))
                .settingsFooterStyle()
        }
    }

    private var allReady: Bool {
        model.claudeHooksInstalled && model.codexHooksInstalled && model.openCodePluginInstalled
            && model.qoderHooksInstalled && model.qwenCodeHooksInstalled && model.factoryHooksInstalled && model.codebuddyHooksInstalled
            && model.cursorHooksInstalled && model.geminiHooksInstalled && model.kimiHooksInstalled && model.claudeUsageInstalled
    }

    @ViewBuilder
    private var emptyStateBanner: some View {
        Section {
            Label {
                Text(lang.t("setup.banner.noHooks.title"))
                Text(lang.t("setup.banner.noHooks.message"))
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
            }
        }
    }

    private func statusBadge(_ text: String) -> some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .labelStyle(.titleAndIcon)
    }

    private var codexHookConfigURL: URL? {
        if let hooksURL = model.codexHookStatus?.hooksURL, FileManager.default.fileExists(atPath: hooksURL.path) {
            return hooksURL
        }
        return model.codexHookStatus?.configURL ?? model.codexHookStatus?.hooksURL
    }

    private var geminiHookConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/settings.json")
    }

    private var antigravityHookConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/config/hooks.json")
    }

    private var hasErrors: Bool {
        let claudeErrors = model.claudeHealthReport?.errors.count ?? 0
        let codexErrors = model.codexHealthReport?.errors.count ?? 0
        return claudeErrors + codexErrors > 0
    }

    private var hasRepairableIssues: Bool {
        let claude = model.claudeHealthReport?.repairableIssues.isEmpty == false
        let codex = model.codexHealthReport?.repairableIssues.isEmpty == false
        return claude || codex
    }

    private var hasNotices: Bool {
        let claude = model.claudeHealthReport?.notices.isEmpty == false
        let codex = model.codexHealthReport?.notices.isEmpty == false
        return claude || codex
    }

    @ViewBuilder
    private var hookDiagnosticsSection: some View {
        Section(lang.t("setup.section.diagnostics")) {
            if let claudeReport = model.claudeHealthReport, !claudeReport.issues.isEmpty {
                issueList(report: claudeReport)
            }
            if let codexReport = model.codexHealthReport, !codexReport.issues.isEmpty {
                issueList(report: codexReport)
            }

            if model.claudeHealthReport == nil && model.codexHealthReport == nil {
                LabeledContent(lang.t("setup.diagnostics.notRun")) {
                    Button(lang.t("setup.diagnostics.runCheck")) {
                        model.runHealthChecks()
                    }
                }
            } else if !hasErrors {
                LabeledContent {
                    Button(lang.t("setup.diagnostics.recheck")) {
                        model.runHealthChecks()
                    }
                } label: {
                    Label {
                        Text(lang.t("setup.diagnostics.allHealthy"))
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } else {
                LabeledContent {
                    HStack(spacing: 8) {
                        Button(lang.t("setup.diagnostics.recheck")) {
                            model.runHealthChecks()
                        }
                        if hasRepairableIssues {
                            Button(lang.t("setup.diagnostics.repair")) {
                                model.repairHooks()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } label: {
                    Label {
                        Text(lang.t("setup.diagnostics.issuesFound"))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func issueList(report: HookHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.agent == "claude" ? "Claude Code" : "Codex")
                .font(.headline)

            ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                Label {
                    Text(issue.description)
                        .foregroundStyle(issue.severity == .info ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: issueIcon(for: issue))
                        .foregroundStyle(issueColor(for: issue))
                }
            }

            if let binaryPath = report.binaryPath {
                Text("Binary: \(binaryPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func issueIcon(for issue: HookHealthReport.Issue) -> String {
        switch issue.severity {
        case .info: "info.circle.fill"
        case .error: issue.isAutoRepairable ? "wrench.fill" : "exclamationmark.triangle.fill"
        }
    }

    private func issueColor(for issue: HookHealthReport.Issue) -> Color {
        switch issue.severity {
        case .info: .blue
        case .error: issue.isAutoRepairable ? .orange : .red
        }
    }

    @ViewBuilder
    private func hookRow(
        name: String,
        installed: Bool,
        busy: Bool,
        requiresBinary: Bool = true,
        configLocationURL: URL? = nil,
        installAction: @escaping () -> Void,
        uninstallAction: @escaping () -> Void
    ) -> some View {
        LabeledContent(name) {
            if installed {
                HStack(spacing: 10) {
                    statusBadge(lang.t("settings.general.activated"))
                    if let configLocationURL {
                        Button {
                            revealInFinder(configLocationURL)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help(lang.t("setup.revealConfigLocation"))
                    }
                    Button(lang.t("settings.general.uninstall")) {
                        uninstallAction()
                    }
                }
            } else if busy {
                ProgressView().controlSize(.small)
            } else {
                Button(lang.t("settings.general.install")) {
                    installAction()
                }
                .disabled(requiresBinary && model.hooksBinaryURL == nil)
            }
        }
    }

    private func revealInFinder(_ url: URL) {
        let fileManager = FileManager.default
        let standardizedURL = url.standardizedFileURL

        if fileManager.fileExists(atPath: standardizedURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([standardizedURL])
            return
        }

        let directoryURL = standardizedURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directoryURL.path) {
            NSWorkspace.shared.open(directoryURL)
        }
    }
}

// MARK: - Music

struct MusicSettingsPane: View {
    var model: AppModel
    @AppStorage("music.connectedApp") private var connectedApp: String = "none"

    var body: some View {
        Form {
            Section {
                Picker("Player", selection: $connectedApp) {
                    Text("None").tag("none")
                    Text("Apple Music").tag("appleMusic")
                    if FileManager.default.fileExists(atPath: "/Applications/Spotify.app") {
                        Text("Spotify").tag("spotify")
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Music Player")
            } footer: {
                Text("NotchTune will only connect to the selected app. Choose None to disable music controls entirely.")
                    .settingsFooterStyle()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Music")
    }
}

// MARK: - Placeholder

struct PlaceholderSettingsPane: View {
    var model: AppModel
    let titleKey: String
    let subtitleKey: String

    private var lang: LanguageManager { model.lang }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(lang.t(subtitleKey))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(lang.t(titleKey))
    }
}

// MARK: - Remote Connection

struct RemoteConnectionSection: View {
    var model: AppModel

    @State private var copiedCommand: String?

    private var remoteSessionCount: Int {
        model.state.sessions.filter(\.isRemote).count
    }

    private var socketName: String {
        "open-island-\(getuid()).sock"
    }

    private var setupCommand: String {
        "./scripts/remote-setup.sh user@host"
    }

    private var sshCommand: String {
        "ssh -R /tmp/\(socketName):/tmp/\(socketName) user@host"
    }

    private var sshConfigSnippet: String {
        """
        Host myserver
            RemoteForward /tmp/\(socketName) /tmp/\(socketName)
        """
    }

    var body: some View {
        Section {
            LabeledContent {
                if remoteSessionCount > 0 {
                    Label {
                        Text("\(remoteSessionCount) active")
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("No remote sessions")
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text("SSH remote")
                Text("Monitor Claude Code running on remote servers via SSH.")
            }

            remoteSetupStep(
                title: "1. Deploy hooks to the remote server",
                description: "Run from the NotchTune repo directory:",
                command: setupCommand
            )

            VStack(alignment: .leading, spacing: 10) {
                remoteSetupStep(
                    title: "2. Connect with socket forwarding",
                    description: "Add to ~/.ssh/config (recommended):",
                    command: sshConfigSnippet,
                    multiline: true
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Or connect directly:")
                        .foregroundStyle(.secondary)
                    copyableCommand(sshCommand)
                }
            }
        } header: {
            Text("Remote (Beta)")
        } footer: {
            Text("The remote sshd needs `StreamLocalBindUnlink yes` in /etc/ssh/sshd_config for reliable reconnects.")
                .settingsFooterStyle()
        }
    }

    @ViewBuilder
    private func remoteSetupStep(
        title: String,
        description: String,
        command: String,
        multiline: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(description)
                .foregroundStyle(.secondary)
            copyableCommand(command, multiline: multiline)
        }
    }

    @ViewBuilder
    private func copyableCommand(_ command: String, multiline: Bool = false) -> some View {
        let isCopied = copiedCommand == command
        GroupBox {
            HStack(alignment: multiline ? .top : .center) {
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(multiline ? nil : 1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copiedCommand = command
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedCommand == command {
                            copiedCommand = nil
                        }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(isCopied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.borderless)
                .help("Copy")
            }
            .padding(.vertical, multiline ? 2 : 0)
        }
    }
}

// MARK: - Footer style

extension View {
    /// Section footers the way System Settings sets them: small secondary
    /// text, leading-aligned under the section (a macOS grouped `Form`
    /// otherwise right-aligns footer content).
    func settingsFooterStyle() -> some View {
        self
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Line up with the rows' content inset, not the card edge.
            .padding(.horizontal, 10)
    }
}
