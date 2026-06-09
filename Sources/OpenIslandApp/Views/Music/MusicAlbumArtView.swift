import SwiftUI

struct MusicAlbumArtView: View {
    var playerManager: MusicPlayerManager
    var imageSize: CGFloat = 140

    @State private var isPressed = false

    // Flip-on-change state. `displayedArt` is what's actually on screen; it only
    // swaps to the live artwork at the midpoint of the flip, so the previous
    // cover stays visible (no placeholder flash) until the new one turns in.
    @State private var displayedArt: Image = Image(systemName: "music.note")
    @State private var flipAngle: Double = 0
    @State private var isFlipping = false

    var body: some View {
        displayedArt
            .resizable()
            .aspectRatio(1, contentMode: .fill)
            .frame(width: imageSize, height: imageSize)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .rotation3DEffect(
                .degrees(flipAngle),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .onTapGesture {
                isPressed = true
                playerManager.openMusicApp()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isPressed = false
                }
            }
            .onAppear { displayedArt = playerManager.track.albumArt }
            .onChange(of: playerManager.track.artworkVersion) { _, _ in
                flipToCurrentArt()
            }
    }

    /// Half-flip out to edge-on, swap the cover, half-flip back in.
    /// We never cross 180°, so the new artwork lands front-facing (un-mirrored).
    private func flipToCurrentArt() {
        guard !isFlipping else {
            // Mid-flip change: just keep the latest art for the in-swing.
            displayedArt = playerManager.track.albumArt
            return
        }
        isFlipping = true

        withAnimation(.easeIn(duration: 0.18)) {
            flipAngle = 90
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            displayedArt = playerManager.track.albumArt
            flipAngle = -90 // jump to the other edge, content already swapped
            withAnimation(.easeOut(duration: 0.18)) {
                flipAngle = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                isFlipping = false
            }
        }
    }
}
