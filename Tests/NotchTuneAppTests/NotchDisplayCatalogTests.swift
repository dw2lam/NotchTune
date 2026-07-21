import Foundation
import Testing
@testable import NotchTuneApp

struct NotchDisplayCatalogTests {
    @Test
    func recognizesEveryNotchedChassisIdentifier() {
        // One representative per generation and size class.
        for id in [
            "MacBookPro18,3",   // 14" M1 Pro
            "MacBookPro18,1",   // 16" M1 Pro
            "Mac14,2",          // Air 13.6 M2
            "Mac14,10",         // 16" M2 Pro
            "Mac15,12",         // Air 13.6 M3
            "Mac16,1",          // 14" M4
            "Mac16,13",         // Air 15.3 M4
        ] {
            #expect(NotchDisplayCatalog.hasNotch(modelIdentifier: id), "\(id) should be notched")
        }
    }

    @Test
    func rejectsNotchlessMacs() {
        for id in [
            "MacBookPro17,1",   // 13" M1 Touch Bar
            "Mac14,7",          // 13" M2 Touch Bar
            "Mac14,12",         // Mac mini M2
            "Mac13,1",          // Mac Studio M1 Max
            "MacBookAir10,1",   // Air M1 (old chassis)
            "iMac21,1",
        ] {
            #expect(!NotchDisplayCatalog.hasNotch(modelIdentifier: id), "\(id) should NOT be notched")
        }
    }

    @Test
    func futureMacBookGenerationsAreAssumedNotched() {
        #expect(NotchDisplayCatalog.hasNotch(modelIdentifier: "Mac17,1"))
        #expect(NotchDisplayCatalog.hasNotch(modelIdentifier: "Mac18,4"))
    }

    @Test
    func estimatesScaleWithTheChosenDesktopWidth() {
        // Default scaling on a 14" MBP.
        let mbp14 = NotchDisplayCatalog.estimatedNotchSize(forPointWidth: 1512)
        #expect(mbp14.width == 200)
        #expect(mbp14.height == 32)

        // An off-catalog width (e.g. a scaled desktop) matches the nearest
        // chassis — 1800pt is closest to the 16" profile — and scales from it.
        let scaled = NotchDisplayCatalog.estimatedNotchSize(forPointWidth: 1800)
        #expect(scaled.width == (200 * 1800 / 1728).rounded())

        // Air 13.6 default.
        let air13 = NotchDisplayCatalog.estimatedNotchSize(forPointWidth: 1280)
        #expect(air13.width == 195)
        #expect(air13.height == 30)

        // 16" default.
        let mbp16 = NotchDisplayCatalog.estimatedNotchSize(forPointWidth: 1728)
        #expect(mbp16.width == 200)
    }
}
