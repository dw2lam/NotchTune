import SwiftUI
import AppKit
import NotchTuneCore
import UniformTypeIdentifiers

// MARK: - Settings tabs

/// The sidebar's sections, in sidebar order. About and Updates live at the
/// top of General now; `resolving(_:)` still lands their old names there.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case setup
    case appearance
    case display
    case sound
    case music

    var id: String { rawValue }

    /// The tab a raw name selects, retired names included ("about" and
    /// "updates" → General).
    static func resolving(_ raw: String) -> SettingsTab? {
        if let tab = SettingsTab(rawValue: raw) { return tab }
        return ["about", "updates"].contains(raw) ? .general : nil
    }

    func label(_ lang: LanguageManager) -> String {
        switch self {
        case .general:    lang.t("settings.tab.general")
        case .setup:      lang.t("settings.tab.setup")
        case .appearance: lang.t("settings.tab.appearance")
        case .display:    lang.t("settings.tab.display")
        case .sound:      lang.t("settings.tab.sound")
        case .music:      "Music"
        }
    }

    /// The section's glyph, in the island tab bar's outline style (Setup
    /// shares the Agents tab's terminal, Music the Music tab's note).
    var icon: String {
        switch self {
        case .general:    "gearshape"
        case .setup:      "terminal"
        case .appearance: "paintbrush.pointed"
        case .display:    "display"
        case .sound:      "speaker.wave.2"
        case .music:      "music.note"
        }
    }

    /// The section's colour, from its sidebar tile to the glow behind its
    /// hero. Setup and Display take the app icon's grass and sky.
    var tint: SettingsTint {
        switch self {
        case .general:    .graphite
        case .setup:      .grass
        case .display:    .sky
        case .sound:      .rose
        case .music:      .ember
        case .appearance: .violet
        }
    }

    var section: SettingsSection {
        switch self {
        case .general:                       .app
        case .setup, .appearance, .display: .island
        case .sound, .music:                 .media
        }
    }
}

/// The sidebar's groups, as System Settings groups its own: the app, the
/// island and what it shows, then what it plays.
enum SettingsSection: String, CaseIterable {
    case app
    case island
    case media

    var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0.section == self }
    }
}

// MARK: - Root settings view

struct SettingsView: View {
    var model: AppModel
    @State private var selectedTab: SettingsTab = .general
    @State private var isWindowOnScreen = true
    @Namespace private var selectionNamespace

    private var lang: LanguageManager { model.lang }

    var body: some View {
        // One glass surface: a full-height sidebar under the traffic lights,
        // a hairline, then the pane.
        HStack(spacing: 0) {
            sidebar
            detailView
                .environment(\.settingsWindowIsOnScreen, isWindowOnScreen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            GeometryReader { proxy in
                SettingsPaneGlow(tint: glowTint, window: proxy)
            }
            .ignoresSafeArea()
        }
        .background(SettingsWindowGlass().ignoresSafeArea())
        .settingsTheme()
        .onWindowOnScreenChange { isWindowOnScreen = $0 }
        .frame(minWidth: 780, idealWidth: 860, maxWidth: 1240, minHeight: 540, idealHeight: 640)
        .onReceive(NotificationCenter.default.publisher(for: .notchTuneSelectSetupTab)) { _ in
            selectedTab = .setup
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchTuneSelectSettingsTab)) { note in
            if let raw = note.object as? String, let tab = SettingsTab.resolving(raw) {
                selectedTab = tab
            }
        }
    }

