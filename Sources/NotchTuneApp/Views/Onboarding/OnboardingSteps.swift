import AppKit
import ApplicationServices
import SwiftUI
import UserNotifications

// MARK: - Welcome

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
                .shadow(color: OnboardingTheme.accent.opacity(0.2), radius: 22, y: 10)

            Text("Meet NotchTune")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(OnboardingTheme.primaryText)

            Text("Your notch becomes a calm home for AI coding sessions, music, quick thoughts, files, and reminders.")
                .font(.system(size: 14))
                .foregroundStyle(OnboardingTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            HStack(spacing: 10) {
                featureCard("Live agents", icon: "terminal")
                featureCard("Music", icon: "music.note")
                featureCard("Myspace", icon: "square.grid.2x2")
                featureCard("Reminders", icon: "bell")
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func featureCard(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(OnboardingTheme.primaryText.opacity(0.75))
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(.white.opacity(0.055), in: Capsule())
    }
}

// MARK: - Agents

struct OnboardingAgentsStep: View {
    var model: AppModel
    @State private var showsMoreAgents = false

    private var allReady: Bool {
        model.claudeHooksInstalled && model.codexHooksInstalled
            && model.cursorHooksInstalled && model.openCodePluginInstalled
            && model.geminiHooksInstalled && model.kimiHooksInstalled
            && model.antigravityHooksInstalled && model.qoderHooksInstalled
            && model.qwenCodeHooksInstalled && model.factoryHooksInstalled
            && model.codebuddyHooksInstalled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingStepHeading(
                title: "Connect your AI tools",
                detail: "Install only the local integrations you use — everything stays editable in Settings → Setup."
            )

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                agentCard("Claude Code", installed: model.claudeHooksInstalled, busy: model.isClaudeHookSetupBusy, action: model.installClaudeHooks)
                agentCard("Codex", installed: model.codexHooksInstalled, busy: model.isCodexSetupBusy, action: model.installCodexHooks)
                agentCard("Cursor", installed: model.cursorHooksInstalled, busy: model.isCursorHookSetupBusy, action: model.installCursorHooks)
                agentCard("OpenCode", installed: model.openCodePluginInstalled, busy: model.isOpenCodeSetupBusy, action: model.installOpenCodePlugin)
                agentCard("Gemini CLI", installed: model.geminiHooksInstalled, busy: model.isGeminiHookSetupBusy, action: model.installGeminiHooks)
                agentCard("Kimi CLI", installed: model.kimiHooksInstalled, busy: model.isKimiHookSetupBusy, action: model.installKimiHooks)
                agentCard("Antigravity", installed: model.antigravityHooksInstalled, busy: model.isAntigravityHookSetupBusy, action: model.installAntigravityHooks)
            }

            DisclosureGroup(isExpanded: $showsMoreAgents) {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ], spacing: 10) {
                    agentCard("Qoder", installed: model.qoderHooksInstalled, busy: model.isQoderHookSetupBusy, action: model.installQoderHooks)
                    agentCard("Qwen Code", installed: model.qwenCodeHooksInstalled, busy: model.isQwenCodeHookSetupBusy, action: model.installQwenCodeHooks)
                    agentCard("Factory", installed: model.factoryHooksInstalled, busy: model.isFactoryHookSetupBusy, action: model.installFactoryHooks)
                    agentCard("CodeBuddy", installed: model.codebuddyHooksInstalled, busy: model.isCodebuddyHookSetupBusy, action: model.installCodebuddyHooks)
                }
                .padding(.top, 8)
            } label: {
                Text("More Claude-compatible agents")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }
            .tint(OnboardingTheme.secondaryText)

            HStack {
                if model.hooksBinaryURL == nil {
                    Label("Hooks binary missing — build the package first.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10.5))
                        .foregroundStyle(OnboardingTheme.attention)
                }
                Spacer()
                Button("Install all") {
                    installAll()
                }
                .controlSize(.small)
                .disabled(model.hooksBinaryURL == nil || allReady)
            }
        }
    }

    private func installAll() {
        if !model.claudeHooksInstalled { model.installClaudeHooks() }
        if !model.codexHooksInstalled { model.installCodexHooks() }
        if !model.cursorHooksInstalled { model.installCursorHooks() }
        if !model.openCodePluginInstalled { model.installOpenCodePlugin() }
        if !model.geminiHooksInstalled { model.installGeminiHooks() }
        if !model.kimiHooksInstalled { model.installKimiHooks() }
        if !model.antigravityHooksInstalled { model.installAntigravityHooks() }
        if !model.qoderHooksInstalled { model.installQoderHooks() }
        if !model.qwenCodeHooksInstalled { model.installQwenCodeHooks() }
        if !model.factoryHooksInstalled { model.installFactoryHooks() }
        if !model.codebuddyHooksInstalled { model.installCodebuddyHooks() }
    }

    private func agentCard(
        _ name: String,
        installed: Bool,
        busy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(installed ? OnboardingTheme.ready : OnboardingTheme.tertiaryText)
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))

            Text(name)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(OnboardingTheme.primaryText)

            Spacer()

            if installed {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(OnboardingTheme.ready)
            } else if busy {
                ProgressView().controlSize(.small)
            } else {
                Button("Connect", action: action)
                    .controlSize(.small)
                    .disabled(model.hooksBinaryURL == nil)
            }
        }
        .padding(10)
        .onboardingCard()
    }
}

