import AppKit
import SwiftUI
import NotchTuneCore

/// Per-cell state for the closed-island agents grid. Drives tile rendering:
/// running = full color, idle = dim, waiting = opacity pulse.
enum AgentGridCellState: Equatable {
    case running
    case idle
    case waiting
}

/// One cell in the closed-island agents grid. `.session` carries the agent
/// tool's brand color and its current state. `.overflow` is a single trailing
/// cell shown when there are more sessions than the grid can display.
enum AgentGridCell: Equatable {
    case session(color: Color, state: AgentGridCellState)
    case overflow(Int)
}

/// Concrete payload for the closed island's right slot. The `AppModel`
/// computes one of these from live session state according to the user's
/// `islandRightSlot` preference; the view side is agnostic to which
/// setting produced it.
enum IslandRightSlotContent: Equatable {
    case count(Int)              // "×N" badge
    case agents([AgentGridCell]) // balanced grid, one tile per session
}

// MARK: - Right-slot renderers

struct V6RightSlotView: View {
    let content: IslandRightSlotContent

    var body: some View {
        switch content {
        case .count(let n):
            Text("×\(n)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(V6Palette.paper.opacity(0.72))
        case .agents(let cells):
            AgentsGridBody(cells: cells)
        }
    }

    /// Intrinsic width used by the fluid-layout math. Values are slightly
    /// padded beyond the raw text measurement so the pill always reserves
    /// enough room for the `.fixedSize()` content to render on one line,
    /// without HStack compression forcing a wrap.
    static func intrinsicWidth(of content: IslandRightSlotContent) -> CGFloat {
        switch content {
        case .count(let n):
            let digits = Double(max(1, String(n).count))
            // "×" + digits at 11pt mono ≈ 7.2pt/char.
            return CGFloat(14.4 + max(0.0, digits - 1.0) * 7.2)
        case .agents(let cells):
            let n = cells.count
            guard n > 0 else { return 0 }
            let rows = balancedRows(n)
            let maxRow = rows.max() ?? 0
            let geom = cellGeometry(rowCount: rows.count)
            return CGFloat(maxRow) * geom.cell + CGFloat(max(0, maxRow - 1)) * geom.gap
        }
    }

    // MARK: Balanced layout algorithm
    //
    // For each n from 1 to 9, we hand-tune the per-row cell counts so the
    // matrix reads as a deliberate shape instead of a wrap-at-4-columns grid.
    // For n >= 10 the AppModel caps the list at 7 sessions + 1 overflow cell,
    // which lays out as [4,4] — so balancedRows(8) is what actually renders
    // for all high-count cases in production.
    static func balancedRows(_ n: Int) -> [Int] {
        switch n {
        case ..<1: return []
        case 1: return [1]
        case 2: return [2]
        case 3: return [3]
        case 4: return [2, 2]
        case 5: return [3, 2]
        case 6: return [3, 3]
        case 7: return [4, 3]
        case 8: return [4, 4]
        case 9: return [3, 3, 3]
        default: return [4, 4]
        }
    }

    /// Cell size shrinks when the matrix has 3 rows so total height still
    /// fits inside the pill's internal vertical budget (~20pt).
    static func cellGeometry(rowCount: Int) -> (cell: CGFloat, gap: CGFloat, radius: CGFloat) {
        if rowCount >= 3 { return (cell: 6, gap: 1.5, radius: 1.0) }
        return (cell: 8, gap: 2, radius: 1.5)
    }

    static func splitIntoRows(_ cells: [AgentGridCell], rowSizes: [Int]) -> [[AgentGridCell]] {
        var out: [[AgentGridCell]] = []
        var idx = 0
        for size in rowSizes {
            let end = min(idx + size, cells.count)
            out.append(Array(cells[idx..<end]))
            idx = end
            if idx >= cells.count { break }
        }
        return out
    }
}

// MARK: - Agents grid body

/// V1a Dense Grid renderer. 2D matrix of 8×8 rounded squares (6×6 when 3 rows),
/// each row horizontally centered around the widest row. Running = full color,
/// idle = 22% alpha, waiting = opacity 0.35 ↔ 1 breathing pulse.
private struct AgentsGridBody: View {
    let cells: [AgentGridCell]

