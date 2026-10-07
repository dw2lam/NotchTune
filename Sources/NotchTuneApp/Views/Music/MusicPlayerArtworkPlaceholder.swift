import SwiftUI

/// Stand-in cover when there's no album art: the selected player's REAL app
/// icon on a faint wash of its brand colour. Replaces the old blown-up
/// `music.note` glyph.
struct MusicPlayerArtworkPlaceholder: View {
    let player: MusicPlayerKind?
    var size: CGFloat
    var cornerRadius: CGFloat = 12
    /// Icon size relative to the tile.
    var iconScale: CGFloat = 0.46
    /// Vertical nudge for the icon (the identity tile lifts it above its caption).
    var iconOffset: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(Color.white.opacity(0.045))
            shape.fill(
                LinearGradient(
                    colors: [accent.opacity(0.34), accent.opacity(0.10), accent.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.16), .white.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )

            icon
                .frame(width: size * iconScale, height: size * iconScale)
                .shadow(color: .black.opacity(0.35), radius: size * 0.04, x: 0, y: size * 0.02)
                .offset(y: iconOffset)
        }
        .frame(width: size, height: size)
    }

    private var accent: Color {
        player.map { Color(nsColor: $0.accent) } ?? .white
    }

    @ViewBuilder
    private var icon: some View {
        if let player, let nsImage = MusicPlayerIcon.icon(for: player) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "music.note")
                .resizable()
                .scaledToFit()
                .padding(size * 0.08)
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}
