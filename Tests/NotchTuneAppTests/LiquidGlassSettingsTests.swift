import Testing
@testable import NotchTuneApp

struct LiquidGlassSettingsTests {
    @Test
    func defaultsUseClearGlassForOpenAndExternalClosedSurfaces() {
        let settings = LiquidGlassSettings()

        #expect(settings.isEnabled)
        #expect(settings.style == .clear)
        #expect(settings.tintStrength == 0.22)
        #expect(settings.openGlass?.style == .clear)
        #expect(settings.closedGlass(layout: .external)?.style == .clear)
        #expect(settings.closedGlass(layout: .macbook) == nil)
    }

    @Test
    func disablingGlassFallsBackToSolidInkEverywhere() {
        var settings = LiquidGlassSettings()
        settings.isEnabled = false
        settings.closedScope = .always

        #expect(settings.openGlass == nil)
        #expect(settings.closedGlass(layout: .external) == nil)
        #expect(settings.closedGlass(layout: .macbook) == nil)
    }

    @Test
    func closedScopeControlsEachDisplayLayout() {
        var settings = LiquidGlassSettings()

        settings.closedScope = .off
        #expect(settings.closedGlass(layout: .external) == nil)

        settings.closedScope = .always
        #expect(settings.closedGlass(layout: .external) != nil)
        #expect(settings.closedGlass(layout: .macbook) != nil)
    }
}
