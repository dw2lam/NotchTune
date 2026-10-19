import AppKit
import SwiftUI

// MARK: - Theme

/// Settings wears the notch's look on real glass: the desktop shows through
/// the whole window, blurred and darkened enough for paper (#F1EAD9) type.
/// Colour comes from the app icon's sky (the accent) and from each
/// section's own tile; the island's status colours mark only status.
/// Always dark, like the island.
enum SettingsTheme {
    /// The opaque stand-in for the glass, when Reduce Transparency is on: a
    /// warm near-black, a step up from the island's pure ink.
    static let window = Color(red: 0.055, green: 0.051, blue: 0.047)
    /// Laid over the window's frost: dense enough that a loud wallpaper
    /// only tints the window, light enough that the desktop still glows
    /// through.
    static let glassTint = Color(red: 0.03, green: 0.03, blue: 0.035).opacity(0.72)
    /// The island's own ink, for tiles that stand in for the hardware.
    static let ink = V6Palette.ink
    static let paper = V6Palette.paper

    /// The app icon's sky, lifted for dark glass: switches, the selected
    /// segmented thumb, picture-tile rings and checks.
    static let accent = Color(red: 0.25, green: 0.68, blue: 0.98)
    /// Glyphs and type on an accent fill.
    static let onAccent = Color.white

    /// Raised surfaces on the glass (cards): frosted a shade lighter.
    static let surfaceFill = paper.opacity(0.06)
    static let surfaceStroke = paper.opacity(0.09)
    /// Hairline between rows.
    static let hairline = paper.opacity(0.085)
    /// Hovered surfaces.
    static let hoverFill = paper.opacity(0.06)

    /// Status colours, shared with the island's session dots.
    static let positive = IslandDesignPalette.Status.completed
    static let informative = IslandDesignPalette.Status.running
    static let caution = IslandDesignPalette.Status.waitingAggregate
    static let critical = IslandDesignPalette.Status.waitingForApproval

    /// The row of section tabs across the top, title bar included.
    static let tabBarHeight: CGFloat = 72
    static let surfaceRadius: CGFloat = IslandRadius.card + 2
}

/// A section's colour: a two-stop gradient, lit from the top like the
/// island's glass, for its tab tile, its hero tile and the glow behind
/// the hero.
struct SettingsTint: Equatable, Sendable {
    let top: Color
    let bottom: Color
    /// The glyph drawn on the tile.
    var glyph: Color = .white

    var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static let graphite = SettingsTint(top: Color(red: 0.62, green: 0.65, blue: 0.72), bottom: Color(red: 0.36, green: 0.39, blue: 0.45))
    /// The app icon's grass.
    static let grass = SettingsTint(top: Color(red: 0.30, green: 0.85, blue: 0.47), bottom: Color(red: 0.05, green: 0.62, blue: 0.26))
    /// The app icon's sky.
    static let sky = SettingsTint(top: Color(red: 0.38, green: 0.80, blue: 1.0), bottom: Color(red: 0.09, green: 0.51, blue: 0.90))
    static let rose = SettingsTint(top: Color(red: 1.0, green: 0.45, blue: 0.58), bottom: Color(red: 0.89, green: 0.20, blue: 0.37))
    static let ember = SettingsTint(top: Color(red: 1.0, green: 0.69, blue: 0.36), bottom: Color(red: 0.94, green: 0.40, blue: 0.15))
    static let violet = SettingsTint(top: Color(red: 0.74, green: 0.56, blue: 1.0), bottom: Color(red: 0.45, green: 0.30, blue: 0.93))
    static let indigo = SettingsTint(top: Color(red: 0.52, green: 0.60, blue: 1.0), bottom: Color(red: 0.27, green: 0.34, blue: 0.89))
    static let teal = SettingsTint(top: Color(red: 0.33, green: 0.84, blue: 0.86), bottom: Color(red: 0.07, green: 0.58, blue: 0.66))
}

private struct SettingsTintKey: EnvironmentKey {
    static let defaultValue: SettingsTint? = nil
}

