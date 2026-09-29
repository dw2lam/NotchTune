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
    }

    var model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .welcome
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var notificationAuthorization = "Checking…"

    var body: some View {
        OnboardingScrollWithFooter {
            stepContent
                .id(step)
                .transition(.opacity)
                .frame(maxWidth: OnboardingTheme.contentWidth)
                .padding(.horizontal, 40)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
        } footer: {
            footer
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 600, idealHeight: 660)
        .modifier(OnboardingWindowChrome())
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
        .onReceive(NotificationCenter.default.publisher(for: .notchTuneSelectOnboardingStep)) { note in
            if let index = note.object as? Int, let target = Step(rawValue: index) {
                step = target
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

    /// Setup Assistant footer: a quiet skip on the leading edge, page dots in
    /// the middle, Back + the primary action on the trailing edge.
    private var footer: some View {
        ZStack {
            OnboardingPageDots(count: Step.allCases.count, current: step.rawValue)
                .accessibilityValue(step.title)

            HStack(spacing: 10) {
                Button(step == .tryLive ? "Skip Tour" : "Skip Setup") {
                    if step == .tryLive, model.onboardingTourOutcome == nil {
                        model.onboardingTourOutcome = .skipped
                    }
                    finish()
                }
                .buttonStyle(.link)
                .help(step == .tryLive ? "Finish setup without the guided tour" : "Finish setup now — everything stays editable in Settings")

                Spacer()

                if step != .welcome {
                    Button {
                        move(by: -1)
                    } label: {
                        Text("Back").frame(minWidth: 64)
                    }
                    .controlSize(.large)
                }

                Button {
                    if step == .tryLive {
                        finish()
                        model.startOnboardingTour()
                    } else {
                        move(by: 1)
                    }
                } label: {
                    Text(step == .tryLive ? "Start Tour" : "Continue").frame(minWidth: 84)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
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
        // `swift run` (harness) has no bundle proxy; UNUserNotificationCenter
        // raises instead of returning.
        guard Bundle.main.bundleIdentifier != nil else {
            notificationAuthorization = "Unavailable"
            return
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorization = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Allow"
        @unknown default: "Unknown"
        }
    }
}

/// Hide the redundant window title (the step header carries it) and let the
/// title bar blend into the content, like Apple's welcome windows.
private struct OnboardingWindowChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}

/// The step content scrolls; the footer stays pinned. On macOS 26 the footer
/// is a safe-area bar, so content scrolling beneath it gets the system's soft
/// scroll-edge effect instead of a hard divider.
private struct OnboardingScrollWithFooter<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        if #available(macOS 26.0, *) {
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaBar(edge: .bottom) {
                footer
            }
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    content
                }
                .scrollBounceBehavior(.basedOnSize)
                footer
            }
        }
    }
}
