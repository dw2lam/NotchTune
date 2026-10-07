import SwiftUI

struct MusicPanelView: View {
    @Bindable var playerManager: MusicPlayerManager
    var horizontalPadding: CGFloat = 24

    var body: some View {
        if playerManager.isMusicEnabled {
            Group {
                if showsNowPlaying {
                    musicControls
                        .transition(.opacity)
                } else if let player = playerManager.playerKind {
                    MusicEmptyStateView(playerManager: playerManager, player: player)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showsNowPlaying)
        } else {
            musicDisabledPlaceholder
        }
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
            playerManager.startTimer()
        }
        .onDisappear {
            playerManager.stopTimer()
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
