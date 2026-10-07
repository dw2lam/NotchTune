import SwiftUI

/// v6 `UnifiedBars` glyph — three vertical bars that share the same geometry
/// across all three notch states (idle / running / waiting), so transitions
/// animate bar heights smoothly instead of swapping glyphs.
///
/// Canonical geometry (from the design handoff): 24×24 box, 3 bars of width
/// 2.5 centered on columns x = 5.25 / 10.75 / 16.25, rounded to a pill.
struct UnifiedBars: View {
    enum Mode: Hashable {
        case idle       // rest — 3 short bars, middle breathes
        case running    // wave — heights 4→12→4, stagger 0.15s
        case waiting    // pause — outer bars tall, middle hidden, cross-pulse
    }

    var mode: Mode
    var size: CGFloat = 24
    var character: IslandCharacter = .dino
    /// When true the glyph is off-screen / hidden (island opened, collapsed, or
    /// behind a fullscreen window). Freeze to a single static frame so the
    /// display link can idle instead of redrawing the Canvas every frame.
    var paused: Bool = false
    /// Changes to trigger a one-shot "jump" bounce (idle-session nudge).
    var nudgeTrigger: UUID? = nil
    /// Ink color for bars / tick. Defaults to the v6 paper ink.
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

extension IslandCharacter {

    var title: String {
        switch self {
        case .dino: "Dino"
        case .ghost: "Ghost"
        case .crab: "Crab"
        case .duck: "Duck"
        case .claude: "Claude"
        }
    }

