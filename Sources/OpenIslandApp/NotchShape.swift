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

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = compactW + (expandedW - compactW) * progress
        let h = compactH + (expandedH - compactH) * progress
        let r = compactR + (expandedR - compactR) * progress
        let x = (rect.width - w) / 2

        return Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x + w, y: 0))
            p.addLine(to: CGPoint(x: x + w, y: h - r))
            p.addArc(center: CGPoint(x: x + w - r, y: h - r),
                     radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: x + r, y: h))
            p.addArc(center: CGPoint(x: x + r, y: h - r),
                     radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            p.closeSubpath()
        }
    }
}

// MARK: -

struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let topR = min(topCornerRadius, rect.width / 4, rect.height / 4)
        let botR = min(bottomCornerRadius, rect.width / 4, rect.height / 2)

        var path = Path()

        // Start at top-left, after the inward curve
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left inward curve (concave, mimics notch edge)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
            control: CGPoint(x: rect.minX + topR, y: rect.minY)
        )

        // Left edge down to bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))

        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
            control: CGPoint(x: rect.minX + topR, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))

        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
            control: CGPoint(x: rect.maxX - topR, y: rect.maxY)
        )

        // Right edge up to top-right inward curve
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))

        // Top-right inward curve (concave)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topR, y: rect.minY)
        )

        // Top edge back to start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        path.closeSubpath()
        return path
    }
}

extension NotchShape {
    /// The opened island uses a concave-top-corner notch shape so it blends
    /// with the physical MacBook notch on built-in displays. The closed
    /// state no longer uses this shape — it renders via `V6ClosedPillShape`
    /// instead.
    static let openedTopRadius: CGFloat = 22
    static let openedBottomRadius: CGFloat = 22

    static var opened: NotchShape {
        NotchShape(topCornerRadius: openedTopRadius, bottomCornerRadius: openedBottomRadius)
    }
}
