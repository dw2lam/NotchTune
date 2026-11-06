import SwiftUI

/// `AppModel.notice` as one calm row: what went wrong, what can be done about
/// it, and a way to wave it off. The same row in the open panel and as the
/// toast a closed notch opens for it.
struct NoticeBanner: View {
    let notice: AppNotice
    let onAction: () -> Void
    let onDismiss: () -> Void

    static let height: CGFloat = 50

    @Environment(\.islandControlGlass) private var usesGlass

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IslandDesignPalette.Status.waitingAggregate.opacity(0.85))
                .accessibilityHidden(true)

            Text(notice.message)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.88))
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            if let actionTitle = notice.actionTitle, notice.action != nil {
                Button(actionTitle, action: onAction)
                    .buttonStyle(NoticeActionButtonStyle(usesGlass: usesGlass))
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(V6Palette.paper.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(NotchPlainButtonStyle())
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: IslandRadius.card, style: .continuous)
                .fill(.white.opacity(0.055))
                .overlay {
                    RoundedRectangle(cornerRadius: IslandRadius.card, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.75)
                }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct NoticeActionButtonStyle: ButtonStyle {
    let usesGlass: Bool

    func makeBody(configuration: Configuration) -> some View {
        actionBody(configuration).notchHapticOnPress(configuration.isPressed, .confirm)
    }

    @ViewBuilder
    private func actionBody(_ configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(V6Palette.paper.opacity(0.92))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

        if usesGlass, LiquidGlass.isSupported {
            label
                .islandGlass(in: Capsule(), tint: .white.opacity(0.1))
                .opacity(configuration.isPressed ? 0.8 : 1)
        } else {
            label
                .background(.white.opacity(configuration.isPressed ? 0.08 : 0.12), in: Capsule())
        }
    }
}
