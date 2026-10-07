import AppKit
import NotchTuneCore
import SwiftUI

// MARK: - Preview states

/// The moments of the island the Personalization preview walks through.
enum PersonalizationPreviewPhase: Int, CaseIterable, Hashable {
    case idle
    case working
    case needsApproval
    case finished

    /// How long the auto-cycle rests on each moment.
    var dwell: Duration {
        switch self {
        case .idle:          .seconds(2.6)
        case .working:       .seconds(3.8)
        case .needsApproval: .seconds(3.2)
        case .finished:      .seconds(2.6)
        }
    }

    var next: PersonalizationPreviewPhase {
        let all = Self.allCases
        return all[(rawValue + 1) % all.count]
    }

    var glyphMode: UnifiedBars.Mode {
        switch self {
        case .idle, .finished: .idle
        case .working:         .running
        case .needsApproval:   .waiting
        }
    }

    /// The status color the stage glows with under the notch.
    var statusColor: Color {
        switch self {
        case .idle:          V6Palette.paper
        case .working:       IslandDesignPalette.Status.running
        case .needsApproval: IslandDesignPalette.Status.waitingForApproval
        case .finished:      IslandDesignPalette.Status.completed
        }
    }

    /// The sample agent each moment is about (drives "Color by agent").
    var tool: AgentTool {
        switch self {
        case .idle, .working: .claudeCode
        case .needsApproval:  .codex
        case .finished:       .geminiCLI
        }
    }
}

/// What the state picker under the stage pins the preview to.
enum PersonalizationPreviewPin: Hashable, CaseIterable {
    case auto
    case idle
    case working
    case waiting

    /// `nil` = keep cycling.
    var phase: PersonalizationPreviewPhase? {
        switch self {
        case .auto:    nil
        case .idle:    .idle
        case .working: .working
        case .waiting: .needsApproval
        }
    }
}

/// Real geometry of the screen the edited profile describes.
struct PersonalizationPreviewScreen: Equatable {
    /// Hardware cutout width (MacBook) or the virtual notch width (external).
    var notchWidth: CGFloat
    /// Closed pill height for the edited density.
    var pillHeight: CGFloat
    /// Menu bar height (the cutout height on a notched screen).
    var menuBarHeight: CGFloat

    @MainActor
    static func resolve(
        profile: IslandAppearanceDisplayProfile,
        density: IslandDensity
    ) -> PersonalizationPreviewScreen {
        let screens = NSScreen.screens
        switch profile {
        case .notch:
            if let screen = screens.first(where: { $0.isNotchedScreen }) {
                let height = screen.closedIslandHeight(density: density)
                return .init(notchWidth: screen.notchSize.width, pillHeight: height, menuBarHeight: height)
            }
            // No notched display attached: a 14" Pro at default scaling.
            let height = NSScreen.computeClosedIslandHeight(
                density: density,
                isNotched: true,
                safeAreaInsetsTop: 32,
                catalogNotchHeight: 32,
                menuBarHeight: 24
            )
            return .init(notchWidth: 185, pillHeight: height, menuBarHeight: height)
        case .topBar:
            let height: CGFloat
            if let screen = screens.first(where: { !$0.isNotchedScreen }) {
                height = screen.closedIslandHeight(density: density)
            } else {
                height = NSScreen.computeClosedIslandHeight(
                    density: density,
                    isNotched: false,
                    safeAreaInsetsTop: 0,
                    catalogNotchHeight: nil,
                    menuBarHeight: 24
                )
            }
            return .init(
                notchWidth: NSScreen.externalDisplayNotchWidth,
                pillHeight: height,
                menuBarHeight: max(24, height)
            )
        }
    }
}

// MARK: - Stage