// MARK: - Permissions

struct OnboardingPermissionsStep: View {
    @Binding var axTrusted: Bool
    @Binding var notificationAuthorization: String
    var requestNotifications: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingStepHeading(
                title: "Let NotchTune help",
                detail: "Permissions stay under your control and can be changed any time in System Settings."
            )

            permissionRow(
                title: "Accessibility",
                detail: "Focus the correct terminal window and pane on jump-back.",
                systemImage: "accessibility",
                status: axTrusted ? "Allowed" : "Not allowed",
                isReady: axTrusted
            ) {
                openPrivacyPane("Privacy_Accessibility")
            }

            permissionRow(
                title: "Notifications",
                detail: "Show completed agents and timed reminders.",
                systemImage: "bell.badge",
                status: notificationAuthorization,
                isReady: notificationAuthorization == "Allowed",
                action: requestNotifications
            )

            permissionRow(
                title: "Automation",
                detail: "Jump back to supported terminal apps and control your music player. macOS asks on first use.",
                systemImage: "gearshape.2",
                status: "Optional",
                isReady: false
            ) {
                openPrivacyPane("Privacy_Automation")
            }
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func permissionRow(
        title: String,
        detail: String,
        systemImage: String,
        status: String,
        isReady: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isReady ? OnboardingTheme.ready : OnboardingTheme.tertiaryText)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(OnboardingTheme.tertiaryText)
            }

            Spacer()

            Button(status, action: action)
                .controlSize(.small)
        }
        .padding(12)
        .onboardingCard()
    }
}

// MARK: - Music

struct OnboardingMusicStep: View {
    var model: AppModel
    @State private var selection: String = UserDefaults.standard.string(forKey: musicConnectedAppDefaultsKey) ?? "none"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingStepHeading(
                title: "Pick your music player",
                detail: "The Music tab controls playback, artwork, and progress right from the notch."
            )

            HStack(spacing: 12) {
                musicCard(
                    title: "Apple Music",
                    detail: "Built into macOS",
                    icon: "music.note",
                    tag: "appleMusic"
                ) {
                    model.playerManager.switchToAppleMusic()
                }

                if model.playerManager.isSpotifyAvailable {
                    musicCard(
                        title: "Spotify",
                        detail: "Uses the installed app",
                        icon: "waveform",
                        tag: "spotify"
                    ) {
                        model.playerManager.switchToSpotify()
                    }
                }

                musicCard(
                    title: "No music",
                    detail: "Agents only — enable later in Settings",
                    icon: "speaker.slash",
                    tag: "none"
                ) {
                    model.playerManager.switchToNone()
                }
            }

