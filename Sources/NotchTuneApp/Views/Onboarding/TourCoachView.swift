import SwiftUI

/// The guided tour's coach bubble, rendered inside the island's overlay panel
/// (which is always opened-size and front, so no extra window is needed).
/// While the island is closed the panel ignores mouse events, so the bubble is
/// passive text there — the Skip button only appears when the island is open.
struct TourCoachView: View {
    var model: AppModel

    var body: some View {
        let tour = model.tour

        HStack(spacing: 10) {
            Image(systemName: icon(for: tour.phase))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint(for: tour.phase))

            Text(tour.coachText)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(OnboardingTheme.primaryText.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            if model.notchStatus == .opened, tour.phase != .celebrate {
                Button("Skip tour") {
                    tour.skip()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(OnboardingTheme.tertiaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(V6Palette.ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
        .frame(maxWidth: 420)
    }

    private func icon(for phase: OnboardingTourController.TourPhase) -> String {
        switch phase {
        case .waitHoverOpen: "cursorarrow.motionlines"
        case .waitApprovalResolved: "checkmark.circle"
        case .promptMusicTab: "music.note"
        case .waitFileDrop: "tray.and.arrow.down"
        case .celebrate: "sparkles"
        case .idle, .done: "sparkles"
        }
    }

    private func tint(for phase: OnboardingTourController.TourPhase) -> Color {
        switch phase {
        case .waitHoverOpen: OnboardingTheme.accent
        case .waitApprovalResolved: OnboardingTheme.attention
        case .promptMusicTab: OnboardingTheme.accent
        case .waitFileDrop: OnboardingTheme.optionalTint
        case .celebrate, .idle, .done: OnboardingTheme.ready
        }
    }
}