/// The Personalization hero: the top of a Mac display — wallpaper, menu bar,
/// the hardware notch — with the REAL closed pill on it, rendered with the
/// edited profile's character, tint, density, top curve, glass, right slot,
/// center label and live-activity mode, moving through `phase`.
struct PersonalizationPreviewStage: View {
    let preferences: IslandAppearancePreferences
    let profile: IslandAppearanceDisplayProfile
    let glassSettings: LiquidGlassSettings
    let phase: PersonalizationPreviewPhase
    /// When the current phase began (drives the live timers).
    let phaseStartedAt: Date
    /// Changes once a finished peek lands, so the character hops.
    let finishHop: UUID?
    let isAutoCycling: Bool
    let lang: LanguageManager
    /// Resolved once per stage value: it walks `NSScreen.screens` (~0.2 ms a
    /// call) and the layout reads it ~30 times per pass — on every phase,
    /// every setting and every frame of a window resize.
    private let screen: PersonalizationPreviewScreen

    static let height: CGFloat = 184

    init(
        preferences: IslandAppearancePreferences,
        profile: IslandAppearanceDisplayProfile,
        glassSettings: LiquidGlassSettings,
        phase: PersonalizationPreviewPhase,
        phaseStartedAt: Date,
        finishHop: UUID?,
        isAutoCycling: Bool,
        lang: LanguageManager
    ) {
        self.preferences = preferences
        self.profile = profile
        self.glassSettings = glassSettings
        self.phase = phase
        self.phaseStartedAt = phaseStartedAt
        self.finishHop = finishHop
        self.isAutoCycling = isAutoCycling
        self.lang = lang
        self.screen = .resolve(profile: profile, density: preferences.density)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsWindowIsOnScreen) private var isOnScreen

    private var layout: V6ClosedLayout {
        profile == .notch ? .macbook : .external
    }

    private var metrics: IslandChromeMetrics {
        .metrics(for: preferences.density)
    }

    var body: some View {
        GeometryReader { proxy in
            let stageWidth = proxy.size.width
            // The pill is drawn at its real size, scaled down just enough
            // that the widest live activity of this configuration fits —
            // so its text never truncates earlier than on the real notch.
            let scale = fitScale(stageWidth: stageWidth)
            let virtualWidth = stageWidth / scale
            let virtualHeight = proxy.size.height / scale
            let pill = previewPill(virtualWidth: virtualWidth, phase: phase)
            let outerWidth = pill.outerWidth(metrics: metrics)
            let offsetX = notchAlignmentOffset(for: pill)

            ZStack(alignment: .top) {
                PersonalizationWallpaper(animated: !reduceMotion, paused: !isOnScreen)

                ZStack(alignment: .top) {
                    phaseGlow
                        .frame(width: 680, height: 270)
                        .position(x: virtualWidth / 2 + offsetX, y: screen.pillHeight)

                    PreviewMenuBar(
                        height: screen.menuBarHeight,
                        showsBar: layout == .external,
                        leadingRoom: virtualWidth / 2 + offsetX - outerWidth / 2,
                        trailingRoom: virtualWidth / 2 - offsetX - outerWidth / 2
                    )
                    .animation(morphAnimation, value: outerWidth)

                    pillSurface(pill: pill, outerWidth: outerWidth)
                        .offset(x: offsetX)
                        .animation(morphAnimation, value: outerWidth)
                        .animation(morphAnimation, value: offsetX)

                    if layout == .macbook {
                        HardwareNotchShape()
                            .fill(Color.black)
                            .frame(width: screen.notchWidth, height: screen.menuBarHeight)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: virtualWidth, height: virtualHeight, alignment: .top)
                .scaleEffect(scale, anchor: .top)
                .frame(width: stageWidth, height: proxy.size.height, alignment: .top)

                VStack {
                    Spacer(minLength: 0)
                    caption
                        .padding(.bottom, 16)
                }
            }
            .frame(width: stageWidth, height: proxy.size.height)
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        // The stage is a dark wallpaper whatever the window's appearance.
        .environment(\.colorScheme, .dark)
        .environment(\.islandChromeMetrics, metrics)
        .environment(\.islandNotchEarRadius, earRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lang.t("settings.appearance.preview"))
        .accessibilityValue("\(phaseTitle). \(phaseDetail)")
    }

    /// ≤ 1: how much the screen-top layer shrinks so the widest moment of
    /// this configuration (with the real 196pt wing cap) fits the stage.
    private func fitScale(stageWidth: CGFloat) -> CGFloat {
        let margin: CGFloat = 12
        var halfExtent: CGFloat = 0
        for candidate in PersonalizationPreviewPhase.allCases {
            let pill = previewPill(virtualWidth: .greatestFiniteMagnitude, phase: candidate)
            switch layout {
            case .macbook:
                let left = pill.liveLeftWingWidth > 0
                    ? pill.liveLeftWingWidth
                    : (pill.outerWidth(metrics: metrics) - screen.notchWidth) / 2
                let right = pill.liveLeftWingWidth > 0 ? pill.liveRightWingWidth : left
                halfExtent = max(halfExtent, screen.notchWidth / 2 + max(left, right))
            case .external:
                halfExtent = max(halfExtent, pill.outerWidth(metrics: metrics) / 2)
            }
        }
        guard halfExtent > 0 else { return 1 }
        return min(1, max(0.6, (stageWidth / 2 - margin) / halfExtent))
    }

    // MARK: Pill

    private var morphAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.5, extraBounce: 0.12)
    }

