import AppKit
import Foundation
import Testing
@testable import NotchTuneApp

struct IslandDensityTests {
    // MARK: - Metrics per density

    @Test
    func regularMetricsKeepTheShippedNumbers() {
        let m = IslandChromeMetrics.regular
        #expect(m.closedGlyphSize == 24)
        #expect(m.albumArtSize == 22)
        #expect(m.notchedClosedMinimumWingReserve == 44)
        #expect(m.notchedClosedHorizontalPadding == 14)
        #expect(m.notchedMusicLeadingPadding == 8)
        #expect(m.notchedMusicTrailingPadding == 8)
        #expect(m.notchedClosedContentGap == 8)
        #expect(m.waveformWidth == 20)
        #expect(m.waveformHeight == 14)
        #expect(m.playIconWidth == 18)
        #expect(m.notificationTitleFontSize == 11)
        #expect(m.notificationArtistFontSize == 10)
        #expect(m.closedHoverScale == CGSize(width: 1.035, height: 1.035))
        #expect(m.closedPopScale == CGSize(width: 1.04, height: 1.04))
        #expect(m.closedFileDragHintScale == CGSize(width: 1.07, height: 1.07))
        // 24 glyph + 14 padding + 8 gap = 46 beats the 44 floor (unchanged).
        #expect(m.notchedClosedWingReserve() == 46)
        #expect(m.notchedClosedWingReserve(rightSlotWidth: 38) == 60)
        #expect(m.notchedCompactMusicLeftWingReserve() == 30)
        #expect(m.notchedCompactMusicRightWingReserve() == 28)
        #expect(m.notchedMusicNotificationRightWingReserve() == 26)
    }

    @Test
    func compactMetricsTrimTheClosedChrome() {
        let m = IslandChromeMetrics.compact
        #expect(m.closedGlyphSize == 18)
        #expect(m.albumArtSize == 18)
        #expect(m.notchedClosedMinimumWingReserve == 36)
        #expect(m.notchedClosedHorizontalPadding == 10)
        #expect(m.notchedMusicLeadingPadding == 6)
        #expect(m.notchedMusicTrailingPadding == 6)
        #expect(m.notchedClosedContentGap == 6)
        #expect(m.notificationTitleFontSize == 10.5)
        #expect(m.notificationArtistFontSize == 9.5)
        // Two text lines must fit inside a 24pt external menu-bar pill.
        let textBlockHeight = m.notificationTitleLineHeight
            + m.notificationTextSpacing
            + m.notificationArtistLineHeight
        #expect(textBlockHeight <= 24)
        #expect(m.notchedClosedWingReserve() == 36)
        #expect(m.notchedCompactMusicLeftWingReserve() == 24)
        #expect(m.notchedCompactMusicRightWingReserve() == 24)
    }

    @Test
    func compactScaleEffectsStayOnTheXAxis() {
        let m = IslandChromeMetrics.compact
        #expect(m.closedHoverScale == CGSize(width: 1.02, height: 1))
        #expect(m.closedPopScale.height == 1)
        #expect(m.closedFileDragHintScale.height == 1)
        #expect(m.closedHoverScale.width < IslandChromeMetrics.regular.closedHoverScale.width)
    }

    @Test
    func metricsResolveByDensity() {
        #expect(IslandChromeMetrics.metrics(for: .regular) == .regular)
        #expect(IslandChromeMetrics.metrics(for: .compact) == .compact)
        #expect(IslandChromeMetrics.regular != IslandChromeMetrics.compact)
    }

    // MARK: - Preference persistence

    @Test
    func densityDefaultsToRegular() {
        #expect(IslandAppearancePreferences().density == .regular)
        #expect(IslandDensity(rawValue: "compact") == .compact)
        #expect(IslandDensity(rawValue: "") == nil)
    }

    @Test @MainActor
    func densityRoundTripsThroughUserDefaultsPerProfile() {
        let defaults = UserDefaults.standard
        let notchKey = "appearance.island.v8.notch.density"
        let topBarKey = "appearance.island.v8.topBar.density"
        let previousNotch = defaults.string(forKey: notchKey)
        let previousTopBar = defaults.string(forKey: topBarKey)
        defer {
            restore(defaults, key: notchKey, value: previousNotch)
            restore(defaults, key: topBarKey, value: previousTopBar)
        }

        let writer = AppModel()
        writer.updateAppearancePreferences(for: .notch) { $0.density = .compact }
        // Flip through compact so the regular write is a real change and persists.
        writer.updateAppearancePreferences(for: .topBar) { $0.density = .compact }
        writer.updateAppearancePreferences(for: .topBar) { $0.density = .regular }

        #expect(defaults.string(forKey: notchKey) == "compact")
        #expect(defaults.string(forKey: topBarKey) == "regular")

        let reader = AppModel()
        #expect(reader.appearancePreferences(for: .notch).density == .compact)
        #expect(reader.appearancePreferences(for: .topBar).density == .regular)
    }

    @Test @MainActor
    func harnessOverrideWinsWithoutTouchingThePersistedPreference() {
        let defaults = UserDefaults.standard
        let topBarKey = "appearance.island.v8.topBar.density"
        let previous = defaults.string(forKey: topBarKey)
        defer { restore(defaults, key: topBarKey, value: previous) }

        let model = AppModel()
        model.updateAppearancePreferences(for: .topBar) { $0.density = .compact }
        model.updateAppearancePreferences(for: .topBar) { $0.density = .regular }
        model.islandDensityHarnessOverride = .compact
        // No placement diagnostics → the active profile is `.topBar`.
        #expect(model.islandDensity == .compact)
        #expect(model.appearancePreferences(for: .topBar).density == .regular)
        #expect(defaults.string(forKey: topBarKey) == "regular")
    }

    private func restore(_ defaults: UserDefaults, key: String, value: String?) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
