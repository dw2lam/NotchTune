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

/// The library opened over a playing track: the same layout as the empty
/// state, with the playing track's cover as the tile. The tile leads back to
/// the controls, and picking something returns there on its own.
struct MusicNowPlayingLibraryView: View {
    var playerManager: MusicPlayerManager
    let player: MusicPlayerKind
    var tileSize: CGFloat = 166
    var showControls: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            MusicNowPlayingTile(playerManager: playerManager, size: tileSize, action: showControls)

            MusicLibraryChooserView(library: playerManager.library, player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: tileSize)
        .onAppear { playerManager.library.activate() }
    }
}

/// The playing track's cover with its title; click returns to the controls.
struct MusicNowPlayingTile: View {
    var playerManager: MusicPlayerManager
    var size: CGFloat
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            cover
                .frame(width: size, height: size)
                .overlay {
                    // Keeps the caption legible on a bright cover.
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0), location: 0.45),
                            .init(color: .black.opacity(isHovering ? 0.78 : 0.68), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .topLeading) { badge }
                .overlay(alignment: .bottomLeading) { caption }
                .clipShape(shape)
                .overlay { shape.stroke(.white.opacity(0.08), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                .contentShape(shape)
        }
        .buttonStyle(MusicPressButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .help("Show playback controls")
        .accessibilityLabel("Now playing: \(playerManager.track.title). Show playback controls")
    }

    @ViewBuilder
    private var cover: some View {
        if playerManager.hasAlbumArt {
            playerManager.track.albumArt
                .resizable()
                .interpolation(.high)
                .aspectRatio(1, contentMode: .fill)
        } else {
            MusicPlayerArtworkPlaceholder(
                player: playerManager.playerKind,
                size: size,
                iconScale: 0.43,
                iconOffset: -size * 0.09
            )
        }
    }

    private var badge: some View {
        HStack(spacing: 4) {
            Image(systemName: playerManager.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                .font(.system(size: 8, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
            Text("Now Playing")
                .font(.system(size: 9.5, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(.black.opacity(0.42), in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5) }
        .padding(8)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(playerManager.track.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
            HStack(spacing: 3) {
                if isHovering {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 8.5, weight: .bold))
                }
                Text(isHovering ? "Show controls" : playerManager.track.artist)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white.opacity(isHovering ? 0.78 : 0.6))
            .contentTransition(.opacity)
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}

/// Opens the library from the now-playing controls.
struct MusicLibraryButton: View {
    static let side: CGFloat = 24

    let player: MusicPlayerKind
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "music.note.list")
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: Self.side, height: Self.side)
        }
        .buttonStyle(IslandGlassIconButtonStyle(
            fallbackFill: .white.opacity(0.08),
            foreground: .white.opacity(0.72)
        ))
        .help(help)
        .accessibilityLabel(help)
    }

    private var help: String {
        switch player {
        case .appleMusic: "Browse playlists and songs"
        case .spotify: "Browse pinned and recent"
        }
    }
}
