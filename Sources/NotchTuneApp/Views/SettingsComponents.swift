import AppKit
import SwiftUI

// MARK: - Layout tokens

/// The roomy Settings layout: one hero header per pane, then soft rounded
/// cards holding generously spaced rows. Every pane reads these numbers so
/// the rhythm stays identical from pane to pane.
enum SettingsMetrics {
    /// Widest the pane's column grows before it centers in a wide window.
    static let contentMaxWidth: CGFloat = 680
    static let paneHorizontalPadding: CGFloat = 32
    static let paneTopPadding: CGFloat = 14
    static let paneBottomPadding: CGFloat = 44
    /// Space between the hero and the first card, and between cards.
    static let sectionSpacing: CGFloat = 30

    static let heroIconSize: CGFloat = 58
    static let sidebarIconSize: CGFloat = 24

    static let cardCornerRadius: CGFloat = 16
    static let cardHorizontalPadding: CGFloat = 20
    static let cardVerticalPadding: CGFloat = 4
    static let rowVerticalPadding: CGFloat = 14
    static let rowMinHeight: CGFloat = 54

    static let rowTitleFont = Font.system(size: 14)
    static let rowSubtitleFont = Font.system(size: 12)
    static let sectionTitleFont = Font.system(size: 15, weight: .semibold)
    static let footerFont = Font.system(size: 12)
}

// MARK: - Icon tile

/// The colored rounded-square icon: 24pt in the sidebar, ~58pt in each
/// pane's hero header. A soft top highlight and hairline edge keep it from
/// reading as a flat sticker at the larger size.
struct SettingsIconTile: View {
    let systemName: String
    let color: Color
    var size: CGFloat = SettingsMetrics.sidebarIconSize

    private var radius: CGFloat { size * 0.27 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(color.gradient)
            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(0.24), .white.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            Image(systemName: systemName)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: size > 30 ? 1.5 : 0.5, y: size > 30 ? 1 : 0.5)
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

// MARK: - Pane scaffold

/// A pane: hero header (big icon tile, title, one-line description) over a
/// scrolling column of cards.
struct SettingsPane<Hero: View, Content: View>: View {
    let title: String
    @ViewBuilder let hero: () -> Hero
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                hero()
                content()
            }
            .padding(.horizontal, SettingsMetrics.paneHorizontalPadding)
            .padding(.top, SettingsMetrics.paneTopPadding)
            .padding(.bottom, SettingsMetrics.paneBottomPadding)
            .frame(maxWidth: SettingsMetrics.contentMaxWidth + SettingsMetrics.paneHorizontalPadding * 2)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(title)
        .modifier(HeroCollapsingToolbarTitle())
    }
}

extension SettingsPane where Hero == SettingsHeroHeader<SettingsHeroIcon> {
    /// The standard pane: the tab's own icon and color in the hero.
    init(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.hero = {
            SettingsHeroHeader(title: title, subtitle: subtitle) {
                SettingsHeroIcon(systemName: systemImage, color: color)
            }
        }
        self.content = content
    }
}

/// The toolbar repeats the pane's title only once the hero has scrolled out
/// of view, like a collapsing large title — at rest the hero says it.
private struct HeroCollapsingToolbarTitle: ViewModifier {
    @State private var heroScrolledAway = false

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 70
                } action: { _, scrolledAway in
                    heroScrolledAway = scrolledAway
                }
                .toolbar(removing: heroScrolledAway ? nil : .title)
        } else {
            content
        }
    }
}

/// The hero's large icon tile, with a soft colored glow beneath it.
struct SettingsHeroIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        SettingsIconTile(systemName: systemName, color: color, size: SettingsMetrics.heroIconSize)
            .shadow(color: color.opacity(0.35), radius: 12, y: 6)
    }
}

struct SettingsHeroHeader<Icon: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            icon()

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Cards

