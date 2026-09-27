import SwiftUI

// MARK: - Opened-notch control language
//
// The opened panel's backdrop is real Liquid Glass (`IslandSurfaceBackground`).
// This file gives the controls that sit on it the same material so they read as
// native macOS 26 glass controls instead of hand-drawn white-opacity shapes:
//
//   - capsule buttons  → `.glassEffect` capsule; a prominent kind layers its
//                        semantic tint on top (Allow = warm, primary = paper)
//   - circle icons     → `.glassEffect` circle (header gear/power, toast chevrons)
//   - chips / badges   → a lightweight glass bezel (tinted fill + specular rim),
//                        not a live `.glassEffect`: session rows are rasterised
//                        with `drawingGroup()` for scroll performance, and a live
//                        glass effect can't sample the backdrop through that.
//
// Every piece falls back to the pre-glass look (exactly) below macOS 26, or when
// the user turned glass off for the open panel (`glassSettings.openGlass == nil`)
// — the solid-ink panel keeps its solid-ink controls.

// MARK: Environment

private struct IslandControlGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether opened-notch controls render as Liquid Glass. Resolved once at the
    /// island root: macOS 26+ AND the open panel itself is glass.
    var islandControlGlass: Bool {
        get { self[IslandControlGlassKey.self] }
        set { self[IslandControlGlassKey.self] = newValue }
    }
}

extension LiquidGlassSettings {
    /// Controls follow the open panel: glass controls only on a glass panel.
    var usesGlassControls: Bool {
        LiquidGlass.isSupported && openGlass != nil
    }
}

// MARK: Metrics

/// One corner-radius family for the opened notch (4pt steps). Controls that
/// adopt glass are capsules/circles; these cover the rectangular surfaces.
enum IslandRadius {
    /// Tiny inline chips (option index keys, inline code).
    static let chip: CGFloat = 6
    /// Tiles and wells nested inside a card (option rows, command preview,
    /// reply field, legacy action buttons).
    static let inner: CGFloat = 10
    /// Cards that hold other controls (question / completion cards, hints).
    static let card: CGFloat = 14
}

// MARK: Glass primitives

extension View {
    /// Liquid Glass behind this control in `shape`. `tint` is painted as a plain
    /// fill above the material (not via `Glass.tint`) so it is present on the
    /// very first frame of the island's open morph — the material's integrated
    /// tint only resolves on a later re-render there (see `IslandSurfaceBackground`).
    /// No-op below macOS 26; callers branch to their legacy look first.
    @ViewBuilder
    func islandGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = true
    ) -> some View {
        if #available(macOS 26.0, *) {
            self
                .background {
                    if let tint {
                        // A painted tint covers the material's own edge light,
                        // so give it back a top-lit specular rim.
                        shape.fill(tint)
                            .overlay {
                                shape.stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.42), .white.opacity(0.0), .white.opacity(0.14)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                            }
                    }
                }
                .glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            self
        }
    }

    /// Groups sibling glass controls so they share one sampling pass and blend
    /// like native toolbar controls. Plain pass-through when glass is off.
    @ViewBuilder
    func islandGlassContainer(enabled: Bool, spacing: CGFloat? = nil) -> some View {
        if enabled, #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

/// A lightweight glass bezel for chips and badges: tinted translucent fill, a
/// top-lit specular rim, and a faint coloured lower edge. Safe inside
/// `drawingGroup()` (no backdrop sampling).
struct IslandGlassBezel<S: InsettableShape>: View {
    var shape: S
    var tint: Color?
    var isEmphasized = false

    var body: some View {
        shape
            .fill(fill)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(isEmphasized ? 0.34 : 0.26),
                            .white.opacity(0.05),
                            (tint ?? .white).opacity(isEmphasized ? 0.26 : 0.14),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            }
    }

    private var fill: Color {
        if let tint {
            return tint.opacity(isEmphasized ? 0.22 : 0.16)
        }
        return .white.opacity(isEmphasized ? 0.13 : 0.085)
    }
}

// MARK: Button styles

/// Circular icon button (header gear/power, toast queue chevrons).
///
/// The label supplies the glyph and its frame; the style supplies the disc.
struct IslandGlassIconButtonStyle: ButtonStyle {
    /// Pre-glass disc fill.
    var fallbackFill: Color = .white.opacity(0.08)
    /// Pre-glass disc fill while pressed.
    var fallbackPressedFill: Color? = nil
    /// Glyph colour; `nil` leaves the label's own foreground untouched.
    var foreground: Color? = nil
    var pressedForeground: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        IslandGlassIconDisc(
            label: configuration.label,
            isPressed: configuration.isPressed,
            fallbackFill: fallbackFill,
            fallbackPressedFill: fallbackPressedFill,
            foreground: foreground,
            pressedForeground: pressedForeground
        )
    }
}

/// Body of `IslandGlassIconButtonStyle`, a real view so it can read the
/// environment (and be reused by other icon styles).
struct IslandGlassIconDisc<Label: View>: View {
    var label: Label
    var isPressed: Bool
    var fallbackFill: Color
    var fallbackPressedFill: Color?
    var foreground: Color?
    var pressedForeground: Color?

    @Environment(\.islandControlGlass) private var usesGlass

    var body: some View {
        let glyph = label
            .foregroundStyle(glyphStyle)
            .contentShape(Circle())

        if usesGlass, LiquidGlass.isSupported {
            glyph
                .islandGlass(in: Circle())
                .scaleEffect(isPressed ? 0.94 : 1)
                .animation(.easeOut(duration: 0.12), value: isPressed)
        } else {
            glyph
                .background(
                    isPressed ? (fallbackPressedFill ?? fallbackFill) : fallbackFill,
                    in: Circle()
                )
        }
    }

    private var glyphStyle: AnyShapeStyle {
        if isPressed, let pressedForeground {
            return AnyShapeStyle(pressedForeground)
        }
        if let foreground {
            return AnyShapeStyle(foreground)
        }
        return AnyShapeStyle(.foreground)
    }
}

extension View {
    /// Chip / badge background: the glass bezel when glass controls are on,
    /// otherwise `fallback` (the caller's exact pre-glass styling).
    @ViewBuilder
    func islandChipBackground<S: InsettableShape, Fallback: View>(
        _ shape: S,
        usesGlass: Bool,
        tint: Color? = nil,
        isEmphasized: Bool = false,
        @ViewBuilder fallback: (Self) -> Fallback
    ) -> some View {
        if usesGlass {
            background { IslandGlassBezel(shape: shape, tint: tint, isEmphasized: isEmphasized) }
        } else {
            fallback(self)
        }
    }
}
