import Foundation
import Testing
@testable import NotchTuneApp

/// Personalization Sync: one set of choices for the MacBook notch and the
/// external display, like a car's dual-zone climate SYNC.
@MainActor
struct AppearanceSyncTests {
    @Test
    func syncingTakesEveryChoiceButTheExternalAutoHide() {
        var source = IslandAppearancePreferences()
        source.character = .cat
        source.characterMotion = .lively
        source.density = .compact
        source.topCurve = false
        source.autoHideWhenInactive = true
        var target = IslandAppearancePreferences()
        target.autoHideWhenInactive = false

        let synced = target.syncing(from: source)

        var expected = source
        expected.autoHideWhenInactive = false
        #expect(synced == expected)
    }

    @Test
    func syncIsOffByDefault() {
        withIsolatedAppearanceDefaults {
            #expect(AppModel().appearanceSyncEnabled == false)
        }
    }

    @Test
    func turningSyncOnCopiesTheEditedDisplayOntoTheOther() {
        withIsolatedAppearanceDefaults {
            let model = AppModel()
            model.updateAppearancePreferences(for: .notch) {
                $0.character = .cat
                $0.density = .compact
            }
            model.updateAppearancePreferences(for: .topBar) {
                $0.character = .duck
                $0.autoHideWhenInactive = true
            }
            model.editAppearanceProfile(.notch)
            let notch = model.appearancePreferences(for: .notch)

            model.setAppearanceSync(true)

            #expect(model.appearanceSyncEnabled)
            #expect(model.appearancePreferences(for: .notch) == notch)
            let topBar = model.appearancePreferences(for: .topBar)
            #expect(topBar.character == .cat)
            #expect(topBar.density == .compact)
            #expect(topBar.autoHideWhenInactive, "the external display keeps its own auto-hide")
        }
    }

    @Test
    func editsWhileSyncedLandOnBothDisplays() {
        withIsolatedAppearanceDefaults {
            let model = AppModel()
            model.setAppearanceSync(true)

            model.updateAppearancePreferences(for: .notch) { $0.character = .ghost }
            #expect(model.appearancePreferences(for: .topBar).character == .ghost)

            model.updateAppearancePreferences(for: .topBar) { $0.characterMotion = .still }
            #expect(model.appearancePreferences(for: .notch).characterMotion == .still)

            // The island's own setters (the active display) sync too.
            model.islandCharacter = .frog
            #expect(model.appearancePreferences(for: .notch).character == .frog)
            #expect(model.appearancePreferences(for: .topBar).character == .frog)
        }
    }

    @Test
    func autoHideStaysOnTheExternalDisplayWhileSynced() {
        withIsolatedAppearanceDefaults {
            let model = AppModel()
            model.setAppearanceSync(true)

            model.updateAppearancePreferences(for: .topBar) { $0.autoHideWhenInactive = true }
            #expect(model.appearancePreferences(for: .notch).autoHideWhenInactive == false)

            model.updateAppearancePreferences(for: .notch) { $0.density = .compact }
            #expect(model.appearancePreferences(for: .topBar).autoHideWhenInactive)
        }
    }

    @Test
    func pickingOneDisplayTurnsSyncOffAndKeepsBothDisplaysChoices() {
        withIsolatedAppearanceDefaults {
            let model = AppModel()
            model.editAppearanceProfile(.notch)
            model.setAppearanceSync(true)
            model.updateAppearancePreferences(for: .notch) { $0.character = .robot }
            let notch = model.appearancePreferences(for: .notch)
            let topBar = model.appearancePreferences(for: .topBar)

            model.editAppearanceProfile(.topBar)

            #expect(model.appearanceSyncEnabled == false)
            #expect(model.appearanceSettingsProfile == .topBar)
            #expect(model.appearancePreferences(for: .notch) == notch)
            #expect(model.appearancePreferences(for: .topBar) == topBar)

            model.updateAppearancePreferences(for: .topBar) { $0.character = .slime }
            #expect(model.appearancePreferences(for: .notch).character == .robot)
        }
    }

    @Test
    func turningSyncOffLeavesBothDisplaysAsTheyAre() {
        withIsolatedAppearanceDefaults {
            let model = AppModel()
            model.setAppearanceSync(true)
            model.updateAppearancePreferences(for: .notch) { $0.character = .octopus }

            model.setAppearanceSync(false)
            #expect(model.appearancePreferences(for: .topBar).character == .octopus)

            model.updateAppearancePreferences(for: .notch) { $0.character = .crab }
            #expect(model.appearancePreferences(for: .topBar).character == .octopus)
        }
    }

    @Test
    func syncPersistsAcrossLaunches() {
        withIsolatedAppearanceDefaults {
            let writer = AppModel()
            writer.setAppearanceSync(true)
            #expect(UserDefaults.standard.bool(forKey: "appearance.island.v8.sync"))
            #expect(AppModel().appearanceSyncEnabled)

            writer.setAppearanceSync(false)
            #expect(AppModel().appearanceSyncEnabled == false)
        }
    }

    @Test
    func launchingSyncedReconcilesTheDisplaysFromTheEditedOne() {
        withIsolatedAppearanceDefaults {
            // As if a build without Sync had edited the external display.
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: "appearance.island.v8.sync")
            defaults.set("notch", forKey: "appearance.island.v8.settingsProfile")
            defaults.set("cat", forKey: "appearance.island.v8.notch.character")
            defaults.set("duck", forKey: "appearance.island.v8.topBar.character")

            let model = AppModel()

            #expect(model.appearancePreferences(for: .topBar).character == .cat)
        }
    }

    /// Runs `body` with every appearance preference cleared, then puts the
    /// suite's defaults back exactly as they were.
    private func withIsolatedAppearanceDefaults(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let prefix = "appearance.island."
        let saved = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix(prefix) }
        let clear = {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
                defaults.removeObject(forKey: key)
            }
        }
        clear()
        defer {
            clear()
            for (key, value) in saved { defaults.set(value, forKey: key) }
        }
        body()
    }
}
