import AppKit
import SwiftUI

/// The setup wizard wears Settings' look: the frosted glass window, paper
/// type, the sky accent, cards a shade lighter than the glass and the
/// coloured System Settings tiles. Always dark, like the island. The pieces
/// that depict hardware (the notch, the island) stay black.
///
/// The island-palette accents below are for the live tour bubble, which renders
/// inside the (always dark) island rather than in the wizard window.
enum OnboardingTheme {
    /// Island accents (the tour bubble lives in the black island).
    static let accent = IslandDesignPalette.Status.running
    static let ready = IslandDesignPalette.Status.completed
    static let attention = IslandDesignPalette.Status.waitingForApproval
    static let optionalTint = IslandDesignPalette.Status.waitingAggregate
    static let primaryText = V6Palette.paper
    static let tertiaryText = V6Palette.paper.opacity(0.45)

    /// Width of the wizard's content column.
    static let contentWidth: CGFloat = 520

    /// A calm, wallpaper-like backdrop for the notch illustrations.
    static let wallpaper = LinearGradient(
        colors: [
            Color(red: 0.24, green: 0.36, blue: 0.78),
            Color(red: 0.55, green: 0.33, blue: 0.78),
            Color(red: 0.93, green: 0.55, blue: 0.52),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Step header

/// Centered header shared by every step: artwork (a coloured tile, lit like
/// Settings' hero), large title, one short explanation — the Setup
/// Assistant pattern.
struct OnboardingStepHeader<Art: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var art: Art

    var body: some View {
        VStack(spacing: 0) {
            art
                .frame(minHeight: 64)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.top, 18)

            Text(detail)
                .font(.system(size: 14.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension OnboardingStepHeader where Art == OnboardingHeaderTile<SettingsSymbolGlyph> {
    init(symbol: String, tint: SettingsTint, title: String, detail: String) {
        self.title = title
        self.detail = detail
        self.art = OnboardingHeaderTile(tint: tint) {
            SettingsSymbolGlyph(systemName: symbol, size: OnboardingHeaderTile<SettingsSymbolGlyph>.size)
        }
    }
}

/// The step's coloured tile, sized and lit like Settings' hero icon.
struct OnboardingHeaderTile<Glyph: View>: View {
    static var size: CGFloat { 64 }

    let tint: SettingsTint
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        SettingsGlyphTile(size: Self.size, tint: tint, glyph: glyph)
            .shadow(color: tint.bottom.opacity(0.5), radius: 18, y: 7)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
}

// MARK: - Grouped rows (Settings cards)

/// A card of rows, frosted a shade lighter than the window's glass.
struct OnboardingGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsCardBackground())
    }
}

/// Hairline between rows, inset past the icon column.
struct OnboardingRowDivider: View {
    var leadingInset: CGFloat = 40

    var body: some View {
        SettingsRowDivider(leadingInset: leadingInset)
    }
}

/// White glyph on a coloured squircle — Settings' hero tile.
struct OnboardingRowIcon: View {
    let systemName: String
    let tint: SettingsTint
    var size: CGFloat = 28

    var body: some View {
        SettingsGlyphTile(systemName: systemName, size: size, tint: tint)
    }
}

/// Icon, title, secondary explanation, and trailing accessory.
struct OnboardingRow<Accessory: View>: View {
    let icon: String
    let tint: SettingsTint
    let title: String
    var detail: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            OnboardingRowIcon(systemName: icon, tint: tint)

            SettingsRowLabel(title: title, subtitle: detail)

            accessory
                .fixedSize()
        }
        .padding(.vertical, detail == nil ? 9 : 12)
        .frame(minHeight: detail == nil ? 46 : 56)
    }
}

/// The "done" state for a row: a green check in the island's bezel.
struct OnboardingStatusLabel: View {
    let text: String

    var body: some View {
        SettingsStatusBadge(text: text)
    }
}

/// Section title above a card, with an optional trailing control.
struct OnboardingSectionHeader<Trailing: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(SettingsMetrics.sectionTitleFont)
                .foregroundStyle(SettingsTheme.paper.opacity(0.88))
                .accessibilityAddTraits(.isHeader)
            if let caption {
                Text(caption)
                    .font(SettingsMetrics.rowSubtitleFont)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 4)
    }
}

extension OnboardingSectionHeader where Trailing == EmptyView {
    init(title: String, caption: String? = nil) {
        self.title = title
        self.caption = caption
        self.trailing = EmptyView()
    }
}

// MARK: - Feature rows

/// A coloured tile, bold title, secondary description — the welcome and
/// tour lists.
struct OnboardingFeatureRow: View {
    let symbol: String
    let tint: SettingsTint
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SettingsGlyphTile(systemName: symbol, size: 38, tint: tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Footer

/// The wizard's primary action: a sky capsule with white type, lit from the
/// top like the selected segment in Settings.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OnboardingPrimaryButton(configuration: configuration)
    }
}

private struct OnboardingPrimaryButton: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(SettingsTheme.onAccent)
            .padding(.horizontal, 18)
            .frame(minHeight: 32)
            .background {
                SettingsAccentThumb(shape: Capsule(), opacity: isEnabled ? (isHovered ? 1 : 0.92) : 0.4)
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .onHover { isHovered = $0 && isEnabled }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// The footer's secondary action (Back): Settings' paper capsule at the
/// primary's height.
struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OnboardingSecondaryButton(configuration: configuration)
    }
}

private struct OnboardingSecondaryButton: View {
    let configuration: ButtonStyleConfiguration

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13.5, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(SettingsTheme.paper.opacity(0.94))
            .padding(.horizontal, 18)
            .frame(minHeight: 32)
            .background {
                Capsule().fill(SettingsTheme.paper.opacity(configuration.isPressed ? 0.16 : isHovered ? 0.12 : 0.075))
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
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Skip: quiet paper text that brightens on hover.
struct OnboardingQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OnboardingQuietButton(configuration: configuration)
    }
}

private struct OnboardingQuietButton: View {
    let configuration: ButtonStyleConfiguration

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(SettingsTheme.paper.opacity(configuration.isPressed ? 0.95 : isHovered ? 0.85 : 0.55))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Progress

/// The wizard's progress: paper dots, the current step a short sky capsule.
struct OnboardingPageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(SettingsTheme.accent) : AnyShapeStyle(SettingsTheme.paper.opacity(index < current ? 0.42 : 0.18)))
                    .frame(width: index == current ? 20 : 7, height: 7)
            }
        }
        .animation(.smooth(duration: 0.3), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

// MARK: - Glow

/// The step's colour, glowing softly from behind its header tile.
struct OnboardingStepGlow: View {
    let tint: SettingsTint

    var body: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [tint.bottom.opacity(0.32), tint.bottom.opacity(0.1), tint.bottom.opacity(0)],
                center: UnitPoint(x: 0.5, y: (proxy.safeAreaInsets.top + 60) / max(proxy.size.height, 1)),
                startRadius: 0,
                endRadius: 420
            )
            .animation(.smooth(duration: 0.35), value: tint)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Character tiles

/// A character in a picture tile: idle at rest, running when chosen or
/// hovered, paused while the wizard is off screen.
struct OnboardingCharacterSprite: View {
    let character: IslandCharacter
    let isSelected: Bool

    @Environment(\.settingsTileIsHovered) private var isHovered
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsWindowIsOnScreen) private var isOnScreen

    var body: some View {
        UnifiedBars(
            mode: (isSelected || isHovered) && !reduceMotion ? .running : .idle,
            size: 34,
            character: character,
            paused: !isOnScreen
        )
        .frame(width: 38, height: 38)
    }
}
