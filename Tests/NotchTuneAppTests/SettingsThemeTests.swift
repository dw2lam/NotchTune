import Testing
@testable import NotchTuneApp

@MainActor
struct SettingsThemeTests {
    @Test
    func everyTabUsesAMonoOutlineGlyphLikeTheIslandTabBar() {
        for tab in SettingsTab.allCases {
            #expect(!tab.icon.hasSuffix(".fill"), "\(tab) uses a filled glyph: \(tab.icon)")
            #expect(!tab.icon.isEmpty)
        }
        // Setup and Music share the island's own tab glyphs.
        #expect(SettingsTab.setup.icon == "terminal")
        #expect(SettingsTab.music.icon == "music.note")
    }

    @Test
    func menuPickerShowsTheSelectedTitleFromWhicheverSectionHoldsIt() {
        let sections: [(title: String?, segments: [SettingsSegment<String>])] = [
            ("System Sounds", [SettingsSegment("Bottle", "Bottle"), SettingsSegment("Glass", "Glass")]),
            ("Custom Sounds", [SettingsSegment("chime.aiff", "chime")]),
        ]
        #expect(SettingsMenuPicker<String>.title(for: "Glass", in: sections) == "Glass")
        // A custom sound shows its cleaned name, not the file name.
        #expect(SettingsMenuPicker<String>.title(for: "chime.aiff", in: sections) == "chime")
        #expect(SettingsMenuPicker<String>.title(for: "missing", in: sections) == "")
    }
}
