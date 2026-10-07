import AppKit
import Testing
@testable import NotchTuneApp

/// The character animates in Core Animation (no per-frame SwiftUI work):
/// each mode installs its keyframes, and a paused glyph runs none.
@MainActor
struct PixelCharacterViewTests {
    private func view(_ mode: UnifiedBars.Mode, paused: Bool = false, character: IslandCharacter = .dino) -> PixelCharacterNSView {
        let view = PixelCharacterNSView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        view.apply(.init(character: character, mode: mode, paused: paused, rgba: [1, 1, 1, 1]))
        return view
    }

    @Test
    func eachModeRunsItsOwnCoreAnimation() {
        #expect(view(.running).runningAnimationKeys == ["frameSwap", "bounce"])
        #expect(view(.idle).runningAnimationKeys == ["blink"])
        #expect(view(.waiting).runningAnimationKeys == ["pulse"])
    }

    @Test
    func pausedGlyphIsAStaticFrame() {
        let paused = view(.running, paused: true)
        #expect(paused.runningAnimationKeys.isEmpty)
        #expect(paused.hasSpriteContents)
    }

    @Test
    func everyCharacterRendersAndHasABouncePeriod() {
        for character in IslandCharacter.allCases {
            #expect(view(.running, character: character).hasSpriteContents)
            #expect(character.runningBouncePeriod > 0)
            // The curve repeats with the declared period.
            let a = character.runningBounce(time: 0.03)
            let b = character.runningBounce(time: 0.03 + character.runningBouncePeriod)
            #expect(abs(a - b) < 0.0001)
        }
    }
}
