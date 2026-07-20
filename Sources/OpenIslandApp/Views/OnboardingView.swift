import AppKit
import ApplicationServices
import SwiftUI
import UserNotifications

struct OnboardingView: View {
    private enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case agents
        case permissions
        case appearance

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .agents: "AI agents"
            case .permissions: "Permissions"
            case .appearance: "Make it yours"
            }
        }

        var systemImage: String {
            switch self {
            case .welcome: "sparkles"
            case .agents: "terminal"
            case .permissions: "lock.shield"
            case .appearance: "paintbrush"
            }
        }
    }

    var model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .welcome
    @State private var notificationAuthorization = "Checking…"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)

            ScrollView {
                stepContent
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 42)
                    .padding(.vertical, 30)
            }

            Divider().opacity(0.35)
            footer
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 540, idealHeight: 590)
        .background(V6Palette.ink)
        .preferredColorScheme(.dark)
        .task {
            await refreshNotificationAuthorization()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                    Text(item.title)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(item == step ? .white : .white.opacity(0.34))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    item == step ? .white.opacity(0.1) : .clear,
                    in: Capsule()
                )

                if item != Step.allCases.last {
                    Rectangle()
                        .fill(.white.opacity(item.rawValue < step.rawValue ? 0.24 : 0.08))
                        .frame(width: 16, height: 1)
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 54)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .agents:
            agentsStep
        case .permissions:
            permissionsStep
        case .appearance:
            appearanceStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
                .shadow(color: .cyan.opacity(0.18), radius: 22, y: 10)

            Text("Meet NotchTune")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("Your notch becomes a calm home for AI coding sessions, quick thoughts, files, music, and reminders.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            HStack(spacing: 10) {
                featureCard("Live agents", icon: "terminal")
                featureCard("Myspace", icon: "square.grid.2x2")
                featureCard("Reminders", icon: "bell")
            }
            .padding(.top, 12)
        }
    }

    private var agentsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeading(
                "Connect your AI tools",
                detail: "Install only the local integrations you use. You can change these later in Settings → Setup."
            )

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                agentCard(
                    "Claude Code",
                    installed: model.claudeHooksInstalled,
                    busy: model.isClaudeHookSetupBusy,
                    action: model.installClaudeHooks
                )
                agentCard(
                    "Codex",
                    installed: model.codexHooksInstalled,
                    busy: model.isCodexSetupBusy,
                    action: model.installCodexHooks
                )
                agentCard(
                    "Cursor",
                    installed: model.cursorHooksInstalled,
                    busy: model.isCursorHookSetupBusy,
                    action: model.installCursorHooks
                )
                agentCard(
                    "OpenCode",
                    installed: model.openCodePluginInstalled,
                    busy: model.isOpenCodeSetupBusy,
                    action: model.installOpenCodePlugin
                )
                agentCard(
                    "Gemini CLI",
                    installed: model.geminiHooksInstalled,
                    busy: model.isGeminiHookSetupBusy,
                    action: model.installGeminiHooks
                )
                agentCard(
                    "Kimi CLI",
                    installed: model.kimiHooksInstalled,
                    busy: model.isKimiHookSetupBusy,
                    action: model.installKimiHooks
                )
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeading(
                "Let NotchTune help",
                detail: "Permissions stay under your control and can be changed any time in System Settings."
            )

            permissionRow(
                title: "Accessibility",
                detail: "Focus the correct terminal window and pane.",
                systemImage: "accessibility",
                status: AXIsProcessTrusted() ? "Allowed" : "Not allowed",
                isReady: AXIsProcessTrusted()
            ) {
                openPrivacyPane("Privacy_Accessibility")
            }

            permissionRow(
                title: "Notifications",
                detail: "Show completed agents and timed reminders.",
                systemImage: "bell.badge",
                status: notificationAuthorization,
                isReady: notificationAuthorization == "Allowed"
            ) {
                requestNotificationAuthorization()
            }

            permissionRow(
                title: "Automation",
                detail: "Jump back to supported terminal apps.",
                systemImage: "gearshape.2",
                status: "Optional",
                isReady: false
            ) {
                openPrivacyPane("Privacy_Automation")
            }
        }
    }

    private var appearanceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeading(
                "Choose your island finish",
                detail: "Start with Liquid Glass or a solid notch. Every detail remains editable in Personalization."
            )

            HStack(spacing: 12) {
                appearanceCard(
                    title: "Clear glass",
                    detail: "Bright and light-bending",
                    selected: model.glassSettings.isEnabled && model.glassSettings.style == .clear
                ) {
                    model.glassSettings.isEnabled = true
                    model.glassSettings.style = .clear
                }

                appearanceCard(
                    title: "Frosted glass",
                    detail: "Softer with more contrast",
                    selected: model.glassSettings.isEnabled && model.glassSettings.style == .regular
                ) {
                    model.glassSettings.isEnabled = true
                    model.glassSettings.style = .regular
                }

                appearanceCard(
                    title: "Solid",
                    detail: "Classic black notch",
                    selected: !model.glassSettings.isEnabled
                ) {
                    model.glassSettings.isEnabled = false
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Tint strength")
                    Spacer()
                    Text("\(Int((model.glassSettings.tintStrength * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
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
            }
            .padding(12)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))

            onboardingIslandPreview
        }
    }

    private var onboardingIslandPreview: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text("NotchTune")
                    .font(.system(size: 12, weight: .semibold))
                Text("Ready for your next session")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Image(systemName: "sparkles")
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .frame(height: 72)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    model.glassSettings.isEnabled
                        ? .white.opacity(
                            model.glassSettings.style == .clear ? 0.075 : 0.13
                        )
                        : .black.opacity(0.88)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(model.glassSettings.isEnabled ? 0.15 : 0.05))
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip setup") {
                finish()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.42))

            Spacer()

            if step != .welcome {
                Button("Back") {
                    move(by: -1)
                }
            }

            Button(step == .appearance ? "Start using NotchTune" : "Continue") {
                if step == .appearance {
                    finish()
                } else {
                    move(by: 1)
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 62)
    }

    private func stepHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.48))
        }
    }

    private func featureCard(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(.white.opacity(0.055), in: Capsule())
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
                .foregroundStyle(installed ? .green : .white.opacity(0.5))
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))

            Text(name)
                .font(.system(size: 11.5, weight: .semibold))

            Spacer()

            if installed {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.green)
            } else if busy {
                ProgressView().controlSize(.small)
            } else {
                Button("Connect", action: action)
                    .controlSize(.small)
                    .disabled(model.hooksBinaryURL == nil)
            }
        }
        .padding(10)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.07), lineWidth: 0.5)
        }
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
                .foregroundStyle(isReady ? .green : .white.opacity(0.52))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Spacer()

            Button(status, action: action)
                .controlSize(.small)
        }
        .padding(12)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private func appearanceCard(
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
                            ? .black.opacity(0.9)
                            : .white.opacity(title == "Clear glass" ? 0.075 : 0.15)
                    )
                    .frame(height: 62)
                    .overlay {
                        Image(systemName: selected ? "checkmark.circle.fill" : "sparkles")
                            .foregroundStyle(selected ? .cyan : .white.opacity(0.4))
                    }

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.white.opacity(selected ? 0.075 : 0.025), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.cyan.opacity(0.55) : .white.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
    }

    private func move(by delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = next
        }
    }

    private func finish() {
        model.firstLaunchCompleted = true
        dismiss()
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in
                await refreshNotificationAuthorization()
            }
        }
    }

    private func refreshNotificationAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorization = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Allow"
        @unknown default: "Unknown"
        }
    }
}
