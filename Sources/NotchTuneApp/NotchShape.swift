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
    /// Clip to nothing (a rect far larger than the view) instead of the
    /// surface outline. Lets a caller turn clipping off without swapping the
    /// clipped view's identity (see `NotchSurfaceClipModifier`).
    var isUnbounded = false

    /// Progress + the compact geometry, so switching the compact target
    /// (pill ↔ hardware notch) animates instead of jumping.
    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>
    > {
        get {
            AnimatablePair(
                AnimatablePair(progress, compactW),
                AnimatablePair(
                    AnimatablePair(compactLeftWingWidth, compactR),
                    AnimatablePair(compactH, compactEarRadius)
                )
            )
        }
        set {
            progress = newValue.first.first
            compactW = newValue.first.second
            compactLeftWingWidth = newValue.second.first.first
            compactR = newValue.second.first.second
            compactH = newValue.second.second.first
            compactEarRadius = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if isUnbounded {
            return Path(rect.insetBy(dx: -Self.unboundedOutset, dy: -Self.unboundedOutset))
        }

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

    nonisolated static let unboundedOutset: CGFloat = 4096

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
        // Closed music surfaces (notification + compact) draw their own
        // V6ClosedPillShape. Parent GrowingNotchShape uses agent wing metrics
        // and misaligns them, which reads as extra side padding — so the clip
        // goes unbounded for them. It stays ONE `clipShape` either way: an
        // `if` here swapped the whole surface's identity on every open/close
        // next to a music pill, re-mounting the opened panel mid-close (its
        // content vanished on frame 1 and the music pill popped in at once).
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
                expandedEarRadius: expandedEarRadius,
                isUnbounded: usesMusicNotificationClip
            )
        )
    }
}