    var idleFrame: PixelFrame {
        switch self {
        case .dino:
            [
            [0, 0, 0, 0, 1, 1, 1, 1, 1],
            [0, 0, 0, 0, 1, 0, 1, 1, 1], // Eye at col 5 (0 means open)
            [0, 0, 0, 0, 1, 1, 1, 1, 1],
            [0, 0, 1, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0], // Arm at col 7
            [1, 1, 1, 1, 1, 1, 1, 0, 0],
            [1, 0, 1, 1, 1, 1, 1, 0, 0], // tail curves up at col 0
            [0, 0, 0, 1, 0, 1, 0, 0, 0], // left leg down, right leg up
            [0, 0, 0, 1, 0, 0, 0, 0, 0]  // left foot
            ]
        case .ghost:
            [
            [0, 0, 1, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 0, 1, 1, 0, 1, 1, 0], // Eyes at (2, 2) and (2, 5)
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 0, 1, 0, 1, 0, 1, 0]
            ]
        case .crab:
            [
            [1, 0, 1, 0, 0, 0, 1, 0, 1], // Stalk eyes at (0, 1) and (0, 7)
            [0, 1, 0, 0, 0, 0, 0, 1, 0], // Stalks
            [0, 0, 1, 1, 1, 1, 1, 0, 0], // Body top
            [1, 1, 1, 1, 1, 1, 1, 1, 1], // Lowered claws + body
            [1, 0, 1, 1, 1, 1, 1, 0, 1], // Claw pincers + body
            [0, 0, 1, 1, 1, 1, 1, 0, 0], // Body bottom
            [0, 1, 0, 1, 0, 1, 0, 1, 0], // Legs (idle)
            [1, 0, 0, 0, 0, 0, 0, 0, 1], // Outer legs
            [0, 0, 0, 0, 0, 0, 0, 0, 0]
            ]
        case .duck:
            [
            [0, 0, 0, 0, 1, 1, 1, 0, 0], // Row 0
            [0, 0, 0, 0, 1, 0, 1, 1, 1], // Row 1: Eye at (1, 5), beak at cols 6-8
            [0, 0, 0, 0, 1, 1, 1, 0, 0], // Row 2
            [0, 0, 0, 0, 0, 1, 1, 0, 0], // Row 3: Neck
            [0, 1, 1, 1, 1, 1, 1, 0, 0], // Row 4: Body
            [1, 1, 0, 1, 1, 1, 1, 0, 0], // Row 5: Wing down (col 2 is 0)
            [1, 1, 1, 1, 1, 1, 1, 0, 0], // Row 6: Body bottom
            [0, 0, 1, 0, 1, 0, 0, 0, 0], // Row 7: Legs
            [0, 0, 1, 1, 0, 1, 1, 0, 0]  // Row 8: Webbed feet
            ]
        case .claude:
            [
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0], // Head top
            [0, 1, 0, 1, 1, 1, 0, 1, 0], // Eyes at Col 2 and Col 6 (0 when open)
            [1, 1, 1, 1, 1, 1, 1, 1, 1], // Arms stick out at Col 0 and 8
            [0, 1, 1, 1, 1, 1, 1, 1, 0], // Body bottom
            [0, 1, 0, 1, 0, 1, 0, 1, 0], // Legs at Col 1, 3, 5, 7
            [0, 1, 0, 1, 0, 1, 0, 1, 0],
            [0, 1, 0, 1, 0, 1, 0, 1, 0]
            ]
        }
    }

    var runningFrame: PixelFrame {
        switch self {
        case .dino:
            [
            [0, 0, 0, 0, 1, 1, 1, 1, 1],
            [0, 0, 0, 0, 1, 0, 1, 1, 1],
            [0, 0, 0, 0, 1, 1, 1, 1, 1],
            [0, 0, 1, 1, 1, 1, 1, 1, 0], // Arm wiggles up to col 7
            [0, 1, 1, 1, 1, 1, 1, 0, 0], // Arm at col 7 is empty
            [1, 1, 1, 1, 1, 1, 1, 0, 0],
            [1, 0, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 0, 0, 1, 0, 0, 0], // left leg up, right leg down
            [0, 0, 0, 0, 0, 1, 0, 0, 0]  // right foot
            ]
        case .ghost:
            [
            [0, 0, 1, 1, 1, 1, 1, 0, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 0, 1, 1, 0, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 0, 1, 0, 1, 0, 1, 0, 1] // shifted wavy bottom
            ]
        case .crab:
            [
            [1, 0, 1, 0, 0, 0, 1, 0, 1], // Stalk eyes at (0, 1) and (0, 7)
            [1, 1, 1, 0, 0, 0, 1, 1, 1], // Lifted claws + stalks
            [1, 0, 1, 1, 1, 1, 1, 0, 1], // Claw pincers + body top
            [0, 0, 1, 1, 1, 1, 1, 0, 0], // Body middle
            [0, 0, 1, 1, 1, 1, 1, 0, 0], // Body bottom
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 1, 0, 1, 0, 1, 0, 0], // Legs wiggled
            [0, 1, 0, 0, 0, 0, 0, 1, 0], // Leg tips shifted
            [0, 0, 0, 0, 0, 0, 0, 0, 0]
            ]
        case .duck:
            [
            [0, 0, 0, 0, 1, 1, 1, 0, 0], // Row 0
            [0, 0, 0, 0, 1, 0, 1, 1, 1], // Row 1
            [0, 0, 0, 0, 1, 1, 1, 0, 0], // Row 2
            [0, 0, 1, 1, 0, 1, 1, 0, 0], // Row 3: Wing up (cols 2-3 are 1) + neck
            [0, 1, 1, 1, 1, 1, 1, 0, 0], // Row 4: Body
            [1, 1, 1, 1, 1, 1, 1, 0, 0], // Row 5: Body bottom (no wing down)
            [1, 1, 1, 1, 1, 1, 1, 0, 0], // Row 6: Body bottom
            [0, 0, 0, 1, 0, 1, 0, 0, 0], // Row 7: Legs wiggled
            [0, 0, 0, 1, 0, 0, 1, 0, 0]  // Row 8: Feet wiggled
            ]
        case .claude:
            [
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 0, 1, 1, 1, 0, 1, 0],
            [1, 1, 1, 1, 1, 1, 1, 1, 1],
            [0, 1, 1, 1, 1, 1, 1, 1, 0],
            [0, 1, 0, 1, 0, 1, 0, 1, 0],
            [0, 1, 0, 1, 0, 1, 0, 1, 0],
            [0, 1, 0, 1, 0, 1, 0, 1, 0]
            ]
        }
    }

    var eyeCoordinate: (row: Int, column: Int)? {
        switch self {
        case .dino: (1, 5)
        case .ghost: (2, 2)
        case .crab: (0, 1)
        case .duck: (1, 5)
        case .claude: (3, 2)
        }
    }

    /// One full period of `runningBounce` (for Core Animation keyframes).
    var runningBouncePeriod: TimeInterval {
        switch self {
        case .dino: 0.2      // |sin(5πt)|
        case .ghost: 1.0     // sin(2πt)
        case .crab: 1.0 / 6  // |sin(6πt)|
        case .duck: 0.25     // |sin(4πt)|
        case .claude: 0.25   // |sin(4πt)|
        }
    }

    func runningBounce(time: TimeInterval) -> CGFloat {
        switch self {
        case .dino:
            abs(sin(time * .pi * 5.0)) * 1.2
        case .ghost:
            sin(time * .pi * 2.0) * 0.8
        case .crab:
            abs(sin(time * .pi * 6.0)) * 0.4
        case .duck:
            abs(sin(time * .pi * 4.0)) * 1.0
        case .claude:
            abs(sin(time * .pi * 4.0)) * 2.0
        }
    }
}
