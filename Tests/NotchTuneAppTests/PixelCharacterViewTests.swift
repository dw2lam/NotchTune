import AppKit
import Foundation
import ImageIO
import Testing
@testable import NotchTuneApp

/// The character animates in Core Animation (no per-frame SwiftUI work):
/// each mode installs its frame loop and motion, and a paused glyph runs none.
@MainActor
struct PixelCharacterViewTests {
    private func view(
        _ mode: UnifiedBars.Mode,
        paused: Bool = false,
        character: IslandCharacter = .dino,
        motion: IslandCharacterMotion = .lively
    ) -> PixelCharacterNSView {
        let view = PixelCharacterNSView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        view.apply(.init(character: character, mode: mode, paused: paused, rgba: [1, 1, 1, 1], motion: motion))
        return view
    }

    @Test
    func eachModeRunsItsOwnCoreAnimation() {
        #expect(view(.running).runningAnimationKeys == ["frames", "motion"])
        #expect(view(.idle).runningAnimationKeys == ["frames"])
        #expect(view(.waiting).runningAnimationKeys == ["frames"])
        // Lively, the ghost floats even at rest.
        #expect(view(.idle, character: .ghost).runningAnimationKeys == ["frames", "motion"])
    }

    @Test
    func calmNeverMovesTheWholeSprite() {
        for character in IslandCharacter.allCases {
            for mode in [UnifiedBars.Mode.idle, .running, .waiting] {
                let glyph = view(mode, character: character, motion: .calm)
                #expect(glyph.runningAnimationKeys == ["frames"], "\(character) \(mode) moves the whole sprite when Calm")
            }
        }
    }

    @Test
    func stillShowsOneFramePerStateAndRunsNothing() {
        for character in IslandCharacter.allCases {
            for mode in [UnifiedBars.Mode.idle, .running, .waiting] {
                let glyph = view(mode, character: character, motion: .still)
                #expect(glyph.runningAnimationKeys.isEmpty, "\(character) \(mode)")
                #expect(glyph.hasSpriteContents, "\(character) \(mode)")
            }
        }
    }

    @Test
    func calmIsTheDefault() {
        #expect(IslandAppearancePreferences().characterMotion == .calm)
        #expect(PixelCharacterNSView.Config(character: .dino, mode: .idle, paused: false, rgba: [1, 1, 1, 1]).motion == .calm)
    }

    @Test
    func theFrameLoopStepsThroughEveryStep() {
        let running = view(.running, character: .claude)
        #expect(running.frameAnimationImageCount == IslandCharacter.claude.sprite.working.steps.count)
        let calm = view(.running, character: .claude, motion: .calm)
        #expect(calm.frameAnimationImageCount == IslandCharacter.claude.sprite.calmWorking.steps.count)
    }

    @Test
    func pausedGlyphIsAStaticFrame() {
        let paused = view(.running, paused: true)
        #expect(paused.runningAnimationKeys.isEmpty)
        #expect(paused.hasSpriteContents)
    }

    @Test
    func everyCharacterRendersInEveryMode() {
        for character in IslandCharacter.allCases {
            for mode in [UnifiedBars.Mode.idle, .running, .waiting] {
                let glyph = view(mode, character: character)
                #expect(glyph.hasSpriteContents, "\(character) \(mode)")
                #expect(glyph.runningAnimationKeys.contains("frames"), "\(character) \(mode) has no frame loop")
            }
        }
    }

    @Test
    func rendererCacheStaysBounded() {
        let color = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        for side in stride(from: CGFloat(10), through: 60, by: 1) {
            for character in IslandCharacter.allCases {
                for frame in character.sprite.frames {
                    _ = PixelCharacterRenderer.image(frame: frame, color: color, side: side, scale: 2)
                }
            }
        }
        #expect(PixelCharacterRenderer.cachedImageCount <= PixelCharacterRenderer.cacheLimit)
    }

    @Test
    func retinaNotchGlyphDrawsOnWholePixels() {
        // 24pt at 2x: 3px cells, so every dot starts on a pixel boundary.
        let geometry = PixelCharacterRenderer.geometry(columns: 14, rows: 14, side: 24, scale: 2)
        #expect(geometry.cell == 3)
        #expect(geometry.originX == geometry.originX.rounded())
        #expect(geometry.cell * 14 <= CGFloat(geometry.pixels))
    }
}

/// The sprite data (generated from scripts/generate-pixel-sprites.py).
struct PixelCharacterSpriteTests {
    @Test
    func persistedCharacterNamesNeverChange() {
        for name in ["dino", "ghost", "crab", "duck", "claude"] {
            #expect(IslandCharacter(rawValue: name) != nil, "\(name) must keep decoding")
        }
        #expect(IslandCharacter.allCases.count >= 10)
    }

