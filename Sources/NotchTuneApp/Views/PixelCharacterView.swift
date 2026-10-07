import AppKit
import SwiftUI

/// The island character, drawn once per (character, frame, tint, size) into
/// images and animated with Core Animation keyframes: the running frame-swap
/// and bounce, the idle blink and the waiting pulse all run in the render
/// server. A SwiftUI `TimelineView` + `Canvas` re-rendered and re-laid-out
/// the whole notch window on every frame — ~9% CPU while an agent worked.
struct PixelCharacterView: NSViewRepresentable {
    var character: IslandCharacter
    var mode: UnifiedBars.Mode
    var paused: Bool
    var tint: Color

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
                rgba: [rgba.redComponent, rgba.greenComponent, rgba.blueComponent, rgba.alphaComponent]
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
    }

    private let sprite = CALayer()
    private var config: Config?
    private var builtSize: CGSize = .zero
    private var builtScale: CGFloat = 0

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
        builtScale = scale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        sprite.removeAllAnimations()
        sprite.frame = bounds
        sprite.contentsScale = scale
        sprite.opacity = 1

        let character = config.character
        let color = CGColor(srgbRed: config.rgba[0], green: config.rgba[1], blue: config.rgba[2], alpha: config.rgba[3])
        let side = min(bounds.width, bounds.height)
        let render: (PixelFrame) -> CGImage? = { frame in
            PixelCharacterRenderer.image(frame: frame, color: color, side: side, scale: scale)
        }
        let idle = render(character.idleFrame)
        sprite.contents = idle

        guard !config.paused, let idle else { return }
        let unit = side / PixelCharacterRenderer.box

        switch config.mode {
        case .running:
            // 5fps frame swap: idle for 0.2s, running for 0.2s.
            if let running = render(character.runningFrame) {
                let swap = CAKeyframeAnimation(keyPath: "contents")
                swap.values = [idle, running]
                swap.keyTimes = [0, 0.5]
                swap.calculationMode = .discrete
                swap.duration = 0.4
                swap.repeatCount = .infinity
                sprite.add(swap, forKey: "frameSwap")
            }
            // The character's bounce curve, sampled over one period.
            let period = character.runningBouncePeriod
            let samples = 24
            let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bounce.values = (0...samples).map { index in
                -character.runningBounce(time: period * Double(index) / Double(samples)) * unit
            }
            bounce.duration = period
            bounce.repeatCount = .infinity
            sprite.add(bounce, forKey: "bounce")

        case .idle:
            // A 0.15s blink at the start of every 3s.
            if let eye = character.eyeCoordinate {
                var blinkFrame = character.idleFrame
                blinkFrame[eye.row][eye.column] = 1
                if let blink = render(blinkFrame) {
                    let blinkAnimation = CAKeyframeAnimation(keyPath: "contents")
                    blinkAnimation.values = [blink, idle]
                    blinkAnimation.keyTimes = [0, NSNumber(value: 0.15 / 3.0)]
                    blinkAnimation.calculationMode = .discrete
                    blinkAnimation.duration = 3
                    blinkAnimation.repeatCount = .infinity
                    sprite.add(blinkAnimation, forKey: "blink")
                }
            }

        case .waiting:
            // 0.45 ↔ 1.0 cosine pulse over 1.8s.
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.45
            pulse.toValue = 1.0
            pulse.duration = 0.9
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sprite.add(pulse, forKey: "pulse")
        }
    }
}

typealias PixelFrame = [[Int]]

enum PixelCharacterRenderer {
    /// Design box the 9×9 grid is laid out in (matches the old Canvas math).
    static let box: CGFloat = 24
    private static let pixelSize: CGFloat = 1.6
    private static let gap: CGFloat = 0.35

    private struct Key: Hashable {
        let frame: [[Int]]
        let rgba: [CGFloat]
        let side: CGFloat
        let scale: CGFloat
    }

    @MainActor private static var cache: [Key: CGImage] = [:]

    @MainActor
    static func image(frame: PixelFrame, color: CGColor, side: CGFloat, scale: CGFloat) -> CGImage? {
        let rgba = color.components ?? [1, 1, 1, 1]
        let key = Key(frame: frame, rgba: rgba, side: side, scale: scale)
        if let cached = cache[key] { return cached }

        let pixels = max(1, Int((side * scale).rounded(.up)))
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // y-down, in design-box units.
        let unitToPixel = CGFloat(pixels) / box
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: unitToPixel, y: -unitToPixel)
        context.setFillColor(color)

        let grid = frame.count
        let total = CGFloat(grid) * pixelSize + CGFloat(grid - 1) * gap
        let start = (box - total) / 2
        for row in 0..<grid {
            for column in 0..<frame[row].count where frame[row][column] == 1 {
                let rect = CGRect(
                    x: start + CGFloat(column) * (pixelSize + gap),
                    y: start + CGFloat(row) * (pixelSize + gap),
                    width: pixelSize,
                    height: pixelSize
                )
                context.addPath(CGPath(roundedRect: rect, cornerWidth: 0.2, cornerHeight: 0.2, transform: nil))
            }
        }
        context.fillPath()

        let image = context.makeImage()
        if cache.count > 256 { cache.removeAll() }
        cache[key] = image
        return image
    }
}