private struct SettingsTileGlyphColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// The shown pane's colour (its hero tile and glow).
    var settingsTint: SettingsTint? {
        get { self[SettingsTintKey.self] }
        set { self[SettingsTintKey.self] = newValue }
    }

    /// The glyph colour inside a tinted `SettingsGlyphTile`.
    var settingsTileGlyphColor: Color? {
        get { self[SettingsTileGlyphColorKey.self] }
        set { self[SettingsTileGlyphColorKey.self] = newValue }
    }
}

extension View {
    /// The Settings window's appearance: dark, paper type, the sky accent
    /// and the glass behind everything (title bar included).
    func settingsTheme() -> some View {
        modifier(SettingsThemeModifier())
    }
}

private struct SettingsThemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        let themed = content
            .foregroundStyle(SettingsTheme.paper)
            .tint(SettingsTheme.accent)
            .buttonStyle(SettingsCapsuleButtonStyle())
            .toggleStyle(SettingsSwitchToggleStyle())
            .background(SettingsWindowChrome())
            .preferredColorScheme(.dark)
        if #available(macOS 15.0, *) {
            // The glass is the root view's own background; the window
            // paints nothing behind it.
            themed
                .containerBackground(.clear, for: .window)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            themed
        }
    }
}

// MARK: - Window glass

/// The whole window's backdrop: the desktop through a frosted behind-window
/// blur under a dark tint. It stays lit when the window isn't key, like the
/// island. Reduce Transparency gets the opaque window colour.
struct SettingsWindowGlass: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            SettingsTheme.window
        } else {
            ZStack {
                SettingsBehindWindowGlass()
                SettingsTheme.glassTint
            }
        }
    }
}

/// Not `NSGlassEffectView`: window glass follows the window's key state and
/// goes flat and opaque as soon as you click into another app. A
/// visual-effect view pinned `.active` keeps the frost either way.
private struct SettingsBehindWindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let blur = NSVisualEffectView()
        blur.blendingMode = .behindWindow
        blur.material = .hudWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        return blur
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - Glyph tile

/// An icon tile. Tinted, it is a section's coloured squircle as System
/// Settings draws them: a soft gradient, a filled white glyph, no rim; a
/// small shadow seats it on the glass. Untinted, the notch-style ink square
/// with a paper glyph and a faint paper rim.
struct SettingsGlyphTile<Glyph: View>: View {
    var size: CGFloat
    var tint: SettingsTint? = nil
    @ViewBuilder let glyph: () -> Glyph

