import CoreGraphics

enum IslandChromeMetrics {
    static let openedShadowHorizontalInset: CGFloat = 18
    static let openedShadowBottomInset: CGFloat = 22
    static let closedShadowHorizontalInset: CGFloat = 12
    static let closedShadowBottomInset: CGFloat = 14
    static let closedHoverScale: CGFloat = 1.028
    static let notchedClosedMinimumWingReserve: CGFloat = 44
    static let notchedClosedHorizontalPadding: CGFloat = 14
    static let notchedClosedContentGap: CGFloat = 8

    static func notchedClosedWingReserve(rightSlotWidth: CGFloat = 0) -> CGFloat {
        let glyphWidth: CGFloat = 24
        let requiredContentWidth = max(glyphWidth, rightSlotWidth)
        let requiredReserve = requiredContentWidth
            + notchedClosedHorizontalPadding
            + notchedClosedContentGap
        return max(notchedClosedMinimumWingReserve, ceil(requiredReserve))
    }
}
