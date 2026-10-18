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
}

// MARK: - Welcome hero

/// The top of General, the pane Settings opens on: a greeting for the time
/// of day and the user's name, their character on a little ink notch
/// (posed like the island: busy while agents work, waving when one needs
/// them), what's going on right now, and a few shortcuts.
struct SettingsWelcomeHero: View {
    var model: AppModel

    @Environment(\.settingsWindowIsOnScreen) private var isOnScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lang: LanguageManager { model.lang }

    var body: some View {
        // Minute ticks keep the greeting and colour true to the hour.
        TimelineView(.everyMinute) { context in
            let dayPart = SettingsWelcome.dayPart(at: context.date)
            let agents = SettingsWelcome.agents(
                attentionCount: model.liveAttentionCount,
                runningCount: model.liveRunningCount
            )
            content(dayPart: dayPart, agents: agents)
        }
    }

    private func content(dayPart: SettingsWelcome.DayPart, agents: SettingsWelcome.Agents) -> some View {
        let tint = dayPart.tint
        let shape = RoundedRectangle(cornerRadius: SettingsMetrics.cardCornerRadius + 4, style: .continuous)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 22) {
                WelcomeStage(
                    character: model.islandCharacter,
                    mode: agents.mode,
                    motion: model.islandCharacterMotion,
                    paused: !isOnScreen || reduceMotion,
                    tint: tint
                )

                VStack(alignment: .leading, spacing: 9) {
                    Text(greeting(for: dayPart))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(SettingsTheme.paper)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    statusLine(agents: agents)
                }

                Spacer(minLength: 0)
            }

            shortcuts
        }
        .padding(20)
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

    // MARK: Shortcuts

    private var shortcuts: some View {
        // Four fit the narrowest window; the row drops Music before it would
        // wrap or clip.
        ViewThatFits(in: .horizontal) {
            shortcutRow([.appearance, .setup, .sound, .music])
            shortcutRow([.appearance, .setup, .sound])
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(lang.t("settings.welcome.shortcuts"))
    }

    private func shortcutRow(_ tabs: [SettingsTab]) -> some View {
        HStack(spacing: 8) {
            ForEach(tabs) { tab in
                WelcomeShortcut(title: shortcutTitle(tab), tint: tab.tint) {
                    withAnimation(.smooth(duration: 0.3, extraBounce: 0.08)) {
                        NotificationCenter.default.post(name: .notchTuneSelectSettingsTab, object: tab.rawValue)
                    }
                } glyph: {
                    if tab == .appearance {
                        // Personalize wears the user's own character.
                        PixelCharacterView(
                            character: model.islandCharacter,
                            mode: .idle,
                            paused: true,
                            tint: tab.tint.glyph
                        )
                        .frame(width: 12, height: 12)
                    } else {
                        SettingsSymbolGlyph(systemName: tab.icon, size: 20)
                    }
                }
            }
        }
        .fixedSize()
    }

    private func shortcutTitle(_ tab: SettingsTab) -> String {
        tab == .appearance ? lang.t("settings.welcome.shortcut.appearance") : tab.label(lang)
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
                    endRadius: 78
                )
            )
            PixelCharacterView(
                character: character,
                mode: mode,
                paused: paused,
                tint: SettingsTheme.paper,
                motion: motion
            )
            // 4pt a pixel: crisp at any scale.
            .frame(width: 56, height: 56)
            .offset(y: 2)
        }
        .frame(width: 128, height: 92)
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

/// A shortcut to another pane: its coloured tile and name on a soft capsule.
private struct WelcomeShortcut<Glyph: View>: View {
    let title: String
    let tint: SettingsTint
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                SettingsGlyphTile(size: 20, tint: tint, glyph: glyph)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(SettingsTheme.paper.opacity(isHovered ? 0.97 : 0.84))
            .padding(.leading, 5)
            .padding(.trailing, 13)
            .frame(height: 30)
            .background(Capsule().fill(SettingsTheme.paper.opacity(isHovered ? 0.12 : 0.065)))
            .overlay(Capsule().strokeBorder(SettingsTheme.paper.opacity(0.1), lineWidth: 0.75))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(title)
    }
}