    private var radius: CGFloat { size * 0.2237 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if let tint {
                shape.fill(tint.gradient)
                    .shadow(color: .black.opacity(0.28), radius: size > 40 ? 6 : 1.5, y: size > 40 ? 3 : 0.75)
            } else {
                shape.fill(SettingsTheme.ink)
                shape.fill(
                    LinearGradient(
                        colors: [SettingsTheme.paper.opacity(0.10), SettingsTheme.paper.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
            glyph()
                .environment(\.settingsTileGlyphColor, tint?.glyph)
        }
        .frame(width: size, height: size)
        .overlay {
            if tint == nil {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [SettingsTheme.paper.opacity(0.26), SettingsTheme.paper.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: size > 40 ? 1 : 0.75
                )
            }
        }
        .accessibilityHidden(true)
    }
}

extension SettingsGlyphTile where Glyph == SettingsSymbolGlyph {
    init(systemName: String, size: CGFloat, tint: SettingsTint? = nil) {
        self.size = size
        self.tint = tint
        self.glyph = { SettingsSymbolGlyph(systemName: systemName, size: size) }
    }
}

/// A filled SF Symbol sized for a `SettingsGlyphTile`: white on a tinted
/// tile, paper on an ink one.
struct SettingsSymbolGlyph: View {
    let systemName: String
    let size: CGFloat

    @Environment(\.settingsTileGlyphColor) private var glyphColor

    var body: some View {
        Image(systemName: systemName)
            .symbolVariant(.fill)
            .font(.system(size: size * 0.56, weight: .medium))
            .foregroundStyle(glyphColor ?? SettingsTheme.paper.opacity(0.92))
    }
}

// MARK: - Buttons

/// The island's capsule controls, for every plain push button in Settings:
/// a soft paper capsule with paper type that lifts on hover. Destructive
/// buttons take the island's approval red; disabled ones fade.
struct SettingsCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsCapsuleButton(configuration: configuration)
    }
}

private struct SettingsCapsuleButton: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let isDestructive = configuration.role == .destructive
        let ink = isDestructive ? SettingsTheme.critical : SettingsTheme.paper
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(ink.opacity(isEnabled ? 0.94 : 0.4))
            .padding(.horizontal, 13)
            .frame(minHeight: 27)
            .background {
                Capsule()
                    .fill(fill(tint: isDestructive ? SettingsTheme.critical : SettingsTheme.paper))
            }
            .overlay {
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [SettingsTheme.paper.opacity(0.2), SettingsTheme.paper.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { isHovered = $0 && isEnabled }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }

    private func fill(tint: Color) -> Color {
        guard isEnabled else { return tint.opacity(0.04) }
        if configuration.isPressed { return tint.opacity(0.16) }
        return tint.opacity(isHovered ? 0.12 : 0.075)
    }
}

/// The one button that matters on a surface (an update waiting to be
/// installed): the capsule on the sky accent, white type.
struct SettingsAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(SettingsTheme.onAccent)
            .padding(.horizontal, 14)
            .frame(minHeight: 27)
            .background(SettingsAccentThumb(shape: Capsule(), opacity: configuration.isPressed ? 0.8 : 1))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Switch

/// The switch: a sky track with a white knob when on, a faint paper track
/// with a paper knob when off. Looks the same whether or not the window is
/// key (the system switch greys out in an inactive window), and VoiceOver
/// still meets a real switch.
struct SettingsSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsSwitch(configuration: configuration)
    }
}

private struct SettingsSwitch: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trackSize = CGSize(width: 38, height: 22)
    private let knobInset: CGFloat = 3

    var body: some View {
        let isOn = configuration.isOn
        let knob = trackSize.height - knobInset * 2
        Capsule()
            .fill(isOn ? SettingsTheme.accent : SettingsTheme.paper.opacity(0.13))
            .overlay {
                Capsule().strokeBorder(
                    isOn ? Color.white.opacity(0.22) : SettingsTheme.paper.opacity(0.12),
                    lineWidth: 0.75
                )
            }
            .frame(width: trackSize.width, height: trackSize.height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? Color.white : SettingsTheme.paper.opacity(0.88))
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .padding(knobInset)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
            .onTapGesture {
                guard isEnabled else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.78)) {
                    configuration.isOn.toggle()
                }
            }
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
                    .toggleStyle(.switch)
            }
    }
}

// MARK: - Segmented control

/// One choice in a `SettingsSegmentedControl` / `SettingsMenuPicker`.
struct SettingsSegment<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var systemImage: String? = nil

    var id: Value { value }

    init(_ value: Value, _ title: String, systemImage: String? = nil) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
    }
}