    @Test
    func everyFrameIsOnTheSharedGridAndEverySequenceIsWellFormed() {
        for character in IslandCharacter.allCases {
            let sprite = character.sprite
            #expect(!character.title.isEmpty)
            for frame in sprite.frames {
                #expect(frame.width == 14 && frame.height == 14, "\(character)")
                #expect(frame.cells.contains(1), "\(character) has a blank frame")
            }
            for sequence in [sprite.idle, sprite.working, sprite.waiting,
                             sprite.calmIdle, sprite.calmWorking, sprite.calmWaiting] {
                #expect(!sequence.steps.isEmpty)
                for step in sequence.steps {
                    #expect(sprite.frames.indices.contains(step.frame), "\(character)")
                    #expect(step.duration > 0)
                }
            }
        }
    }

    @Test
    func workingLoopsAreLivelyAndStayInStepWithTheirHop() {
        for character in IslandCharacter.allCases {
            let working = character.sprite.working
            #expect(Set(working.steps.map(\.frame)).count >= 3, "\(character) needs a real work cycle")
            #expect(working.cycleDuration <= 1.2, "\(character) works too slowly")
            guard let motion = working.motion, motion.curve == .hop else { continue }
            // The hop must land on the same frames every loop.
            let ratio = max(working.cycleDuration, motion.period) / min(working.cycleDuration, motion.period)
            #expect(abs(ratio - ratio.rounded()) < 0.01, "\(character) hop drifts against its frames")
        }
    }

    @Test
    func idleIsMostlyStillWithMomentsOfLife() {
        for character in IslandCharacter.allCases {
            let idle = character.sprite.idle
            let rest = idle.steps[0].frame
            let restTime = idle.steps.filter { $0.frame == rest }.reduce(0) { $0 + $1.duration }
            #expect(idle.cycleDuration >= 4, "\(character) idles too busily")
            #expect(restTime / idle.cycleDuration >= 0.6, "\(character) is rarely still")
            #expect(Set(idle.steps.map(\.frame)).count >= 3, "\(character) needs a blink and a fidget")
        }
    }

    @Test
    func waitingShowsANeedsYouCue() {
        for character in IslandCharacter.allCases {
            let sprite = character.sprite
            let waitingFrames = Set(sprite.waiting.steps.map(\.frame))
            #expect(waitingFrames.count >= 2, "\(character) waiting must change, not just pulse")
            #expect(waitingFrames.contains { sprite.frames[$0] != sprite.rest }, "\(character)")
        }
    }

    @Test
    func calmIdleIsNearlyStill() {
        for character in IslandCharacter.allCases {
            let idle = character.sprite.calmIdle
            let rest = idle.steps[0].frame
            let restTime = idle.steps.filter { $0.frame == rest }.reduce(0) { $0 + $1.duration }
            #expect(idle.steps[0].frame == character.sprite.idle.steps[0].frame, "\(character) rests on another pose when Calm")
            #expect(idle.cycleDuration >= 12, "\(character) idles too busily when Calm")
            #expect(restTime / idle.cycleDuration >= 0.8, "\(character) is rarely still when Calm")
            #expect(idle.motion == nil)
            // Moments of life stay rare: a few seconds of rest between them.
            let restSpells = idle.steps.filter { $0.frame == rest }.map(\.duration)
            #expect(restSpells.max() ?? 0 >= 4, "\(character)")
        }
    }

    @Test
    func calmWorkIsSlowAndInPlace() {
        for character in IslandCharacter.allCases {
            let sprite = character.sprite
            let working = sprite.calmWorking
            #expect(working.motion == nil, "\(character)")
            #expect(Set(working.steps.map(\.frame)).count >= 2, "\(character) must still show it's busy")
            for step in working.steps {
                #expect(step.duration >= 0.25, "\(character) flickers when Calm")
            }
            // Calm work is calmer than Lively work.
            let lively = sprite.working.cycleDuration / Double(sprite.working.steps.count)
            let calm = working.cycleDuration / Double(working.steps.count)
            #expect(calm >= lively * 2, "\(character) works as fast when Calm")
        }
    }

    @Test
    func calmWaitingHoldsANeedsYouCue() {
        for character in IslandCharacter.allCases {
            let sprite = character.sprite
            let waiting = sprite.calmWaiting
            #expect(waiting.motion == nil, "\(character)")
            // Still shows this first frame: it must read as "needs you".
            #expect(sprite.frames[waiting.steps[0].frame] != sprite.rest, "\(character)")
            for step in waiting.steps {
                #expect(sprite.frames[step.frame] != sprite.rest, "\(character) drops its cue while waiting")
                #expect(step.duration >= 0.8, "\(character) flashes when Calm")
            }
        }
    }