    var body: some View {
        let rowSizes = V6RightSlotView.balancedRows(cells.count)
        let geom = V6RightSlotView.cellGeometry(rowCount: rowSizes.count)
        let rows = V6RightSlotView.splitIntoRows(cells, rowSizes: rowSizes)

        VStack(spacing: geom.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: geom.gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        AgentsGridTileView(cell: cell, size: geom.cell, radius: geom.radius)
                    }
                }
            }
        }
        .fixedSize()
    }
}

private struct AgentsGridTileView: View {
    let cell: AgentGridCell
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        switch cell {
        case .session(let color, let state):
            switch state {
            case .running:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
            case .idle:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color.opacity(0.22))
                    .frame(width: size, height: size)
            case .waiting:
                AgentsGridWaitingTile(color: color, size: size, radius: radius)
            }
        case .overflow(let n):
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(V6Palette.paper.opacity(0.14))
                Text("+\(n)")
                    .font(.system(size: max(5, size * 0.55), weight: .bold, design: .monospaced))
                    .foregroundStyle(V6Palette.paper)
            }
            .frame(width: size, height: size)
        }
    }
}

private struct AgentsGridWaitingTile: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .opacity(pulse ? 1.0 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Center label renderer

struct V6CenterLabelView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(V6Palette.paper)
    }

    static func intrinsicWidth(of text: String) -> CGFloat {
        CGFloat(Double(text.count) * 7.3 + 10)
    }
}

// MARK: - Closed-pill layouts

/// The canonical v6 closed-island pill rendered inside a fixed-height frame.
/// Pure view — takes all parameters explicitly so it can be reused for the
/// live settings preview and the real island.
struct V6ClosedPill: View {
    var mode: UnifiedBars.Mode
    var character: IslandCharacter = .dino
    var label: String?          // suppressed automatically in MacBook layout
    var rightSlot: IslandRightSlotContent?
    var layout: V6ClosedLayout
    var height: CGFloat = 32

    /// MacBook mode only — width of the physical notch cutout to wrap.
    var physicalNotchWidth: CGFloat = 0

    /// External mode only — minimum pill width (locked). Defaults to the
    /// width that fits just the glyph.
    var minWidth: CGFloat = 70

    /// Liquid Glass material for the pill background. `nil` renders solid ink.
    var glass: ResolvedGlass? = nil

    /// Freeze the animated glyph when the pill is hidden/off-screen.
    var glyphPaused: Bool = false

    /// Changes to trigger a one-shot jump on the glyph (idle-session nudge).
    var nudgeTrigger: UUID? = nil

    /// "Color by agent": the character's tint; `nil` keeps the paper ink.
    var glyphTint: Color? = nil

    /// MacBook mode only — when set, the wings widen to `liveWingWidth` and
    /// carry the activity's text + timer instead of the glyph/right slot.
    var liveActivity: IslandLiveActivity? = nil
    var liveLeftWingWidth: CGFloat = 0
    var liveRightWingWidth: CGFloat = 0

    @Environment(\.islandChromeMetrics) private var metrics

    var body: some View {
        switch layout {
        case .external:
            if let liveActivity {
                externalLiveActivityBody(liveActivity)
            } else {
                externalBody
            }
        case .macbook:
            if let liveActivity, liveLeftWingWidth > 0 {
                liveActivityBody(liveActivity)
            } else {
                macbookBody
            }
        }
    }

    // MARK: External live activity (single line — menu bars are ~24pt)

    private func externalLiveActivityBody(_ activity: IslandLiveActivity) -> some View {
        let glyphW = metrics.closedGlyphSize
        let width = activity.externalPillWidth(metrics: metrics, height: height, minWidth: minWidth)

        return ZStack {
            IslandSurfaceBackground(
                shape: V6ClosedPillShape(topFilletRadius: 0),
                glass: glass
            )

            HStack(spacing: 0) {
                UnifiedBars(mode: mode, size: glyphW, character: character, paused: glyphPaused, nudgeTrigger: nudgeTrigger, tint: glyphTint ?? UnifiedBars.paperInk)
                    .frame(width: glyphW, height: glyphW)

                LiveActivityInlineText(activity: activity, metrics: metrics)
                    .padding(.leading, 8)
                    .id(activity.sessionID + String(describing: activity.kind))
                    .transition(.opacity)

                Spacer(minLength: Self.innerGap)

                LiveActivityTrailingView(activity: activity, metrics: metrics)
            }
            .padding(.horizontal, pad)
        }
        .frame(width: width, height: height)
        .animation(.smooth(duration: 0.45, extraBounce: 0.08), value: width)
    }