/// The soft card fill: a whisper of white over the dark window, a white
/// card with a faint shadow in light mode.
struct SettingsCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = SettingsMetrics.cardCornerRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isDark = colorScheme == .dark
        shape
            .fill(isDark ? Color.white.opacity(0.055) : Color.white)
            .overlay(shape.strokeBorder(Color.primary.opacity(isDark ? 0.07 : 0.06), lineWidth: 1))
            .shadow(color: .black.opacity(isDark ? 0 : 0.05), radius: 3, y: 1)
    }
}

/// A titled group of rows. The heading sits above the card in calm semibold
/// type; an optional description sits under the heading, an optional footer
/// under the card. `accessory` goes trailing on the heading line.
struct SettingsCard<Accessory: View, Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var footer: String? = nil
    var insets = EdgeInsets(
        top: SettingsMetrics.cardVerticalPadding,
        leading: SettingsMetrics.cardHorizontalPadding,
        bottom: SettingsMetrics.cardVerticalPadding,
        trailing: SettingsMetrics.cardHorizontalPadding
    )
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || subtitle != nil {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let title {
                            Text(title)
                                .font(SettingsMetrics.sectionTitleFont)
                                .accessibilityAddTraits(.isHeader)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(SettingsMetrics.rowSubtitleFont)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    accessory()
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(insets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsCardBackground())

            if let footer {
                SettingsFooterText(footer)
            }
        }
    }
}

extension SettingsCard where Accessory == EmptyView {
    init(
        title: String? = nil,
        subtitle: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.footer = footer
        self.accessory = { EmptyView() }
        self.content = content
    }

    /// A card whose content runs edge to edge (a preview stage).
    init(
        title: String? = nil,
        subtitle: String? = nil,
        footer: String? = nil,
        insets: EdgeInsets,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.footer = footer
        self.insets = insets
        self.accessory = { EmptyView() }
        self.content = content
    }
}

/// Secondary explanatory text under a card.
struct SettingsFooterText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(SettingsMetrics.footerFont)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// Hairline between rows, inset to the card's content edge.
struct SettingsRowDivider: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Divider()
            .padding(.leading, leadingInset)
    }
}

// MARK: - Rows

/// Title over an optional secondary description.
struct SettingsRowLabel: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SettingsMetrics.rowTitleFont)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(SettingsMetrics.rowSubtitleFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One roomy row: label on the leading side, control trailing.
struct SettingsRow<Label: View, Accessory: View>: View {
    var alignment: VerticalAlignment = .center
    @ViewBuilder let label: () -> Label
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: alignment, spacing: 16) {
            label()
            accessory()
                .fixedSize()
        }
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
        .frame(minHeight: SettingsMetrics.rowMinHeight)
    }
}

extension SettingsRow where Label == SettingsRowLabel {
    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.label = { SettingsRowLabel(title: title, subtitle: subtitle) }
        self.accessory = accessory
    }
}

/// A switch row. The visible text is decorative; the switch itself carries
/// the title (and the description as its hint) for VoiceOver.
struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        SettingsRow {
            SettingsRowLabel(title: title, subtitle: subtitle)
                .accessibilityHidden(true)
                .contentShape(Rectangle())
                .onTapGesture { isOn.toggle() }
        } accessory: {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityHint(subtitle ?? "")
        }
    }
}

enum SettingsPickerStyle {
    /// Trailing pop-up menu.
    case menu
    /// Trailing segmented control.
    case segmented
    /// Segmented control under the label — for a long description.
    case segmentedBelow
}