    private var earRadius: CGFloat {
        preferences.topCurve ? IslandChromeMetrics.closedEarRadius : 0
    }

    private var resolvedGlass: ResolvedGlass? {
        glassSettings.closedGlass(layout: layout)
    }

    /// One surface whose width springs between states, with the pill's
    /// content cross-fading on top — the same "the notch grows" morph the
    /// island's animated clip produces.
    private func pillSurface(pill: IslandPreviewPill, outerWidth: CGFloat) -> some View {
        let silhouette = V6ClosedPillShape(topFilletRadius: 0, outwardEarRadius: earRadius)
        return ZStack(alignment: .top) {
            IslandSurfaceBackground(shape: silhouette, glass: resolvedGlass)
                .frame(width: outerWidth, height: screen.pillHeight)
                .shadow(color: .black.opacity(resolvedGlass == nil ? 0.32 : 0.12), radius: 14, y: 7)

            ZStack {
                pill
                    .id(phase)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
            }
            // On the persistent container (not the outgoing view, which
            // keeps its old values): content never spills past the surface.
            .mask {
                silhouette
                    .frame(width: outerWidth, height: screen.pillHeight)
            }
        }
        .frame(height: screen.pillHeight)
    }

    private func previewPill(virtualWidth: CGFloat, phase: PersonalizationPreviewPhase) -> IslandPreviewPill {
        let activity = liveActivity(for: phase)
        var left: CGFloat = 0
        var right: CGFloat = 0
        if layout == .macbook, let activity {
            let maxWing = max(0, (virtualWidth - screen.notchWidth) / 2 - 12)
            left = activity.leftWingWidth(metrics: metrics, maxWingWidth: maxWing)
            right = max(
                activity.rightWingWidth(metrics: metrics, maxWingWidth: maxWing),
                metrics.notchedClosedMinimumWingReserve
            )
        }
        return IslandPreviewPill(
            mode: phase.glyphMode,
            character: preferences.character,
            label: centerLabel(for: phase),
            rightSlot: rightSlotContent(for: phase),
            layout: layout,
            height: screen.pillHeight,
            physicalNotchWidth: layout == .macbook ? screen.notchWidth : 0,
            minWidth: 70,
            glyphTint: glyphTint(for: phase),
            nudgeTrigger: reduceMotion ? nil : finishHop,
            liveActivity: activity,
            liveLeftWingWidth: left,
            liveRightWingWidth: right,
            showsSurface: false
        )
    }

