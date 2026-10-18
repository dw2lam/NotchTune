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

        #expect(settings.openGlass == nil)
        #expect(settings.closedGlass(layout: .external) == nil)
        #expect(settings.closedGlass(layout: .macbook) == nil)
    }

    @Test
    func theBuiltInNotchPillAlwaysStaysSolid() {
        // Not a setting any more: glass there broke the blend with the
        // hardware notch and read as solid over the dark menu bar anyway.
        var settings = LiquidGlassSettings()
        settings.style = .regular
        settings.tintStrength = 0
        #expect(settings.closedGlass(layout: .macbook) == nil)
        #expect(settings.closedGlass(layout: .external)?.style == .regular)
    }
}
