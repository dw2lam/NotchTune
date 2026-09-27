import AppKit
import SwiftUI

/// Closed-island chrome metrics, resolved once per `IslandDensity`.
///
/// `regular` is the shipped v6 pill; `compact` trims every closed-pill
/// dimension so the pill hugs the physical notch / menu bar. Everything that
/// used to be a bare static on this type is now an instance value so the
/// SwiftUI views (via `\.islandChromeMetrics`), the wing math in
/// `IslandPanelView`, and the controller's hit-area budget all read the same
/// numbers for the active density.
struct IslandChromeMetrics: Equatable, Sendable {
    // MARK: Density-independent (opened panel shadow budget)

    static let openedShadowHorizontalInset: CGFloat = 18
    static let openedShadowBottomInset: CGFloat = 22
    /// Outward top-curve radii (closed pill → opened panel). The opened one
    /// must stay under `openedShadowHorizontalInset`: the ears draw into it.
    static let closedEarRadius: CGFloat = 6
    static let openedEarRadius: CGFloat = 14

    // MARK: Resolved sets

    static let regular = IslandChromeMetrics(density: .regular)
    static let compact = IslandChromeMetrics(density: .compact)

    static func metrics(for density: IslandDensity) -> IslandChromeMetrics {
        switch density {
        case .regular: regular
        case .compact: compact
        }
    }

    let density: IslandDensity

    // MARK: Closed-pill scale effects (x, y)

    /// Hover swell of the closed pill. Compact keeps the y axis at 1 so the
    /// pill never grows taller than the notch it is flush with.
    let closedHoverScale: CGSize
    /// `notchStatus == .popping` pulse.
    let closedPopScale: CGSize
    /// File-drag approach hint ("ready to catch").
    let closedFileDragHintScale: CGSize

    // MARK: Agent pill

    /// Minimum wing width on a notched MacBook (content in the ears).
    let notchedClosedMinimumWingReserve: CGFloat
    /// Outer edge inset before the glyph / after the right slot (MacBook wings).
    let notchedClosedHorizontalPadding: CGFloat
    /// Gap between the glyph / right slot and the wing's inner (notch) edge.
    let notchedClosedContentGap: CGFloat
    /// `UnifiedBars` glyph size in the closed pill.
    let closedGlyphSize: CGFloat

    // MARK: Music surfaces

    /// Outer leading inset before album art on closed music surfaces.
    let notchedMusicLeadingPadding: CGFloat
    /// Trailing outer inset after play icon / waveform on closed music surfaces.
    /// Matches `notchedMusicLeadingPadding` so the compact pill is symmetric
    /// around the notch (album art and trailing cluster get equal breathing room).
    let notchedMusicTrailingPadding: CGFloat
    let albumArtSize: CGFloat
    let albumArtCornerRadius: CGFloat
    let waveformWidth: CGFloat
    let waveformHeight: CGFloat
    let playIconWidth: CGFloat
    let playIconFontSize: CGFloat

    // MARK: Music notification text

    let notificationTitleFontSize: CGFloat
    let notificationArtistFontSize: CGFloat
    let notificationTitleLineHeight: CGFloat
    let notificationArtistLineHeight: CGFloat
    let notificationTextSpacing: CGFloat

