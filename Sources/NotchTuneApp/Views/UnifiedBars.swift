import SwiftUI

/// The closed island's pixel character in a 24×24 design box. Each mode
/// plays the character's own loop (see PixelCharacterSprite / the generated
/// PixelSprites.swift), animated by Core Animation in PixelCharacterView.
struct UnifiedBars: View {
    enum Mode: Hashable {
        case idle       // mostly still: blinks, glances, the odd fidget
        case running    // an agent is working: the character's work cycle
        case waiting    // an agent needs the user: "!" and a wave
    }

    var mode: Mode
    var size: CGFloat = 24
    var character: IslandCharacter = .dino
    /// When true the glyph is off-screen / hidden (island opened, collapsed, or
    /// behind a fullscreen window). Freeze to the character's rest frame with
    /// no animation running.
    var paused: Bool = false
    /// Changes to trigger a one-shot "jump" bounce (idle-session nudge).
    var nudgeTrigger: UUID? = nil
    /// Ink color for the character. Defaults to the v6 paper ink.
    var tint: Color = UnifiedBars.paperInk

    static let paperInk = Color(red: 0xf1 / 255.0, green: 0xea / 255.0, blue: 0xd9 / 255.0)

    private static let box: CGFloat = 24

    /// Transient upward offset for the nudge jump, animated on `nudgeTrigger`.
    @State private var nudgeBounce: CGFloat = 0

    var body: some View {
        // Core Animation drives every mode (see PixelCharacterView): no
        // per-frame SwiftUI work. Hidden/frozen → static frame, no animation.
        PixelCharacterView(character: character, mode: mode, paused: paused, tint: tint)
            .frame(width: size, height: size)
            .offset(y: -nudgeBounce * size / Self.box)
            .onChange(of: nudgeTrigger) { _, newValue in
                // Skip while hidden/frozen — no point animating an off-screen glyph.
                guard newValue != nil, !paused else { return }
                // Jump up sharply, then settle back with a springy landing.
                withAnimation(.easeOut(duration: 0.16)) { nudgeBounce = 3 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.5)) { nudgeBounce = 0 }
                }
            }
    }
}
