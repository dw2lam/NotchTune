import SwiftUI
import AppKit

/// Where the closed / compact pill should adopt Liquid Glass.
enum GlassClosedScope: String, CaseIterable, Identifiable, Sendable {
    case off            // never — the closed pill stays solid ink
    case externalOnly   // only on external (non-notched) displays
    case always         // every display, including the built-in notch

    var id: String { rawValue }
}

/// User-configurable Liquid Glass appearance. Stored globally (not per display
/// profile) since it is a cross-cutting material choice. Persisted by `AppModel`.
///
/// The default matches the curated look: dark-tinted glass on the open panel
/// and on closed pills on external displays, leaving the notched-Mac closed
/// pill solid so it still merges with the physical notch.
struct LiquidGlassSettings: Equatable, Sendable {
    var isEnabled: Bool = true
    /// Tint hue, sRGB components 0...1. Default black keeps the dark "ink" identity.
    var tintRed: Double = 0
    var tintGreen: Double = 0
    var tintBlue: Double = 0
    /// How strongly the tint colors / darkens the glass (0 = clear, 1 = opaque tint).
    var tintStrength: Double = 0.5
    /// Apply glass to the expanded / open panel.
    var openView: Bool = true
    /// Where the closed / compact pill adopts glass.
    var closedScope: GlassClosedScope = .externalOnly

    var tintColor: Color {
        Color(.sRGB, red: tintRed, green: tintGreen, blue: tintBlue, opacity: 1)
    }

    /// The tint actually fed to `.glassEffect(.regular.tint(_:))` — hue with the
    /// configured strength baked in as opacity.
    var effectiveTint: Color { tintColor.opacity(tintStrength) }

    /// Resolved glass tint for the open panel. `nil` means render the solid ink fill.
    var openTint: Color? { (isEnabled && openView) ? effectiveTint : nil }

    /// Resolved glass tint for a closed pill on the given layout. `nil` = solid ink.
    func closedTint(layout: V6ClosedLayout) -> Color? {
        guard isEnabled else { return nil }
        switch closedScope {
        case .off:          return nil
        case .externalOnly: return layout == .external ? effectiveTint : nil
        case .always:       return effectiveTint
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
/// tint is supplied) clipped to `shape`, otherwise the solid ink fill. Drop in
/// wherever a surface previously used `shape.fill(V6Palette.ink)`.
struct IslandSurfaceBackground<S: Shape>: View {
    var shape: S
    /// `nil` → solid ink. Non-nil → Liquid Glass tinted with this color (the
    /// color already carries the strength as its opacity).
    var glassTint: Color?

    var body: some View {
        if let glassTint {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(glassTint), in: shape)
            } else {
                shape.fill(V6Palette.ink)
            }
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
