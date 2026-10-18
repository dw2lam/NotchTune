import AppKit
import SwiftUI

/// The island character, drawn once per (frame, tint, size) into images and
/// animated with Core Animation keyframes: each mode's frame sequence (walk
/// cycles, blinks, glances, the "needs you" wave) and, when Lively, its
/// smooth hop / sway all run in the render server. Still installs nothing. A SwiftUI `TimelineView` + `Canvas`
/// re-rendered and re-laid-out the whole notch window on every frame — ~9%
/// CPU while an agent worked.
struct PixelCharacterView: NSViewRepresentable {
    var character: IslandCharacter
    var mode: UnifiedBars.Mode
    var paused: Bool
    var tint: Color
    /// `nil` follows the environment's `islandCharacterMotion` (the
    /// user's Character motion setting where the island sets it).
    var motion: IslandCharacterMotion? = nil

    func makeNSView(context: Context) -> PixelCharacterNSView {
        PixelCharacterNSView()
    }

    func updateNSView(_ view: PixelCharacterNSView, context: Context) {
        let rgba = NSColor(tint).usingColorSpace(.sRGB) ?? .white
        view.apply(
            PixelCharacterNSView.Config(
                character: character,
                mode: mode,
                paused: paused,
                rgba: [rgba.redComponent, rgba.greenComponent, rgba.blueComponent, rgba.alphaComponent],
                motion: motion ?? context.environment.islandCharacterMotion
            )
        )
    }
}

final class PixelCharacterNSView: NSView {
    struct Config: Equatable {
        var character: IslandCharacter
        var mode: UnifiedBars.Mode
        var paused: Bool
        var rgba: [CGFloat]
        var motion: IslandCharacterMotion = .calm
    }

    static let framesAnimationKey = "frames"
    static let motionAnimationKey = "motion"

    private let sprite = CALayer()
    private var config: Config?
    private var builtSize: CGSize = .zero

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        sprite.contentsGravity = .resize
        layer?.addSublayer(sprite)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Test seam: the Core Animation keys currently running on the sprite.
    var runningAnimationKeys: Set<String> { Set(sprite.animationKeys() ?? []) }
    var hasSpriteContents: Bool { sprite.contents != nil }
    /// Test seam: the frame images the running frame animation steps through.
    var frameAnimationImageCount: Int {
        (sprite.animation(forKey: Self.framesAnimationKey) as? CAKeyframeAnimation)?.values?.count ?? 0
    }

    func apply(_ newConfig: Config) {
        guard newConfig != config else { return }
        config = newConfig
        rebuild()
    }

    override func layout() {
        super.layout()
        if bounds.size != builtSize { rebuild() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuild()
    }

    // MARK: - Building

    private func rebuild() {
        guard let config, bounds.width > 0, bounds.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        builtSize = bounds.size

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        sprite.removeAllAnimations()
        sprite.frame = bounds
        sprite.contentsScale = scale

        let character = config.character.sprite
        let color = CGColor(srgbRed: config.rgba[0], green: config.rgba[1], blue: config.rgba[2], alpha: config.rgba[3])
        let side = min(bounds.width, bounds.height)
        let render: (PixelFrame) -> CGImage? = { frame in
            PixelCharacterRenderer.image(frame: frame, color: color, side: side, scale: scale)
        }

        guard !config.paused else {
            sprite.contents = render(character.rest)
            return
        }

        let sequence = character.sequence(for: config.mode, motion: config.motion)
        var images: [Int: CGImage] = [:]
        for step in sequence.steps where images[step.frame] == nil {
            images[step.frame] = render(character.frames[step.frame])
        }
        let first = sequence.steps.first.flatMap { images[$0.frame] }
        sprite.contents = first

        // Frame sequence: discrete contents swaps at each step's start.
        let values = sequence.steps.compactMap { images[$0.frame] }
        if values.count == sequence.steps.count, values.count > 1 {
            let total = sequence.cycleDuration
            var elapsed: TimeInterval = 0
            var keyTimes: [NSNumber] = []
            for step in sequence.steps {
                keyTimes.append(NSNumber(value: elapsed / total))
                elapsed += step.duration
            }
            keyTimes.append(1)
            let frames = CAKeyframeAnimation(keyPath: "contents")
            frames.values = values
            frames.keyTimes = keyTimes
            frames.calculationMode = .discrete
            frames.duration = total
            frames.repeatCount = .infinity
            sprite.add(frames, forKey: Self.framesAnimationKey)
        }

        // Smooth hop / sway, sampled over one period.
        if let motion = sequence.motion, let reference = sequence.steps.first {
            let cell = PixelCharacterRenderer.cellPoints(
                for: character.frames[reference.frame], side: side, scale: scale
            )
            let samples = 24
            let animation = CAKeyframeAnimation(
                keyPath: motion.axis == .y ? "transform.translation.y" : "transform.translation.x"
            )
            animation.values = (0...samples).map { index in
                let offset = motion.offset(at: motion.period * Double(index) / Double(samples)) * cell
                // Flipped view: up is negative y.
                return motion.axis == .y ? -offset : offset
            }
            animation.duration = motion.period
            animation.repeatCount = .infinity
            sprite.add(animation, forKey: Self.motionAnimationKey)
        }
    }
}

enum PixelCharacterRenderer {
    /// Design box the glyph is laid out in.
    static let box: CGFloat = 24
    /// Share of the glyph the character grid spans.
    static let extentRatio: CGFloat = 21.0 / 24.0
    /// A pixel's share of its cell (the rest is the dot-matrix gap).
    static let dotRatio: CGFloat = 0.9
    /// Opacity of '+' (dim) pixels.
    static let dimAlpha: CGFloat = 0.38
    /// Images kept across views; cleared when it overflows.
    static let cacheLimit = 384