    // MARK: MacBook live activity (widened wings)

    private func liveActivityBody(_ activity: IslandLiveActivity) -> some View {
        let leftWing = liveLeftWingWidth
        let rightWing = max(liveRightWingWidth, metrics.notchedClosedMinimumWingReserve)
        let glyphW = metrics.closedGlyphSize

        return ZStack {
            IslandSurfaceBackground(
                shape: V6ClosedPillShape(topFilletRadius: 0),
                glass: glass
            )

            HStack(spacing: 0) {
                HStack(spacing: metrics.notchedClosedContentGap) {
                    UnifiedBars(mode: mode, size: glyphW, character: character, paused: glyphPaused, nudgeTrigger: nudgeTrigger, tint: glyphTint ?? UnifiedBars.paperInk)
                        .frame(width: glyphW, height: glyphW)

                    LiveActivityTextBlock(activity: activity, metrics: metrics)
                        .id(activity.sessionID + String(describing: activity.kind))
                        .transition(.opacity.combined(with: .move(edge: .leading)))

                    Spacer(minLength: 0)
                }
                .padding(.leading, metrics.notchedClosedHorizontalPadding)
                .frame(width: leftWing, alignment: .leading)
                .clipped()

                Color.clear
                    .frame(width: physicalNotchWidth)

                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    LiveActivityTrailingView(activity: activity, metrics: metrics)
                        .transition(.opacity)
                }
                .padding(.trailing, metrics.notchedClosedHorizontalPadding)
                .frame(width: rightWing, alignment: .trailing)
            }
        }
        .frame(width: leftWing + physicalNotchWidth + rightWing, height: height)
        .animation(.smooth(duration: 0.45, extraBounce: 0.08), value: leftWing + rightWing)
        .animation(.easeInOut(duration: 0.25), value: activity)
    }

    // Horizontal edge padding is identical left/right — canonical v6 pill
    // has r = h/2 semicircular bottoms, so edge inset = r keeps content
    // clear of the curve.
    private var pad: CGFloat { height / 2 }

    // Minimum breathing room between the center label (or glyph, when no
    // label) and the right-slot content so they never touch at small widths.
    private static let innerGap: CGFloat = 6

    // MARK: External (fluid)

    private var externalBody: some View {
        let glyphW: CGFloat = metrics.closedGlyphSize
        let labelW = label.map { V6CenterLabelView.intrinsicWidth(of: $0) } ?? 0
        let rightW = rightSlot.map { V6RightSlotView.intrinsicWidth(of: $0) } ?? 0

        let labelBlock = (label == nil ? 0 : 6 + labelW)
        let rightBlock = (rightSlot == nil ? 0 : Self.innerGap + rightW)
        let intrinsic = pad * 2 + glyphW + labelBlock + rightBlock
        let width = max(minWidth, intrinsic)

        return ZStack {
            IslandSurfaceBackground(
                shape: V6ClosedPillShape(topFilletRadius: 0),
                glass: glass
            )

            HStack(spacing: 0) {
                UnifiedBars(mode: mode, size: glyphW, character: character, paused: glyphPaused, nudgeTrigger: nudgeTrigger, tint: glyphTint ?? UnifiedBars.paperInk)
                    .frame(width: glyphW, height: glyphW)

                if let label {
                    V6CenterLabelView(text: label)
                        .padding(.leading, 6)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: Self.innerGap)

                if let rightSlot {
                    V6RightSlotView(content: rightSlot)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, pad)
        }
        .frame(width: width, height: height)
        .animation(
            .smooth(duration: 0.4, extraBounce: 0.1),
            value: AnyHashable([
                AnyHashable(label ?? ""),
                AnyHashable(rightSlot.map(RightSlotKey.init) ?? .none),
                AnyHashable(mode),
                AnyHashable(character),
            ])
        )
    }

    // MARK: MacBook (outer width locked)

    private var macbookBody: some View {
        let rightWidth = rightSlot.map { V6RightSlotView.intrinsicWidth(of: $0) } ?? 0
        let wingReserve = metrics.notchedClosedWingReserve(rightSlotWidth: rightWidth)
        let outer = wingReserve + physicalNotchWidth + wingReserve
        let glyphW = metrics.closedGlyphSize

        return ZStack {
            IslandSurfaceBackground(
                shape: V6ClosedPillShape(topFilletRadius: 0),
                glass: glass
            )

            HStack(spacing: 0) {
                HStack {
                    UnifiedBars(mode: mode, size: glyphW, character: character, paused: glyphPaused, nudgeTrigger: nudgeTrigger, tint: glyphTint ?? UnifiedBars.paperInk)
                        .frame(width: glyphW, height: glyphW)
                    Spacer(minLength: 0)
                }
                .padding(.leading, metrics.notchedClosedHorizontalPadding)
                .frame(width: wingReserve)

                Color.clear
                    .frame(width: physicalNotchWidth)

                if let rightSlot {
                    HStack {
                        Spacer(minLength: 0)
                        V6RightSlotView(content: rightSlot)
                    }
                    .padding(.trailing, metrics.notchedClosedHorizontalPadding)
                    .frame(width: wingReserve)
                } else {
                    Color.clear
                        .frame(width: wingReserve)
                }
            }
        }
        .frame(width: outer, height: height)
    }
}