    init(density: IslandDensity) {
        self.density = density
        switch density {
        case .regular:
            closedHoverScale = CGSize(width: 1.035, height: 1.035)
            closedPopScale = CGSize(width: 1.04, height: 1.04)
            closedFileDragHintScale = CGSize(width: 1.07, height: 1.07)
            notchedClosedMinimumWingReserve = 44
            notchedClosedHorizontalPadding = 14
            notchedClosedContentGap = 8
            closedGlyphSize = 24
            notchedMusicLeadingPadding = 8
            notchedMusicTrailingPadding = 8
            albumArtSize = 22
            albumArtCornerRadius = 5
            waveformWidth = 20
            waveformHeight = 14
            playIconWidth = 18
            playIconFontSize = 10
            notificationTitleFontSize = 11
            notificationArtistFontSize = 10
            notificationTitleLineHeight = 14
            notificationArtistLineHeight = 12
            notificationTextSpacing = 1
        case .compact:
            // Scale on the x axis only: the pill may swell sideways but never
            // stand taller than the notch / menu bar it is flush with.
            closedHoverScale = CGSize(width: 1.02, height: 1)
            closedPopScale = CGSize(width: 1.03, height: 1)
            closedFileDragHintScale = CGSize(width: 1.05, height: 1)
            notchedClosedMinimumWingReserve = 36
            notchedClosedHorizontalPadding = 10
            notchedClosedContentGap = 6
            closedGlyphSize = 18
            notchedMusicLeadingPadding = 6
            notchedMusicTrailingPadding = 6
            albumArtSize = 18
            albumArtCornerRadius = 4
            waveformWidth = 18
            waveformHeight = 12
            playIconWidth = 16
            playIconFontSize = 9
            // 12 + 0 + 11 = 23pt: fits inside a 24pt external menu-bar pill.
            notificationTitleFontSize = 10.5
            notificationArtistFontSize = 9.5
            notificationTitleLineHeight = 12
            notificationArtistLineHeight = 11
            notificationTextSpacing = 0
        }
    }

    // MARK: Fonts

    var notificationTitleFont: Font {
        .system(size: notificationTitleFontSize, weight: .semibold, design: .monospaced)
    }