    struct Geometry: Equatable {
        /// Bitmap side in pixels.
        let pixels: Int
        /// One grid cell, in pixels.
        let cell: CGFloat
        let originX: CGFloat
        let originY: CGFloat
    }

    /// Cells of 3px and up snap to whole pixels so every dot starts on a
    /// pixel boundary — crisp at the notch's 24pt on Retina.
    static func geometry(columns: Int, rows: Int, side: CGFloat, scale: CGFloat) -> Geometry {
        let pixels = max(1, Int((side * scale).rounded(.up)))
        let span = CGFloat(max(columns, rows, 1))
        var cell = CGFloat(pixels) * extentRatio / span
        if cell >= 3 {
            cell = cell.rounded()
            if cell * span > CGFloat(pixels) { cell -= 1 }
        }
        return Geometry(
            pixels: pixels,
            cell: cell,
            originX: ((CGFloat(pixels) - cell * CGFloat(columns)) / 2).rounded(),
            originY: ((CGFloat(pixels) - cell * CGFloat(rows)) / 2).rounded()
        )
    }

    /// One grid cell in points — the unit motion amplitudes are given in.
    static func cellPoints(for frame: PixelFrame, side: CGFloat, scale: CGFloat) -> CGFloat {
        geometry(columns: frame.width, rows: frame.height, side: side, scale: scale).cell / max(scale, 1)
    }

    private struct Key: Hashable {
        let frame: PixelFrame
        let rgba: [CGFloat]
        let side: CGFloat
        let scale: CGFloat
    }

    @MainActor private static var cache: [Key: CGImage] = [:]

    @MainActor static var cachedImageCount: Int { cache.count }

    @MainActor
    static func image(frame: PixelFrame, color: CGColor, side: CGFloat, scale: CGFloat) -> CGImage? {
        let rgba = color.components ?? [1, 1, 1, 1]
        let key = Key(frame: frame, rgba: rgba, side: side, scale: scale)
        if let cached = cache[key] { return cached }

        let image = draw(frame: frame, color: color, side: side, scale: scale)
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[key] = image
        return image
    }

    /// Uncached drawing (also used by the sprite contact-sheet test).
    static func draw(frame: PixelFrame, color: CGColor, side: CGFloat, scale: CGFloat) -> CGImage? {
        let geometry = geometry(columns: frame.width, rows: frame.height, side: side, scale: scale)
        guard let context = CGContext(
            data: nil, width: geometry.pixels, height: geometry.pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // y-down, in pixels.
        context.translateBy(x: 0, y: CGFloat(geometry.pixels))
        context.scaleBy(x: 1, y: -1)

        let dot = geometry.cell * dotRatio
        let corner = dot * 0.12
        let full = CGMutablePath()
        let dim = CGMutablePath()
        for row in 0..<frame.height {
            for column in 0..<frame.width {
                let value = frame[row, column]
                guard value != 0 else { continue }
                let rect = CGRect(
                    x: geometry.originX + CGFloat(column) * geometry.cell,
                    y: geometry.originY + CGFloat(row) * geometry.cell,
                    width: dot,
                    height: dot
                )
                (value == 1 ? full : dim).addRoundedRect(in: rect, cornerWidth: corner, cornerHeight: corner)
            }
        }
        context.setFillColor(color)
        context.addPath(full)
        context.fillPath()
        if !dim.isEmpty {
            context.setFillColor(color.copy(alpha: color.alpha * dimAlpha) ?? color)
            context.addPath(dim)
            context.fillPath()
        }
        return context.makeImage()
    }
}

private struct IslandCharacterMotionKey: EnvironmentKey {
    static let defaultValue: IslandCharacterMotion = .calm
}

extension EnvironmentValues {
    /// How much pixel characters below move (the Character motion setting).
    var islandCharacterMotion: IslandCharacterMotion {
        get { self[IslandCharacterMotionKey.self] }
        set { self[IslandCharacterMotionKey.self] = newValue }
    }
}
