import SwiftUI

struct MusicPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
    }
}

struct MusicControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.1 : 1.0)
            .buttonStyle(PlainButtonStyle())
    }
}

extension Button {
    func musicPressStyle() -> some View {
        buttonStyle(MusicPressButtonStyle())
    }
}