enum V6ClosedLayout: Equatable {
    case external
    case macbook
}

// MARK: - Music track notification (closed)

struct MusicNotificationClipMetrics: Equatable {
    var width: CGFloat = 0
    var leftWingWidth: CGFloat = 0
}

enum MusicNotificationClipMetricsKey: PreferenceKey {
    static let defaultValue = MusicNotificationClipMetrics()
    static func reduce(value: inout MusicNotificationClipMetrics, nextValue: () -> MusicNotificationClipMetrics) {
        let next = nextValue()
        if next.width > 0 {
            value = next
        }
    }
}

// MARK: - Music notification marquee text

private struct MusicNotificationMarqueeText: View {
    let text: String
    let font: Font
    let nsFont: NSFont
    let foregroundStyle: Color
    let lineHeight: CGFloat
    let maxWidth: CGFloat
    /// Measured once at init — the text/font are immutable, so there's no reason
    /// to re-run Core Text measurement inside the per-frame scroll timeline.
    private let intrinsicWidth: CGFloat

    init(text: String, font: Font, nsFont: NSFont, foregroundStyle: Color, lineHeight: CGFloat, maxWidth: CGFloat) {
        self.text = text
        self.font = font
        self.nsFont = nsFont
        self.foregroundStyle = foregroundStyle
        self.lineHeight = lineHeight
        self.maxWidth = maxWidth
        self.intrinsicWidth = text.isEmpty
            ? 0
            : ceil((text as NSString).size(withAttributes: [.font: nsFont]).width)
    }

    private var shouldScroll: Bool {
        maxWidth > 0 && intrinsicWidth > maxWidth + 1
    }

    var body: some View {
        Group {
            if shouldScroll {
                scrollingLabel
            } else {
                label
                    .frame(maxWidth: max(maxWidth, 0), alignment: .leading)
            }
        }
        .frame(width: max(maxWidth, 0), height: lineHeight, alignment: .leading)
        .clipped()
    }

