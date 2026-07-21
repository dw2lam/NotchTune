import SwiftUI

struct OpenedIslandSurfaceShape: Shape {
    static let openedBottomRadius: CGFloat = 22

    enum TopProfile: Equatable {
        case notch
        case topBar
    }

    var topProfile: TopProfile
    var bottomCornerRadius: CGFloat = OpenedIslandSurfaceShape.openedBottomRadius

    var animatableData: CGFloat {
        get { bottomCornerRadius }
        set { bottomCornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        switch topProfile {
        case .notch:
            return V6ClosedPillShape(cornerRadius: bottomCornerRadius, topFilletRadius: 0)
                .path(in: rect)
        case .topBar:
            return V6ClosedPillShape(cornerRadius: bottomCornerRadius, topFilletRadius: 0)
                .path(in: rect)
        }
    }
}
