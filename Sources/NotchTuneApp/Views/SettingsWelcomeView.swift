import AppKit
import SwiftUI

// MARK: - Welcome logic

/// The pure parts of General's welcome: who to greet and how, and what the
/// island is up to right now. Everything is read on this Mac.
enum SettingsWelcome {
    enum DayPart: Equatable {
        case morning
        case afternoon
        case evening
        case night

        /// The welcome's colour through the day: sunrise ember, daylight
        /// sky, evening violet, night indigo.
        var tint: SettingsTint {
            switch self {
            case .morning:   .ember
            case .afternoon: .sky
            case .evening:   .violet
            case .night:     .indigo
            }
        }

        var greetingKey: String {
            switch self {
            case .morning:   "settings.welcome.greeting.morning"
            case .afternoon: "settings.welcome.greeting.afternoon"
            case .evening:   "settings.welcome.greeting.evening"
            case .night:     "settings.welcome.greeting.night"
            }
        }
    }

    static func dayPart(forHour hour: Int) -> DayPart {
        switch hour {
        case 5..<12:  .morning
        case 12..<17: .afternoon
        case 17..<22: .evening
        default:      .night
        }
    }

    static func dayPart(at date: Date, calendar: Calendar = .current) -> DayPart {
        dayPart(forHour: calendar.component(.hour, from: date))
    }

    /// The first word of the account's full name ("David Lam" → "David"),
    /// or nil when there is nothing friendly to call the user.
    static func firstName(fromFullName fullName: String) -> String? {
        guard let first = fullName.split(whereSeparator: \.isWhitespace).first else { return nil }
        return String(first)
    }

    /// What the island's agents are doing; the one that needs the user wins.
    enum Agents: Equatable {
        case needYou(Int)
        case working(Int)
        case quiet

        /// The character's pose to match: the island's own.
        var mode: UnifiedBars.Mode {
            switch self {
            case .needYou: .waiting
            case .working: .running
            case .quiet:   .idle
            }
        }
    }

    static func agents(attentionCount: Int, runningCount: Int) -> Agents {
        if attentionCount > 0 { return .needYou(attentionCount) }
        if runningCount > 0 { return .working(runningCount) }
        return .quiet
    }

    /// "Title — Artist" for the playing track, nil when nothing plays.
    static func nowPlaying(title: String, artist: String, isPlaying: Bool) -> String? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPlaying, !title.isEmpty else { return nil }
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return artist.isEmpty ? title : "\(title) — \(artist)"
    }

    /// The account's first name, read once (it never leaves the Mac).
    static let userFirstName: String? = firstName(fromFullName: NSFullUserName())

    /// "2.1.5 (1180)": the version with its build, the build left off when
    /// the bundle has none; nil for a bundle with no version (a dev build).
    static func versionLine(version: String?, build: String?) -> String? {
        guard let version = version?.trimmingCharacters(in: .whitespaces), !version.isEmpty else { return nil }
        guard let build = build?.trimmingCharacters(in: .whitespaces), !build.isEmpty, build != version else {
            return version
        }
        return "\(version) (\(build))"
    }

    /// What the update line says, most pressing first.
    enum UpdateStatus: Equatable {
        case checking
        case available(String)
        case upToDate(checkedAt: Date)
        /// No check on record yet: Sparkle checks on its own schedule.
        case automatic
    }

    static func updateStatus(isChecking: Bool, availableVersion: String?, lastCheck: Date?) -> UpdateStatus {
        if isChecking { return .checking }
        if let availableVersion { return .available(availableVersion) }
        if let lastCheck { return .upToDate(checkedAt: lastCheck) }
        return .automatic
    }
}

// MARK: - Welcome hero

/// The top of General, the pane Settings opens on: a greeting for the time
/// of day and the user's name, their character on a little ink notch
/// (posed like the island: busy while agents work, waving when one needs
/// them) and what's going on right now; under it the app itself — icon,
/// version, updates — and its credits. It's About and Updates, at home.
struct SettingsWelcomeHero: View {
    var model: AppModel

    @Environment(\.settingsWindowIsOnScreen) private var isOnScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lang: LanguageManager { model.lang }

    var body: some View {
        // Minute ticks keep the greeting, colour and "checked … ago" true.
        TimelineView(.everyMinute) { context in
            let dayPart = SettingsWelcome.dayPart(at: context.date)
            let agents = SettingsWelcome.agents(
                attentionCount: model.liveAttentionCount,
                runningCount: model.liveRunningCount
            )
            content(dayPart: dayPart, agents: agents, now: context.date)
        }
    }

