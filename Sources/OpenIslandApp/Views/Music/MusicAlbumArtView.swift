import SwiftUI

struct MusicAlbumArtView: View {
    var playerManager: MusicPlayerManager
    var imageSize: CGFloat = 140

    @State private var isPressed = false

    var body: some View {
        playerManager.track.albumArt
            .resizable()
            .aspectRatio(1, contentMode: .fill)
            .frame(width: imageSize, height: imageSize)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .onTapGesture {
                isPressed = true
                playerManager.openMusicApp()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isPressed = false
                }
            }
    }
}
