import SwiftUI
import NotchTuneCore

/// Personalization pane.
///
/// A roomy pane led by a LIVE preview: the real closed pill on a wallpaper,
/// at the top of a mock display, cycling Idle → Working → Needs approval →
/// Finished (or pinned to one state) and redrawn instantly with every choice
/// below. Picture choices are tiles; the rest are switches and pickers in
/// soft cards. Every setting edits the display profile chosen under the
/// preview.
struct AppearanceSettingsPane: View {
    var model: AppModel

    @State private var previewPin: PersonalizationPreviewPin = .auto
    @State private var previewPhase: PersonalizationPreviewPhase = .idle
    @State private var phaseStartedAt = Date()
    @State private var finishHop: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lang: LanguageManager { model.lang }
    private var editingProfile: IslandAppearanceDisplayProfile { model.appearanceSettingsProfile }
    private var editingPreferences: IslandAppearancePreferences {
        model.appearancePreferences(for: editingProfile)
    }

    var body: some View {
        SettingsPane(
            title: lang.t("settings.tab.appearance"),
            subtitle: lang.t("settings.hero.appearance"),
            systemImage: SettingsTab.appearance.icon,
            color: SettingsTab.appearance.iconColor
        ) {
            previewCard
            characterCard
            notchCard
            liquidGlassCard
            sessionListCard
        }
        .task(id: previewPin) {
            await runPreview()
        }
    }