    /// General's glow follows the welcome's colour for the hour.
    private var glowTint: SettingsTint {
        selectedTab == .general ? SettingsWelcome.dayPart(at: Date()).tint : selectedTab.tint
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Groups are separated by spacing only — no header text that
            // would repeat the panes' own titles.
            ForEach(Array(SettingsSection.allCases.enumerated()), id: \.element) { index, section in
                if index > 0 {
                    Spacer().frame(height: 16)
                }
                ForEach(section.tabs) { tab in
                    SettingsSidebarRow(
                        title: tab.label(lang),
                        isSelected: selectedTab == tab,
                        selectionNamespace: selectionNamespace
                    ) {
                        withAnimation(.smooth(duration: 0.3, extraBounce: 0.08)) { selectedTab = tab }
                    } glyph: {
                        sidebarGlyph(for: tab)
                    }
                }
            }
        }
        // The rows start under the traffic lights; the sidebar's own
        // surface runs up behind them to the window's top edge.
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .frame(width: SettingsTheme.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            SettingsSidebarBackground()
                .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    @ViewBuilder
    private func sidebarGlyph(for tab: SettingsTab) -> some View {
        if tab == .appearance {
            // Personalization is the character's own pane: it shows the one
            // being picked there (the edited profile's, which may not be
            // the one on screen right now), swapping as you choose.
            let character = model.appearancePreferences(for: model.appearanceSettingsProfile).character
            SettingsGlyphTile(size: Self.sidebarTileSize, tint: tab.tint) {
                ZStack {
                    PixelCharacterView(
                        character: character,
                        mode: .idle,
                        paused: true,
                        tint: tab.tint.glyph
                    )
                    .id(character)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
                .frame(width: 15, height: 15)
                .animation(.smooth(duration: 0.3), value: character)
            }
        } else {
            SettingsGlyphTile(systemName: tab.icon, size: Self.sidebarTileSize, tint: tab.tint)
        }
    }

    private static let sidebarTileSize: CGFloat = 20

    // MARK: Detail

    @ViewBuilder
    private var detailView: some View {
        ZStack {
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
            }
        }
        .environment(\.settingsTint, selectedTab.tint)
        .id(selectedTab)
        .transition(.opacity)
    }
}

/// The shown section's colour, glowing up from behind its hero tile across
/// the window's glass (sidebar included), so it never ends in an edge.
private struct SettingsPaneGlow: View {
    let tint: SettingsTint
    let window: GeometryProxy

