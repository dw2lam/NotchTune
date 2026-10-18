import SwiftUI

/// The opened island's meeting heads-up: the calendar's colour, the title,
/// a countdown and the time, with Join (when the event has a call link) and
/// dismiss. Fixed height, so the empty-state panel can reserve room for it.
struct MeetingHeadsUpBanner: View {
    let meeting: CalendarEventSnapshot
    let onJoin: (() -> Void)?
    let onDismiss: () -> Void

    static let height: CGFloat = 50

    /// One tick a minute on the meeting's own second, so a whole-minute
    /// countdown flips exactly when it should (`.everyMinute` ticks on the
    /// wall-clock minute and hands back that minute's start, a minute early).
    static func countdownSchedule(for start: Date) -> PeriodicTimelineSchedule {
        .periodic(from: start.addingTimeInterval(-24 * 60 * 60), by: 60)
    }

    @Environment(\.islandControlGlass) private var usesGlass

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(LiveActivityPalette.meetingColor(meeting))
                .frame(width: 3.5, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Minutes only: one redraw a minute.
                TimelineView(Self.countdownSchedule(for: meeting.start)) { context in
                    Text(detail(now: context.date))
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(V6Palette.paper.opacity(0.5))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let onJoin {
                Button(action: onJoin) {
                    Label("Join", systemImage: "video.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(MeetingJoinButtonStyle(usesGlass: usesGlass))
                .help("Join the call")
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(V6Palette.paper.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss meeting heads-up")
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

    private func detail(now: Date) -> String {
        let minutes = CalendarHeadsUpResolver.minutesUntil(meeting.start, now: now)
        let when = minutes == 0 ? "Now" : "In \(minutes) min"
        return "\(when) · \(IslandLiveActivity.meetingTimeRange(meeting))"
    }
}

/// Join: the island's green "go" on a small capsule (Liquid Glass when the
/// island's controls are glass).
private struct MeetingJoinButtonStyle: ButtonStyle {
    let usesGlass: Bool

    func makeBody(configuration: Configuration) -> some View {
        let tint = IslandDesignPalette.Status.completed
        let label = configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

        if usesGlass, LiquidGlass.isSupported {
            label
                .islandGlass(in: Capsule(), tint: tint.opacity(0.18))
                .opacity(configuration.isPressed ? 0.8 : 1)
        } else {
            label
                .background(tint.opacity(0.15), in: Capsule())
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}
