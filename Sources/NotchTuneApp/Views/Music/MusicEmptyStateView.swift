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
/// Hovering it brings up tiny controls — a progress bar, previous,
/// play/pause and next — without leaving the library, plus an expand
/// button back to the full player.
struct MusicNowPlayingTile: View {
    var playerManager: MusicPlayerManager
    var size: CGFloat
    var action: () -> Void

    @State private var isHovering = MusicHarnessOverride.current?.hoversNowPlayingTile ?? false
    /// Whether this tile currently holds the position timer (only while
    /// hovered: the progress bar is the only thing that needs it).
    @State private var holdsPositionUpdates = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        // The cover itself (outside the tiny controls) returns to the full
        // player: a real button, so VoiceOver and the keyboard reach it.
        Button(action: action) {
            cover
                .frame(width: size, height: size)
                .overlay {
                    // Keeps the caption / controls legible on a bright cover.
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(isHovering ? 0.12 : 0), location: 0),
                            .init(color: .black.opacity(0), location: isHovering ? 0.32 : 0.45),
                            .init(color: .black.opacity(isHovering ? 0.82 : 0.68), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show the full player")
        .overlay(alignment: .topLeading) { badge.accessibilityHidden(true) }
        // The hover extras stay in the view tree, faded out and click-through
        // while the pointer is away, so assistive tech can always reach them.
        .overlay(alignment: .topTrailing) {
            expandButton
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                // The cover button already does this.
                .accessibilityHidden(true)
        }
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                caption
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isHovering ? 0 : 1)
                    .accessibilityHidden(true)
                MusicTileMiniControls(playerManager: playerManager)
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(isHovering)
            }
        }
        .clipShape(shape)
        .overlay { shape.stroke(.white.opacity(0.08), lineWidth: 0.5).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        .contentShape(shape)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
            setHoldsPositionUpdates(hovering)
        }
        .onAppear { if isHovering { setHoldsPositionUpdates(true) } }
        .onDisappear { setHoldsPositionUpdates(false) }
        .help("Show the full player")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(nowPlayingLabel)
    }

    private var nowPlayingLabel: String {
        let artist = playerManager.track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return artist.isEmpty
            ? "Now playing: \(playerManager.track.title)"
            : "Now playing: \(playerManager.track.title), \(artist)"
    }

    private func setHoldsPositionUpdates(_ holds: Bool) {
        guard holds != holdsPositionUpdates else { return }
        holdsPositionUpdates = holds
        if holds {
            playerManager.beginPositionUpdates()
        } else {
            playerManager.endPositionUpdates()
        }
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

    /// Back to the full-size player.
    private var expandButton: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 22, height: 22)
                .background(.black.opacity(0.42), in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.14), lineWidth: 0.5) }
                .contentShape(Circle())
        }
        .buttonStyle(MusicPressButtonStyle())
        .padding(6)
        .help("Show the full player")
        .accessibilityLabel("Show the full player")
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(playerManager.track.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
            Text(playerManager.track.artist)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}

/// The tile's hover controls: title, a hairline progress bar, and small
/// previous / play-pause / next — the full player in miniature.
struct MusicTileMiniControls: View {
    var playerManager: MusicPlayerManager

    var body: some View {
        VStack(spacing: 8) {
            Text(playerManager.track.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            progressBar

            HStack(spacing: 20) {
                button(
                    playerManager.track.isPodcast ? "15.arrow.trianglehead.counterclockwise" : "backward.fill",
                    size: 11,
                    label: "Previous track",
                    action: playerManager.previousTrack
                )
                button(
                    playerManager.isPlaying ? "pause.fill" : "play.fill",
                    size: 15,
                    label: playerManager.isPlaying ? "Pause" : "Play",
                    action: playerManager.togglePlayPause
                )
                button(
                    playerManager.track.isPodcast ? "15.arrow.trianglehead.clockwise" : "forward.fill",
                    size: 11,
                    label: "Next track",
                    action: playerManager.nextTrack
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var fraction: CGFloat {
        let duration = playerManager.track.duration
        guard duration > 0 else { return 0 }
        return min(1, max(0, playerManager.seekerPosition / duration))
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: max(3, proxy.size.width * fraction))
            }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(playerManager.formattedPlaybackPosition) of \(playerManager.formattedDuration)")
    }

    private func button(_ symbol: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(MusicPressButtonStyle())
        .help(label)
        .accessibilityLabel(label)
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
