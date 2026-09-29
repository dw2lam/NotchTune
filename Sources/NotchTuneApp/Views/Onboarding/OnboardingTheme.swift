import AppKit
import SwiftUI

/// The setup wizard is a standard macOS window: system background, semantic
/// label colors, the user's accent color, and grouped rows modelled on System
/// Settings — it follows the Light/Dark appearance. Only the pieces that depict
/// hardware (the notch, the island) stay black.
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
    static let groupCornerRadius: CGFloat = 10

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

/// Centered header shared by every step: artwork, large title, one short
/// explanation — the Setup Assistant pattern.
struct OnboardingStepHeader<Art: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var art: Art

    var body: some View {
        VStack(spacing: 0) {
            art
                .frame(height: 58)
                .accessibilityHidden(true)

            Text(title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Text(detail)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }
}

extension OnboardingStepHeader where Art == OnboardingHeaderSymbol {
    init(
        symbol: String,
        color: Color,
        rendering: SymbolRenderingMode = .hierarchical,
        title: String,
        detail: String
    ) {
        self.title = title
        self.detail = detail
        self.art = OnboardingHeaderSymbol(systemName: symbol, color: color, rendering: rendering)
    }
}

struct OnboardingHeaderSymbol: View {
    let systemName: String
    let color: Color
    var rendering: SymbolRenderingMode = .hierarchical

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 50, weight: .regular))
            .symbolRenderingMode(rendering)
            .foregroundStyle(color)
    }
}

// MARK: - Grouped rows (System Settings style)

/// A rounded group of rows, like a grouped `Form` section.
struct OnboardingGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .quinary,
            in: RoundedRectangle(cornerRadius: OnboardingTheme.groupCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OnboardingTheme.groupCornerRadius, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        }
    }
}

/// Hairline between rows, inset past the icon column.
struct OnboardingRowDivider: View {
    var leadingInset: CGFloat = 50

    var body: some View {
        Divider().padding(.leading, leadingInset)
    }
}

/// White glyph on a tinted rounded square — the System Settings row icon.
struct OnboardingRowIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// Icon, title, secondary explanation, and trailing accessory.
struct OnboardingRow<Accessory: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    var detail: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            OnboardingRowIcon(systemName: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory
        }
        .padding(.horizontal, 12)
        .padding(.vertical, detail == nil ? 6 : 10)
        .frame(minHeight: detail == nil ? 38 : 44)
    }
}

/// Green check + label, the "done" state for a row.
struct OnboardingStatusLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

/// Section title above a group, with an optional trailing control.
struct OnboardingSectionHeader<Trailing: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.headline)
            if let caption {
                Text(caption)
                    .font(.callout)
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

// MARK: - Choice tiles (Appearance-picker style)

/// A thumbnail with a selection ring and a label underneath — the pattern of
/// the Appearance picker in System Settings and Setup Assistant.
struct OnboardingChoiceTile<Thumbnail: View>: View {
    let title: String
    var detail: String?
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var thumbnail: Thumbnail

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                thumbnail
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                    }

                VStack(spacing: 1) {
                    Text(title)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Progress

/// Subtle page dots — the wizard's only progress indicator.
struct OnboardingPageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(width: 7, height: 7)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
