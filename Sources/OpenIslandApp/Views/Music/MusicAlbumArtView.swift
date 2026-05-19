import SwiftUI

struct MusicAlbumArtView: View {
    var playerManager: MusicPlayerManager
    var imageSize: CGFloat = 140

    var body: some View {
        playerManager.track.albumArt
            .resizable()
            .aspectRatio(1, contentMode: .fill)
            .frame(width: imageSize, height: imageSize)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
            .onTapGesture { playerManager.openMusicApp() }
    }
}
