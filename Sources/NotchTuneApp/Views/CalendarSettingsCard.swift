import AppKit
import SwiftUI

/// Settings → Sound → Meetings: the calendar heads-up and quiet-during-
/// meetings switches. Off by default; turning the heads-up on is the only
/// thing that ever asks for calendar access.
struct CalendarSettingsCard: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }
    private var calendar: CalendarHeadsUpService { model.calendar }

    var body: some View {
        SettingsCard(title: lang.t("settings.calendar.title"), footer: lang.t("settings.calendar.footer")) {
            SettingsToggleRow(
                lang.t("settings.calendar.headsUp"),
                subtitle: lang.t("settings.calendar.headsUp.note"),
                isOn: Binding(
                    get: { calendar.isEnabled },
                    set: { enabled in Task { await calendar.setEnabled(enabled) } }
                )
            )

            if calendar.isEnabled {
                SettingsRowDivider()

                switch calendar.authorization {
                case .granted:
                    grantedRows
                case .notDetermined:
                    SettingsRow(
                        lang.t("settings.calendar.access.title"),
                        subtitle: lang.t("settings.calendar.access.request.note")
                    ) {
                        Button(lang.t("settings.calendar.access.request")) {
                            Task { await calendar.requestAccess() }
                        }
                    }
                case .denied, .restricted:
                    SettingsRow(
                        lang.t("settings.calendar.access.denied"),
                        subtitle: lang.t("settings.calendar.access.denied.note")
                    ) {
                        Button(lang.t("settings.calendar.access.openSettings")) {
                            Self.openCalendarPrivacySettings()
                        }
                    }
                case .unavailable:
                    SettingsRow(
                        lang.t("settings.calendar.access.unavailable"),
                        subtitle: lang.t("settings.calendar.access.unavailable.note")
                    ) {
                        EmptyView()
                    }
                }
            }
        }
        // Coming back from System Settings → Privacy, show the new answer.
        .onAppear { calendar.accessMayHaveChanged() }
    }

    @ViewBuilder
    private var grantedRows: some View {
        SettingsRow(lang.t("settings.calendar.next"), subtitle: nextMeetingText) {
            EmptyView()
        }

        SettingsRowDivider()

        SettingsPickerRow(
            lang.t("settings.calendar.leadTime"),
            selection: Binding(
                get: { calendar.leadTime },
                set: { calendar.leadTime = $0 }
            ),
            style: .segmented,
            segments: CalendarLeadTime.allCases.map {
                SettingsSegment($0, lang.t("settings.calendar.leadTime.minutes", $0.rawValue))
            }
        )

        SettingsRowDivider()

        SettingsToggleRow(
            lang.t("settings.calendar.quiet"),
            subtitle: lang.t("settings.calendar.quiet.note"),
            isOn: Binding(
                get: { calendar.quietDuringMeetings },
                set: { calendar.quietDuringMeetings = $0 }
            )
        )

        if calendar.calendars.count > 1 {
            SettingsRowDivider()

            SettingsStackedRow(
                lang.t("settings.calendar.calendars"),
                subtitle: lang.t("settings.calendar.calendars.note")
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(calendar.calendars) { source in
                        Toggle(isOn: Binding(
                            get: { calendar.isCalendarSelected(source.id) },
                            set: { calendar.setCalendar(source.id, selected: $0) }
                        )) {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(Self.color(source.color))
                                    .frame(width: 8, height: 8)
                                Text(source.title)
                                    .font(SettingsMetrics.rowTitleFont)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    /// "Standup · Today at 10:00", or that nothing is coming up.
    private var nextMeetingText: String {
        guard let next = calendar.nextEvent else { return lang.t("settings.calendar.next.none") }
        return "\(next.title) · \(Self.nextFormatter.string(from: next.start))"
    }

    private static let nextFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static func color(_ color: CalendarColor?) -> Color {
        guard let color else { return .secondary }
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    static func openCalendarPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