/// The island tab bar as a segmented control: a soft capsule track with the
/// selection on a sky thumb that slides between segments.
struct SettingsSegmentedControl<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let segments: [SettingsSegment<Value>]

    @Namespace private var namespace
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                segmentButton(segment)
            }
        }
        .padding(2.5)
        .background(Capsule().fill(SettingsTheme.ink.opacity(0.45)))
        .overlay(Capsule().strokeBorder(SettingsTheme.paper.opacity(0.09), lineWidth: 0.75))
        .opacity(isEnabled ? 1 : 0.45)
        .fixedSize()
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(segments) { Text($0.title).tag($0.value) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func segmentButton(_ segment: SettingsSegment<Value>) -> some View {
        let isSelected = segment.value == selection
        return Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.28, extraBounce: 0.06)) {
                selection = segment.value
            }
        } label: {
            HStack(spacing: 5) {
                if let systemImage = segment.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10.5, weight: .semibold))
                }
                Text(segment.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? SettingsTheme.onAccent : SettingsTheme.paper.opacity(0.6))
            .padding(.horizontal, 11)
            .frame(height: 25)
            .background {
                if isSelected {
                    SettingsAccentThumb(shape: Capsule())
                        .matchedGeometryEffect(id: "segment", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The selected segment: the sky accent, lit from the top,
/// with a bright rim.
struct SettingsAccentThumb<S: InsettableShape>: View {
    var shape: S
    var opacity: Double = 1

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [SettingsTheme.accent.opacity(0.92 * opacity), SettingsTheme.accent.opacity(0.78 * opacity)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.4 * opacity), .white.opacity(0.06 * opacity)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            }
            .shadow(color: SettingsTheme.accent.opacity(0.3 * opacity), radius: 6, y: 2)
    }
}

// MARK: - Menu picker

/// A pop-up choice as an island capsule: the current value and a chevron;
/// the menu itself is the system's (sections, checkmark and all).
struct SettingsMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let sections: [(title: String?, segments: [SettingsSegment<Value>])]
    /// How many sections the menu lists in place; the rest become submenus.
    let inlineSections: Int

    init(_ title: String, selection: Binding<Value>, segments: [SettingsSegment<Value>]) {
        self.title = title
        self._selection = selection
        self.sections = [(nil, segments)]
        self.inlineSections = 1
    }

    /// `inlineSections` keeps a long menu on the screen: a menu taller than
    /// the display hides its ends behind scroll arrows, so past that many
    /// sections each one folds into its own submenu.
    init(
        _ title: String,
        selection: Binding<Value>,
        sections: [(title: String?, segments: [SettingsSegment<Value>])],
        inlineSections: Int = .max
    ) {
        self.title = title
        self._selection = selection
        self.sections = sections
        self.inlineSections = inlineSections
    }

    private var currentTitle: String {
        Self.title(for: selection, in: sections)
    }

    /// The label shown in the capsule: the selected choice's title, from
    /// whichever section holds it ("" when nothing matches).
    static func title(for value: Value, in sections: [(title: String?, segments: [SettingsSegment<Value>])]) -> String {
        sections.lazy.flatMap(\.segments).first { $0.value == value }?.title ?? ""
    }

    var body: some View {
        Menu {
            SettingsMenuPickerItems(selection: $selection, sections: sections, inlineSections: inlineSections)
        } label: {
            HStack(spacing: 7) {
                Text(currentTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SettingsTheme.paper.opacity(0.55))
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(SettingsCapsuleButtonStyle())
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(currentTitle)
    }
}

/// A `SettingsMenuPicker`'s rows: one checkmark row per choice, the first
/// `inlineSections` sections listed in place under their headers and the
/// rest as submenus. Rows are toggles, not one `Picker`, because a choice
/// can sit in a submenu: picking a row (even the checked one) selects it.
struct SettingsMenuPickerItems<Value: Hashable>: View {
    @Binding var selection: Value
    let sections: [(title: String?, segments: [SettingsSegment<Value>])]
    var inlineSections: Int = .max

    var body: some View {
        ForEach(Array(sections.prefix(inlineSections).enumerated()), id: \.offset) { _, section in
            if let sectionTitle = section.title {
                Section(sectionTitle) { rows(section.segments) }
            } else {
                rows(section.segments)
            }
        }
        // (a titled section already closes with a separator)
        ForEach(Array(sections.dropFirst(inlineSections).enumerated()), id: \.offset) { _, section in
            Menu(section.title ?? "") { rows(section.segments) }
        }
    }

    private func rows(_ segments: [SettingsSegment<Value>]) -> some View {
        ForEach(segments) { segment in
            Toggle(segment.title, isOn: Binding(
                get: { selection == segment.value },
                set: { _ in selection = segment.value }
            ))
        }
    }
}

// MARK: - Window chrome

/// Glass all the way up: a transparent title bar and a clear, non-opaque
/// window, so `SettingsWindowGlass` shows behind everything (SwiftUI's own
/// toolbar-background control covers the toolbar, not an AppKit-hosted
/// window's title bar).
struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) {}

    final class ChromeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}
