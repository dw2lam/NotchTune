import SwiftUI
import AppKit

/// Where the closed / compact pill should adopt Liquid Glass.
enum GlassClosedScope: String, CaseIterable, Identifiable, Sendable {
    case off            // never — the closed pill stays solid ink
    case externalOnly   // only on external (non-notched) displays
    case always         // every display, including the built-in notch

    var id: String { rawValue }
}

/// The Liquid Glass material variant. `clear` is the transparent, light-bending
/// glass (most "liquid"); `regular` is the frosted, more opaque control material.
enum GlassStyle: String, CaseIterable, Identifiable, Sendable {
    case clear
    case regular

    var id: String { rawValue }
}

/// A fully resolved glass instruction for one surface: the material variant plus
/// the tint to apply. `nil` (at the call site) means render solid ink instead.
struct ResolvedGlass: Equatable {
    var style: GlassStyle
    var tint: Color
}

/// User-configurable Liquid Glass appearance. Stored globally (not per display
/// profile) since it is a cross-cutting material choice. Persisted by `AppModel`.
///
/// Defaults to the curated look: clear, lightly dark-tinted glass on the open
/// panel and on closed pills on external displays, leaving the notched-Mac
/// closed pill solid so it still merges with the physical notch.
struct LiquidGlassSettings: Equatable, Sendable {
    var isEnabled: Bool = true
    var style: GlassStyle = .clear
    /// Tint hue, sRGB components 0...1. Default black keeps the dark "ink" identity.
    var tintRed: Double = 0
    var tintGreen: Double = 0
    var tintBlue: Double = 0
    /// How strongly the tint colors / darkens the glass (0 = pure glass, 1 = opaque tint).
    /// Kept low by default so the material's lensing/specular still reads.
    var tintStrength: Double = 0.22
    /// Apply glass to the expanded / open panel.
    var openView: Bool = true
    /// Where the closed / compact pill adopts glass.
    var closedScope: GlassClosedScope = .externalOnly

    var tintColor: Color {
        Color(.sRGB, red: tintRed, green: tintGreen, blue: tintBlue, opacity: 1)
    }

    /// The tint actually fed to `Glass.tint(_:)` — hue with the configured
    /// strength baked in as opacity. Strength 0 → no tint at all (pure glass).
    var effectiveTint: Color {
        tintStrength <= 0 ? .clear : tintColor.opacity(tintStrength)
    }

    /// Resolved glass for the open panel. `nil` means render the solid ink fill.
    var openGlass: ResolvedGlass? {
        (isEnabled && openView) ? ResolvedGlass(style: style, tint: effectiveTint) : nil
    }

    /// Resolved glass for a closed pill on the given layout. `nil` = solid ink.
    func closedGlass(layout: V6ClosedLayout) -> ResolvedGlass? {
        guard isEnabled else { return nil }
        let resolved = ResolvedGlass(style: style, tint: effectiveTint)
        switch closedScope {
        case .off:          return nil
        case .externalOnly: return layout == .external ? resolved : nil
        case .always:       return resolved
        }
    }
}

/// Liquid Glass is only a real material on macOS 26+. Below that we always fall
/// back to the solid ink fill, regardless of settings.
enum LiquidGlass {
    static var isSupported: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

/// Background fill for an island surface: real Liquid Glass (macOS 26+, when a
/// glass instruction is supplied) clipped to `shape`, otherwise the solid ink
/// fill. Drop in wherever a surface previously used `shape.fill(V6Palette.ink)`.
struct IslandSurfaceBackground<S: Shape>: View {
    var shape: S
    /// `nil` → solid ink. Non-nil → Liquid Glass with the given material + tint.
    var glass: ResolvedGlass?

    var body: some View {
        if let glass, #available(macOS 26.0, *) {
            let base: Glass = glass.style == .regular ? .regular : .clear
            Color.clear.glassEffect(base.tint(glass.tint), in: shape)
        } else {
            shape.fill(V6Palette.ink)
        }
    }
}

extension Color {
    /// sRGB components for persistence. Falls back to black if the color can't
    /// be resolved into the sRGB space (e.g. a catalog/dynamic color).
    func islandResolvedRGB() -> (r: Double, g: Double, b: Double) {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
    }
}
