import CoreGraphics
import Foundation

/// One picture of a pixel character on its grid.
struct PixelFrame: Hashable, Sendable {
    let width: Int
    let height: Int
    /// Row-major cells: 0 = empty, 1 = pixel, 2 = dim pixel.
    let cells: [UInt8]

    /// Rows top to bottom: '#' = pixel, '+' = dim pixel, anything else = empty.
    init(_ rows: String...) {
        height = rows.count
        width = rows.first?.utf8.count ?? 0
        var cells: [UInt8] = []
        cells.reserveCapacity(width * height)
        for row in rows {
            precondition(row.utf8.count == width, "ragged pixel frame")
            for byte in row.utf8 {
                cells.append(byte == UInt8(ascii: "#") ? 1 : byte == UInt8(ascii: "+") ? 2 : 0)
            }
        }
        self.cells = cells
    }

    subscript(row: Int, column: Int) -> UInt8 {
        cells[row * width + column]
    }
}

/// A smooth whole-sprite movement layered over a frame sequence, run by Core
/// Animation (no per-frame app work).
struct PixelMotion: Hashable, Sendable {
    enum Curve: Hashable, Sendable {
        /// Bounces up and lands every `period`: |sin|.
        case hop
        /// Swings both ways over `period`: sin.
        case wave
    }

    enum Axis: Hashable, Sendable {
        case x
        case y
    }

    let curve: Curve
    let axis: Axis
    /// Peak offset in grid cells.
    let amplitude: CGFloat
    let period: TimeInterval

    /// Offset in grid cells at `time` (up / right is positive).
    func offset(at time: TimeInterval) -> CGFloat {
        let phase = time / period
        switch curve {
        case .hop: return abs(sin(phase * .pi)) * amplitude
        case .wave: return sin(phase * 2 * .pi) * amplitude
        }
    }
}

/// Frames shown in turn, each for its duration, looping.
struct PixelSequence: Sendable {
    let steps: [(frame: Int, duration: TimeInterval)]
    let motion: PixelMotion?

    var cycleDuration: TimeInterval {
        steps.reduce(0) { $0 + $1.duration }
    }
}

/// A character's art and its loops: Lively (with optional hops / sways) and
/// Calm (no whole-sprite motion) for each state. The data lives in the
/// generated PixelSprites.swift (scripts/generate-pixel-sprites.py).
struct PixelCharacterSprite: Sendable {
    let frames: [PixelFrame]
    /// Lively: mostly still, with brief moments of life (blinks, glances, fidgets).
    let idle: PixelSequence
    /// Lively: an agent is working.
    let working: PixelSequence
    /// Lively: an agent needs the user.
    let waiting: PixelSequence
    /// Calm: long rests, an occasional blink or glance.
    let calmIdle: PixelSequence
    /// Calm: small in-place changes at a slow pace.
    let calmWorking: PixelSequence
    /// Calm: a steady "needs you" cue that changes slowly.
    let calmWaiting: PixelSequence

    /// The still pose: paused glyphs and static previews.
    var rest: PixelFrame {
        frames[idle.steps[0].frame]
    }

    func sequence(for mode: UnifiedBars.Mode, motion: IslandCharacterMotion = .lively) -> PixelSequence {
        switch motion {
        case .lively:
            switch mode {
            case .idle: idle
            case .running: working
            case .waiting: waiting
            }
        case .calm:
            switch mode {
            case .idle: calmIdle
            case .running: calmWorking
            case .waiting: calmWaiting
            }
        case .still:
            // One frame per state: the calm loop's first (calm waiting
            // opens on its "needs you" frame).
            PixelSequence(steps: [(sequence(for: mode, motion: .calm).steps[0].frame, 1)], motion: nil)
        }
    }
}
