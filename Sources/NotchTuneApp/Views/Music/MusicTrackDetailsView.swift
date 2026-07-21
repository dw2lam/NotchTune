import SwiftUI

struct PlayerTrackDetailsView: View {
    var playerManager: MusicPlayerManager

    var body: some View {
        Button(action: playerManager.openMusicApp) {
            VStack(alignment: .center, spacing: 2) {
                Text(playerManager.track.isEmpty() ? "Nothing playing" : playerManager.track.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(MusicConstants.Opacity.primary))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                Text(playerManager.track.isEmpty() ? playerManager.connectedAppName : playerManager.track.artist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(MusicConstants.Opacity.secondary))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .musicPressStyle()
        .buttonStyle(.plain)
    }
}