    var notificationTitleNSFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: notificationTitleFontSize, weight: .bold)
    }

    var notificationArtistFont: Font {
        .system(size: notificationArtistFontSize, weight: .medium, design: .monospaced)
    }

    var notificationArtistNSFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: notificationArtistFontSize, weight: .medium)
    }

    // MARK: Agent pill wings

    func notchedClosedWingReserve(rightSlotWidth: CGFloat = 0) -> CGFloat {
        let requiredContentWidth = max(closedGlyphSize, rightSlotWidth)
        let requiredReserve = requiredContentWidth
            + notchedClosedHorizontalPadding
            + notchedClosedContentGap
        return max(notchedClosedMinimumWingReserve, ceil(requiredReserve))
    }

    // MARK: Compact music wings

    /// Total outer width of a compact music pill on a notched MacBook.
    func notchedCompactMusicOuterWidth(physicalNotchWidth: CGFloat) -> CGFloat {
        notchedCompactMusicLeftWingReserve()
            + physicalNotchWidth
            + notchedCompactMusicRightWingReserve()
    }

    /// Left wing for compact music — outer leading inset plus album art against the notch.
    func notchedCompactMusicLeftWingReserve() -> CGFloat {
        notchedMusicLeadingPadding + albumArtSize
    }

    /// Right wing for compact music — waveform against the notch, trailing outer inset.
    func notchedCompactMusicRightWingReserve() -> CGFloat {
        ceil(waveformWidth + notchedMusicTrailingPadding)
    }

    // MARK: Music notification wings

    /// Max left-wing width before the notch-anchored pill extends past the panel edge.
    func notchedMusicNotificationMaxLeftWingReserve(
        panelContentWidth: CGFloat,
        physicalNotchWidth: CGFloat
    ) -> CGFloat {
        guard panelContentWidth > 0 else { return .greatestFiniteMagnitude }
        return max(0, floor(panelContentWidth / 2 - physicalNotchWidth / 2))
    }

    private var notchedMusicNotificationFixedLeftChromeWidth: CGFloat {
        notchedMusicLeadingPadding + albumArtSize + notchedClosedContentGap
    }

    /// Left wing for music notifications — album art plus stacked title/artist.
    func notchedMusicNotificationLeftWingReserve(
        title: String,
        artist: String,
        panelContentWidth: CGFloat = .greatestFiniteMagnitude,
        physicalNotchWidth: CGFloat = 0
    ) -> CGFloat {
        let textReserve = estimatedTextBlockWidth(title: title, artist: artist)
        let required = notchedMusicNotificationFixedLeftChromeWidth + textReserve
        let ideal = ceil(required)
        guard physicalNotchWidth > 0, panelContentWidth < .greatestFiniteMagnitude else {
            return ideal
        }
        return min(ideal, notchedMusicNotificationMaxLeftWingReserve(
            panelContentWidth: panelContentWidth,
            physicalNotchWidth: physicalNotchWidth
        ))
    }

    /// Right wing for music notifications — play/pause icon pinned to the outer edge.
    func notchedMusicNotificationRightWingReserve() -> CGFloat {
        ceil(notchedMusicTrailingPadding + playIconWidth)
    }

    func notchedMusicNotificationLeftTextWidth(
        title: String,
        artist: String,
        panelContentWidth: CGFloat = .greatestFiniteMagnitude,
        physicalNotchWidth: CGFloat = 0
    ) -> CGFloat {
        let leftWing = notchedMusicNotificationLeftWingReserve(
            title: title,
            artist: artist,
            panelContentWidth: panelContentWidth,
            physicalNotchWidth: physicalNotchWidth
        )
        let available = leftWing - notchedMusicNotificationFixedLeftChromeWidth
        let desired = estimatedTextBlockWidth(title: title, artist: artist)
        return min(desired, max(MusicTrackNotificationMetrics.minimumTextWidth, available))
    }

    // MARK: Music notification width estimates

    func estimatedMusicOuterWidth(
        for layout: V6ClosedLayout,
        track: PlayerTrack,
        physicalNotchWidth: CGFloat,
        panelContentWidth: CGFloat = .greatestFiniteMagnitude
    ) -> CGFloat {
        switch layout {
        case .external:
            return min(estimatedExternalMusicWidth(track: track), panelContentWidth)
        case .macbook:
            let leftWing = notchedMusicNotificationLeftWingReserve(
                title: track.title,
                artist: track.artist,
                panelContentWidth: panelContentWidth,
                physicalNotchWidth: physicalNotchWidth
            )
            let rightWing = notchedMusicNotificationRightWingReserve()
            return leftWing + physicalNotchWidth + rightWing
        }
    }

    func estimatedTextBlockWidth(title: String, artist: String) -> CGFloat {
        let natural = max(intrinsicTitleWidth(title), intrinsicArtistWidth(artist))
        return min(
            max(natural, MusicTrackNotificationMetrics.minimumTextWidth),
            MusicTrackNotificationMetrics.maximumTextWidth
        )
    }

    func estimatedExternalMusicWidth(track: PlayerTrack) -> CGFloat {
        let textWidth = estimatedTextBlockWidth(title: track.title, artist: track.artist)
        return notchedMusicLeadingPadding
            + albumArtSize
            + notchedClosedContentGap
            + textWidth
            + notchedClosedContentGap
            + playIconWidth
            + notchedMusicTrailingPadding
    }

    func intrinsicTitleWidth(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let width = (text as NSString).size(withAttributes: [.font: notificationTitleNSFont]).width
        return ceil(width) + MusicTrackNotificationMetrics.measurementFudge
    }

    func intrinsicArtistWidth(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let width = (text as NSString).size(withAttributes: [.font: notificationArtistNSFont]).width
        return ceil(width) + MusicTrackNotificationMetrics.measurementFudge
    }
}

/// Density-independent text budget for the music notification pill.
enum MusicTrackNotificationMetrics {
    static let minimumTextWidth: CGFloat = 48
    static let maximumTextWidth: CGFloat = 300
    static let measurementFudge: CGFloat = 14
}

// MARK: - SwiftUI environment

private struct IslandChromeMetricsEnvironmentKey: EnvironmentKey {
    static let defaultValue = IslandChromeMetrics.regular
}

extension EnvironmentValues {
    /// Closed-island metrics for the active density. Injected at the root of
    /// `IslandPanelView` (and the settings preview) so `V6ClosedPill` /
    /// `V6ClosedMusicSurface` never have to be threaded a density by hand.
    var islandChromeMetrics: IslandChromeMetrics {
        get { self[IslandChromeMetricsEnvironmentKey.self] }
        set { self[IslandChromeMetricsEnvironmentKey.self] = newValue }
    }
}
