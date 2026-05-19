import SwiftUI

struct MusicPlaybackPositionView: View {
    @Bindable var playerManager: MusicPlayerManager

    var body: some View {
        VStack(spacing: 0) {
            MusicCustomSliderView(
                value: $playerManager.seekerPosition,
                isDragging: $playerManager.isDraggingPlaybackPositionView,
                range: 0...max(1, playerManager.track.duration),
                onEndedDragging: { _ in playerManager.seekTrack() }
            )
            .padding(.bottom, 5)
            .frame(height: 12)
            .onChange(of: playerManager.isDraggingPlaybackPositionView) { _, dragging in
                if dragging { playerManager.draggingPlaybackPosition() }
            }
            .onChange(of: playerManager.seekerPosition) { _, _ in
                if playerManager.isDraggingPlaybackPositionView {
                    playerManager.draggingPlaybackPosition()
                }
            }

            HStack {
                Text(playerManager.formattedPlaybackPosition)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(playerManager.formattedDuration)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 3)
        }
    }
}
