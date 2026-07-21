import SwiftUI

struct MusicPlaybackButtonsView: View {
    @Bindable var playerManager: MusicPlayerManager
    var buttonSize: CGFloat = 22
    var spacing: CGFloat = 16

    var body: some View {
        HStack(spacing: spacing) {
            MusicHoverButton(icon: "shuffle", iconSize: buttonSize * 0.75) {
                playerManager.setShuffle()
            }
            .fontWeight(playerManager.shuffleIsOn ? .black : .ultraLight)
            .opacity(playerManager.shuffleContextEnabled ? 1.0 : 0.4)
            .disabled(!playerManager.shuffleContextEnabled)

            MusicHoverButton(
                icon: playerManager.track.isPodcast ? "15.arrow.trianglehead.counterclockwise" : "backward.fill",
                iconSize: buttonSize
            ) {
                playerManager.previousTrack()
            }

            MusicHoverButton(
                icon: playerManager.isPlaying ? "pause.fill" : "play.fill",
                iconSize: buttonSize * 1.3
            ) {
                playerManager.togglePlayPause()
            }

            MusicHoverButton(
                icon: playerManager.track.isPodcast ? "15.arrow.trianglehead.clockwise" : "forward.fill",
                iconSize: buttonSize
            ) {
                playerManager.nextTrack()
            }

            MusicHoverButton(icon: "repeat", iconSize: buttonSize * 0.75) {
                playerManager.setRepeat()
            }
            .fontWeight(playerManager.repeatIsOn ? .bold : .light)
            .opacity(playerManager.repeatContextEnabled ? 1.0 : 0.4)
            .disabled(!playerManager.repeatContextEnabled)
        }
        .foregroundStyle(.white.opacity(0.8))
    }
}
