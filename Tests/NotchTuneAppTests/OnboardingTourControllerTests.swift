import Foundation
import Testing
@testable import NotchTuneApp
@testable import NotchTuneCore

@MainActor
struct OnboardingTourControllerTests {
    private typealias Phase = OnboardingTourController.TourPhase
    private typealias Context = OnboardingTourController.TourContext

    private func context(
        notch: NotchStatus = .closed,
        demoPhase: SessionPhase? = .waitingForApproval,
        tab: IslandTab = .agents,
        thoughts: Int = 0,
        music: Bool = true
    ) -> Context {
        Context(
            notchStatus: notch,
            demoPhase: demoPhase,
            activeTab: tab,
            thoughtCount: thoughts,
            isMusicEnabled: music
        )
    }

    // MARK: - Pure phase machine

    @Test
    func hoverPhaseAdvancesOnlyWhenIslandOpens() {
        #expect(OnboardingTourController.nextPhase(
            from: .waitHoverOpen, given: context(notch: .closed), baselineThoughts: 0
        ) == nil)
        #expect(OnboardingTourController.nextPhase(
            from: .waitHoverOpen, given: context(notch: .popping), baselineThoughts: 0
        ) == nil)
        #expect(OnboardingTourController.nextPhase(
            from: .waitHoverOpen, given: context(notch: .opened), baselineThoughts: 0
        ) == .waitApprovalResolved)
    }

    @Test
    func approvalPhaseAdvancesOnAnyResolutionAndSkipsMusicWhenDisabled() {
        #expect(OnboardingTourController.nextPhase(
            from: .waitApprovalResolved,
            given: context(notch: .opened, demoPhase: .waitingForApproval),
            baselineThoughts: 0
        ) == nil)
        // Approved → running
        #expect(OnboardingTourController.nextPhase(
            from: .waitApprovalResolved,
            given: context(notch: .opened, demoPhase: .running),
            baselineThoughts: 0
        ) == .promptMusicTab)
        // Demo removed entirely still advances
        #expect(OnboardingTourController.nextPhase(
            from: .waitApprovalResolved,
            given: context(notch: .opened, demoPhase: nil),
            baselineThoughts: 0
        ) == .promptMusicTab)
        // Music off → straight to the file drop
        #expect(OnboardingTourController.nextPhase(
            from: .waitApprovalResolved,
            given: context(notch: .opened, demoPhase: .completed, music: false),
            baselineThoughts: 0
        ) == .waitFileDrop)
    }

    @Test
    func musicPromptAdvancesOnTabSwitchOrEarlyFileDrop() {
        #expect(OnboardingTourController.nextPhase(
            from: .promptMusicTab,
            given: context(notch: .opened, tab: .agents),
            baselineThoughts: 0
        ) == nil)
        #expect(OnboardingTourController.nextPhase(
            from: .promptMusicTab,
            given: context(notch: .opened, tab: .music),
            baselineThoughts: 0
        ) == .waitFileDrop)
        // Skipping ahead by dropping a file wins outright.
        #expect(OnboardingTourController.nextPhase(
            from: .promptMusicTab,
            given: context(notch: .opened, tab: .agents, thoughts: 3),
            baselineThoughts: 2
        ) == .celebrate)
    }

    @Test
    func fileDropAdvancesOnlyWhenANewThoughtLands() {
        #expect(OnboardingTourController.nextPhase(
            from: .waitFileDrop,
            given: context(thoughts: 2),
            baselineThoughts: 2
        ) == nil)
        #expect(OnboardingTourController.nextPhase(
            from: .waitFileDrop,
            given: context(thoughts: 3),
            baselineThoughts: 2
        ) == .celebrate)
    }

    @Test
    func terminalAndIdlePhasesNeverAdvanceFromContext() {
        for phase in [Phase.idle, .celebrate, .done] {
            #expect(OnboardingTourController.nextPhase(
                from: phase,
                given: context(notch: .opened, demoPhase: nil, tab: .music, thoughts: 99),
                baselineThoughts: 0
            ) == nil)
        }
    }

    // MARK: - Integration with AppModel

    @Test
    func startSeedsDemoAndSkipCleansUpPreservingRealSessions() {
        let model = AppModel()
        model.state.insertSession(
            AgentSession(
                id: "real",
                title: "Real session",
                tool: .codex,
                phase: .running,
                summary: "Working",
                updatedAt: .now
            )
        )

        model.startOnboardingTour()
        #expect(model.tour.phase == .waitHoverOpen)
        #expect(model.state.session(id: OnboardingTourController.demoSessionID)?.origin == .demo)
        #expect(model.state.session(id: "real") != nil)

        model.tour.skip()
        #expect(model.tour.phase == .done)
        #expect(model.state.session(id: OnboardingTourController.demoSessionID) == nil)
        #expect(model.state.session(id: "real") != nil)
        #expect(model.hooks.intentStore.onboardingTourOutcome == .skipped)
    }

    @Test
    func demoApprovalResolvesLocallyAndRewritesTheCard() {
        let model = AppModel()
        model.startOnboardingTour()
        let before = model.lastActionMessage

        model.approvePermission(for: OnboardingTourController.demoSessionID, action: .allowOnce)

        // Local resolution only: no bridge send, so no user message churn.
        #expect(model.lastActionMessage == before)
        let demo = model.state.session(id: OnboardingTourController.demoSessionID)
        #expect(demo?.phase != .waitingForApproval)
        #expect(demo?.permissionRequest == nil)

        model.tour.skip()
    }

    @Test
    func observationLoopDrivesTwoConsecutiveTransitions() async {
        let model = AppModel()
        model.startOnboardingTour()
        #expect(model.tour.phase == .waitHoverOpen)

        model.overlay.notchOpen(reason: .hover)
        await pumpMainActor()
        #expect(model.tour.phase == .waitApprovalResolved)

        model.approvePermission(for: OnboardingTourController.demoSessionID, action: .allowOnce)
        await pumpMainActor()
        // Music defaults to none in a fresh test environment unless the suite
        // machine has a player configured — accept either follow-up phase.
        #expect(model.tour.phase == .promptMusicTab || model.tour.phase == .waitFileDrop)
        // The demo card was rewritten into the completed win on the way out.
        #expect(model.state.session(id: OnboardingTourController.demoSessionID)?.phase == .completed)

        model.tour.skip()
    }

    private func pumpMainActor() async {
        for _ in 0..<8 {
            await Task.yield()
        }
    }
}
