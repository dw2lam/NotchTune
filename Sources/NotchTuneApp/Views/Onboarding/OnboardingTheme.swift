import SwiftUI

/// Onboarding speaks the island's design language: ink surfaces, warm paper
/// text, and the session-status tints as functional accents — no foreign
/// accent colors.
enum OnboardingTheme {
    /// Primary interactive accent (CTAs, selection) — the "running" blue.
    static let accent = IslandDesignPalette.Status.running
    /// Ready / installed / granted.
    static let ready = IslandDesignPalette.Status.completed
    /// Needs the user's attention.
    static let attention = IslandDesignPalette.Status.waitingForApproval
    /// Optional / pending states.
    static let optionalTint = IslandDesignPalette.Status.waitingAggregate

    static let cardFill = Color.white.opacity(0.035)
    static let cardStroke = Color.white.opacity(0.07)
    static let selectedFill = Color.white.opacity(0.075)

    static let primaryText = V6Palette.paper
    static let secondaryText = V6Palette.paper.opacity(0.55)
    static let tertiaryText = V6Palette.paper.opacity(0.4)
}

struct OnboardingCardBackground: ViewModifier {
    var selected = false
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(
                selected ? OnboardingTheme.selectedFill : OnboardingTheme.cardFill,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        selected
                            ? OnboardingTheme.accent.opacity(0.55)
                            : OnboardingTheme.cardStroke,
                        lineWidth: selected ? 1.2 : 0.5
                    )
            }
    }
}

extension View {
    func onboardingCard(selected: Bool = false, cornerRadius: CGFloat = 12) -> some View {
        modifier(OnboardingCardBackground(selected: selected, cornerRadius: cornerRadius))
    }
}
