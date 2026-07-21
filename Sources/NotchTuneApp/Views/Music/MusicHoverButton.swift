import SwiftUI

struct MusicHoverButton: View {
    var icon: String
    var iconSize: CGFloat = 60
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: iconSize, height: iconSize)
                .overlay {
                    Capsule()
                        .fill(isHovering ? Color.gray.opacity(0.3) : .clear)
                        .frame(width: iconSize * 1.75, height: iconSize * 1.75)
                        .overlay {
                            Image(systemName: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: isHovering ? iconSize * 1.15 : iconSize, height: isHovering ? iconSize * 1.15 : iconSize)
                                .contentTransition(.symbolEffect)
                        }
                }
        }
        .buttonStyle(MusicPressButtonStyle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.25)) { isHovering = hovering }
        }
    }
}