            Text("macOS will ask once for Automation permission the first time NotchTune talks to your player.")
                .font(.system(size: 10.5))
                .foregroundStyle(OnboardingTheme.tertiaryText)
        }
    }

    private func musicCard(
        title: String,
        detail: String,
        icon: String,
        tag: String,
        action: @escaping () -> Void
    ) -> some View {
        let selected = selection == tag
        return Button {
            selection = tag
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(selected ? OnboardingTheme.accent : OnboardingTheme.secondaryText)
                    .frame(height: 22)

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(OnboardingTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .onboardingCard(selected: selected, cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Personalize

struct OnboardingPersonalizeStep: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingStepHeading(
                title: "Make it yours",
                detail: "Your real island is open right now — every change below applies to it instantly."
            )

            livePreviewHint
            characterRow
            glassRow
            tintRow
        }
    }

    /// The preview IS the real notch: the island is pinned open while this
    /// step is visible (`beginAppearanceLivePreview`).
    private var livePreviewHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(OnboardingTheme.accent)
            Text("Look up — the open island at the top of your screen is the live preview.")
                .font(.system(size: 11))
                .foregroundStyle(OnboardingTheme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(OnboardingTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(OnboardingTheme.accent.opacity(0.25), lineWidth: 0.5)
        }
    }

    private var characterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Character")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.secondaryText)
                Text("· lives on the closed pill")
                    .font(.system(size: 10))
                    .foregroundStyle(OnboardingTheme.tertiaryText)
            }

            HStack(spacing: 10) {
                ForEach(IslandCharacter.allCases) { option in
                    let selected = model.islandCharacter == option
                    Button {
                        model.islandCharacter = option
                    } label: {
                        VStack(spacing: 6) {
                            UnifiedBars(mode: .idle, size: 24, character: option)
                                .frame(width: 30, height: 30)
                            Text(String(describing: option).capitalized)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(
                                    selected
                                        ? OnboardingTheme.primaryText
                                        : OnboardingTheme.tertiaryText
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .onboardingCard(selected: selected)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var glassRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Finish")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(OnboardingTheme.secondaryText)

            HStack(spacing: 12) {
                glassCard(
                    title: "Clear glass",
                    detail: "Bright and light-bending",
                    selected: model.glassSettings.isEnabled && model.glassSettings.style == .clear
                ) {
                    model.glassSettings.isEnabled = true
                    model.glassSettings.style = .clear
                }

                glassCard(
                    title: "Frosted glass",
                    detail: "Softer with more contrast",
                    selected: model.glassSettings.isEnabled && model.glassSettings.style == .regular
                ) {
                    model.glassSettings.isEnabled = true
                    model.glassSettings.style = .regular
                }

                glassCard(
                    title: "Solid",
                    detail: "Classic black notch",
                    selected: !model.glassSettings.isEnabled
                ) {
                    model.glassSettings.isEnabled = false
                }
            }
        }
    }

    private func glassCard(
        title: String,
        detail: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        title == "Solid"
                            ? Color.black.opacity(0.9)
                            : Color.white.opacity(title == "Clear glass" ? 0.075 : 0.15)
                    )
                    .frame(height: 54)
                    .overlay {
                        Image(systemName: selected ? "checkmark.circle.fill" : "sparkles")
                            .foregroundStyle(
                                selected ? OnboardingTheme.accent : OnboardingTheme.tertiaryText
                            )
                    }

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(OnboardingTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .onboardingCard(selected: selected, cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    private var tintRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Tint strength")
                    .foregroundStyle(OnboardingTheme.primaryText)
                Spacer()
                Text("\(Int((model.glassSettings.tintStrength * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(OnboardingTheme.tertiaryText)
            }
            .font(.system(size: 11.5, weight: .medium))

            Slider(
                value: Binding(
                    get: { model.glassSettings.tintStrength },
                    set: { model.glassSettings.tintStrength = $0 }
                ),
                in: 0...0.65
            )
            .disabled(!model.glassSettings.isEnabled)
            .tint(OnboardingTheme.accent)
        }
        .padding(12)
        .onboardingCard()
    }

}

// MARK: - Keep running

struct OnboardingKeepRunningStep: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingStepHeading(
                title: "Keep it running",
                detail: "NotchTune is most useful when it's always there."
            )

            HStack(spacing: 12) {
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        model.launchAtLoginEnabled
                            ? OnboardingTheme.ready
                            : OnboardingTheme.tertiaryText
                    )
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                    Text("Start NotchTune automatically when you sign in.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(OnboardingTheme.tertiaryText)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.launchAtLoginEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .padding(12)
            .onboardingCard()

            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(OnboardingTheme.ready)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic updates")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                    Text("Signed releases install in place — nothing to do.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(OnboardingTheme.tertiaryText)
                }

                Spacer()
            }
            .padding(12)
            .onboardingCard()
        }
    }
}

// MARK: - Try it live

struct OnboardingTryLiveStep: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.03))
                    .frame(height: 120)
                V6ClosedPillShape()
                    .fill(Color.black)
                    .frame(width: 190, height: 34)
                    .overlay {
                        Image(systemName: "hand.point.up.left")
                            .font(.system(size: 13))
                            .foregroundStyle(OnboardingTheme.accent)
                            .offset(y: 44)
                    }
            }

            Text("Try it live")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(OnboardingTheme.primaryText)

            Text("A 60-second hands-on tour in your real notch: open the island, resolve a demo approval, peek the music controls, and drop a file into Myspace. Nothing fake sticks around afterwards.")
                .font(.system(size: 12.5))
                .foregroundStyle(OnboardingTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared heading

struct OnboardingStepHeading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(OnboardingTheme.primaryText)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(OnboardingTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
