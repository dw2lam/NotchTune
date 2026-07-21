import Foundation
import NotchTuneCore
import Observation

/// Drives the hands-on first-run tour that happens in the REAL notch: a seeded
/// demo agent session walks the user through hover-open, approving a request,
/// peeking the Music tab, and dropping a file into Myspace.
///
/// The controller never mutates UI directly — it advances a phase machine by
/// observing `AppModel` state (`withObservationTracking`), and the coach bubble
/// in `IslandPanelView` renders whatever the current phase asks for.
@MainActor
@Observable
final class OnboardingTourController {
    enum TourPhase: Equatable {
        case idle
        /// Demo approval seeded; waiting for the user to open the island.
        case waitHoverOpen
        /// Island open; waiting for the demo approval to be resolved.
        case waitApprovalResolved
        /// Invite the user to peek the Music tab (skipped when music is off).
        case promptMusicTab
        /// Waiting for any file to land in Myspace.
        case waitFileDrop
        /// Short "you're set" moment before cleanup.
        case celebrate
        case done
    }

    /// Snapshot of everything the phase machine reads — kept as a plain value
    /// so transitions are a pure, table-testable function.
    struct TourContext: Equatable {
        var notchStatus: NotchStatus
        var demoPhase: SessionPhase?
        var activeTab: IslandTab
        var thoughtCount: Int
        var isMusicEnabled: Bool
    }

    static let demoSessionID = "onboarding-tour-demo"
    private static let celebrateSeconds: Double = 4

    private(set) var phase: TourPhase = .idle

    var isActive: Bool { phase != .idle && phase != .done }

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var baselineThoughts = 0
    @ObservationIgnored private var celebrateTask: Task<Void, Never>?

    // MARK: - Phase machine (pure)

    /// Returns the next phase, or nil to stay put. `celebrate → done` is
    /// time-driven (not context-driven) and handled by the controller.
    static func nextPhase(
        from phase: TourPhase,
        given ctx: TourContext,
        baselineThoughts: Int
    ) -> TourPhase? {
        switch phase {
        case .idle, .celebrate, .done:
            return nil
        case .waitHoverOpen:
            return ctx.notchStatus == .opened ? .waitApprovalResolved : nil
        case .waitApprovalResolved:
            // Any resolution (allow or deny) — or the demo vanishing — advances.
            guard ctx.demoPhase != .waitingForApproval else { return nil }
            return ctx.isMusicEnabled ? .promptMusicTab : .waitFileDrop
        case .promptMusicTab:
            // A user who skips ahead and just drops a file shouldn't be held back.
            if ctx.thoughtCount > baselineThoughts { return .celebrate }
            return ctx.activeTab == .music ? .waitFileDrop : nil
        case .waitFileDrop:
            return ctx.thoughtCount > baselineThoughts ? .celebrate : nil
        }
    }

    // MARK: - Lifecycle

    func start(model: AppModel) {
        self.model = model
        celebrateTask?.cancel()
        // Idempotent re-seed for replays.
        model.removeTourDemoSession()
        model.insertTourDemoSession()
        baselineThoughts = model.myspaceStore.thoughts.count
        phase = .waitHoverOpen
        armObservation()
    }

    func skip() {
        guard isActive else { return }
        end(outcome: .skipped)
    }

    private func end(outcome: AgentIntentStore.OnboardingTourOutcome) {
        celebrateTask?.cancel()
        celebrateTask = nil
        model?.removeTourDemoSession()
        model?.onboardingTourOutcome = outcome
        phase = .done
    }

    // MARK: - Observation loop

    private func armObservation() {
        guard isActive, let model else { return }
        withObservationTracking {
            _ = Self.context(of: model)
        } onChange: { [weak self] in
            // onChange fires at willSet — re-read on the next main-actor tick,
            // then ALWAYS re-arm (a missed re-arm silently stalls the tour).
            Task { @MainActor [weak self] in
                self?.evaluate()
            }
        }
    }

    static func context(of model: AppModel) -> TourContext {
        TourContext(
            notchStatus: model.notchStatus,
            demoPhase: model.state.session(id: demoSessionID)?.phase,
            activeTab: model.islandActiveTab,
            thoughtCount: model.myspaceStore.thoughts.count,
            isMusicEnabled: model.playerManager.isMusicEnabled
        )
    }

    /// Re-reads model state and advances if the context allows it. Internal so
    /// tests can drive transitions deterministically.
    func evaluate() {
        guard isActive, let model else { return }
        let ctx = Self.context(of: model)
        if let next = Self.nextPhase(from: phase, given: ctx, baselineThoughts: baselineThoughts) {
            transition(to: next)
        }
        armObservation()
    }

    private func transition(to next: TourPhase) {
        if phase == .waitApprovalResolved {
            // Leaving the approval phase: turn the demo card into a small win.
            model?.completeTourDemoSession()
        }
        phase = next

        if next == .celebrate {
            celebrateTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.celebrateSeconds))
                guard !Task.isCancelled else { return }
                self?.end(outcome: .completed)
            }
        }
    }

    // MARK: - Coach copy

    /// Instruction shown in the coach bubble; adapts to whether the island is
    /// a real notch or an external-display top bar.
    var coachText: String {
        let surface = model?.activeAppearanceProfile == .topBar ? "the pill" : "the notch"
        switch phase {
        case .idle, .done:
            return ""
        case .waitHoverOpen:
            return "A demo agent needs your approval — hover \(surface) to open the island."
        case .waitApprovalResolved:
            return "That's the demo card. Click Allow (or Deny) to resolve it."
        case .promptMusicTab:
            return "Nice. Now peek the Music tab — playback lives here too."
        case .waitFileDrop:
            return "Last one: drag any file from Finder onto \(surface) to hold it in Myspace."
        case .celebrate:
            return "You're all set. NotchTune stays out of the way until something needs you."
        }
    }
}
