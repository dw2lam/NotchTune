import Testing
@testable import NotchTuneApp

/// The sidebar's sections now that About and Updates live on General.
struct SettingsSidebarTests {
    @Test
    func theSidebarListsSixSectionsInThreeGroups() {
        #expect(SettingsTab.allCases == [.general, .setup, .appearance, .display, .sound, .music])
        #expect(SettingsSection.app.tabs == [.general])
        #expect(SettingsSection.island.tabs == [.setup, .appearance, .display])
        #expect(SettingsSection.media.tabs == [.sound, .music])
    }

    @Test
    func aboutAndUpdatesStillOpenSettingsOnGeneral() {
        #expect(SettingsTab.resolving("about") == .general)
        #expect(SettingsTab.resolving("updates") == .general)
        for tab in SettingsTab.allCases {
            #expect(SettingsTab.resolving(tab.rawValue) == tab)
        }
        #expect(SettingsTab.resolving("nowhere") == nil)
    }
}