    /// Writes one field of the profile being edited.
    private func binding<Value>(
        _ keyPath: WritableKeyPath<IslandAppearancePreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { editingPreferences[keyPath: keyPath] },
            set: { value in
                model.updateAppearancePreferences(for: editingProfile) { $0[keyPath: keyPath] = value }
            }
        )
    }

    // MARK: - Live preview

    private var previewCard: some View {
        SettingsCard(
            footer: profileFooter,
            insets: EdgeInsets(top: 10, leading: 10, bottom: 14, trailing: 10)
        ) {
            PersonalizationPreviewStage(
                preferences: editingPreferences,
                profile: editingProfile,
                glassSettings: model.glassSettings,
                phase: previewPhase,
                phaseStartedAt: phaseStartedAt,
                finishHop: finishHop,
                isAutoCycling: previewPin == .auto,
                lang: lang
            )

            HStack(spacing: 12) {
                Picker(lang.t("settings.appearance.profile.title"), selection: Binding(
                    get: { model.appearanceSettingsProfile },
                    set: { model.appearanceSettingsProfile = $0 }
                )) {
                    Label(lang.t("settings.appearance.profile.macbook.title"), systemImage: "laptopcomputer")
                        .tag(IslandAppearanceDisplayProfile.notch)
                    Label(lang.t("settings.appearance.profile.external.title"), systemImage: "display")
                        .tag(IslandAppearanceDisplayProfile.topBar)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(lang.t("settings.appearance.profile.note"))

                Spacer(minLength: 8)

                Picker(lang.t("settings.appearance.state.title"), selection: $previewPin) {
                    Text(lang.t("settings.appearance.state.auto")).tag(PersonalizationPreviewPin.auto)
                    Text(lang.t("settings.appearance.state.idle")).tag(PersonalizationPreviewPin.idle)
                    Text(lang.t("settings.appearance.state.working")).tag(PersonalizationPreviewPin.working)
                    Text(lang.t("settings.appearance.state.waiting")).tag(PersonalizationPreviewPin.waiting)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.top, 14)
            .padding(.horizontal, 6)
        }
    }

    /// "Editing <profile>: <what it is>. NotchTune applies …".
    private var profileFooter: String {
        let note = editingProfile == .notch
            ? lang.t("settings.appearance.profile.macbook.note")
            : lang.t("settings.appearance.profile.external.note")
        return "\(note) \(lang.t("settings.appearance.profile.note"))"
    }

    /// Pinned: jump to that state. Auto: walk the moments forever, resting
    /// on each for its dwell.
    private func runPreview() async {
        if let pinned = previewPin.phase {
            showPreviewPhase(pinned)
            return
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: previewPhase.dwell)
            guard !Task.isCancelled else { return }
            showPreviewPhase(previewPhase.next)
        }
    }

    private func showPreviewPhase(_ phase: PersonalizationPreviewPhase) {
        guard phase != previewPhase else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45)) {
            previewPhase = phase
            phaseStartedAt = Date()
        }
        // The real island hops the character when a finish peek lands.
        if phase == .finished, !reduceMotion {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                finishHop = UUID()
            }
        }
    }

    // MARK: - Character

    private var characterCard: some View {
        SettingsCard(title: lang.t("settings.appearance.character.title")) {
            SettingsTileRow(
                title: lang.t("settings.appearance.character.row"),
                detail: lang.t("settings.appearance.character.note")
            ) {
                ForEach(IslandCharacter.allCases) { option in
                    let isSelected = editingPreferences.character == option
                    SettingsTile(
                        title: title(for: option),
                        isSelected: isSelected,
                        thumbnailHeight: 78
                    ) {
                        model.updateAppearancePreferences(for: editingProfile) { $0.character = option }
                    } thumbnail: {
                        CharacterTileSprite(character: option, isSelected: isSelected)
                    }
                }
            }

            SettingsRowDivider()

            SettingsToggleRow(
                lang.t("settings.appearance.colorByAgent.title"),
                subtitle: lang.t("settings.appearance.colorByAgent.note"),
                isOn: binding(\.colorByAgent)
            )

            if editingPreferences.colorByAgent {
                SettingsRowDivider()

                SettingsStackedRow(lang.t("settings.appearance.colorByAgent.legend")) {
                    HStack(spacing: 10) {
                        ForEach([AgentTool.claudeCode, .codex, .geminiCLI, .cursor], id: \.self) { tool in
                            AgentColorChip(tool: tool, character: editingPreferences.character)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: editingPreferences.colorByAgent)
    }

    // MARK: - Notch

    private var notchCard: some View {
        SettingsCard(title: lang.t("settings.appearance.notchPart.title")) {
            SettingsTileRow(
                title: lang.t("settings.appearance.density.title"),
                detail: lang.t("settings.appearance.density.note")
            ) {
                ForEach(IslandDensity.allCases) { option in
                    SettingsTile(
                        title: title(for: option),
                        isSelected: editingPreferences.density == option,
                        thumbnailHeight: 70,
                        background: .wallpaper
                    ) {
                        model.updateAppearancePreferences(for: editingProfile) { $0.density = option }
                    } thumbnail: {
                        DensityPreview(option: option, character: editingPreferences.character)
                    }
                }
            }

            SettingsRowDivider()

            SettingsToggleRow(
                lang.t("settings.appearance.topCurve.title"),
                subtitle: lang.t("settings.appearance.topCurve.note"),
                isOn: binding(\.topCurve)
            )

            SettingsRowDivider()

            SettingsStackedRow(
                lang.t("settings.appearance.liveActivity.title"),
                subtitle: lang.t("settings.appearance.liveActivity.note")
            ) {
                Picker(lang.t("settings.appearance.liveActivity.title"), selection: binding(\.liveActivity)) {
                    ForEach(IslandLiveActivityMode.allCases) { mode in
                        Text(lang.t("settings.appearance.liveActivity.\(mode.rawValue)")).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            SettingsRowDivider()

            SettingsTileRow(
                title: lang.t("settings.appearance.rightSlot.title"),
                detail: lang.t("settings.appearance.rightSlot.note")
            ) {
                rightSlotTile(.count, title: lang.t("settings.appearance.rightSlot.count"))
                rightSlotTile(.agents, title: lang.t("settings.appearance.rightSlot.agents"))
                rightSlotTile(.none, title: lang.t("settings.appearance.rightSlot.none"))
            }

            SettingsRowDivider()

            SettingsTileRow(
                title: lang.t("settings.appearance.centerLabel.title"),
                detail: lang.t("settings.appearance.centerLabel.note")
            ) {
                centerLabelTile(.agentAction, sample: lang.t("settings.appearance.preview.agentEditing"))
                centerLabelTile(.sessionName, sample: "docs")
                centerLabelTile(.off, sample: "—")
            }

            if editingProfile == .topBar {
                SettingsRowDivider()

                SettingsToggleRow(
                    lang.t("settings.appearance.autoHide.title"),
                    subtitle: lang.t("settings.appearance.autoHide.note"),
                    isOn: binding(\.autoHideWhenInactive)
                )
            }
        }
    }

    /// A right-slot choice: a miniature pill carrying that slot.
    private func rightSlotTile(_ option: IslandRightSlot, title: String) -> some View {
        SettingsTile(
            title: title,
            isSelected: editingPreferences.rightSlot == option,
            background: .wallpaper
        ) {
            model.updateAppearancePreferences(for: editingProfile) { $0.rightSlot = option }
        } thumbnail: {
            RightSlotPillPreview(option: option, character: editingPreferences.character)
        }
    }

    private func centerLabelTile(_ option: IslandCenterLabel, sample: String) -> some View {
        let title: String = switch option {
        case .agentAction: lang.t("settings.appearance.centerLabel.agentAction")
        case .sessionName: lang.t("settings.appearance.centerLabel.sessionName")
        case .off:         lang.t("settings.appearance.centerLabel.off")
        }
        return SettingsTile(
            title: title,
            isSelected: editingPreferences.centerLabel == option
        ) {
            model.updateAppearancePreferences(for: editingProfile) { $0.centerLabel = option }
        } thumbnail: {
            Text(sample)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(V6Palette.paper.opacity(option == .off ? 0.4 : 0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
        }
    }

    // MARK: - Liquid Glass

    private var glassControlsDisabled: Bool {
        !model.glassSettings.isEnabled || !LiquidGlass.isSupported
    }

    private var liquidGlassCard: some View {
        SettingsCard(
            title: "Liquid Glass",
            footer: LiquidGlass.isSupported ? nil : lang.t("settings.appearance.glass.unsupported")
        ) {
            SettingsToggleRow(
                lang.t("settings.appearance.glass.enabled"),
                subtitle: lang.t("settings.appearance.glass.enabled.note"),
                isOn: Binding(
                    get: { model.glassSettings.isEnabled },
                    set: { model.glassSettings.isEnabled = $0 }
                )
            )
            .disabled(!LiquidGlass.isSupported)

            Group {
                SettingsRowDivider()

                SettingsPickerRow(
                    lang.t("settings.appearance.glass.material"),
                    subtitle: model.glassSettings.style == .clear
                        ? lang.t("settings.appearance.glass.material.clear.note")
                        : lang.t("settings.appearance.glass.material.regular.note"),
                    selection: Binding(
                        get: { model.glassSettings.style },
                        set: { model.glassSettings.style = $0 }
                    ),
                    style: .segmented
                ) {
                    ForEach(GlassStyle.allCases) { style in
                        Text(title(for: style)).tag(style)
                    }
                }

                SettingsRowDivider()

                SettingsRow(lang.t("settings.appearance.glass.tintColor")) {
                    ColorPicker(
                        lang.t("settings.appearance.glass.tintColor"),
                        selection: Binding(
                            get: { model.glassSettings.tintColor },
                            set: { newColor in
                                let rgb = newColor.islandResolvedRGB()
                                var s = model.glassSettings
                                s.tintRed = rgb.r
                                s.tintGreen = rgb.g
                                s.tintBlue = rgb.b
                                model.glassSettings = s
                            }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }

                SettingsRowDivider()

                SettingsRow(lang.t("settings.appearance.glass.tintStrength")) {
                    HStack(spacing: 12) {
                        Slider(value: Binding(
                            get: { model.glassSettings.tintStrength },
                            set: { model.glassSettings.tintStrength = $0 }
                        ), in: 0...1) {
                            Text(lang.t("settings.appearance.glass.tintStrength"))
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        Text("\(Int((model.glassSettings.tintStrength * 100).rounded()))%")
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                SettingsRowDivider()

                SettingsToggleRow(
                    lang.t("settings.appearance.glass.openView"),
                    isOn: Binding(
                        get: { model.glassSettings.openView },
                        set: { model.glassSettings.openView = $0 }
                    )
                )

                SettingsRowDivider()

                SettingsPickerRow(
                    lang.t("settings.appearance.glass.closedScope"),
                    subtitle: closedScopeNote,
                    selection: Binding(
                        get: { model.glassSettings.closedScope },
                        set: { model.glassSettings.closedScope = $0 }
                    )
                ) {
                    ForEach(GlassClosedScope.allCases) { scope in
                        Text(title(for: scope)).tag(scope)
                    }
                }
            }
            .disabled(glassControlsDisabled)
        }
    }

    private var closedScopeNote: String {
        switch model.glassSettings.closedScope {
        case .off:          lang.t("settings.appearance.glass.closedScope.off.note")
        case .externalOnly: lang.t("settings.appearance.glass.closedScope.externalOnly.note")
        case .always:       lang.t("settings.appearance.glass.closedScope.always.note")
        }
    }

    private func title(for scope: GlassClosedScope) -> String {
        switch scope {
        case .off:          lang.t("settings.appearance.glass.closedScope.off")
        case .externalOnly: lang.t("settings.appearance.glass.closedScope.externalOnly")
        case .always:       lang.t("settings.appearance.glass.closedScope.always")
        }
    }

    private func title(for style: GlassStyle) -> String {
        switch style {
        case .clear:   lang.t("settings.appearance.glass.material.clear")
        case .regular: lang.t("settings.appearance.glass.material.regular")
        }
    }

    // MARK: - Session list

    private var sessionListCard: some View {
        SettingsCard(title: lang.t("settings.appearance.sessionListPart.title")) {
            SettingsPreviewStage(contentTopPadding: 20, contentBottomPadding: 24) {
                SessionListPanelPreview(
                    sections: previewSessionSections,
                    showsSections: editingPreferences.sessionGroup != .none,
                    indicator: editingPreferences.sessionStateIndicator,
                    profile: editingProfile,
                    lang: lang
                )
                .padding(.horizontal, 4)
            }
            // Wider than the rows: bleeds into the card's side padding so
            // the panel mock gets its full width.
            .padding(.horizontal, -10)
            .padding(.top, 14)
            .padding(.bottom, 4)

            SettingsTileRow(
                title: lang.t("settings.appearance.stateIndicator.title"),
                detail: lang.t("settings.appearance.stateIndicator.note")
            ) {
                ForEach([IslandSessionStateIndicator.animatedDot, .bar, .glyph, .tint], id: \.self) { option in
                    SettingsTile(
                        title: title(for: option),
                        isSelected: editingPreferences.sessionStateIndicator == option
                    ) {
                        model.updateAppearancePreferences(for: editingProfile) { $0.sessionStateIndicator = option }
                    } thumbnail: {
                        StateIndicatorPreview(option: option)
                    }
                }
            }

            SettingsRowDivider()

            SettingsPickerRow(
                lang.t("settings.appearance.usageDisplay.title"),
                subtitle: lang.t("settings.appearance.usageDisplay.note"),
                selection: binding(\.usageDisplay),
                style: .segmented
            ) {
                ForEach(IslandUsageDisplay.allCases) { option in
                    Text(title(for: option)).tag(option)
                }
            }

            SettingsRowDivider()

            SettingsPickerRow(
                lang.t("settings.appearance.sessionGroup.title"),
                subtitle: lang.t("settings.appearance.sessionGroup.note"),
                selection: binding(\.sessionGroup),
                style: .segmented
            ) {
                ForEach(IslandSessionGroup.allCases) { option in
                    Text(title(for: option)).tag(option)
                }
            }

            SettingsRowDivider()

            SettingsPickerRow(
                lang.t("settings.appearance.sessionSort.title"),
                subtitle: lang.t("settings.appearance.sessionSort.note"),
                selection: binding(\.sessionSort),
                style: .segmented
            ) {
                ForEach(IslandSessionSort.allCases) { option in
                    Text(title(for: option)).tag(option)
                }
            }

            SettingsRowDivider()

            SettingsPickerRow(
                lang.t("settings.appearance.staleThreshold.title"),
                subtitle: lang.t("settings.appearance.staleThreshold.note"),
                selection: binding(\.completedStaleThreshold)
            ) {
                ForEach(IslandCompletedStaleThreshold.allCases) { option in
                    Text(title(for: option)).tag(option)
                }
            }
        }
    }

    // MARK: - Titles

    private func title(for character: IslandCharacter) -> String {
        switch character {
        case .dino: return "Dino"
        case .ghost: return "Ghost"
        case .crab: return "Crab"
        case .duck: return "Duck"
        case .claude: return "Claude"
        }
    }

    private func title(for option: IslandSessionStateIndicator) -> String {
        switch option {
        case .animatedDot: lang.t("settings.appearance.stateIndicator.animatedDot")
        case .bar:         lang.t("settings.appearance.stateIndicator.bar")
        case .glyph:       lang.t("settings.appearance.stateIndicator.glyph")
        case .tint:        lang.t("settings.appearance.stateIndicator.tint")
        }
    }

    private func title(for option: IslandDensity) -> String {
        switch option {
        case .regular: lang.t("settings.appearance.density.regular")
        case .compact: lang.t("settings.appearance.density.compact")
        }
    }

    private func title(for option: IslandUsageDisplay) -> String {
        switch option {
        case .hidden:  lang.t("settings.appearance.usageDisplay.hidden")
        case .compact: lang.t("settings.appearance.usageDisplay.compact")
        }
    }

    private func title(for option: IslandSessionGroup) -> String {
        switch option {
        case .none:    lang.t("settings.appearance.sessionGroup.none")
        case .state:   lang.t("settings.appearance.sessionGroup.state")
        case .agent:   lang.t("settings.appearance.sessionGroup.agent")
        case .project: lang.t("settings.appearance.sessionGroup.project")
        }
    }

    private func title(for option: IslandSessionSort) -> String {
        switch option {
        case .attention:  lang.t("settings.appearance.sessionSort.attention")
        case .lastUpdate: lang.t("settings.appearance.sessionSort.lastUpdate")
        }
    }

    private func title(for option: IslandCompletedStaleThreshold) -> String {
        switch option {
        case .twoMinutes:    lang.t("settings.appearance.staleThreshold.twoMinutes")
        case .fiveMinutes:   lang.t("settings.appearance.staleThreshold.fiveMinutes")
        case .tenMinutes:    lang.t("settings.appearance.staleThreshold.tenMinutes")
        case .twentyMinutes: lang.t("settings.appearance.staleThreshold.twentyMinutes")
        case .never:         lang.t("settings.appearance.staleThreshold.never")
        }
    }

    // MARK: - Session list sample data

    private var previewSessionSections: [AppearanceSessionPreviewSection] {
        let items = sortedPreviewSessionItems

        switch editingPreferences.sessionGroup {
        case .none:
            return [
                AppearanceSessionPreviewSection(
                    id: "all",
                    title: lang.t("settings.appearance.sessionGroup.none"),
                    items: items
                )
            ]
        case .state:
            let groups: [(String, String, (AppearanceSessionPreviewItem) -> Bool)] = [
                ("approval", lang.t("island.section.needsApproval"), { $0.phase == .approval }),
                ("answer", lang.t("island.section.needsAnswer"), { $0.phase == .answer }),
                ("running", lang.t("island.section.inProgress"), { $0.phase == .running }),
                ("done", lang.t("island.section.justDone"), { $0.phase == .done }),
                ("idle", lang.t("island.section.idle"), { $0.phase == .idle }),
            ]
            return groups.compactMap { id, title, include in
                let groupItems = items.filter(include)
                guard !groupItems.isEmpty else { return nil }
                return AppearanceSessionPreviewSection(id: id, title: title, items: groupItems)
            }
        case .agent:
            let groups = ["Codex", "Claude", "Cursor", "Gemini"]
            return groups.compactMap { agent in
                let groupItems = items.filter { $0.agent == agent }
                guard !groupItems.isEmpty else { return nil }
                return AppearanceSessionPreviewSection(id: agent, title: agent, items: groupItems)
            }
        case .project:
            let groups = ["open-island", "website", "docs"]
            return groups.compactMap { project in
                let groupItems = items.filter { $0.project == project }
                guard !groupItems.isEmpty else { return nil }
                return AppearanceSessionPreviewSection(id: project, title: project, items: groupItems)
            }
        }
    }

    private var sortedPreviewSessionItems: [AppearanceSessionPreviewItem] {
        switch editingPreferences.sessionSort {
        case .attention:
            return previewSessionItems.sorted { lhs, rhs in
                if lhs.attentionRank == rhs.attentionRank {
                    return lhs.updatedRank < rhs.updatedRank
                }
                return lhs.attentionRank < rhs.attentionRank
            }
        case .lastUpdate:
            return previewSessionItems.sorted { $0.updatedRank < $1.updatedRank }
        }
    }

    private var previewSessionItems: [AppearanceSessionPreviewItem] {
        [
            .init(
                id: "approval",
                title: "Codex · open-island",
                detail: lang.t("settings.appearance.preview.approveShellCommand"),
                agent: "Codex",
                agentShort: "codex",
                agentColor: Color(hex: AgentTool.codex.brandColorHex) ?? Color(red: 0.55, green: 0.72, blue: 1.0),
                project: "open-island",
                branch: "v8-design",
                prompt: lang.t("settings.appearance.preview.promptImplementPlan"),
                terminal: "Ghostty",
                age: "now",
                phase: .approval,
                attentionRank: 0,
                updatedRank: 2
            ),
            .init(
                id: "answer",
                title: "Claude · open-island",
                detail: lang.t("settings.appearance.preview.waitingForAnswer"),
                agent: "Claude",
                agentShort: "claude",
                agentColor: Color(hex: AgentTool.claudeCode.brandColorHex) ?? Color(red: 0.9, green: 0.55, blue: 0.34),
                project: "open-island",
                branch: "main",
                prompt: lang.t("settings.appearance.preview.promptChooseNotificationCopy"),
                terminal: "Ghostty",
                age: "1m",
                phase: .answer,
                attentionRank: 1,
                updatedRank: 3
            ),
            .init(
                id: "running",
                title: "Cursor · website",
                detail: lang.t("settings.appearance.preview.editingSessionListPreview"),
                agent: "Cursor",
                agentShort: "cursor",
                agentColor: Color(hex: AgentTool.cursor.brandColorHex) ?? Color(red: 0.62, green: 0.66, blue: 1.0),
                project: "website",
                branch: "main",
                prompt: lang.t("settings.appearance.preview.promptTightenSettingsUI"),
                terminal: "Cursor",
                age: "2m",
                phase: .running,
                attentionRank: 2,
                updatedRank: 0
            ),
            .init(
                id: "done",
                title: "Gemini · docs",
                detail: lang.t("settings.appearance.preview.replyAvailable"),
                agent: "Gemini",
                agentShort: "gemini",
                agentColor: Color(hex: AgentTool.geminiCLI.brandColorHex) ?? Color(red: 0.45, green: 0.78, blue: 1.0),
                project: "docs",
                branch: "main",
                prompt: lang.t("settings.appearance.preview.promptSummarizeDesignBundle"),
                terminal: "WezTerm",
                age: title(for: editingPreferences.completedStaleThreshold),
                phase: .done,
                attentionRank: 3,
                updatedRank: 1
            ),
            .init(
                id: "idle",
                title: "Codex · open-island",
                detail: lang.t("settings.appearance.preview.completedEarlier"),
                agent: "Codex",
                agentShort: "codex",
                agentColor: Color(hex: AgentTool.codex.brandColorHex) ?? Color(red: 0.55, green: 0.72, blue: 1.0),
                project: "open-island",
                branch: nil,
                prompt: nil,
                terminal: "Ghostty",
                age: lang.t("island.sessionOverview.idle"),
                phase: .idle,
                attentionRank: 4,
                updatedRank: 4
            ),
        ]
    }
}

// MARK: - Character tiles

/// A character tile's sprite: the selected (or hovered) character runs, the
/// others rest and blink.
private struct CharacterTileSprite: View {
    let character: IslandCharacter
    let isSelected: Bool

    @Environment(\.settingsTileIsHovered) private var isHovered
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        UnifiedBars(
            mode: (isSelected || isHovered) && !reduceMotion ? .running : .idle,
            size: 42,
            character: character
        )
        .frame(width: 46, height: 46)
    }
}

/// "Color by agent" legend entry: the chosen character in an agent's color.
private struct AgentColorChip: View {
    let tool: AgentTool
    let character: IslandCharacter

    private var color: Color {
        Color(hex: tool.brandColorHex) ?? UnifiedBars.paperInk
    }

    var body: some View {
        HStack(spacing: 8) {
            UnifiedBars(mode: .idle, size: 20, character: character, tint: color)
                .frame(width: 22, height: 22)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(SettingsTileBackground.islandInk)
                )
            Text(tool.displayName)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Small preview ornaments

private struct AppearanceSessionPreviewSection: Identifiable {
    let id: String
    let title: String
    let items: [AppearanceSessionPreviewItem]
}

private struct AppearanceSessionPreviewItem: Identifiable {
    enum Phase {
        case approval
        case answer
        case running
        case done
        case idle
    }

    let id: String
    let title: String
    let detail: String
    let agent: String
    let agentShort: String
    let agentColor: Color
    let project: String
    let branch: String?
    let prompt: String?
    let terminal: String
    let age: String
    let phase: Phase
    let attentionRank: Int
    let updatedRank: Int
}

private struct SettingsPreviewStage<Content: View>: View {
    var contentTopPadding: CGFloat = 20
    var contentBottomPadding: CGFloat = 24
    let content: Content

    init(
        contentTopPadding: CGFloat = 20,
        contentBottomPadding: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.contentTopPadding = contentTopPadding
        self.contentBottomPadding = contentBottomPadding
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.top, contentTopPadding)
                .padding(.bottom, contentBottomPadding)
        }
        .frame(maxWidth: .infinity)
        .background(PersonalizationWallpaper())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }
}

private struct SessionListPanelPreview: View {
    let sections: [AppearanceSessionPreviewSection]
    let showsSections: Bool
    let indicator: IslandSessionStateIndicator
    let profile: IslandAppearanceDisplayProfile
    let lang: LanguageManager

    private var items: [AppearanceSessionPreviewItem] {
        sections.flatMap(\.items)
    }

    private var waitingCount: Int {
        items.filter { $0.phase == .approval || $0.phase == .answer }.count
    }

    private var runningCount: Int {
        items.filter { $0.phase == .running }.count
    }

    private var doneCount: Int {
        items.filter { $0.phase == .done }.count
    }

    private var idleCount: Int {
        items.filter { $0.phase == .idle }.count
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            panel(width: preferredPanelWidth)
            panel(width: 500)
            panel(width: 460)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var preferredPanelWidth: CGFloat {
        profile == .notch ? 540 : 520
    }

    private func panel(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            surfaceShape
                .fill(V6Palette.ink)
                .shadow(color: .black.opacity(0.36), radius: 22, y: 12)

            VStack(spacing: 0) {
                panelHead
                listBody
                panelFoot
            }
            .clipShape(surfaceShape)
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var surfaceShape: OpenedIslandSurfaceShape {
        OpenedIslandSurfaceShape(topProfile: profile == .notch ? .notch : .topBar)
    }

    private var sideInset: CGFloat {
        profile == .notch ? 46 : 16
    }

    private var panelHead: some View {
        HStack(spacing: 8) {
            UnifiedBars(mode: .waiting, size: 22)
                .frame(width: 24, height: 24)

            Text(lang.t("island.sessionList.title").uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(V6Palette.paper.opacity(0.55))

            ViewThatFits(in: .horizontal) {
                previewSessionOverview(compact: false)
                previewSessionOverview(compact: true)
            }

            Spacer(minLength: 0)

            previewHeaderButton(systemName: "gearshape.fill")
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .frame(height: 42)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.05))
                .frame(height: 1)
        }
    }

    private func previewHeaderButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .frame(width: 22, height: 22)
            .background(.white.opacity(0.08), in: Circle())
    }

    private func previewSessionOverview(compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 9) {
            previewSessionOverviewMetric(
                count: items.count,
                title: lang.t("island.sessionOverview.total"),
                compactTitle: "",
                tint: nil,
                compact: compact
            )
            if waitingCount > 0 {
                previewSessionOverviewMetric(
                    count: waitingCount,
                    title: lang.t("island.sessionOverview.waiting"),
                    compactTitle: lang.t("island.sessionOverview.waitingCompact"),
                    tint: IslandDesignPalette.Status.waitingAggregate,
                    compact: compact
                )
            }
            if runningCount > 0 {
                previewSessionOverviewMetric(
                    count: runningCount,
                    title: lang.t("island.sessionOverview.running"),
                    compactTitle: lang.t("island.sessionOverview.runningCompact"),
                    tint: IslandDesignPalette.Status.running,
                    compact: compact
                )
            }
            if doneCount > 0 {
                previewSessionOverviewMetric(
                    count: doneCount,
                    title: lang.t("island.sessionOverview.done"),
                    compactTitle: lang.t("island.sessionOverview.done"),
                    tint: IslandDesignPalette.Status.completed,
                    compact: compact
                )
            }
            if idleCount > 0 {
                previewSessionOverviewMetric(
                    count: idleCount,
                    title: lang.t("island.sessionOverview.idle"),
                    compactTitle: lang.t("island.sessionOverview.idle"),
                    tint: IslandDesignPalette.Status.idle,
                    compact: compact
                )
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func previewSessionOverviewMetric(
        count: Int,
        title: String,
        compactTitle: String,
        tint: Color?,
        compact: Bool
    ) -> some View {
        HStack(spacing: 4) {
            if let tint {
                Circle()
                    .fill(tint)
                    .frame(width: 5.5, height: 5.5)
            }

            let label = title == "total"
                ? (compact ? "\(count)" : "\(count) \(title)")
                : "\(count) \(compact ? compactTitle : title)"

            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint == nil ? V6Palette.paper.opacity(0.34) : V6Palette.paper.opacity(0.48))
        }
    }

    private var listBody: some View {
        VStack(spacing: 0) {
            ForEach(sections) { section in
                if showsSections {
                    sectionHeader(section)
                }

                ForEach(section.items) { item in
                    SessionListLivePreviewRow(
                        item: item,
                        indicator: indicator,
                        sideInset: sideInset,
                        lang: lang
                    )
                }
            }
        }
    }

    private func sectionHeader(_ section: AppearanceSessionPreviewSection) -> some View {
        HStack(spacing: 8) {
            sectionDot(for: section)
            Text(section.title.uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(V6Palette.paper.opacity(0.7))
            Text("\(section.items.count)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(V6Palette.paper.opacity(0.4))
            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.top, 9)
        .padding(.bottom, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.05))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func sectionDot(for section: AppearanceSessionPreviewSection) -> some View {
        Circle()
            .fill(section.items.first?.phase.tint ?? V6Palette.paper.opacity(0.35))
            .frame(width: 7, height: 7)
    }

    private var panelFoot: some View {
        Color.clear
            .frame(height: 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.05))
                .frame(height: 1)
        }
    }
}

private struct SessionListLivePreviewRow: View {
    let item: AppearanceSessionPreviewItem
    let indicator: IslandSessionStateIndicator
    let sideInset: CGFloat
    let lang: LanguageManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                if indicator != .tint {
                    indicatorView
                }

                VStack(alignment: .leading, spacing: 3) {
                    titleLine

                    if let prompt = item.prompt {
                        Text(prompt)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(V6Palette.paper.opacity(item.phase == .idle ? 0.34 : 0.52))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 10)

                HStack(spacing: 6) {
                    agentChip
                    sideBadge(item.terminal)
                    Text(item.age)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(item.phase == .idle ? 0.32 : 0.45))
                        .frame(minWidth: 30, alignment: .trailing)

                    Image(systemName: item.phase == .idle ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(V6Palette.paper.opacity(item.phase == .idle ? 0.42 : 0.68))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(.white.opacity(item.phase == .idle ? 0.02 : 0.045))
                        )
                }
            }
            .padding(.horizontal, rowLeadingPadding)
            .padding(.vertical, 11)
            .background(rowFill)

            if item.phase != .idle {
                detailPreview
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.04))
                .frame(height: 1)
        }
        .overlay(alignment: .leading) {
            if indicator == .bar {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(tint)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 14)
            }
        }
        .opacity(item.phase == .idle ? 0.74 : 1)
    }

    private var titleLine: some View {
        HStack(spacing: 0) {
            Text(item.project)
                .fontWeight(.semibold)
                .foregroundStyle(projectColor)
            if let branch = item.branch {
                Text(" (\(branch))")
                    .foregroundStyle(V6Palette.paper.opacity(0.55))
            }
            Text(" · ")
                .foregroundStyle(V6Palette.paper.opacity(0.22))
            Text(item.detail)
                .foregroundStyle(V6Palette.paper.opacity(0.7))
        }
        .font(.system(size: 13, weight: .medium))
        .lineLimit(1)
    }

    private var agentChip: some View {
        Text(item.agentShort)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(item.agentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(item.agentColor.opacity(0.13), in: Capsule())
            .overlay(Capsule().stroke(item.agentColor.opacity(0.35), lineWidth: 1))
    }

    private func sideBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(V6Palette.paper.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(0.06), in: Capsule())
    }

    private var detailPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            switch item.phase {
            case .approval:
                Text(lang.t("approval.toolPermissionRequested"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.86))
                Text(lang.t("settings.appearance.preview.permissionBody"))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(V6Palette.paper.opacity(0.78))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            case .answer:
                Text(lang.t("settings.appearance.preview.pickOrTypeAnswer"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.82))
            case .running:
                Text(item.detail)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(V6Palette.paper.opacity(0.78))
            case .done:
                Text(lang.t("settings.appearance.preview.replyAvailable"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.82))
            case .idle:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, detailLeadingPadding)
        .padding(.trailing, sideInset)
        .padding(.bottom, 12)
        .background(.white.opacity(0.015))
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch indicator {
        case .animatedDot:
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
                .shadow(color: tint.opacity(item.phase == .idle ? 0 : 0.44), radius: 5)
                .frame(width: 20, height: 20)
        case .bar:
            EmptyView()
        case .glyph:
            glyphView
                .frame(width: 20, height: 20)
        case .tint:
            EmptyView()
        }
    }

    private var rowFill: Color {
        guard indicator == .tint else { return Color.clear }
        return tint.opacity(item.phase == .idle ? 0.015 : 0.045)
    }

    @ViewBuilder
    private var glyphView: some View {
        switch item.phase {
        case .idle:
            UnifiedBars(mode: .idle, size: 16, tint: tint)
        case .running:
            UnifiedBars(mode: .running, size: 16, tint: tint)
        case .approval, .answer:
            UnifiedBars(mode: .waiting, size: 16, tint: tint)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var projectColor: Color {
        indicator == .tint && item.phase != .idle ? tint : V6Palette.paper.opacity(item.phase == .idle ? 0.72 : 0.92)
    }

    private var tint: Color {
        item.phase.tint
    }

    private var rowLeadingPadding: CGFloat {
        switch indicator {
        case .bar: max(28, sideInset)
        case .tint: sideInset
        case .animatedDot, .glyph: sideInset
        }
    }

    private var detailLeadingPadding: CGFloat {
        switch indicator {
        case .bar: max(28, sideInset)
        case .tint: sideInset
        case .animatedDot, .glyph: sideInset + 30
        }
    }
}

private extension AppearanceSessionPreviewItem.Phase {
    var tint: Color {
        switch self {
        case .approval:
            IslandDesignPalette.Status.waitingForApproval
        case .answer:
            IslandDesignPalette.Status.waitingForAnswer
        case .running:
            IslandDesignPalette.Status.running
        case .done:
            IslandDesignPalette.Status.completed
        case .idle:
            IslandDesignPalette.Status.idle
        }
    }
}

/// Option-card thumbnail for the right slot: a miniature closed pill with
/// that slot filled in (three sample sessions).
private struct RightSlotPillPreview: View {
    let option: IslandRightSlot
    let character: IslandCharacter

    private var content: IslandRightSlotContent? {
        switch option {
        case .none:
            return nil
        case .count:
            return .count(3)
        case .agents:
            return .agents([AgentTool.claudeCode, .codex, .geminiCLI].map { tool in
                .session(color: Color(hex: tool.brandColorHex) ?? .white, state: .running)
            })
        }
    }

    var body: some View {
        V6ClosedPill(
            mode: .idle,
            character: character,
            label: nil,
            rightSlot: content,
            layout: .external,
            height: 30,
            minWidth: 60,
            glyphPaused: true
        )
        .environment(\.islandChromeMetrics, .regular)
        .frame(height: 30)
    }
}

private struct StateIndicatorPreview: View {
    let option: IslandSessionStateIndicator

    var body: some View {
        HStack(spacing: 8) {
            indicator
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(V6Palette.paper.opacity(option == .tint ? 0.55 : 0.22))
                .frame(width: 58, height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(option == .tint ? Color(hex: AgentTool.codex.brandColorHex)?.opacity(0.22) ?? Color.white.opacity(0.08) : Color.clear)
        )
    }

    @ViewBuilder
    private var indicator: some View {
        let color = Color(hex: AgentTool.codex.brandColorHex) ?? V6Palette.paper
        switch option {
        case .animatedDot:
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.55), radius: 5)
        case .bar:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 4, height: 28)
        case .glyph:
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        case .tint:
            Circle()
                .fill(V6Palette.paper.opacity(0.72))
                .frame(width: 10, height: 10)
        }
    }
}

/// Option-card icon for the density picker: a miniature closed pill drawn
/// with the real metrics for that density, so the card previews the actual
/// glyph / padding trim rather than a label.
private struct DensityPreview: View {
    let option: IslandDensity
    var character: IslandCharacter = .dino

    var body: some View {
        let metrics = IslandChromeMetrics.metrics(for: option)
        let height: CGFloat = option == .compact ? 24 : 32
        V6ClosedPill(
            mode: .idle,
            character: character,
            label: nil,
            rightSlot: .count(3),
            layout: .external,
            height: height,
            minWidth: 70,
            glyphPaused: true
        )
        .environment(\.islandChromeMetrics, metrics)
        .frame(height: height)
    }
}
