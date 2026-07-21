import AppKit
import ApplicationServices
import SwiftUI
import UserNotifications

/// The first-run setup wizard. Ends by handing off to the live guided tour in
/// the real notch (`OnboardingTourController`) — or finishing without it.
struct OnboardingView: View {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case agents
        case permissions
        case music
        case personalize
        case keepRunning
        case tryLive

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .agents: "Agents"
            case .permissions: "Permissions"
            case .music: "Music"
            case .personalize: "Style"
            case .keepRunning: "Startup"
            case .tryLive: "Tour"
            }
        }

        var systemImage: String {
            switch self {
            case .welcome: "sparkles"
            case .agents: "terminal"
            case .permissions: "lock.shield"
            case .music: "music.note"
            case .personalize: "paintbrush"
            case .keepRunning: "power"
            case .tryLive: "play.circle"
            }
        }
    }

    var model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .welcome
    @State private var axTrusted = AXIsProcessTrusted()
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
        .frame(minWidth: 700, idealWidth: 760, minHeight: 560, idealHeight: 610)
        .background(V6Palette.ink)
        .preferredColorScheme(.dark)
        .task {
            await refreshNotificationAuthorization()
        }
        .task(id: step) {
            // Live AX status while the permissions step is visible — the grant
            // happens in System Settings, so poll to reflect it immediately.
            guard step == .permissions else { return }
            while !Task.isCancelled {
                axTrusted = AXIsProcessTrusted()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onAppear {
            // Resume where a previously closed wizard left off.
            let stage = model.onboardingWizardStage
            if stage > 0, let resumed = Step(rawValue: min(stage, Step.tryLive.rawValue)) {
                step = resumed
            }
            if step == .personalize {
                model.beginAppearanceLivePreview()
            }
        }
        .onChange(of: step) { old, new in
            // Personalize previews on the REAL notch: pin the island open for
            // the duration of the step.
            if new == .personalize {
                model.beginAppearanceLivePreview()
            } else if old == .personalize {
                model.endAppearanceLivePreview()
            }
        }
        .onDisappear {
            model.endAppearanceLivePreview()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases) { item in
                let isActive = item == step
                HStack(spacing: 6) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                    if isActive {
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundStyle(
                    isActive
                        ? OnboardingTheme.primaryText
                        : item.rawValue < step.rawValue
                            ? OnboardingTheme.ready.opacity(0.75)
                            : OnboardingTheme.primaryText.opacity(0.3)
                )
                .padding(.horizontal, isActive ? 11 : 8)
                .frame(height: 28)
                .background(
                    isActive ? Color.white.opacity(0.1) : .clear,
                    in: Capsule()
                )

                if item != Step.allCases.last {
                    Rectangle()
                        .fill(.white.opacity(item.rawValue < step.rawValue ? 0.24 : 0.08))
                        .frame(width: 12, height: 1)
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 54)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    // MARK: - Content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStep()
        case .agents:
            OnboardingAgentsStep(model: model)
        case .permissions:
            OnboardingPermissionsStep(
                axTrusted: $axTrusted,
                notificationAuthorization: $notificationAuthorization,
                requestNotifications: requestNotificationAuthorization
            )
        case .music:
            OnboardingMusicStep(model: model)
        case .personalize:
            OnboardingPersonalizeStep(model: model)
        case .keepRunning:
            OnboardingKeepRunningStep(model: model)
        case .tryLive:
            OnboardingTryLiveStep()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(step == .tryLive ? "Finish without tour" : "Skip setup") {
                if step == .tryLive, model.onboardingTourOutcome == nil {
                    model.onboardingTourOutcome = .skipped
                }
                finish()
            }
            .buttonStyle(.plain)
            .foregroundStyle(OnboardingTheme.tertiaryText)

            Spacer()

            if step != .welcome {
                Button("Back") {
                    move(by: -1)
                }
            }

            Button(step == .tryLive ? "Start the guided tour" : "Continue") {
                if step == .tryLive {
                    finish()
                    model.startOnboardingTour()
                } else {
                    move(by: 1)
                }
            }
            .keyboardShortcut(.defaultAction)
            .tint(OnboardingTheme.accent)
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 62)
    }

    // MARK: - Actions

    private func move(by delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = next
        }
        model.onboardingWizardStage = next.rawValue
    }

    private func finish() {
        model.firstLaunchCompleted = true
        dismiss()
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