    private func content(dayPart: SettingsWelcome.DayPart, agents: SettingsWelcome.Agents, now: Date) -> some View {
        let tint = dayPart.tint
        let shape = RoundedRectangle(cornerRadius: SettingsMetrics.cardCornerRadius + 4, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 24) {
                WelcomeStage(
                    character: model.islandCharacter,
                    mode: agents.mode,
                    motion: model.islandCharacterMotion,
                    paused: !isOnScreen || reduceMotion,
                    tint: tint
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(greeting(for: dayPart))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(SettingsTheme.paper)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    statusLine(agents: agents)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 26)

            heroDivider

            appRow(now: now)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

            heroDivider

            credits
                .padding(.horizontal, 24)
                .padding(.top, 13)
                .padding(.bottom, 15)
        }
        .background {
            ZStack {
                SettingsCardBackground(cornerRadius: SettingsMetrics.cardCornerRadius + 4)
                shape.fill(
                    LinearGradient(
                        colors: [tint.top.opacity(0.26), tint.bottom.opacity(0.10), tint.bottom.opacity(0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .animation(.smooth(duration: 0.6), value: tint)
        }
        .padding(.top, 6)
    }

    private var heroDivider: some View {
        SettingsTheme.hairline
            .frame(height: 1)
            .padding(.horizontal, 24)
    }

    private func greeting(for dayPart: SettingsWelcome.DayPart) -> String {
        if let name = SettingsWelcome.userFirstName {
            return lang.t(dayPart.greetingKey + ".named", name)
        }
        return lang.t(dayPart.greetingKey)
    }

    // MARK: Status

    private func statusLine(agents: SettingsWelcome.Agents) -> some View {
        let track = model.playerManager.track
        let nowPlaying = SettingsWelcome.nowPlaying(
            title: track.title,
            artist: track.artist,
            isPlaying: model.isMusicPlaybackActive
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor(agents))
                    .frame(width: 7, height: 7)
                    .shadow(color: statusColor(agents).opacity(0.7), radius: 3)
                Text(statusText(agents))
                    .font(.system(size: 13.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(SettingsTheme.paper.opacity(0.78))
                    .lineLimit(1)
            }
            if let nowPlaying {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(SettingsTint.ember.top)
                        .frame(width: 7)
                    Text(nowPlaying)
                        .font(.system(size: 12.5))
                        .foregroundStyle(SettingsTheme.paper.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statusText(_ agents: SettingsWelcome.Agents) -> String {
        switch agents {
        case .needYou(1):         lang.t("settings.welcome.agents.needYou.one")
        case .needYou(let count): lang.t("settings.welcome.agents.needYou.other", count)
        case .working(1):         lang.t("settings.welcome.agents.working.one")
        case .working(let count): lang.t("settings.welcome.agents.working.other", count)
        case .quiet:              lang.t("settings.welcome.agents.quiet")
        }
    }

    private func statusColor(_ agents: SettingsWelcome.Agents) -> Color {
        switch agents {
        case .needYou: SettingsTheme.caution
        case .working: SettingsTheme.informative
        case .quiet:   SettingsTheme.positive
        }
    }

    // MARK: App and updates

    private var versionLine: String? {
        #if DEBUG
        // Harness: the debug binary has no Info.plist to read a version from.
        if let version = ProcessInfo.processInfo.environment["NOTCHTUNE_HARNESS_APP_VERSION"] {
            return version
        }
        #endif
        let info = Bundle.main.infoDictionary
        return SettingsWelcome.versionLine(
            version: info?["CFBundleShortVersionString"] as? String,
            build: info?["CFBundleVersion"] as? String
        )
    }

    /// The app's icon, name, version and one-liner over its update line:
    /// what Sparkle last found, and the button to check (or install).
    private func appRow(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            appIdentity
            updateRow(now: now)
        }
    }

    private var appIdentity: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 50, height: 50)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(lang.t("app.name"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsTheme.paper)
                    if let versionLine {
                        Text(lang.t("settings.about.version", versionLine))
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(SettingsTheme.paper.opacity(0.62))
                            .textSelection(.enabled)
                    }
                }
                Text(lang.t("app.description"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(SettingsTheme.paper.opacity(0.6))
                Text(lang.t("settings.about.origin"))
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.paper.opacity(0.38))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
    }

    private func updateRow(now: Date) -> some View {
        let checker = model.updateChecker
        let status = SettingsWelcome.updateStatus(
            isChecking: checker.isChecking,
            availableVersion: checker.hasUpdate ? checker.latestVersion : nil,
            lastCheck: checker.lastCheckDate
        )
        return HStack(spacing: 12) {
            updateStatusLine(status, now: now)
            Spacer(minLength: 0)
            if case .available(let version) = status {
                Button(lang.t("settings.updates.install", version)) {
                    checker.checkForUpdates()
                }
                .buttonStyle(SettingsAccentButtonStyle())
            } else {
                Button(lang.t("settings.updates.checkForUpdates")) {
                    checker.checkForUpdates()
                }
                .disabled(!checker.canCheckForUpdates || status == .checking)
            }
        }
        // A quiet well under the identity, so the line reads as one control.
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsTheme.ink.opacity(0.28))
        )
    }

    private func updateStatusLine(_ status: SettingsWelcome.UpdateStatus, now: Date) -> some View {
        HStack(spacing: 6) {
            switch status {
            case .checking:
                ProgressView()
                    .controlSize(.mini)
                Text(lang.t("settings.updates.checking"))
            case .available(let version):
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(SettingsTheme.informative)
                Text(lang.t("settings.updates.available", version))
            case .upToDate(let checkedAt):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SettingsTheme.positive)
                Text(lang.t("settings.updates.upToDate", Self.relative(checkedAt, now: now)))
            case .automatic:
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(SettingsTheme.paper.opacity(0.5))
                Text(lang.t("settings.updates.automatic"))
            }
        }
        .font(.system(size: 12.5, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(SettingsTheme.paper.opacity(0.66))
        .lineLimit(1)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static func relative(_ date: Date, now: Date) -> String {
        // "now" rather than "in 0 sec." for a check that just finished.
        guard now.timeIntervalSince(date) >= 60 else { return relativeFormatter.localizedString(fromTimeInterval: 0) }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    // MARK: Credits

    /// Where NotchTune comes from, as a line of links, with its release
    /// notes and source beside it (under it when the window is narrow).
    private var credits: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                creditsText.fixedSize()
                Spacer(minLength: 0)
                projectLinks
            }
            VStack(alignment: .leading, spacing: 9) {
                creditsText
                projectLinks
            }
        }
    }

    private var creditsText: some View {
        let markdown = lang.t("settings.about.credits")
        let text = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        return Text(text)
            .font(.system(size: 12))
            .foregroundStyle(SettingsTheme.paper.opacity(0.5))
            .tint(SettingsTheme.accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var projectLinks: some View {
        HStack(spacing: 14) {
            WelcomeLink(title: lang.t("settings.updates.releaseNotes"), url: UpdateChecker.releasesURL)
            WelcomeLink(title: lang.t("settings.about.source"), url: Self.sourceURL)
        }
        .fixedSize()
    }

    private static let sourceURL = URL(string: "https://github.com/dw2lam/NotchTune")!
}

/// A quiet outbound link: accent type and a "leaves the app" arrow.
private struct WelcomeLink: View {
    let title: String
    let url: URL

    @State private var isHovered = false

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SettingsTheme.accent.opacity(isHovered ? 1 : 0.88))
            .underline(isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// The character's stage: a little ink notch, lit from beneath in the
/// hour's colour.
private struct WelcomeStage: View {
    let character: IslandCharacter
    let mode: UnifiedBars.Mode
    let motion: IslandCharacterMotion
    let paused: Bool
    let tint: SettingsTint

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 8,
            bottomLeadingRadius: 28,
            bottomTrailingRadius: 28,
            topTrailingRadius: 8,
            style: .continuous
        )
        ZStack {
            shape.fill(SettingsTheme.ink)
            shape.fill(
                RadialGradient(
                    colors: [tint.top.opacity(0.42), tint.bottom.opacity(0.12), .clear],
                    center: .bottom,
                    startRadius: 0,
                    endRadius: 92
                )
            )
            PixelCharacterView(
                character: character,
                mode: mode,
                paused: paused,
                tint: SettingsTheme.paper,
                motion: motion
            )
            // 5pt a pixel: crisp at any scale.
            .frame(width: 70, height: 70)
            .offset(y: 3)
        }
        .frame(width: 156, height: 112)
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [SettingsTheme.paper.opacity(0.22), SettingsTheme.paper.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        }
        .shadow(color: tint.bottom.opacity(0.4), radius: 16, y: 6)
        .animation(.smooth(duration: 0.6), value: tint)
        .accessibilityHidden(true)
    }
}