    private var scrollingLabel: some View {
        TimelineView(.animation) { timeline in
            let gap: CGFloat = 20
            let overflow = intrinsicWidth - maxWidth
            let travel = overflow + gap
            let speed: CGFloat = 30
            let pause: Double = 1.1
            let scrollDuration = max(0.8, Double(travel / speed))
            let cycle = (pause + scrollDuration) * 2
            let t = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: cycle)
            let offset: CGFloat = {
                if t < pause { return 0 }
                if t < pause + scrollDuration {
                    let progress = (t - pause) / scrollDuration
                    return -CGFloat(progress) * travel
                }
                if t < pause + scrollDuration + pause {
                    return -travel
                }
                let progress = (t - pause - scrollDuration - pause) / scrollDuration
                return -travel + CGFloat(progress) * travel
            }()

            HStack(spacing: gap) {
                label
                label
            }
            .offset(x: offset)
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

enum V6ClosedMusicSurfacePhase: Equatable {
    case notification
    case compact
}

enum V6ClosedMusicSurfaceMetrics {
    static let morphAnimation = Animation.easeInOut(duration: 0.58)
}

private struct MusicClosedAlbumArtThumbnail: View {
    let nsImage: NSImage
    let size: CGFloat
    let cornerRadius: CGFloat

    private var hasLoadedArt: Bool {
        nsImage.size.width > 0 && nsImage.size.height > 0
    }

    var body: some View {
        Group {
            if hasLoadedArt {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(V6Palette.paper.opacity(0.35))
                    .padding(4)
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

/// Unified closed music surface. Morphs between the transient track notification
/// (title/artist) and the persistent compact view (album art + waveform).
struct V6ClosedMusicSurface: View {
    let track: PlayerTrack
    let albumArtNSImage: NSImage
    let isPlaying: Bool
    let phase: V6ClosedMusicSurfacePhase
    var layout: V6ClosedLayout
    var height: CGFloat
    var physicalNotchWidth: CGFloat = 0
    var panelContentWidth: CGFloat = .greatestFiniteMagnitude

    /// Liquid Glass material for the surface background. `nil` renders solid ink.
    var glass: ResolvedGlass? = nil

    @Environment(\.islandChromeMetrics) private var metrics

    private var isNotification: Bool { phase == .notification }

    var body: some View {
        Group {
            switch layout {
            case .external: externalBody
            case .macbook:  macbookBody
            }
        }
        .animation(V6ClosedMusicSurfaceMetrics.morphAnimation, value: phase)
    }

    // MARK: MacBook

    private var macbookBody: some View {
        let textWidth = metrics.notchedMusicNotificationLeftTextWidth(
            title: track.title,
            artist: track.artist,
            panelContentWidth: panelContentWidth,
            physicalNotchWidth: physicalNotchWidth
        )
        let notificationLeftWing = metrics.notchedMusicNotificationLeftWingReserve(
            title: track.title,
            artist: track.artist,
            panelContentWidth: panelContentWidth,
            physicalNotchWidth: physicalNotchWidth
        )
        let compactLeftWing = metrics.notchedCompactMusicLeftWingReserve()
        let compactRightWing = metrics.notchedCompactMusicRightWingReserve()
        let notificationRightWing = metrics.notchedMusicNotificationRightWingReserve()
        let leftWing = isNotification ? notificationLeftWing : compactLeftWing
        let rightWing = isNotification ? notificationRightWing : compactRightWing
        let outer = leftWing + physicalNotchWidth + rightWing

        return ZStack(alignment: .topLeading) {
            IslandSurfaceBackground(
                shape: V6ClosedPillShape(topFilletRadius: 0),
                glass: glass
            )

            HStack(spacing: 0) {
                macbookLeftWing(
                    leftWing: leftWing,
                    textWidth: textWidth
                )

                Color.clear
                    .frame(width: physicalNotchWidth)

                macbookRightWing(width: rightWing)
            }
            .frame(width: outer, height: height, alignment: .leading)
        }
        .frame(width: outer, height: height, alignment: .topLeading)
        .background(macbookClipReporter(
            width: outer,
            leftWing: leftWing
        ))
    }

    private var musicLeadingInset: some View {
        Color.clear
            .frame(width: metrics.notchedMusicLeadingPadding)
    }

    private var musicTrailingInset: some View {
        Color.clear
            .frame(width: metrics.notchedMusicTrailingPadding)
    }

    private func macbookLeftWing(leftWing: CGFloat, textWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            musicLeadingInset

            if isNotification {
                HStack(spacing: metrics.notchedClosedContentGap) {
                    sharedAlbumArt
                        .layoutPriority(1)

                    notificationTextBlock(maxWidth: textWidth)
                        .opacity(1)
                        .frame(width: textWidth, alignment: .leading)
                        .clipped()

                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    sharedAlbumArt
                        .layoutPriority(1)
                }
            }
        }
        .frame(width: leftWing, height: height, alignment: .leading)
    }

    @ViewBuilder
    private func macbookRightWing(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                playStateIcon
                musicTrailingInset
            }
            .frame(width: width, height: height, alignment: .leading)
            .opacity(isNotification ? 1 : 0)

            HStack(spacing: 0) {
                MusicWaveformView(isPlaying: isPlaying && !isNotification, color: track.avgAlbumColor)
                Spacer(minLength: 0)
                musicTrailingInset
            }
            .frame(width: width, height: height, alignment: .leading)
            .opacity(isNotification ? 0 : 1)
        }
        .frame(width: width, height: height, alignment: .leading)
    }

    @ViewBuilder
    private func macbookClipReporter(width: CGFloat, leftWing: CGFloat) -> some View {
        if isNotification {
            GeometryReader { geo in
                Color.clear.preference(
                    key: MusicNotificationClipMetricsKey.self,
                    value: MusicNotificationClipMetrics(
                        width: geo.size.width,
                        leftWingWidth: leftWing
                    )
                )
            }
        }
    }

    // MARK: External

    private var externalRenderedTextWidth: CGFloat {
        let chrome: CGFloat =
            metrics.notchedMusicLeadingPadding
            + metrics.albumArtSize
            + metrics.notchedClosedContentGap
            + metrics.notchedMusicTrailingPadding
            + metrics.playIconWidth
        let available = panelContentWidth - chrome
        let maxText = min(
            MusicTrackNotificationMetrics.maximumTextWidth,
            max(MusicTrackNotificationMetrics.minimumTextWidth, available)
        )
        return min(
            maxText,
            metrics.estimatedTextBlockWidth(
                title: track.title,
                artist: track.artist
            )
        )
    }

    private var externalBody: some View {
        HStack(spacing: metrics.notchedClosedContentGap) {
            musicLeadingInset

            sharedAlbumArt
                .layoutPriority(1)

            notificationTextBlock(maxWidth: externalRenderedTextWidth)
                .opacity(1)
                .frame(width: externalRenderedTextWidth, alignment: .leading)
                .clipped()
                .allowsHitTesting(true)

            Spacer(minLength: 0)

            ZStack {
                playStateIcon
                    .opacity(isNotification ? 1 : 0)
                MusicWaveformView(isPlaying: isPlaying && !isNotification, color: track.avgAlbumColor)
                    .opacity(isNotification ? 0 : 1)
            }

            musicTrailingInset
        }
        .frame(height: height)
        .fixedSize(horizontal: true, vertical: true)
        .background {
            IslandSurfaceBackground(
                shape: V6ClosedPillShape(topFilletRadius: 0),
                glass: glass
            )
        }
        .background(externalClipReporter)
    }

    @ViewBuilder
    private var externalClipReporter: some View {
        if isNotification {
            GeometryReader { geo in
                Color.clear.preference(
                    key: MusicNotificationClipMetricsKey.self,
                    value: MusicNotificationClipMetrics(
                        width: geo.size.width,
                        leftWingWidth: 0
                    )
                )
            }
        }
    }

    // MARK: Shared chrome

    private var sharedAlbumArt: some View {
        MusicClosedAlbumArtThumbnail(
            nsImage: albumArtNSImage,
            size: metrics.albumArtSize,
            cornerRadius: metrics.albumArtCornerRadius
        )
    }

    private func notificationTextBlock(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: metrics.notificationTextSpacing) {
            MusicNotificationMarqueeText(
                text: track.title,
                font: metrics.notificationTitleFont,
                nsFont: metrics.notificationTitleNSFont,
                foregroundStyle: V6Palette.paper,
                lineHeight: metrics.notificationTitleLineHeight,
                maxWidth: maxWidth
            )
            MusicNotificationMarqueeText(
                text: track.artist,
                font: metrics.notificationArtistFont,
                nsFont: metrics.notificationArtistNSFont,
                foregroundStyle: V6Palette.paper.opacity(0.55),
                lineHeight: metrics.notificationArtistLineHeight,
                maxWidth: maxWidth
            )
        }
        .frame(width: maxWidth, alignment: .leading)
    }

    private var playStateIcon: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: metrics.playIconFontSize, weight: .bold))
            .foregroundStyle(track.avgAlbumColor)
            .frame(width: metrics.playIconWidth,
                   height: metrics.playIconWidth)
    }
}