    @Test
    func stillPicksEachStatesCalmPose() {
        for character in IslandCharacter.allCases {
            let sprite = character.sprite
            for mode in [UnifiedBars.Mode.idle, .running, .waiting] {
                let still = sprite.sequence(for: mode, motion: .still)
                #expect(still.steps.count == 1 && still.motion == nil, "\(character) \(mode)")
                #expect(still.steps[0].frame == sprite.sequence(for: mode, motion: .calm).steps[0].frame)
            }
            #expect(sprite.sequence(for: .idle, motion: .still).steps[0].frame == sprite.idle.steps[0].frame)
        }
    }

    @Test
    func claudeDancesLikeClawd() {
        // The CLI's moves: feet tap one pair then the other, arms go up.
        let sprite = IslandCharacter.claude.sprite
        let rest = sprite.rest
        let working = Set(sprite.working.steps.map(\.frame)).map { sprite.frames[$0] }
        func legCells(_ frame: PixelFrame) -> Int {
            (10...11).reduce(0) { total, row in total + (0..<frame.width).filter { frame[row, $0] == 1 }.count }
        }
        #expect(working.contains { legCells($0) < legCells(rest) }, "Claude never lifts a foot")
        #expect(working.contains { frame in
            (0..<frame.width).contains { frame[5, $0] == 1 && $0 < 2 }
        }, "Claude never throws its arms up")
    }

    @Test
    func motionCurvesRepeatEveryPeriod() {
        for character in IslandCharacter.allCases {
            for motion in [character.sprite.idle.motion, character.sprite.working.motion, character.sprite.waiting.motion] {
                guard let motion else { continue }
                #expect(abs(motion.offset(at: 0.03) - motion.offset(at: 0.03 + motion.period)) < 0.0001)
                #expect(abs(motion.offset(at: 0)) < 0.0001, "\(character) motion must start at rest")
            }
        }
    }
}

/// `NOTCHTUNE_SPRITE_SHEET_DIR=/some/dir swift test --filter PixelSpriteContactSheet`
/// writes every frame of every character and state, drawn by the real
/// renderer, into a contact sheet: big frames plus real notch sizes.
struct PixelSpriteContactSheet {
    /// Rows per character: Lively idle / working / waiting, then Calm.
    static func sequences(_ sprite: PixelCharacterSprite) -> [PixelSequence] {
        [sprite.idle, sprite.working, sprite.waiting, sprite.calmIdle, sprite.calmWorking, sprite.calmWaiting]
    }

    @Test
    func writeContactSheet() throws {
        guard let directory = ProcessInfo.processInfo.environment["NOTCHTUNE_SPRITE_SHEET_DIR"] else { return }
        let ink = CGColor(srgbRed: 0.04, green: 0.04, blue: 0.045, alpha: 1)
        let paper = CGColor(srgbRed: 0xf1 / 255, green: 0xea / 255, blue: 0xd9 / 255, alpha: 1)
        let big: CGFloat = 84
        let realSides: [(side: CGFloat, scale: CGFloat)] = [(24, 2), (18, 2), (24, 1)]
        let gap: CGFloat = 10
        let characters = IslandCharacter.allCases
        let columns = characters.map { c in
            Self.sequences(c.sprite).map { Set($0.steps.map(\.frame)).count }.max() ?? 1
        }.max() ?? 1
        let realWidth = realSides.reduce(0) { $0 + $1.side * $1.scale + gap }
        let width = Int(gap + CGFloat(columns) * (big + gap) + realWidth + gap)
        let height = Int(gap + CGFloat(characters.count * 6) * (big + gap))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.35, green: 0.36, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var row = 0
        for character in characters {
            let sprite = character.sprite
            for sequence in Self.sequences(sprite) {
                var seen: [Int] = []
                for step in sequence.steps where !seen.contains(step.frame) { seen.append(step.frame) }
                let y = CGFloat(height) - gap - CGFloat(row + 1) * (big + gap) + gap
                var x = gap
                for index in seen {
                    context.setFillColor(ink)
                    context.fill(CGRect(x: x, y: y, width: big, height: big))
                    if let image = PixelCharacterRenderer.draw(frame: sprite.frames[index], color: paper, side: big, scale: 1) {
                        context.draw(image, in: CGRect(x: x, y: y, width: big, height: big))
                    }
                    x += big + gap
                }
                x = gap + CGFloat(columns) * (big + gap)
                for real in realSides {
                    let pixels = real.side * real.scale
                    context.setFillColor(ink)
                    context.fill(CGRect(x: x, y: y + big - pixels, width: pixels, height: pixels))
                    if let first = seen.first,
                       let image = PixelCharacterRenderer.draw(frame: sprite.frames[first], color: paper, side: real.side, scale: real.scale) {
                        context.interpolationQuality = .none
                        context.draw(image, in: CGRect(x: x, y: y + big - pixels, width: pixels, height: pixels))
                    }
                    x += pixels + gap
                }
                row += 1
            }
        }
        let image = try #require(context.makeImage())
        let url = URL(fileURLWithPath: directory).appendingPathComponent("pixel-sprites.png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
