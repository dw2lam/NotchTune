import SwiftUI

struct MusicPanelView: View {
    @Bindable var playerManager: MusicPlayerManager

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                MusicAlbumArtView(playerManager: playerManager, imageSize: 110)

                VStack(alignment: .leading, spacing: 8) {
                    PlayerTrackDetailsView(playerManager: playerManager)

                    Spacer(minLength: 0)

                    MusicPlaybackButtonsView(playerManager: playerManager, buttonSize: 18, spacing: 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

            MusicPlaybackPositionView(playerManager: playerManager)

            MusicVolumeControlView(playerManager: playerManager)

            if playerManager.isSpotifyAvailable {
                appPickerRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear {
            playerManager.startTimer()
            playerManager.getVolume()
        }
        .onDisappear {
            playerManager.stopTimer()
        }
    }

    private var appPickerRow: some View {
        HStack(spacing: 6) {
            Spacer()

            Button {
                playerManager.switchToAppleMusic()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                    Text("Apple Music")
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isAppleMusic
                        ? Color.white.opacity(0.18)
                        : Color.clear,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(isAppleMusic ? 0.9 : 0.45))

            Button {
                playerManager.switchToSpotify()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 10))
                    Text("Spotify")
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    !isAppleMusic
                        ? Color.white.opacity(0.18)
                        : Color.clear,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(!isAppleMusic ? 0.9 : 0.45))
        }
    }

    private var isAppleMusic: Bool {
        (UserDefaults.standard.string(forKey: MusicPlayerManager.connectedAppKey) ?? "appleMusic") == "appleMusic"
    }
}
