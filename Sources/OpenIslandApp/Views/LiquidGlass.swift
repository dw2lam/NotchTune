import AppKit
import SwiftUI

enum GlassClosedScope: String, CaseIterable, Identifiable, Sendable {
    case off
    case externalOnly
    case always

    var id: String { rawValue }
}

enum GlassStyle: String, CaseIterable, Identifiable, Sendable {
    case clear
    case regular

    var id: String { rawValue }
}

struct ResolvedGlass: Equatable {
    var style: GlassStyle
    var tint: Color
}

struct LiquidGlassSettings: Equatable, Sendable {
    var isEnabled: Bool = true
    var style: GlassStyle = .clear
    var tintRed: Double = 0
    var tintGreen: Double = 0
    var tintBlue: Double = 0
    var tintStrength: Double = 0.22
    var openView: Bool = true
    var closedScope: GlassClosedScope = .externalOnly

    var tintColor: Color {
        Color(.sRGB, red: tintRed, green: tintGreen, blue: tintBlue, opacity: 1)
    }

    var effectiveTint: Color {
        tintStrength <= 0 ? .clear : tintColor.opacity(tintStrength)
    }

    var openGlass: ResolvedGlass? {
        (isEnabled && openView) ? ResolvedGlass(style: style, tint: effectiveTint) : nil
    }

    func closedGlass(layout: V6ClosedLayout) -> ResolvedGlass? {
        guard isEnabled else { return nil }
        let resolved = ResolvedGlass(style: style, tint: effectiveTint)
        switch closedScope {
        case .off:
            return nil
        case .externalOnly:
            return layout == .external ? resolved : nil
        case .always:
            return resolved
        }
    }
}

enum LiquidGlass {
    static var isSupported: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

struct IslandSurfaceBackground<S: Shape>: View {
    var shape: S
    var glass: ResolvedGlass?

    var body: some View {
        if let glass, #available(macOS 26.0, *) {
            let base: Glass = glass.style == .regular ? .regular : .clear
            GlassEffectContainer {
                Color.clear.glassEffect(base, in: shape)
            }
            .overlay { shape.fill(glass.tint) }
        } else {
            shape.fill(V6Palette.ink)
        }
    }
}

extension Color {
    func islandResolvedRGB() -> (r: Double, g: Double, b: Double) {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
    }
}