/// A row with a trailing menu or segmented picker.
struct SettingsPickerRow<Value: Hashable, Options: View>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var selection: Value
    var style: SettingsPickerStyle = .menu
    @ViewBuilder let options: () -> Options

    init(
        _ title: String,
        subtitle: String? = nil,
        selection: Binding<Value>,
        style: SettingsPickerStyle = .menu,
        @ViewBuilder options: @escaping () -> Options
    ) {
        self.title = title
        self.subtitle = subtitle
        self._selection = selection
        self.style = style
        self.options = options
    }

    var body: some View {
        if style == .segmentedBelow {
            VStack(alignment: .leading, spacing: 12) {
                SettingsRowLabel(title: title, subtitle: subtitle)
                    .accessibilityHidden(true)
                picker
                    .fixedSize()
                    .accessibilityHint(subtitle ?? "")
            }
            .padding(.vertical, 16)
        } else {
            SettingsRow {
                SettingsRowLabel(title: title, subtitle: subtitle)
                    .accessibilityHidden(true)
            } accessory: {
                picker
                    .accessibilityHint(subtitle ?? "")
            }
        }
    }

    @ViewBuilder
    private var picker: some View {
        let base = Picker(title, selection: $selection) { options() }
            .labelsHidden()
        switch style {
        case .menu:
            base.pickerStyle(.menu)
        case .segmented, .segmentedBelow:
            base.pickerStyle(.segmented)
        }
    }
}

/// A row whose content sits UNDER the label (picture choices, previews).
struct SettingsStackedRow<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsRowLabel(title: title, subtitle: subtitle)
            content()
        }
        .padding(.vertical, 16)
    }
}

/// A small status capsule: a colored glyph and a short word.
struct SettingsStatusBadge: View {
    let text: String
    var systemImage: String = "checkmark.circle.fill"
    var color: Color = .green

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A small round glyph button (play, reveal in Finder, copy) that lifts on
/// hover. `help` doubles as its accessibility label.
struct SettingsIconButton: View {
    let systemName: String
    let help: String
    var tint: Color? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint ?? Color.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(isHovered ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Picture tiles

/// What a tile's thumbnail sits on.
enum SettingsTileBackground {
    /// Black, like the island hardware itself — for glyphs drawn in the
    /// island's paper ink.
    case island
    /// The preview wallpaper, for miniature pills that sit on a desktop.
    case wallpaper
    /// A neutral fill that follows the system appearance.
    case neutral

    static let islandInk = Color(white: 0.09)
}

private struct SettingsTileHoveredKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the pointer rests on the enclosing `SettingsTile`, so a
    /// thumbnail can wake up (the character sprites start running).
    var settingsTileIsHovered: Bool {
        get { self[SettingsTileHoveredKey.self] }
        set { self[SettingsTileHoveredKey.self] = newValue }
    }
}

/// A picture choice: a rounded thumbnail with an accent selection ring and a
/// check badge, a caption underneath. Hover lifts the ring, press squishes.
struct SettingsTile<Thumbnail: View>: View {
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    var thumbnailHeight: CGFloat = 64
    var background: SettingsTileBackground = .island
    let action: () -> Void
    @ViewBuilder let thumbnail: () -> Thumbnail

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let thumbnailRadius: CGFloat = 11

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    backgroundView
                    thumbnail()
                        .environment(\.settingsTileIsHovered, isHovered)
                }
                .frame(maxWidth: .infinity)
                .frame(height: thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: thumbnailRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: thumbnailRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(Color.accentColor))
                            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                            .padding(6)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .padding(3.5)
                .overlay(
                    RoundedRectangle(cornerRadius: thumbnailRadius + 3.5, style: .continuous)
                        .strokeBorder(ringColor, lineWidth: isSelected ? 2.5 : 1.5)
                )

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsTileButtonStyle(reduceMotion: reduceMotion))
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var ringColor: Color {
        if isSelected { return .accentColor }
        return isHovered ? Color.primary.opacity(0.18) : .clear
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch background {
        case .island:
            SettingsTileBackground.islandInk
        case .wallpaper:
            PersonalizationWallpaper()
        case .neutral:
            Rectangle().fill(.quaternary)
        }
    }
}

private struct SettingsTileButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A stacked row holding a title, an explanatory line and a row of tiles.
struct SettingsTileRow<Tiles: View>: View {
    let title: String
    var detail: String? = nil
    var spacing: CGFloat = 12
    @ViewBuilder let tiles: () -> Tiles

    var body: some View {
        SettingsStackedRow(title, subtitle: detail) {
            HStack(alignment: .top, spacing: spacing) {
                tiles()
            }
        }
    }
}
