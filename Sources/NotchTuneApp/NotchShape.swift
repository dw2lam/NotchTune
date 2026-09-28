import SwiftUI

// MARK: - Morphing expand/collapse shape (from Top Notch)
//
// Clip mask that interpolates from the compact pill (progress=0) to the
// fully expanded panel (progress=1). The frame is always the expanded size;
// at progress=0 only the compact-pill rect at the top-centre is visible.

struct GrowingNotchShape: Shape {
    var progress: CGFloat
    var compactW: CGFloat
    var compactH: CGFloat
    var expandedW: CGFloat
    var expandedH: CGFloat
    var compactR: CGFloat = 6
    var expandedR: CGFloat = 22
    /// When set with `compactNotchGapWidth`, anchors the compact clip so the
    /// notch gap lines up with the physical cutout instead of centering the
    /// whole pill (required for asymmetric wings).
    var compactLeftWingWidth: CGFloat = 0
    var compactNotchGapWidth: CGFloat = 0
    /// Outward top curve ("ears"): concave flares where the surface meets the
    /// screen's top edge, drawn OUTSIDE the body so they never eat content
    /// width. Interpolates closed → opened with `progress`; 0 disables.
    var compactEarRadius: CGFloat = 0
    var expandedEarRadius: CGFloat = 0
    /// Extends the top edge this far ABOVE the rect (off the top of the
    /// screen), so an outline stroke or the Liquid Glass rim never draws a
    /// light line along the screen edge — the surface reads as continuous
    /// with the hardware notch / menu bar.
    var topOverscan: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, compactW) }
        set {
            progress = newValue.first
            compactW = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = compactW + (expandedW - compactW) * progress
        let h = compactH + (expandedH - compactH) * progress
        let r = min(compactR + (expandedR - compactR) * progress, h / 2, w / 2)
        let e = max(0, min(compactEarRadius + (expandedEarRadius - compactEarRadius) * progress, h - r))

        let compactX: CGFloat
        if compactNotchGapWidth > 0 {
            compactX = rect.midX - compactLeftWingWidth - compactNotchGapWidth / 2
        } else {
            compactX = (rect.width - compactW) / 2
        }
        let expandedX = (rect.width - expandedW) / 2
        // Closed: anchor the notch gap to the physical cutout. Open: center the panel.
        let x = compactX + (expandedX - compactX) * progress

        return Self.surfacePath(x: x, width: w, height: h, bottomRadius: r, earRadius: e, topOverscan: topOverscan)
    }

    /// Flat top edge (flared outward by `earRadius`), straight sides, rounded
    /// bottom. Shared by the morph clip, the growing background and the
    /// closed pill so all three trace the same outline.
    static func surfacePath(
        x: CGFloat,
        width w: CGFloat,
        height h: CGFloat,
        bottomRadius r: CGFloat,
        earRadius e: CGFloat,
        topOverscan o: CGFloat = 0
    ) -> Path {
        Path { p in
            p.move(to: CGPoint(x: x - e, y: -o))
            p.addLine(to: CGPoint(x: x + w + e, y: -o))
            p.addLine(to: CGPoint(x: x + w + e, y: 0))
            if e > 0 {
                p.addQuadCurve(to: CGPoint(x: x + w, y: e), control: CGPoint(x: x + w, y: 0))
            }
            p.addLine(to: CGPoint(x: x + w, y: h - r))
            p.addArc(center: CGPoint(x: x + w - r, y: h - r),
                     radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: x + r, y: h))
            p.addArc(center: CGPoint(x: x + r, y: h - r),
                     radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            p.addLine(to: CGPoint(x: x, y: e))
            if e > 0 {
                p.addQuadCurve(to: CGPoint(x: x - e, y: 0), control: CGPoint(x: x, y: 0))
            }
            p.addLine(to: CGPoint(x: x - e, y: -o))
            p.closeSubpath()
        }
    }
}

/// Dedicated compact clip for the music track notification. Sized from the
/// pill's live measurements so long titles can extend the left wing without
/// cropping album art. Only used while the notification is visible.
struct NotchSurfaceClipModifier: ViewModifier {
    let usesMusicNotificationClip: Bool
    let musicClipMetrics: MusicNotificationClipMetrics
    let musicNotchGapWidth: CGFloat
    let morphProgress: CGFloat
    let compactW: CGFloat
    let compactH: CGFloat
    let expandedW: CGFloat
    let expandedH: CGFloat
    let compactR: CGFloat
    let compactLeftWingWidth: CGFloat
    let compactNotchGapWidth: CGFloat
    var compactEarRadius: CGFloat = 0
    var expandedEarRadius: CGFloat = 0

    func body(content: Content) -> some View {
        if usesMusicNotificationClip {
            // Closed music surfaces (notification + compact) draw their own
            // V6ClosedPillShape. Parent GrowingNotchShape uses agent wing metrics
            // and misaligns them, which reads as extra side padding.
            content
        } else {
            content.clipShape(
                GrowingNotchShape(
                    progress: morphProgress,
                    compactW: compactW,
                    compactH: compactH,
                    expandedW: expandedW,
                    expandedH: expandedH,
                    compactR: compactR,
                    compactLeftWingWidth: compactLeftWingWidth,
                    compactNotchGapWidth: compactNotchGapWidth,
                    compactEarRadius: compactEarRadius,
                    expandedEarRadius: expandedEarRadius
                )
            )
        }
    }
}
