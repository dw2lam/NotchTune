import SwiftUI

/// The Music tab when nothing is playing (player closed, or open with nothing
/// loaded): the player's app icon where the cover would be, and a chooser to
/// start something from that player.
struct MusicEmptyStateView: View {
    var playerManager: MusicPlayerManager
    let player: MusicPlayerKind
    var tileSize: CGFloat = 166

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            MusicPlayerIdentityTile(player: player, size: tileSize) {
                playerManager.library.openPlayerApp()
            }

            MusicLibraryChooserView(library: playerManager.library, player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: tileSize)
        .onAppear { playerManager.library.activate() }
    }
}

/// The cover-sized tile: real app icon + "Nothing playing". Click opens the app.
struct MusicPlayerIdentityTile: View {
    let player: MusicPlayerKind
    var size: CGFloat
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            MusicPlayerArtworkPlaceholder(
                player: player,
                size: size,
                iconScale: 0.43,
                iconOffset: -size * 0.09
            )
            .overlay(alignment: .bottom) {
                VStack(spacing: 2) {
                    Text("Nothing playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                    HStack(spacing: 3) {
                        Text(isHovering ? "Open \(player.displayName)" : player.displayName)
                        if isHovering {
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovering ? 0.7 : 0.45))
                    .contentTransition(.opacity)
                }
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.bottom, size * 0.1)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(MusicPressButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .help("Open \(player.displayName)")
        .accessibilityLabel("Nothing playing. Open \(player.displayName)")
    }
}
