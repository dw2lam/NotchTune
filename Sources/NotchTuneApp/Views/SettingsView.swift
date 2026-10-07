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

    /// White glyph drawn on the colored tile.
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

// MARK: - Root settings view

struct SettingsView: View {
    var model: AppModel
    @State private var selectedTab: SettingsTab = .general

    private var lang: LanguageManager { model.lang }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detailView
        }
        .frame(minWidth: 780, idealWidth: 860, maxWidth: 1240, minHeight: 540, idealHeight: 640)
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
            // Groups are separated by spacing only — no header text that
            // would repeat the panes' own titles.
            ForEach(SettingsSection.allCases, id: \.self) { section in
                Section {
                    ForEach(section.tabs) { tab in
                        Label {
                            Text(tab.label(lang))
                                .font(.system(size: 13.5))
                        } icon: {
                            SettingsIconTile(systemName: tab.icon, color: tab.iconColor)
                        }
                        .padding(.vertical, 3)
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
        SettingsPane(
            title: lang.t("settings.tab.general"),
            subtitle: lang.t("settings.hero.general"),
            systemImage: SettingsTab.general.icon,
            color: SettingsTab.general.iconColor
        ) {
            SettingsCard(title: lang.t("settings.general.startup")) {
                SettingsToggleRow(lang.t("settings.general.launchAtLogin"), isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.launchAtLoginEnabled = $0 }
                ))

                SettingsRowDivider()

                SettingsPickerRow(lang.t("settings.general.monitor"), selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )) {
                    Text(lang.t("settings.general.automatic")).tag(OverlayDisplayOption.automaticID)
                    ForEach(model.overlayDisplayOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }

            SettingsCard(title: lang.t("settings.general.behavior")) {
                SettingsToggleRow(lang.t("settings.general.hideDockIcon"), isOn: Binding(
                    get: { !model.showDockIcon },
                    set: { model.showDockIcon = !$0 }
                ))

                SettingsRowDivider()

                SettingsToggleRow(lang.t("settings.general.hapticFeedback"), isOn: Binding(
                    get: { model.hapticFeedbackEnabled },
                    set: { model.hapticFeedbackEnabled = $0 }
                ))

                SettingsRowDivider()

                SettingsToggleRow(lang.t("settings.general.completionReply"), isOn: Binding(
                    get: { model.completionReplyEnabled },
                    set: { model.completionReplyEnabled = $0 }
                ))

                SettingsRowDivider()

                SettingsPickerRow(
                    lang.t("settings.general.hoverOpen"),
                    subtitle: lang.t("settings.general.hoverOpen.note"),
                    selection: Binding(
                        get: { model.hoverOpenMode },
                        set: { model.hoverOpenMode = $0 }
                    ),
                    style: .segmentedBelow
                ) {
                    ForEach(HoverOpenMode.allCases) { mode in
                        Text(lang.t("settings.general.hoverOpen.\(mode.rawValue)")).tag(mode)
                    }
                }

                SettingsRowDivider()

                SettingsToggleRow(
                    lang.t("settings.general.suppressFrontmostNotifications"),
                    subtitle: lang.t("settings.general.suppressFrontmostNotifications.note"),
                    isOn: Binding(
                        get: { model.suppressFrontmostNotifications },
                        set: { model.suppressFrontmostNotifications = $0 }
                    )
                )
            }

            SettingsCard(title: lang.t("settings.general.gettingStarted")) {
                SettingsRow(
                    lang.t("settings.general.setupAssistant"),
                    subtitle: lang.t("settings.general.setupAssistant.note")
                ) {
                    Button(lang.t("settings.general.open")) {
                        model.showOnboarding()
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    lang.t("settings.general.tour"),
                    subtitle: lang.t("settings.general.tour.note")
                ) {
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
                }
            }
        }
    }
}

// MARK: - Display

struct DisplaySettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        SettingsPane(
            title: lang.t("settings.tab.display"),
            subtitle: lang.t("settings.hero.display"),
            systemImage: SettingsTab.display.icon,
            color: SettingsTab.display.iconColor
        ) {
            SettingsCard(
                title: lang.t("settings.display.monitor"),
                footer: lang.t("settings.display.position.footer")
            ) {
                SettingsStackedRow(lang.t("settings.display.position")) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12, alignment: .top)],
                        alignment: .leading,
                        spacing: 14
                    ) {
                        displayTile(
                            id: OverlayDisplayOption.automaticID,
                            title: lang.t("settings.general.automatic"),
                            subtitle: nil,
                            systemImage: "sparkles"
                        )
                        ForEach(model.overlayDisplayOptions) { option in
                            displayTile(
                                id: option.id,
                                title: option.title,
                                subtitle: option.subtitle,
                                systemImage: Self.symbol(forDisplayNamed: option.title, subtitle: option.subtitle)
                            )
                        }
                    }
                }
            }

            if let diag = model.overlay.overlayPlacementDiagnostics {
                SettingsCard(title: lang.t("settings.display.diagnostics")) {
                    SettingsRow(lang.t("settings.display.currentScreen")) {
                        Text(diag.targetScreenName)
                            .font(SettingsMetrics.rowTitleFont)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    SettingsRowDivider()

                    SettingsRow(lang.t("settings.display.layoutMode")) {
                        Text(diag.modeDescription)
                            .font(SettingsMetrics.rowTitleFont)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// One display choice: a big symbol on a neutral tile, the display's
    /// name and kind underneath.
    private func displayTile(id: String, title: String, subtitle: String?, systemImage: String) -> some View {
        let isSelected = model.overlayDisplaySelectionID == id
        return SettingsTile(
            title: title,
            subtitle: subtitle,
            isSelected: isSelected,
            thumbnailHeight: 76,
            background: .neutral
        ) {
            model.overlayDisplaySelectionID = id
        } thumbnail: {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        }
    }

    /// The built-in panel draws as a laptop, anything else as a display.
    private static func symbol(forDisplayNamed name: String, subtitle: String) -> String {
        let text = (name + " " + subtitle).lowercased()
        return text.contains("built-in") || text.contains("notch") ? "laptopcomputer" : "display"
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
        SettingsPane(
            title: lang.t("settings.tab.sound"),
            subtitle: lang.t("settings.hero.sound"),
            systemImage: SettingsTab.sound.icon,
            color: SettingsTab.sound.iconColor
        ) {
            SettingsCard(title: lang.t("settings.sound.notifications")) {
                SettingsToggleRow(lang.t("settings.sound.mute"), isOn: Binding(
                    get: { model.isSoundMuted },
                    set: { _ in model.toggleSoundMuted() }
                ))

                SettingsRowDivider()

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

            SettingsCard(
                title: lang.t("settings.sound.customSounds"),
                footer: lang.t("settings.sound.customSounds.footer")
            ) {
                Button(lang.t("settings.sound.addCustomSound"), action: selectCustomSoundFile)
            } content: {
                if customSounds.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Text(lang.t("settings.sound.noCustomSounds"))
                            .font(SettingsMetrics.rowTitleFont)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinHeight, alignment: .leading)
                    .padding(.vertical, 6)
                } else {
                    ForEach(Array(customSounds.enumerated()), id: \.element) { index, filename in
                        if index > 0 {
                            SettingsRowDivider()
                        }
                        SettingsRow(cleanFilename(filename)) {
                            HStack(spacing: 8) {
                                SettingsIconButton(
                                    systemName: "play.fill",
                                    help: lang.t("settings.sound.preview")
                                ) {
                                    NotificationSoundService.play(filename)
                                }
                                SettingsIconButton(
                                    systemName: "trash",
                                    help: lang.t("settings.sound.delete"),
                                    tint: .red,
                                    role: .destructive
                                ) {
                                    deleteSound(filename)
                                }
                            }
                        }
                    }
                }
            }

            nudgeCard
        }
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
        SettingsRow(title) {
            HStack(spacing: 10) {
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

                SettingsIconButton(systemName: "play.fill", help: previewHelp, action: preview)
            }
        }
    }

    private var nudgeCard: some View {
        SettingsCard(
            title: "Idle Session Nudge",
            footer: "When a session waits for you longer than the chosen time, the island's character jumps once and the nudge sound plays. The nudge sound shares the custom sounds added above."
        ) {
            SettingsToggleRow("Nudge me about sessions I haven't answered", isOn: Binding(
                get: { model.nudgeSettings.isEnabled },
                set: { model.nudgeSettings.isEnabled = $0 }
            ))

            SettingsRowDivider()

            SettingsPickerRow("Nudge after", selection: Binding(
                get: { model.nudgeSettings.threshold },
                set: { model.nudgeSettings.threshold = $0 }
            )) {
                ForEach(IdleNudgeThreshold.allCases) { threshold in
                    Text(threshold.displayName).tag(threshold)
                }
            }
            .disabled(!model.nudgeSettings.isEnabled)

            SettingsRowDivider()

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
        SettingsPane(
            title: lang.t("settings.tab.updates"),
            subtitle: lang.t("settings.hero.updates"),
            systemImage: SettingsTab.updates.icon,
            color: SettingsTab.updates.iconColor
        ) {
            SettingsCard(title: lang.t("settings.updates.softwareUpdate")) {
                versionRow(lang.t("settings.updates.currentVersion"), value: currentVersion)

                SettingsRowDivider()

                versionRow(lang.t("settings.updates.build"), value: currentBuild)

                if model.updateChecker.hasUpdate,
                   let latestVersion = model.updateChecker.latestVersion {
                    SettingsRowDivider()

                    SettingsRow(lang.t("settings.updates.availableVersion")) {
                        SettingsStatusBadge(
                            text: latestVersion,
                            systemImage: "arrow.down.circle.fill",
                            color: .blue
                        )
                    }
                }
            }

            SettingsCard {
                SettingsRow(
                    lang.t("settings.updates.checkRow"),
                    subtitle: lang.t("settings.updates.automaticDetail")
                ) {
                    Button(lang.t("settings.updates.checkNow")) {
                        model.updateChecker.checkForUpdates()
                    }
                    .disabled(!model.updateChecker.canCheckForUpdates)
                }

                SettingsRowDivider()

                SettingsRow(lang.t("settings.updates.releaseNotesRow")) {
                    Button(lang.t("settings.updates.releaseNotes")) {
                        NSWorkspace.shared.open(UpdateChecker.releasesURL)
                    }
                }
            }
        }
    }

    private func versionRow(_ title: String, value: String) -> some View {
        SettingsRow(title) {
            Text(value)
                .font(SettingsMetrics.rowTitleFont)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
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
        SettingsPane(title: lang.t("settings.tab.about")) {
            aboutHero
        } content: {
            SettingsCard(title: "Credits") {
                creditLinkRow(
                    title: "View NotchTune source",
                    subtitle: "Open source on GitHub",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    color: .indigo,
                    url: "https://github.com/dw2lam/NotchTune"
                )

                SettingsRowDivider()

                creditLinkRow(
                    title: "Forked from Open Vibe Island",
                    subtitle: "Octane0411/open-vibe-island",
                    systemImage: "arrow.triangle.branch",
                    color: .teal,
                    url: "https://github.com/Octane0411/open-vibe-island"
                )

                SettingsRowDivider()

                creditLinkRow(
                    title: "Music foundation from Tuneful",
                    subtitle: "martinfekete10/Tuneful",
                    systemImage: "music.note",
                    color: .pink,
                    url: "https://github.com/martinfekete10/Tuneful"
                )

                SettingsRowDivider()

                creditLinkRow(
                    title: "Created by David",
                    subtitle: "dw2lam",
                    systemImage: "person.fill",
                    color: .orange,
                    url: "https://github.com/dw2lam"
                )
            }

            SettingsCard {
                SettingsRow(
                    lang.t("settings.about.quitApp"),
                    subtitle: lang.t("settings.about.quitApp.note")
                ) {
                    Button(lang.t("settings.about.quit"), role: .destructive) {
                        model.quitApplication()
                    }
                    .accessibilityIdentifier("settings.about.quitApp")
                }
            }
        }
    }

    /// The app's identity in place of a pane icon: the real app icon,
    /// name, one-line description and version, on a softly lit card.
    private var aboutHero: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
                .padding(.bottom, 4)

            Text(lang.t("app.name"))
                .font(.title.weight(.bold))

            Text(lang.t("app.description"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let versionLine {
                Text(versionLine)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .padding(.top, 2)
            }

            Text("Originally Open Island")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 24)
        .background {
            ZStack {
                SettingsCardBackground()
                RadialGradient(
                    colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0)],
                    center: .top,
                    startRadius: 0,
                    endRadius: 260
                )
                .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.cardCornerRadius, style: .continuous))
            }
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    /// A credit row that opens its page in the browser: a small colored
    /// glyph tile, title + secondary line, a trailing "open externally"
    /// arrow.
    private func creditLinkRow(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        url: String
    ) -> some View {
        Link(destination: URL(string: url)!) {
            SettingsRow {
                HStack(spacing: 12) {
                    SettingsIconTile(systemName: systemImage, color: color, size: 30)
                    SettingsRowLabel(title: title, subtitle: subtitle)
                }
            } accessory: {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
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
        SettingsPane(
            title: lang.t("settings.tab.setup"),
            subtitle: lang.t("settings.hero.setup"),
            systemImage: SettingsTab.setup.icon,
            color: SettingsTab.setup.iconColor
        ) {
            if !model.hasAnyInstalledAgent {
                emptyStateBanner
            }

            hooksCard

            usageCard

            claudeConfigDirectoryCard

            SettingsCard(title: lang.t("setup.section.permissions")) {
                SettingsRow(
                    lang.t("setup.permissionsTitle"),
                    subtitle: lang.t("setup.permissionsDesc")
                ) {
                    Button(lang.t("setup.permissions.open")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            hookDiagnosticsCard

            RemoteConnectionSection(model: model)
        }
    }

    // MARK: Hooks

    private var hooksCard: some View {
        SettingsCard(
            title: lang.t("setup.section.hooks"),
            footer: lang.t("setup.section.hooks.footer")
        ) {
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
        } content: {
            hookRow(
                name: "Claude Code",
                tool: .claudeCode,
                iconTitle: "Claude",
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

            SettingsRowDivider(leadingInset: 44)

            hookRow(
                name: "Codex",
                tool: .codex,
                iconTitle: "Codex",
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

            SettingsRowDivider(leadingInset: 44)

            hookRow(
                name: "OpenCode",
                tool: .openCode,
                iconTitle: "OpenCode",
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

            SettingsRowDivider(leadingInset: 44)

            hookRow(
                name: "Qoder",
                tool: .qoder,
                iconTitle: nil,
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

            SettingsRowDivider(leadingInset: 44)

            hookRow(
                name: "Qwen Code",
                tool: .qwenCode,
                iconTitle: "Qwen Code",
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

            SettingsRowDivider(leadingInset: 44)

            hookRow(
                name: "Factory",
                tool: .factory,
                iconTitle: nil,
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

            SettingsRowDivider(leadingInset: 44)

            hookRow(
                name: "CodeBuddy",
                tool: .codebuddy,
                iconTitle: nil,
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

            SettingsRowDivider(leadingInset: 44)

            hookRow(
                name: "Cursor",
                tool: .cursor,
                iconTitle: "Cursor",
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

            SettingsRowDivider(leadingInset: 44)

            hookRow(
                name: "Gemini CLI",
                tool: .geminiCLI,
                iconTitle: "Gemini",
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

            SettingsRowDivider(leadingInset: 44)

            hookRow(
                name: "Antigravity",
                tool: .antigravity,
                iconTitle: "Antigravity",
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

            SettingsRowDivider(leadingInset: 44)

            hookRow(
                name: "Kimi CLI",
                tool: .kimiCLI,
                iconTitle: "Kimi",
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
        }
    }

    // MARK: Usage

    private var usageCard: some View {
        SettingsCard(
            title: lang.t("setup.section.usage"),
            footer: lang.t("setup.section.usage.footer")
        ) {
            SettingsRow(
                lang.t("setup.usageBridge"),
                subtitle: lang.t("setup.usageBridgeDesc")
            ) {
                if model.claudeUsageInstalled {
                    HStack(spacing: 10) {
                        SettingsStatusBadge(text: lang.t("setup.usageBridgeReady"))
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
            }
            .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallClaudeUsage) {
                Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                    model.uninstallClaudeUsageBridge()
                }
                Button(lang.t("settings.general.cancel"), role: .cancel) {}
            } message: {
                Text(lang.t("settings.general.uninstallConfirmMessage.claudeUsage"))
            }

            SettingsRowDivider()

            SettingsToggleRow(lang.t("settings.general.showCodexUsage"), isOn: Binding(
                get: { model.showCodexUsage },
                set: { model.showCodexUsage = $0 }
            ))
        }
    }

    // MARK: Claude config directory

    private var claudeConfigDirectoryCard: some View {
        SettingsCard(
            title: lang.t("setup.claudeConfigDir.section"),
            footer: lang.t("setup.claudeConfigDir.footer")
        ) {
            SettingsRow {
                VStack(alignment: .leading, spacing: 5) {
                    Text(lang.t("setup.claudeConfigDir.title"))
                        .font(SettingsMetrics.rowTitleFont)
                    Text(ClaudeConfigDirectory.resolved().path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } accessory: {
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
            }
        }
    }

    private var allReady: Bool {
        model.claudeHooksInstalled && model.codexHooksInstalled && model.openCodePluginInstalled
            && model.qoderHooksInstalled && model.qwenCodeHooksInstalled && model.factoryHooksInstalled && model.codebuddyHooksInstalled
            && model.cursorHooksInstalled && model.geminiHooksInstalled && model.kimiHooksInstalled && model.claudeUsageInstalled
    }

    /// First-run welcome: a softly tinted card above the hooks list.
    private var emptyStateBanner: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.accentColor.gradient))

            VStack(alignment: .leading, spacing: 4) {
                Text(lang.t("setup.banner.noHooks.title"))
                    .font(.system(size: 14, weight: .semibold))
                Text(lang.t("setup.banner.noHooks.message"))
                    .font(SettingsMetrics.rowSubtitleFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: SettingsMetrics.cardCornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
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

    // MARK: Diagnostics

    private var hookDiagnosticsCard: some View {
        SettingsCard(title: lang.t("setup.section.diagnostics")) {
            if let claudeReport = model.claudeHealthReport, !claudeReport.issues.isEmpty {
                issueList(report: claudeReport)
                SettingsRowDivider()
            }
            if let codexReport = model.codexHealthReport, !codexReport.issues.isEmpty {
                issueList(report: codexReport)
                SettingsRowDivider()
            }

            if model.claudeHealthReport == nil && model.codexHealthReport == nil {
                SettingsRow {
                    diagnosticsStatusLabel(
                        lang.t("setup.diagnostics.notRun"),
                        systemImage: "stethoscope",
                        color: .secondary
                    )
                } accessory: {
                    Button(lang.t("setup.diagnostics.runCheck")) {
                        model.runHealthChecks()
                    }
                }
            } else if !hasErrors {
                SettingsRow {
                    diagnosticsStatusLabel(
                        lang.t("setup.diagnostics.allHealthy"),
                        systemImage: "checkmark.circle.fill",
                        color: .green
                    )
                } accessory: {
                    Button(lang.t("setup.diagnostics.recheck")) {
                        model.runHealthChecks()
                    }
                }
            } else {
                SettingsRow {
                    diagnosticsStatusLabel(
                        lang.t("setup.diagnostics.issuesFound"),
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                } accessory: {
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
                }
            }
        }
    }

    private func diagnosticsStatusLabel(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(SettingsMetrics.rowTitleFont)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func issueList(report: HookHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(report.agent == "claude" ? "Claude Code" : "Codex")
                .font(.system(size: 14, weight: .semibold))

            ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                Label {
                    Text(issue.description)
                        .font(.system(size: 13))
                        .foregroundStyle(issue.severity == .info ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: issueIcon(for: issue))
                        .foregroundStyle(issueColor(for: issue))
                }
            }

            if let binaryPath = report.binaryPath {
                Text("Binary: \(binaryPath)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
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

    /// One agent: its logo, name and install state; reveal / uninstall when
    /// installed, install otherwise.
    @ViewBuilder
    private func hookRow(
        name: String,
        tool: AgentTool,
        iconTitle: String?,
        installed: Bool,
        busy: Bool,
        requiresBinary: Bool = true,
        configLocationURL: URL? = nil,
        installAction: @escaping () -> Void,
        uninstallAction: @escaping () -> Void
    ) -> some View {
        SettingsRow {
            HStack(spacing: 14) {
                AgentLogoTile(name: name, tool: tool, iconTitle: iconTitle)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(SettingsMetrics.rowTitleFont)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(installed ? Color.green : Color.secondary.opacity(0.45))
                            .frame(width: 6, height: 6)
                        Text(installed ? lang.t("settings.general.activated") : lang.t("setup.hookMissing"))
                            .font(SettingsMetrics.rowSubtitleFont)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } accessory: {
            if installed {
                HStack(spacing: 8) {
                    if let configLocationURL {
                        SettingsIconButton(
                            systemName: "folder",
                            help: lang.t("setup.revealConfigLocation")
                        ) {
                            revealInFinder(configLocationURL)
                        }
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

/// The agent's installed app icon when there is one, otherwise a monogram
/// on the agent's brand color.
private struct AgentLogoTile: View {
    let name: String
    let tool: AgentTool
    let iconTitle: String?

    private let size: CGFloat = 30

    var body: some View {
        Group {
            if let iconTitle, let icon = AgentAppIconProvider.installedAppIcon(forProviderTitle: iconTitle) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                let color = Color(hex: tool.brandColorHex) ?? .gray
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(color.gradient)
                    .overlay(
                        Text(String(name.prefix(1)))
                            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Music

struct MusicSettingsPane: View {
    var model: AppModel
    @AppStorage("music.connectedApp") private var connectedApp: String = "none"

    private var lang: LanguageManager { model.lang }

    private var spotifyInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Spotify.app")
    }

    var body: some View {
        SettingsPane(
            title: "Music",
            subtitle: lang.t("settings.hero.music"),
            systemImage: SettingsTab.music.icon,
            color: SettingsTab.music.iconColor
        ) {
            SettingsCard(
                title: "Music Player",
                footer: "NotchTune will only connect to the selected app. Choose None to disable music controls entirely."
            ) {
                SettingsStackedRow("Player") {
                    HStack(alignment: .top, spacing: 12) {
                        playerTile(tag: "none", title: "None") {
                            Image(systemName: "speaker.slash.fill")
                                .font(.system(size: 26, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        playerTile(tag: "appleMusic", title: "Apple Music") {
                            appIcon(atPath: "/System/Applications/Music.app")
                        }
                        if spotifyInstalled {
                            playerTile(tag: "spotify", title: "Spotify") {
                                appIcon(atPath: "/Applications/Spotify.app")
                            }
                        }
                    }
                    .frame(maxWidth: spotifyInstalled ? .infinity : 420, alignment: .leading)
                }
            }
        }
    }

    private func playerTile<Thumbnail: View>(
        tag: String,
        title: String,
        @ViewBuilder thumbnail: @escaping () -> Thumbnail
    ) -> some View {
        SettingsTile(
            title: title,
            isSelected: connectedApp == tag,
            thumbnailHeight: 84,
            background: .neutral
        ) {
            connectedApp = tag
        } thumbnail: {
            thumbnail()
        }
    }

    private func appIcon(atPath path: String) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: 52, height: 52)
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
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
        SettingsCard(
            title: "Remote (Beta)",
            footer: "The remote sshd needs `StreamLocalBindUnlink yes` in /etc/ssh/sshd_config for reliable reconnects."
        ) {
            SettingsRow(
                "SSH remote",
                subtitle: "Monitor Claude Code running on remote servers via SSH."
            ) {
                if remoteSessionCount > 0 {
                    SettingsStatusBadge(
                        text: "\(remoteSessionCount) active",
                        systemImage: "circle.fill",
                        color: .green
                    )
                } else {
                    Text("No remote sessions")
                        .font(SettingsMetrics.rowSubtitleFont)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsRowDivider()

            remoteSetupStep(
                number: 1,
                title: "Deploy hooks to the remote server",
                description: "Run from the NotchTune repo directory:",
                command: setupCommand
            )

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 12) {
                remoteSetupStep(
                    number: 2,
                    title: "Connect with socket forwarding",
                    description: "Add to ~/.ssh/config (recommended):",
                    command: sshConfigSnippet,
                    multiline: true
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Or connect directly:")
                        .font(SettingsMetrics.rowSubtitleFont)
                        .foregroundStyle(.secondary)
                    copyableCommand(sshCommand)
                }
                .padding(.leading, 34)
            }
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func remoteSetupStep(
        number: Int,
        title: String,
        description: String,
        command: String,
        multiline: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.gradient))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(SettingsMetrics.rowTitleFont)
                    .accessibilityLabel("\(number). \(title)")
                Text(description)
                    .font(SettingsMetrics.rowSubtitleFont)
                    .foregroundStyle(.secondary)
                copyableCommand(command, multiline: multiline)
            }
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func copyableCommand(_ command: String, multiline: Bool = false) -> some View {
        let isCopied = copiedCommand == command
        HStack(alignment: multiline ? .top : .center) {
            Text(command)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(multiline ? nil : 1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            SettingsIconButton(
                systemName: isCopied ? "checkmark" : "doc.on.doc",
                help: "Copy",
                tint: isCopied ? .green : nil
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copiedCommand = command
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if copiedCommand == command {
                        copiedCommand = nil
                    }
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