    /// Asymmetric live wings keep the notch gap on the hardware cutout.
    private func notchAlignmentOffset(for pill: IslandPreviewPill) -> CGFloat {
        guard layout == .macbook, pill.liveLeftWingWidth > 0 else { return 0 }
        return -(pill.liveLeftWingWidth - pill.liveRightWingWidth) / 2
    }

    private func glyphTint(for phase: PersonalizationPreviewPhase) -> Color? {
        guard preferences.colorByAgent else { return nil }
        return Color(hex: phase.tool.brandColorHex)
    }

    /// What the pill says in this moment, honoring the live-activity mode
    /// exactly like `IslandLiveActivity.resolve`.
    private func liveActivity(for phase: PersonalizationPreviewPhase) -> IslandLiveActivity? {
        let mode = preferences.liveActivity
        guard mode != .off else { return nil }
        switch phase {
        case .idle:
            return nil
        case .working:
            guard mode == .active else { return nil }
            return IslandLiveActivity(
                kind: .working,
                sessionID: "preview-working",
                tool: .claudeCode,
                title: "\(AgentTool.claudeCode.displayName) · docs",
                subtitle: lang.t("settings.appearance.preview.live.working"),
                since: phaseStartedAt.addingTimeInterval(-83),
                otherCount: 0
            )
        case .needsApproval:
            return IslandLiveActivity(
                kind: .needsApproval,
                sessionID: "preview-approval",
                tool: .codex,
                title: "\(AgentTool.codex.displayName) needs approval",
                subtitle: "npm run build",
                since: phaseStartedAt.addingTimeInterval(-4),
                otherCount: 1
            )
        case .finished:
            return IslandLiveActivity(
                kind: .finished,
                sessionID: "preview-finished",
                tool: .geminiCLI,
                title: "\(AgentTool.geminiCLI.displayName) finished",
                subtitle: lang.t("settings.appearance.preview.live.finished"),
                since: nil,
                otherCount: 0
            )
        }
    }

    /// External displays only (the cutout covers that space on a MacBook).
    private func centerLabel(for phase: PersonalizationPreviewPhase) -> String? {
        guard layout == .external, preferences.centerLabel != .off else { return nil }
        switch (phase, preferences.centerLabel) {
        case (.idle, _), (.finished, _):
            return nil
        case (.needsApproval, _):
            return lang.t("settings.appearance.preview.permissionNeeded")
        case (.working, .agentAction):
            return lang.t("settings.appearance.preview.agentEditing")
        case (.working, .sessionName):
            return "docs"
        case (.working, .off):
            return nil
        }
    }

    private func rightSlotContent(for phase: PersonalizationPreviewPhase) -> IslandRightSlotContent? {
        switch preferences.rightSlot {
        case .none:
            return nil
        case .count:
            return .count(3)
        case .agents:
            let claude = Color(hex: AgentTool.claudeCode.brandColorHex) ?? .orange
            let codex = Color(hex: AgentTool.codex.brandColorHex) ?? .blue
            let gemini = Color(hex: AgentTool.geminiCLI.brandColorHex) ?? .green
            switch phase {
            case .idle:
                return .agents([
                    .session(color: claude, state: .idle),
                    .session(color: codex, state: .idle),
                    .session(color: gemini, state: .idle),
                ])
            case .working:
                return .agents([
                    .session(color: claude, state: .running),
                    .session(color: codex, state: .idle),
                    .session(color: gemini, state: .running),
                ])
            case .needsApproval:
                return .agents([
                    .session(color: claude, state: .running),
                    .session(color: codex, state: .waiting),
                    .session(color: gemini, state: .idle),
                ])
            case .finished:
                return .agents([
                    .session(color: claude, state: .running),
                    .session(color: codex, state: .idle),
                    .session(color: gemini, state: .idle),
                ])
            }
        }
    }

    // MARK: Glow + caption