struct MusicWaveformView: View {
    let isPlaying: Bool
    let color: Color

    @Environment(\.islandChromeMetrics) private var metrics

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                MusicWaveformBar(index: index, isPlaying: isPlaying, color: color)
            }
        }
        .frame(width: metrics.waveformWidth, height: metrics.waveformHeight)
    }
}

private struct MusicWaveformBar: View {
    let index: Int
    let isPlaying: Bool
    let color: Color

    @State private var scale: CGFloat = 0.3

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 2.2)
            .scaleEffect(y: scale, anchor: .center)
            .onAppear {
                startAnimation()
            }
            .onChange(of: isPlaying) { _, _ in
                startAnimation()
            }
    }

    private func startAnimation() {
        if isPlaying {
            let durations: [Double] = [1.05, 0.82, 0.82, 1.05]
            let delays: [Double] = [0.16, 0, 0, 0.16]
            let duration = durations[index % durations.count]
            let delay = delays[index % delays.count]
            withAnimation(
                .linear(duration: duration)
                    .delay(delay)
                    .repeatForever(autoreverses: true)
            ) {
                scale = 1.0
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                scale = 0.3
            }
        }
    }
}

private enum RightSlotKey: Hashable {
    case count(Int)
    case agents(Int)

    init(_ content: IslandRightSlotContent) {
        switch content {
        case .count(let n):    self = .count(n)
        case .agents(let cs):  self = .agents(cs.count)
        }
    }
}

