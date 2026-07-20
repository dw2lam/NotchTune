import SwiftUI

struct MusicAlbumArtView: View {
    var playerManager: MusicPlayerManager
    var imageSize: CGFloat = 140

    @State private var isPressed = false

    // Flip-on-change state. `displayedArt` is what's actually on screen; it is
    // swapped *only* while the card is edge-on (invisible), so the previous
    // cover stays up until the new one turns in — no placeholder flash and no
    // glimpse of the next cover before the flip.
    @State private var displayedArt: Image = Image(systemName: "music.note")
    @State private var displayedVersion: Int = -1
    @State private var flipAngle: Double = 0
    @State private var isFlipping = false

    private let halfFlip: TimeInterval = 0.18

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
            .onAppear {
                displayedArt = playerManager.track.albumArt
                displayedVersion = playerManager.track.artworkVersion
            }
            .onChange(of: playerManager.track.artworkVersion) { _, _ in
                if !isFlipping { startFlip() }
                // If a flip is already running, the new cover is picked up when
                // the in-flight flip finishes (see the re-check in startFlip).
            }
    }

    /// Half-flip out to edge-on, swap the cover while it's invisible, then
    /// half-flip back in. We never cross 180°, so the new artwork lands
    /// front-facing (un-mirrored). If a newer cover arrived mid-flip, flip again.
    private func startFlip() {
        isFlipping = true

        withAnimation(.easeIn(duration: halfFlip)) {
            flipAngle = 90
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + halfFlip) {
            // Edge-on and invisible — the only safe moment to swap the image.
            displayedArt = playerManager.track.albumArt
            displayedVersion = playerManager.track.artworkVersion
            flipAngle = -90 // jump to the far edge; content already swapped

            withAnimation(.easeOut(duration: halfFlip)) {
                flipAngle = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + halfFlip) {
                isFlipping = false
                if playerManager.track.artworkVersion != displayedVersion {
                    startFlip()
                }
            }
        }
    }
}
