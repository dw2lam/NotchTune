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
        #expect(mbp16.height == 32)
    }

    @Test
    func cutoutHeightScalesWithTheDesktopLikeTheWidth() {
        // The physical cutout is fixed; more points across → more points tall.
        // 14" Pro at "More Space" (1800×1169) reports a 38pt safe area.
        let moreSpace = NotchDisplayCatalog.estimatedNotchHeight(
            forPointSize: CGSize(width: 1800, height: 1169),
            modelIdentifier: "Mac16,1"
        )
        #expect(moreSpace == 38)

        let largerText = NotchDisplayCatalog.estimatedNotchHeight(
            forPointSize: CGSize(width: 1352, height: 878),
            modelIdentifier: "Mac16,1"
        )
        #expect(largerText == (32 * 1352 / 1512).rounded())
    }

    @Test
    func chassisIsResolvedFromTheModelIdentifierFirst() {
        #expect(NotchDisplayCatalog.chassis(forModelIdentifier: "Mac16,1")?.name == "MacBook Pro 14\"")
        #expect(NotchDisplayCatalog.chassis(forModelIdentifier: "Mac16,7")?.name == "MacBook Pro 16\"")
        #expect(NotchDisplayCatalog.chassis(forModelIdentifier: "Mac16,12")?.name == "MacBook Air 13.6\"")
        #expect(NotchDisplayCatalog.chassis(forModelIdentifier: "Mac16,13")?.name == "MacBook Air 15.3\"")
        #expect(NotchDisplayCatalog.chassis(forModelIdentifier: "Mac17,9") == nil)
        #expect(NotchDisplayCatalog.chassis(forModelIdentifier: nil) == nil)
    }

    @Test
    func unknownModelsFallBackToThePanelAspectRatio() {
        // A future 14" (Mac17,*) at 1800pt is wider than a 16" default; the
        // width-only match would pick the 16" and under-estimate the cutout.
        // The aspect ratio (3024:1964) identifies the 14" regardless of scaling.
        let chassis = NotchDisplayCatalog.chassis(
            forPointSize: CGSize(width: 1800, height: 1169),
            modelIdentifier: "Mac17,9"
        )
        #expect(chassis.name == "MacBook Pro 14\"")

        let height = NotchDisplayCatalog.estimatedNotchHeight(
            forPointSize: CGSize(width: 1800, height: 1169),
            modelIdentifier: "Mac17,9"
        )
        #expect(height == 38)

        // 16" at "More Space" (2056×1329) keeps its own ratio.
        let sixteen = NotchDisplayCatalog.chassis(
            forPointSize: CGSize(width: 2056, height: 1329),
            modelIdentifier: nil
        )
        #expect(sixteen.name == "MacBook Pro 16\"")
    }
}
