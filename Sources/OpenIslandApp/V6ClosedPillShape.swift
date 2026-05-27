import SwiftUI

/// v6 closed-island pill: flat top, rounded bottom. Corner radius defaults
/// to `height / 2` so the bottom is a full semicircle.
///
/// Renders as one continuous ink shape regardless of the underlying display:
/// on MacBook it extends past the physical notch (they merge visually since
/// both are black); on external displays it sits as a standalone pill.
struct V6ClosedPillShape: Shape {
    var cornerRadius: CGFloat?
    var topFilletRadius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let f = topFilletRadius
        let r = min(cornerRadius ?? rect.height / 2, (rect.width - 2 * f) / 2, rect.height)
        var path = Path()
        
        // Start at the top edge, left side, at the very edge of the rect
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        
        // Concave curve into the pill body
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + f, y: rect.minY + f),
            control: CGPoint(x: rect.minX + f, y: rect.minY)
        )
        
        // Left side down
        path.addLine(to: CGPoint(x: rect.minX + f, y: rect.maxY - r))
        
        // Bottom left corner
        path.addArc(
            center: CGPoint(x: rect.minX + f + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )
        
        // Bottom right corner
        path.addArc(
            center: CGPoint(x: rect.maxX - f - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true
        )
        
        // Right side up
        path.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY + f))
        
        // Concave curve out to the right edge
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - f, y: rect.minY)
        )
        
        path.closeSubpath()
        return path
    }
}

enum V6Palette {
    static let ink = Color.black
    static let paper = Color(red: 0xf1 / 255.0, green: 0xea / 255.0, blue: 0xd9 / 255.0)
}