    private var phaseGlow: some View {
        let color: Color = {
            if phase == .idle { return V6Palette.paper }
            if preferences.colorByAgent, phase != .needsApproval {
                return Color(hex: phase.tool.brandColorHex) ?? phase.statusColor
            }
            return phase.statusColor
        }()
        let strength: Double = phase == .idle ? 0.2 : 0.62
        return EllipticalGradient(
            colors: [color.opacity(strength), color.opacity(strength * 0.35), color.opacity(0)],
            center: .center,
            startRadiusFraction: 0,
            endRadiusFraction: 0.5
        )
        .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.7), value: phase)
        .animation(.easeInOut(duration: 0.4), value: preferences.colorByAgent)
        .allowsHitTesting(false)
    }

    private var phaseTitle: String {
        switch phase {
        case .idle:          lang.t("settings.appearance.preview.phase.idle")
        case .working:       lang.t("settings.appearance.preview.phase.working")
        case .needsApproval: lang.t("settings.appearance.preview.phase.waiting")
        case .finished:      lang.t("settings.appearance.preview.phase.finished")
        }
    }

    private var phaseDetail: String {
        let mode = preferences.liveActivity
        switch phase {
        case .idle:
            return lang.t("settings.appearance.preview.phase.idle.detail")
        case .working:
            return mode == .active
                ? lang.t("settings.appearance.preview.phase.working.live")
                : lang.t("settings.appearance.preview.phase.working.detail")
        case .needsApproval:
            return mode == .off
                ? lang.t("settings.appearance.preview.phase.waiting.detail")
                : lang.t("settings.appearance.preview.phase.waiting.live")
        case .finished:
            return mode == .off
                ? lang.t("settings.appearance.preview.phase.finished.detail")
                : lang.t("settings.appearance.preview.phase.finished.live")
        }
    }

    private var caption: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(phase.statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: phase.statusColor.opacity(0.8), radius: 4)

            HStack(spacing: 6) {
                Text(phaseTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(phaseDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.66))
            }
            .lineLimit(1)
            .id(phase)
            .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))

            PreviewPhaseDots(current: phase, isAutoCycling: isAutoCycling)
                .padding(.leading, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background { PreviewChipBackground() }
        .animation(.easeInOut(duration: 0.3), value: phase)
    }
}

/// The hardware cutout: flat top with small concave shoulders, rounded
/// bottom corners. Drawn over the pill, as the real panel sits under it.
private struct HardwareNotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let shoulder: CGFloat = 4
        let bottom: CGFloat = min(10, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + shoulder, y: rect.minY + shoulder),
            control: CGPoint(x: rect.minX + shoulder, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + shoulder + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + shoulder, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - shoulder - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - shoulder, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + shoulder))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - shoulder, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// A sketch of the menu bar the island lives in. Like the real one, it
/// drops the items that would collide with the island.
private struct PreviewMenuBar: View {
    let height: CGFloat
    /// External displays get a visible translucent bar; on a notched Mac
    /// the bar is clear and the items float on the wallpaper.
    let showsBar: Bool
    /// Free width left / right of the pill.
    let leadingRoom: CGFloat
    let trailingRoom: CGFloat

    private let edgeInset: CGFloat = 16
    private let pillGap: CGFloat = 12

    var body: some View {
        HStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                leadingItems(menus: ["File", "Edit", "View"])
                leadingItems(menus: ["File", "Edit"])
                leadingItems(menus: ["File"])
                leadingItems(menus: [])
                appleLogo
                Color.clear.frame(width: 0)
            }
            .frame(width: max(0, leadingRoom - edgeInset - pillGap), alignment: .leading)
            .padding(.leading, edgeInset)

            Spacer(minLength: 0)

