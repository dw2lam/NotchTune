import SwiftUI

struct MusicVolumeControlView: View {
    @Bindable var playerManager: MusicPlayerManager
    private let iconSize: CGFloat = 11

    var body: some View {
        HStack(spacing: 6) {
            Button(action: playerManager.decreaseVolume) {
                Image(systemName: "speaker.wave.1.fill")
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
            }
            .musicPressStyle()
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))

            MusicCustomSliderView(
                value: $playerManager.volume,
                isDragging: $playerManager.isDraggingSoundVolumeSlider,
                range: 0...100,
                sliderHeight: 5
            )
            .onChange(of: playerManager.volume) { _, newVolume in
                guard !playerManager.isDraggingSoundVolumeSlider else { return }
                playerManager.setVolume(newVolume: Int(newVolume))
            }
            .onChange(of: playerManager.isDraggingSoundVolumeSlider) { _, dragging in
                if !dragging { playerManager.setVolume(newVolume: Int(playerManager.volume)) }
            }

            Button(action: playerManager.increaseVolume) {
                Image(systemName: "speaker.wave.2.fill")
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
            }
            .musicPressStyle()
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
        }
    }
}