// MARK: - Settings-tab live preview

/// Fixed-width pill that mimics the real island inside the settings-tab
/// preview stage. Parameters match what the tab exposes.
struct IslandPreviewPill: View {
    let mode: UnifiedBars.Mode
    let character: IslandCharacter
    let label: String?
    let rightSlot: IslandRightSlotContent?
    let layout: V6ClosedLayout
    var height: CGFloat = 32
    let physicalNotchWidth: CGFloat
    let now: Date

    var body: some View {
        V6ClosedPill(
            mode: mode,
            character: character,
            label: label,
            rightSlot: rightSlot,
            layout: layout,
            height: height,
            physicalNotchWidth: physicalNotchWidth
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Live activity pieces

/// Two-line text for the widened pill: title over what the agent is doing.
private struct LiveActivityTextBlock: View {
    let activity: IslandLiveActivity
    let metrics: IslandChromeMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.notificationTextSpacing) {
            Text(activity.title)
                .font(metrics.notificationTitleFont.weight(.semibold))
                .foregroundStyle(LiveActivityPalette.titleColor(for: activity.kind))
                .frame(height: metrics.notificationTitleLineHeight, alignment: .leading)

            if let subtitle = activity.subtitle {
                Text(subtitle)
                    .font(metrics.notificationArtistFont)
                    .foregroundStyle(V6Palette.paper.opacity(0.58))
                    .frame(height: metrics.notificationArtistLineHeight, alignment: .leading)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: IslandLiveActivity.maxTextWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One-line variant for the short external menu-bar pill.
private struct LiveActivityInlineText: View {
    let activity: IslandLiveActivity
    let metrics: IslandChromeMetrics

    var body: some View {
        HStack(spacing: 0) {
            Text(activity.title)
                .font(metrics.notificationTitleFont.weight(.semibold))
                .foregroundStyle(LiveActivityPalette.titleColor(for: activity.kind))
                .layoutPriority(1)
            if let subtitle = activity.subtitle {
                Text("  " + subtitle)
                    .font(metrics.notificationArtistFont)
                    .foregroundStyle(V6Palette.paper.opacity(0.55))
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

enum LiveActivityPalette {
    static func titleColor(for kind: IslandLiveActivity.Kind) -> Color {
        switch kind {
        case .working:       return V6Palette.paper.opacity(0.92)
        case .needsApproval: return IslandDesignPalette.Status.waitingForApproval
        case .needsAnswer:   return IslandDesignPalette.Status.waitingForAnswer
        case .finished:      return IslandDesignPalette.Status.completed
        }
    }
}

/// Right wing: a live timer (working / waiting) or a check mark (finished),
/// plus "+N" when other sessions are live.
private struct LiveActivityTrailingView: View {
    let activity: IslandLiveActivity
    let metrics: IslandChromeMetrics

    var body: some View {
        HStack(spacing: 5) {
            if activity.otherCount > 0 {
                Text("+\(activity.otherCount)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(V6Palette.paper.opacity(0.55))
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(.white.opacity(0.1), in: Capsule())
            }

            switch activity.kind {
            case .finished:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IslandDesignPalette.Status.completed)
                    .symbolEffect(.bounce, value: activity.sessionID)
            case .working, .needsApproval, .needsAnswer:
                if let since = activity.since {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(IslandLiveActivity.elapsedText(since: since, now: context.date))
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(timerColor)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .fixedSize()
    }

    private var timerColor: Color {
        switch activity.kind {
        case .needsApproval: return IslandDesignPalette.Status.waitingForApproval
        case .needsAnswer:   return IslandDesignPalette.Status.waitingForAnswer
        default:             return V6Palette.paper.opacity(0.5)
        }
    }
}