            ViewThatFits(in: .horizontal) {
                trailingItems(showsWifi: true, showsBattery: true)
                trailingItems(showsWifi: false, showsBattery: true)
                trailingItems(showsWifi: false, showsBattery: false)
                Color.clear.frame(width: 0)
            }
            .frame(width: max(0, trailingRoom - edgeInset - pillGap), alignment: .trailing)
            .padding(.trailing, edgeInset)
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(1)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background {
            if showsBar {
                Rectangle().fill(.white.opacity(0.1))
            }
        }
        .accessibilityHidden(true)
    }

    private var appleLogo: some View {
        Image(systemName: "apple.logo")
            .font(.system(size: 13.5, weight: .medium))
    }

    private func leadingItems(menus: [String]) -> some View {
        HStack(spacing: 15) {
            appleLogo
            Text("NotchTune")
                .fontWeight(.bold)
            ForEach(menus, id: \.self) { Text($0) }
        }
        .fixedSize()
    }

    private func trailingItems(showsWifi: Bool, showsBattery: Bool) -> some View {
        HStack(spacing: 15) {
            if showsWifi { Image(systemName: "wifi") }
            if showsBattery { Image(systemName: "battery.75percent") }
            Text("Tue 9:41")
        }
        .fixedSize()
    }
}

/// Four dots, one per moment; the current one stretches. While cycling,
/// the current dot fills as the moment plays.
private struct PreviewPhaseDots: View {
    let current: PersonalizationPreviewPhase
    let isAutoCycling: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PersonalizationPreviewPhase.allCases, id: \.self) { phase in
                Capsule()
                    .fill(.white.opacity(phase == current ? 0.9 : 0.3))
                    .frame(width: phase == current ? 14 : 5, height: 5)
            }
        }
        .animation(.smooth(duration: 0.35), value: current)
        .opacity(isAutoCycling ? 1 : 0.7)
    }
}

/// Liquid Glass capsule on macOS 26, a material capsule before that.
private struct PreviewChipBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Wallpaper

/// A dusk wallpaper for the preview stage and the picture tiles: deep indigo
/// into plum with drifting color pools. `animated` lets the pools wander
/// slowly (off for Reduce Motion and for the small tiles).
struct PersonalizationWallpaper: View {
    var animated: Bool = false
    /// Holds the drift (window off screen) without resetting it.
    var paused: Bool = false

    var body: some View {
        if animated {
            // The pools drift over tens of seconds; 20 fps is plenty.
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: paused)) { context in
                layers(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            layers(time: 0)
        }
    }

    private func layers(time t: TimeInterval) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.09, blue: 0.27),
                    Color(red: 0.24, green: 0.12, blue: 0.38),
                    Color(red: 0.47, green: 0.18, blue: 0.42),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            pool(
                Color(red: 1.0, green: 0.40, blue: 0.62),
                opacity: 0.55,
                x: 0.82 + 0.10 * sin(t * 0.21),
                y: 0.95 + 0.08 * cos(t * 0.17),
                radius: 0.75
            )
            pool(
                Color(red: 0.33, green: 0.58, blue: 1.0),
                opacity: 0.45,
                x: 0.12 + 0.10 * cos(t * 0.19),
                y: 0.85 + 0.10 * sin(t * 0.23),
                radius: 0.7
            )
            pool(
                Color(red: 1.0, green: 0.68, blue: 0.36),
                opacity: 0.30,
                x: 0.50 + 0.18 * sin(t * 0.13 + 1.3),
                y: 1.15 + 0.06 * cos(t * 0.29),
                radius: 0.6
            )

            // Darker toward the top so the menu bar and notch read clearly.
            LinearGradient(
                colors: [.black.opacity(0.32), .black.opacity(0)],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.45)
            )
        }
    }

    private func pool(_ color: Color, opacity: Double, x: Double, y: Double, radius: CGFloat) -> some View {
        EllipticalGradient(
            colors: [color.opacity(opacity), color.opacity(0)],
            center: UnitPoint(x: x, y: y),
            startRadiusFraction: 0,
            endRadiusFraction: radius
        )
    }
}