    var body: some View {
        let size = window.size
        // Where the hero tile sits: past the sidebar, in the pane's column,
        // under the title bar.
        let sidebar = SettingsTheme.sidebarWidth
        let paneWidth = max(size.width - sidebar, 0)
        let hero = CGPoint(
            x: sidebar + SettingsMetrics.columnLeadingInset(forPaneWidth: paneWidth)
                + SettingsMetrics.paneHorizontalPadding + SettingsMetrics.heroIconSize / 2,
            y: window.safeAreaInsets.top + SettingsMetrics.paneTopPadding + 6 + SettingsMetrics.heroIconSize / 2
        )
        RadialGradient(
            colors: [tint.bottom.opacity(0.34), tint.bottom.opacity(0.12), tint.bottom.opacity(0)],
            center: UnitPoint(x: hero.x / max(size.width, 1), y: hero.y / max(size.height, 1)),
            startRadius: 0,
            endRadius: 460
        )
        .animation(.smooth(duration: 0.35), value: tint)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One sidebar entry, sized like System Settings' own: the section's
/// coloured tile and a label, the selected one on a sky pill that slides
/// between rows.
private struct SettingsSidebarRow<Glyph: View>: View {
    let title: String
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                glyph()
                    .frame(width: 20, height: 20)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? SettingsTheme.onAccent : SettingsTheme.paper.opacity(isHovered ? 0.95 : 0.86))
            .padding(.horizontal, 7)
            .frame(height: 30)
            .background {
                let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                if isSelected {
                    SettingsAccentThumb(shape: shape)
                        .matchedGeometryEffect(id: "settingsSidebarSelection", in: selectionNamespace)
                } else if isHovered {
                    shape.fill(SettingsTheme.hoverFill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        // Settings opens here, so its hero is a welcome rather than a title,
        // and it carries the app itself (version, updates, credits).
        SettingsPane(title: lang.t("settings.tab.general")) {
            SettingsWelcomeHero(model: model)
        } content: {
            SettingsCard(title: lang.t("settings.general.startup")) {
                SettingsToggleRow(lang.t("settings.general.launchAtLogin"), isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.launchAtLoginEnabled = $0 }
                ))

                SettingsRowDivider()

                SettingsPickerRow(
                    lang.t("settings.general.monitor"),
                    selection: Binding(
                        get: { model.overlayDisplaySelectionID },
                        set: { model.overlayDisplaySelectionID = $0 }
                    ),
                    segments: [SettingsSegment(OverlayDisplayOption.automaticID, lang.t("settings.general.automatic"))]
                        + model.overlayDisplayOptions.map { SettingsSegment($0.id, $0.title) }
                )
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
                    style: .segmentedBelow,
                    segments: HoverOpenMode.allCases.map {
                        SettingsSegment($0, lang.t("settings.general.hoverOpen.\($0.rawValue)"))
                    }
                )

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
}

// MARK: - Display

struct DisplaySettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        SettingsPane(
            title: lang.t("settings.tab.display"),
            subtitle: lang.t("settings.hero.display"),
            systemImage: SettingsTab.display.icon
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
                .foregroundStyle(SettingsTheme.paper.opacity(isSelected ? 0.95 : 0.5))
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
    @State private var customSounds: [String] = NotificationSoundService.availableCustomSounds()
    /// The system sounds, listed when the pane is created — not by a
    /// directory read on every render (twice per body: both pickers).
    @State private var availableSounds: [String] = NotificationSoundService.availableSounds()

    private var lang: LanguageManager { model.lang }

    var body: some View {
        SettingsPane(
            title: lang.t("settings.tab.sound"),
            subtitle: lang.t("settings.hero.sound"),
            systemImage: SettingsTab.sound.icon
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
                                    tint: SettingsTheme.critical,
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
                SettingsMenuPicker(title, selection: selection, sections: soundSections)

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

            SettingsPickerRow(
                "Nudge after",
                selection: Binding(
                    get: { model.nudgeSettings.threshold },
                    set: { model.nudgeSettings.threshold = $0 }
                ),
                segments: IdleNudgeThreshold.allCases.map { SettingsSegment($0, $0.displayName) }
            )
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

    /// NotchTune's own pack, the system sounds, then any custom ones, for
    /// the sound menus.
    private var soundSections: [(title: String?, segments: [SettingsSegment<String>])] {
        var sections: [(title: String?, segments: [SettingsSegment<String>])] = []
        let pack = NotificationSoundService.bundledSounds
        if !pack.isEmpty {
            sections.append((lang.t("settings.sound.notchTuneSounds"), pack.map { SettingsSegment($0.id, $0.title) }))
        }
        sections.append((lang.t("settings.sound.systemSounds"), availableSounds.map { SettingsSegment($0, $0) }))
        if !customSounds.isEmpty {
            sections.append((
                lang.t("settings.sound.customSounds"),
                customSounds.map { SettingsSegment($0, cleanFilename($0)) }
            ))
        }
        return sections
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
            systemImage: SettingsTab.setup.icon
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
                for step in installAllSteps where !step.installed {
                    step.install()
                }
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
                        .font(.system(size: 12))
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

    /// Everything "Install All" installs. Its action and its enabled state
    /// both read this one list, so they can't drift apart (Antigravity was
    /// installed by the button but missing from its "all ready" check, which
    /// greyed the button out while Antigravity still needed installing).
    private var installAllSteps: [(installed: Bool, install: () -> Void)] {
        [
            (model.claudeHooksInstalled, model.installClaudeHooks),
            (model.codexHooksInstalled, model.installCodexHooks),
            (model.openCodePluginInstalled, model.installOpenCodePlugin),
            (model.qoderHooksInstalled, model.installQoderHooks),
            (model.qwenCodeHooksInstalled, model.installQwenCodeHooks),
            (model.factoryHooksInstalled, model.installFactoryHooks),
            (model.codebuddyHooksInstalled, model.installCodebuddyHooks),
            (model.cursorHooksInstalled, model.installCursorHooks),
            (model.geminiHooksInstalled, model.installGeminiHooks),
            (model.antigravityHooksInstalled, model.installAntigravityHooks),
            (model.kimiHooksInstalled, model.installKimiHooks),
            (model.claudeUsageInstalled, model.installClaudeUsageBridge),
        ]
    }

    private var allReady: Bool {
        installAllSteps.allSatisfy(\.installed)
    }

    /// First-run welcome: a card washed in the sky accent above the hooks
    /// list.
    private var emptyStateBanner: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SettingsTheme.onAccent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(SettingsTheme.accent))

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
                .fill(SettingsTheme.accent.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(SettingsTheme.accent.opacity(0.35), lineWidth: 1)
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
                        color: SettingsTheme.positive
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
                        color: SettingsTheme.caution
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
                    .font(.system(size: 11.5))
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
        case .info: SettingsTheme.informative
        case .error: issue.isAutoRepairable ? SettingsTheme.caution : SettingsTheme.critical
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
                            .fill(installed ? SettingsTheme.positive : SettingsTheme.paper.opacity(0.3))
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

/// The agent's installed app icon when there is one, otherwise its initial
/// in the agent's brand colour on a notch tile.
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
                let color = Color(hex: tool.brandColorHex) ?? SettingsTheme.paper
                SettingsGlyphTile(size: size) {
                    Text(String(name.prefix(1)))
                        .font(.system(size: size * 0.48, weight: .bold))
                        .foregroundStyle(color)
                }
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

    /// Through LaunchServices (cached), like the rest of the music code: a
    /// Spotify installed outside /Applications (e.g. ~/Applications, where
    /// its installer goes without admin rights) still gets its tile.
    private var spotifyInstalled: Bool {
        MusicPlayerIcon.icon(for: .spotify) != nil
    }

    var body: some View {
        SettingsPane(
            title: "Music",
            subtitle: lang.t("settings.hero.music"),
            systemImage: SettingsTab.music.icon
        ) {
            SettingsCard(
                title: "Music Player",
                footer: "NotchTune will only connect to the selected app. Choose None to disable music controls entirely."
            ) {
                SettingsStackedRow("Player") {
                    HStack(alignment: .top, spacing: 12) {
                        playerTile(tag: "none", title: "None") {
                            Image(systemName: "speaker.slash")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(SettingsTheme.paper.opacity(0.55))
                        }
                        playerTile(tag: "appleMusic", title: "Apple Music") {
                            appIcon(for: .appleMusic)
                        }
                        if spotifyInstalled {
                            playerTile(tag: "spotify", title: "Spotify") {
                                appIcon(for: .spotify)
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

    /// The player's real app icon, cached — not a fresh NSWorkspace icon
    /// load on every render.
    private func appIcon(for kind: MusicPlayerKind) -> some View {
        Image(nsImage: MusicPlayerIcon.icon(for: kind) ?? NSWorkspace.shared.icon(for: .application))
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
                        color: SettingsTheme.positive
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
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(SettingsTheme.onAccent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(SettingsTheme.accent))
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
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(multiline ? nil : 1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            SettingsIconButton(
                systemName: isCopied ? "checkmark" : "doc.on.doc",
                help: "Copy",
                tint: isCopied ? SettingsTheme.positive : nil
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
            RoundedRectangle(cornerRadius: IslandRadius.inner, style: .continuous)
                .fill(SettingsTheme.ink.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: IslandRadius.inner, style: .continuous)
                .strokeBorder(SettingsTheme.paper.opacity(0.08), lineWidth: 1)
        )
    }
}
