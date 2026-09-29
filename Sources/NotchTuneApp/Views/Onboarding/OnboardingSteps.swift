import AppKit
import ApplicationServices
import SwiftUI
import UserNotifications

// MARK: - Welcome

/// "Welcome to …" feature sheet: big app icon, title, one-line subtitle, and a
/// short list of what the app does.
struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 104, height: 104)
                .accessibilityHidden(true)

            Text("Welcome to NotchTune")
                .font(.largeTitle.weight(.bold))
                .padding(.top, 12)

            Text("A calm home for your work, right in the notch.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 20) {
                OnboardingFeatureRow(
                    symbol: "terminal.fill",
                    color: .blue,
                    title: "Live AI Agents",
                    detail: "Follow Claude Code, Codex, and more. Approve requests and jump back to the right terminal."
                )
                OnboardingFeatureRow(
                    symbol: "music.note",
                    color: .pink,
                    title: "Music at a Glance",
                    detail: "Artwork, progress, and playback controls for Apple Music or Spotify."
                )
                OnboardingFeatureRow(
                    symbol: "square.grid.2x2.fill",
                    color: .orange,
                    title: "Myspace",
                    detail: "Drop files and jot down quick thoughts, always one hover away."
                )
                OnboardingFeatureRow(
                    symbol: "bell.fill",
                    color: .red,
                    title: "Reminders",
                    detail: "Timed nudges that appear right where you're already looking."
                )
            }
            .frame(maxWidth: 440, alignment: .leading)
            .padding(.top, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

/// Colored symbol in a fixed column, bold title, secondary description.
struct OnboardingFeatureRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
                .frame(width: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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
        VStack(spacing: 20) {
            OnboardingStepHeader(
                symbol: "apple.terminal.on.rectangle.fill",
                color: .blue,
                title: "Connect Your AI Tools",
                detail: "Install the integrations for the agents you use."
            )

            VStack(alignment: .leading, spacing: 8) {
                OnboardingSectionHeader(title: "Coding Agents") {
                    Button("Install All") {
                        installAll()
                    }
                    .disabled(model.hooksBinaryURL == nil || allReady)
                }

                OnboardingGroup {
                    agentRow("Claude Code", installed: model.claudeHooksInstalled, busy: model.isClaudeHookSetupBusy, action: model.installClaudeHooks)
                    OnboardingRowDivider()
                    agentRow("Codex", installed: model.codexHooksInstalled, busy: model.isCodexSetupBusy, action: model.installCodexHooks)
                    OnboardingRowDivider()
                    agentRow("Cursor", installed: model.cursorHooksInstalled, busy: model.isCursorHookSetupBusy, action: model.installCursorHooks)
                    OnboardingRowDivider()
                    agentRow("OpenCode", installed: model.openCodePluginInstalled, busy: model.isOpenCodeSetupBusy, action: model.installOpenCodePlugin)
                    OnboardingRowDivider()
                    agentRow("Gemini CLI", installed: model.geminiHooksInstalled, busy: model.isGeminiHookSetupBusy, action: model.installGeminiHooks)
                    OnboardingRowDivider()
                    agentRow("Kimi CLI", installed: model.kimiHooksInstalled, busy: model.isKimiHookSetupBusy, action: model.installKimiHooks)
                    OnboardingRowDivider()
                    agentRow("Antigravity", installed: model.antigravityHooksInstalled, busy: model.isAntigravityHookSetupBusy, action: model.installAntigravityHooks)
                }

                DisclosureGroup(isExpanded: $showsMoreAgents) {
                    OnboardingGroup {
                        agentRow("Qoder", installed: model.qoderHooksInstalled, busy: model.isQoderHookSetupBusy, action: model.installQoderHooks)
                        OnboardingRowDivider()
                        agentRow("Qwen Code", installed: model.qwenCodeHooksInstalled, busy: model.isQwenCodeHookSetupBusy, action: model.installQwenCodeHooks)
                        OnboardingRowDivider()
                        agentRow("Factory", installed: model.factoryHooksInstalled, busy: model.isFactoryHookSetupBusy, action: model.installFactoryHooks)
                        OnboardingRowDivider()
                        agentRow("CodeBuddy", installed: model.codebuddyHooksInstalled, busy: model.isCodebuddyHookSetupBusy, action: model.installCodebuddyHooks)
                    }
                    .padding(.top, 6)
                } label: {
                    Text("More Claude-Compatible Agents")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .padding(.leading, 4)

                if model.hooksBinaryURL == nil {
                    Label {
                        Text("The hooks helper is missing. Build the package first, then come back.")
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                    .font(.callout)
                    .padding(.top, 4)
                    .padding(.leading, 4)
                }
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

    private func agentRow(
        _ name: String,
        installed: Bool,
        busy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        OnboardingRow(
            icon: "terminal.fill",
            iconColor: installed ? .green : .gray,
            title: name
        ) {
            if installed {
                OnboardingStatusLabel(text: "Installed")
            } else if busy {
                ProgressView().controlSize(.small)
            } else {
                Button("Install", action: action)
                    .disabled(model.hooksBinaryURL == nil)
            }
        }
    }
}

// MARK: - Permissions

struct OnboardingPermissionsStep: View {
    @Binding var axTrusted: Bool
    @Binding var notificationAuthorization: String
    var requestNotifications: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            OnboardingStepHeader(
                symbol: "hand.raised.fill",
                color: .blue,
                title: "Privacy & Permissions",
                detail: "NotchTune asks only for what it uses. You can change these any time in System Settings."
            )

            OnboardingGroup {
                OnboardingRow(
                    icon: "accessibility",
                    iconColor: .blue,
                    title: "Accessibility",
                    detail: "Focus the right terminal window and pane when you jump back to a session."
                ) {
                    if axTrusted {
                        OnboardingStatusLabel(text: "Allowed")
                    } else {
                        Button("Open Settings…") {
                            openPrivacyPane("Privacy_Accessibility")
                        }
                    }
                }

                OnboardingRowDivider()

                OnboardingRow(
                    icon: "bell.badge.fill",
                    iconColor: .red,
                    title: "Notifications",
                    detail: "Tell you when an agent finishes and deliver timed reminders."
                ) {
                    notificationAccessory
                }

                OnboardingRowDivider()

                OnboardingRow(
                    icon: "gearshape.2.fill",
                    iconColor: .gray,
                    title: "Automation",
                    detail: "Jump back to supported terminals and control your music player. macOS asks the first time it's needed."
                ) {
                    Button("Open Settings…") {
                        openPrivacyPane("Privacy_Automation")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notificationAccessory: some View {
        switch notificationAuthorization {
        case "Allowed":
            OnboardingStatusLabel(text: "Allowed")
        case "Denied":
            HStack(spacing: 10) {
                Text("Off").foregroundStyle(.secondary)
                Button("Open Settings…") {
                    openNotificationSettings()
                }
            }
        case "Allow":
            Button("Allow", action: requestNotifications)
        default:
            // Checking… / Unavailable (no bundle, e.g. `swift run`) / Unknown.
            HStack(spacing: 10) {
                Text(notificationAuthorization).foregroundStyle(.secondary)
                Button("Allow", action: requestNotifications)
                    .disabled(true)
            }
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Music

struct OnboardingMusicStep: View {
    var model: AppModel
    @State private var selection: String = UserDefaults.standard.string(forKey: musicConnectedAppDefaultsKey) ?? "none"

    var body: some View {
        VStack(spacing: 28) {
            OnboardingStepHeader(
                symbol: "music.note",
                color: .pink,
                title: "Choose Your Music Player",
                detail: "Control playback and see what's playing, with artwork and progress, right from the notch."
            )

            HStack(alignment: .top, spacing: 16) {
                playerTile(
                    title: "Apple Music",
                    detail: "Built into macOS",
                    tag: "appleMusic",
                    icon: Self.appIcon(path: "/System/Applications/Music.app")
                ) {
                    model.playerManager.switchToAppleMusic()
                }

                if model.playerManager.isSpotifyAvailable {
                    playerTile(
                        title: "Spotify",
                        detail: "Uses the installed app",
                        tag: "spotify",
                        icon: Self.appIcon(bundleIdentifier: "com.spotify.client")
                    ) {
                        model.playerManager.switchToSpotify()
                    }
                }

                playerTile(
                    title: "None",
                    detail: "Turn it on later in Settings",
                    tag: "none",
                    icon: nil
                ) {
                    model.playerManager.switchToNone()
                }
            }
            .frame(maxWidth: 460)

            Text("macOS asks once for Automation permission the first time NotchTune talks to your player.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }

    private func playerTile(
        title: String,
        detail: String,
        tag: String,
        icon: NSImage?,
        action: @escaping () -> Void
    ) -> some View {
        OnboardingChoiceTile(
            title: title,
            detail: detail,
            isSelected: selection == tag,
            action: {
                selection = tag
                action()
            }
        ) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.quinary)
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 86)
        }
    }

    private static func appIcon(path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private static func appIcon(bundleIdentifier: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Personalize

struct OnboardingPersonalizeStep: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 24) {
            // The preview IS the real notch: the island is pinned open while
            // this step is visible (`beginAppearanceLivePreview`).
            OnboardingStepHeader(
                symbol: "paintpalette.fill",
                color: .purple,
                rendering: .multicolor,
                title: "Make It Yours",
                detail: "Your island is open at the top of the screen. Changes here apply to it instantly."
            )

            VStack(alignment: .leading, spacing: 8) {
                OnboardingSectionHeader(title: "Character", caption: "Shown on the closed notch")
                HStack(spacing: 8) {
                    ForEach(IslandCharacter.allCases) { option in
                        OnboardingChoiceTile(
                            title: option.rawValue.capitalized,
                            isSelected: model.islandCharacter == option,
                            action: { model.islandCharacter = option }
                        ) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.black)
                                .frame(width: 76, height: 50)
                                .overlay {
                                    UnifiedBars(mode: .idle, size: 32, character: option)
                                        .frame(width: 36, height: 36)
                                }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                OnboardingSectionHeader(title: "Material")
                HStack(spacing: 12) {
                    materialTile(
                        title: "Clear Glass",
                        style: .clear,
                        isSelected: model.glassSettings.isEnabled && model.glassSettings.style == .clear
                    ) {
                        model.glassSettings.isEnabled = true
                        model.glassSettings.style = .clear
                    }
                    materialTile(
                        title: "Frosted Glass",
                        style: .frosted,
                        isSelected: model.glassSettings.isEnabled && model.glassSettings.style == .regular
                    ) {
                        model.glassSettings.isEnabled = true
                        model.glassSettings.style = .regular
                    }
                    materialTile(
                        title: "Solid",
                        style: .solid,
                        isSelected: !model.glassSettings.isEnabled
                    ) {
                        model.glassSettings.isEnabled = false
                    }
                }

                OnboardingGroup {
                    HStack(spacing: 12) {
                        Text("Tint Strength")
                        Slider(
                            value: Binding(
                                get: { model.glassSettings.tintStrength },
                                set: { model.glassSettings.tintStrength = $0 }
                            ),
                            in: 0...0.65
                        )
                        Text("\(Int((model.glassSettings.tintStrength * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .disabled(!model.glassSettings.isEnabled)
                }
                .padding(.top, 6)
            }
        }
    }

    private enum MaterialPreview { case clear, frosted, solid }

    /// A tiny desktop with the island drawn in each finish.
    private func materialTile(
        title: String,
        style: MaterialPreview,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        OnboardingChoiceTile(title: title, isSelected: isSelected, action: action) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(OnboardingTheme.wallpaper)
                .frame(width: 150, height: 72)
                .overlay(alignment: .top) {
                    islandSwatch(style)
                        .frame(width: 92, height: 30)
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    @ViewBuilder
    private func islandSwatch(_ style: MaterialPreview) -> some View {
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: 11,
            bottomTrailingRadius: 11,
            style: .continuous
        )
        switch style {
        case .clear:
            shape.fill(Color.black.opacity(0.22))
                .overlay { shape.strokeBorder(.white.opacity(0.55), lineWidth: 0.75) }
        case .frosted:
            shape.fill(Color.white.opacity(0.42))
                .overlay { shape.strokeBorder(.white.opacity(0.7), lineWidth: 0.75) }
        case .solid:
            shape.fill(Color.black)
        }
    }
}

// MARK: - Keep running

struct OnboardingKeepRunningStep: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 24) {
            OnboardingStepHeader(
                symbol: "power.circle.fill",
                color: .green,
                rendering: .monochrome,
                title: "Keep NotchTune Running",
                detail: "NotchTune is most useful when it's always there, quietly waiting in the notch."
            )

            OnboardingGroup {
                OnboardingRow(
                    icon: "power",
                    iconColor: .gray,
                    title: "Launch at Login",
                    detail: "Start NotchTune automatically when you log in."
                ) {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.launchAtLoginEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                OnboardingRowDivider()

                OnboardingRow(
                    icon: "arrow.down.circle.fill",
                    iconColor: .blue,
                    title: "Automatic Updates",
                    detail: "Signed releases install in place. There's nothing to do."
                ) {
                    OnboardingStatusLabel(text: "On")
                }
            }
        }
    }
}

// MARK: - Try it live

struct OnboardingTryLiveStep: View {
    var body: some View {
        VStack(spacing: 24) {
            OnboardingStepHeader(
                title: "Try It Live",
                detail: "Take a 60-second, hands-on tour in your real notch. Nothing from the demo sticks around afterward."
            ) {
                notchIllustration
            }

            VStack(alignment: .leading, spacing: 14) {
                OnboardingFeatureRow(
                    symbol: "cursorarrow.motionlines",
                    color: .blue,
                    title: "Open the Island",
                    detail: "Hover over the notch to reveal your sessions."
                )
                OnboardingFeatureRow(
                    symbol: "checkmark.bubble.fill",
                    color: .green,
                    title: "Resolve an Approval",
                    detail: "Answer a demo agent's request without leaving your work."
                )
                OnboardingFeatureRow(
                    symbol: "music.note",
                    color: .pink,
                    title: "Peek at Music",
                    detail: "Switch to the Music tab for playback controls."
                )
                OnboardingFeatureRow(
                    symbol: "arrow.down.doc.fill",
                    color: .orange,
                    title: "Drop a File",
                    detail: "Drag something onto the notch to keep it in Myspace."
                )
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
    }

    /// The top of a Mac display: wallpaper, the black notch, a pointer.
    private var notchIllustration: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(OnboardingTheme.wallpaper)
            .frame(width: 200, height: 64)
            .overlay(alignment: .top) {
                V6ClosedPillShape()
                    .fill(Color.black)
                    .frame(width: 70, height: 16)
            }
            .overlay(alignment: .top) {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .offset(x: 30, y: 22)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
    }
}
