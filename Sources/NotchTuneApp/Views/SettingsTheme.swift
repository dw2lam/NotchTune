import AppKit
import SwiftUI

// MARK: - Theme

/// Settings wears the notch's own look: an ink window, paper (#F1EAD9) type,
/// mono SF Symbols, whisper-thin paper hairlines, and the island's status
/// colours only where something has a status. Always dark, like the island.
enum SettingsTheme {
    /// The window: a warm near-black, a step up from the island's pure ink
    /// so cards and the sidebar panel can sit on it.
    static let window = Color(red: 0.055, green: 0.051, blue: 0.047)
    /// The island's own ink, for tiles that stand in for the hardware.
    static let ink = V6Palette.ink
    static let paper = V6Palette.paper

    /// Interactive accent (switches, selection rings, check badges): paper,
    /// as on the island, where selection is a paper/white highlight.
    static let accent = paper

    /// Raised surfaces on the window (cards, the sidebar panel).
    static let surfaceFill = paper.opacity(0.045)
    static let surfaceStroke = paper.opacity(0.085)
    /// Hairline between rows.
    static let hairline = paper.opacity(0.085)
    /// Selected sidebar row / hovered surfaces.
    static let selectionFill = paper.opacity(0.10)
    static let hoverFill = paper.opacity(0.055)

    /// Status colours, shared with the island's session dots.
    static let positive = IslandDesignPalette.Status.completed
    static let informative = IslandDesignPalette.Status.running
    static let caution = IslandDesignPalette.Status.waitingAggregate
    static let critical = IslandDesignPalette.Status.waitingForApproval

    static let sidebarWidth: CGFloat = 214
    static let surfaceRadius: CGFloat = IslandRadius.card + 2
}

extension View {
    /// The Settings window's appearance: dark, paper type, paper accent and
    /// the ink window colour behind everything (title bar included).
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
            themed
                .containerBackground(SettingsTheme.window, for: .window)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            themed
                .background(SettingsTheme.window.ignoresSafeArea())
        }
    }
}

// MARK: - Glyph tile

/// The notch-style icon tile: an ink square with a paper glyph and a faint
/// paper rim, lit from the top like the island's glass controls. Replaces
/// the rainbow System Settings squircles.
struct SettingsGlyphTile<Glyph: View>: View {
    var size: CGFloat
    @ViewBuilder let glyph: () -> Glyph

    private var radius: CGFloat { size * 0.28 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(SettingsTheme.ink)
            shape.fill(
                LinearGradient(
                    colors: [SettingsTheme.paper.opacity(0.10), SettingsTheme.paper.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            glyph()
        }
        .frame(width: size, height: size)
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [SettingsTheme.paper.opacity(0.26), SettingsTheme.paper.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: size > 40 ? 1 : 0.75
            )
        }
        .accessibilityHidden(true)
    }
}

extension SettingsGlyphTile where Glyph == SettingsSymbolGlyph {
    init(systemName: String, size: CGFloat) {
        self.size = size
        self.glyph = { SettingsSymbolGlyph(systemName: systemName, size: size) }
    }
}

/// A paper SF Symbol sized for a `SettingsGlyphTile`.
struct SettingsSymbolGlyph: View {
    let systemName: String
    let size: CGFloat

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(SettingsTheme.paper.opacity(0.92))
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

// MARK: - Switch

/// The island's switch: a paper track with an ink knob when on, a faint
/// paper track with a paper knob when off. Looks the same whether or not
/// the window is key (the system switch greys out in an inactive window),
/// and VoiceOver still meets a real switch.
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
            .fill(isOn ? SettingsTheme.paper.opacity(0.92) : SettingsTheme.paper.opacity(0.11))
            .overlay {
                Capsule().strokeBorder(SettingsTheme.paper.opacity(isOn ? 0 : 0.12), lineWidth: 0.75)
            }
            .frame(width: trackSize.width, height: trackSize.height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? SettingsTheme.ink : SettingsTheme.paper.opacity(0.88))
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
/// selection on a paper bezel that slides between segments.
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
            .foregroundStyle(SettingsTheme.paper.opacity(isSelected ? 0.97 : 0.55))
            .padding(.horizontal, 11)
            .frame(height: 25)
            .background {
                if isSelected {
                    IslandGlassBezel(shape: Capsule(), tint: nil, isEmphasized: true)
                        .matchedGeometryEffect(id: "segment", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Menu picker

/// A pop-up choice as an island capsule: the current value and a chevron;
/// the menu itself is the system's (sections, checkmark and all).
struct SettingsMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let sections: [(title: String?, segments: [SettingsSegment<Value>])]

    init(_ title: String, selection: Binding<Value>, segments: [SettingsSegment<Value>]) {
        self.title = title
        self._selection = selection
        self.sections = [(nil, segments)]
    }

    init(_ title: String, selection: Binding<Value>, sections: [(title: String?, segments: [SettingsSegment<Value>])]) {
        self.title = title
        self._selection = selection
        self.sections = sections
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
            Picker(title, selection: $selection) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    if let sectionTitle = section.title {
                        Section(sectionTitle) {
                            ForEach(section.segments) { Text($0.title).tag($0.value) }
                        }
                    } else {
                        ForEach(section.segments) { Text($0.title).tag($0.value) }
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
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

// MARK: - Window chrome

/// Ink all the way up: makes the hosting window's title bar transparent over
/// the ink background (SwiftUI's own toolbar-background control covers the
/// toolbar, not an AppKit-hosted window's title bar).
struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) {}

    final class ChromeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(SettingsTheme.window)
        }
    }
}
