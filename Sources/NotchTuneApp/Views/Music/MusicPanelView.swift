import SwiftUI

struct MusicPanelView: View {
    @Bindable var playerManager: MusicPlayerManager
    var horizontalPadding: CGFloat = 24

    /// The library is open over a playing track (the list button beside the
    /// title). Resets when the panel goes away, so the tab reopens on the
    /// controls.
    @State private var isBrowsingLibrary = MusicHarnessOverride.current?.opensLibrary ?? false

    /// What the Music tab shows.
    enum Mode: Hashable {
        /// Transport controls for the playing track.
        case nowPlaying
        /// The library, with the playing track as a tile that leads back.
        case library(MusicPlayerKind)
        /// Nothing playing: the player's icon and its library.
        case empty(MusicPlayerKind)
        case none

        static func resolve(showsNowPlaying: Bool, wantsLibrary: Bool, player: MusicPlayerKind?) -> Mode {
            guard let player else { return showsNowPlaying ? .nowPlaying : .none }
            if showsNowPlaying {
                return wantsLibrary ? .library(player) : .nowPlaying
            }
            return .empty(player)
        }
    }

    var body: some View {
        if playerManager.isMusicEnabled {
            // A ZStack, not a Group: a Group hands `.animation` to each branch,
            // so the outgoing view vanished instead of fading out.
            ZStack(alignment: .top) {
                switch mode {
                case .nowPlaying:
                    musicControls
                        .transition(.opacity)
                case .library(let player):
                    MusicNowPlayingLibraryView(playerManager: playerManager, player: player) {
                        setBrowsingLibrary(false)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                case .empty(let player):
                    MusicEmptyStateView(playerManager: playerManager, player: player)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                case .none:
                    EmptyView()
                }
            }
            .animation(Self.modeFade, value: mode)
            .onChange(of: playerManager.library.deliveredPlayCount) { _, _ in
                // Picked something: back to the controls, where its cover flips in.
                setBrowsingLibrary(false)
            }
            .onChange(of: showsNowPlaying) { _, playing in
                // Player quit → the empty state already shows the library.
                if !playing { setBrowsingLibrary(false) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .notchTuneHarnessToggleMusicLibrary)) { _ in
                setBrowsingLibrary(!isBrowsingLibrary)
            }
        } else {
            musicDisabledPlaceholder
        }
    }

    /// Every switch between the tab's views (controls, library, empty state)
    /// cross-fades.
    static let modeFade: Animation = .easeInOut(duration: 0.28)

    private func setBrowsingLibrary(_ browsing: Bool) {
        guard isBrowsingLibrary != browsing else { return }
        withAnimation(Self.modeFade) { isBrowsingLibrary = browsing }
    }

    private var mode: Mode {
        Mode.resolve(
            showsNowPlaying: showsNowPlaying,
            wantsLibrary: isBrowsingLibrary,
            player: playerManager.playerKind
        )
    }

    /// A real track in a running player → transport controls; otherwise the
    /// "Nothing playing" chooser. Reading the library's (observable) running
    /// flag re-evaluates this when the player quits or launches.
    private var showsNowPlaying: Bool {
        playerManager.hasNowPlaying && playerManager.library.isPlayerRunning
    }

    private var musicControls: some View {
        HStack(spacing: 20) {
            MusicAlbumArtView(playerManager: playerManager, imageSize: 166)

            VStack(spacing: 16) {
                PlayerTrackDetailsView(playerManager: playerManager)
                    // Room for the library button, keeping the title centred.
                    .padding(.horizontal, playerManager.playerKind == nil ? 0 : MusicLibraryButton.side + 6)
                    .overlay(alignment: .trailing) {
                        if let player = playerManager.playerKind {
                            MusicLibraryButton(player: player) { setBrowsingLibrary(true) }
                        }
                    }

                MusicPlaybackButtonsView(playerManager: playerManager, buttonSize: 22, spacing: 20)

                VStack(spacing: 12) {
                    MusicPlaybackPositionView(playerManager: playerManager)
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .onAppear {
            playerManager.beginPositionUpdates()
        }
        .onDisappear {
            playerManager.endPositionUpdates()
        }
    }

    private var musicDisabledPlaceholder: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
            Text("No music player selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text("Choose Apple Music or Spotify in Settings → Music")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalPadding)
    }
}
