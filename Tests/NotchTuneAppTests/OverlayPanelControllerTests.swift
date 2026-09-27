import AppKit
import Testing
@testable import NotchTuneApp

struct OverlayPanelControllerTests {
    @Test
    func closedSurfaceRectCentersOnNotch() {
        let notchRect = NSRect(x: 200, y: 900, width: 200, height: 38)
        let closedWidth: CGFloat = 320

        let rect = OverlayPanelController.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )

        // Centered on notch midX (300), width 320
        #expect(rect.minX == 140)
        #expect(rect.minY == 900)
        #expect(rect.width == 320)
        #expect(rect.height == 38)
    }

    @Test
    func closedSurfaceRectHitTestingBoundary() {
        let notchRect = NSRect(x: 400, y: 1_000, width: 200, height: 38)
        let closedWidth: CGFloat = 420

        let rect = OverlayPanelController.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )

        #expect(rect.contains(NSPoint(x: rect.minX + 2, y: rect.midY)))
        #expect(rect.contains(NSPoint(x: rect.maxX - 2, y: rect.midY)))
        #expect(!rect.contains(NSPoint(x: rect.minX - 1, y: rect.midY)))
        #expect(!rect.contains(NSPoint(x: rect.maxX + 1, y: rect.midY)))
    }

    @Test
    func edgeInclusiveHitTestingTreatsMaxBoundaryAsInside() {
        let rect = NSRect(x: 100, y: 200, width: 224, height: 8)
        #expect(OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 150, y: 208)))
        #expect(OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 324, y: 205)))
        #expect(!OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 325, y: 205)))
        #expect(!OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 150, y: 209)))
    }

    @Test
    func notchedDisplayClosedWidthWrapsPhysicalNotchWithFixedReserve() {
        // v6 MacBook layout: outer width = wing + physical notch + wing.
        // The wing is large enough to keep the right-side tile grid outside the notch cutout.
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            isNotchedDisplay: true,
            notchStatus: .closed
        )
        #expect(width == CGFloat(224 + (IslandChromeMetrics.regular.notchedClosedWingReserve() * 2)))
    }

    @Test
    func notchedWingReserveGrowsForDenseAgentTiles() {
        let reserve = IslandChromeMetrics.regular.notchedClosedWingReserve(rightSlotWidth: 38)
        #expect(reserve > IslandChromeMetrics.regular.notchedClosedMinimumWingReserve)
        #expect(reserve == 60)
    }

    @Test
    func externalDisplayClosedWidthUsesFixedHitArea() {
        // v6 external layout: fluid in SwiftUI, but the controller uses a
        // generous fixed hit-area so hover/click works without knowing the
        // live content width.
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 0,
            isNotchedDisplay: false,
            notchStatus: .closed
        )
        #expect(width == CGFloat(360))
    }

    @Test
    func poppingStatusAddsHoverBudget() {
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            isNotchedDisplay: true,
            notchStatus: .popping
        )
        #expect(width == CGFloat(224 + (IslandChromeMetrics.regular.notchedClosedWingReserve() * 2) + 18))
    }

    @Test
    func clickOpensActivateThePanel() {
        #expect(OverlayPanelController.shouldActivatePanel(for: .click))
    }

    @Test
    func passiveOpensDoNotActivateThePanel() {
        #expect(!OverlayPanelController.shouldActivatePanel(for: .hover))
        #expect(!OverlayPanelController.shouldActivatePanel(for: .drag))
        #expect(!OverlayPanelController.shouldActivatePanel(for: .notification))
        #expect(!OverlayPanelController.shouldActivatePanel(for: .boot))
        #expect(!OverlayPanelController.shouldActivatePanel(for: nil))
    }

    @Test
    func fileDragTargetRequiresFilesInsideTheNativeDropZone() {
        let activationRect = NSRect(x: 400, y: 900, width: 320, height: 60)
        let retentionRect = NSRect(x: 300, y: 856, width: 520, height: 104)

        #expect(!OverlayPanelController.shouldPresentFileDragTarget(
            hasFileURLs: false,
            screenLocation: NSPoint(x: 500, y: 920),
            activationRect: activationRect,
            retentionRect: retentionRect,
            isAlreadyPresenting: false
        ))
        #expect(OverlayPanelController.shouldPresentFileDragTarget(
            hasFileURLs: true,
            screenLocation: NSPoint(x: 500, y: 920),
            activationRect: activationRect,
            retentionRect: retentionRect,
            isAlreadyPresenting: false
        ))
        #expect(!OverlayPanelController.shouldPresentFileDragTarget(
            hasFileURLs: true,
            screenLocation: NSPoint(x: 350, y: 870),
            activationRect: activationRect,
            retentionRect: retentionRect,
            isAlreadyPresenting: false
        ))
        #expect(OverlayPanelController.shouldPresentFileDragTarget(
            hasFileURLs: true,
            screenLocation: NSPoint(x: 350, y: 870),
            activationRect: activationRect,
            retentionRect: retentionRect,
            isAlreadyPresenting: true
        ))
    }

    @Test
    func closedNotchOnlyWakesForAFreshFileDragPasteboard() {
        #expect(!OverlayPanelController.shouldWakePanelForFileDrag(
            pasteboardChangeCountAtMouseDown: 41,
            currentPasteboardChangeCount: 41,
            hasFileURLs: true
        ))
        #expect(!OverlayPanelController.shouldWakePanelForFileDrag(
            pasteboardChangeCountAtMouseDown: 41,
            currentPasteboardChangeCount: 42,
            hasFileURLs: false
        ))
        #expect(OverlayPanelController.shouldWakePanelForFileDrag(
            pasteboardChangeCountAtMouseDown: 41,
            currentPasteboardChangeCount: 42,
            hasFileURLs: true
        ))
    }

    @Test
    func fileDragActivationAreaHugsTheClosedNotch() {
        let closedRect = NSRect(x: 400, y: 900, width: 320, height: 38)
        let activationRect = OverlayPanelController.fileDragActivationRect(
            closedSurfaceRect: closedRect
        )

        // Tight hit zone: only edge tolerance, no approach padding — the
        // approach zone hints instead of opening.
        #expect(activationRect == NSRect(x: 394, y: 896, width: 332, height: 46))
        #expect(activationRect.contains(NSPoint(x: closedRect.midX, y: closedRect.minY - 3)))
        #expect(!activationRect.contains(NSPoint(x: closedRect.midX, y: closedRect.minY - 8)))
    }

    @Test
    func fileDragHintAreaSurroundsTheActivationArea() {
        let closedRect = NSRect(x: 400, y: 900, width: 320, height: 38)
        let hintRect = OverlayPanelController.fileDragHintRect(
            closedSurfaceRect: closedRect
        )
        let activationRect = OverlayPanelController.fileDragActivationRect(
            closedSurfaceRect: closedRect
        )

        #expect(hintRect == NSRect(x: 304, y: 836, width: 512, height: 166))
        #expect(hintRect.contains(activationRect))
        // Approaching from below / the side hints without activating.
        let approach = NSPoint(x: closedRect.midX - 80, y: closedRect.minY - 40)
        #expect(hintRect.contains(approach))
        #expect(!activationRect.contains(approach))
    }

    @Test
    func activeFileDragUsesACompactRetentionArea() {
        let notchRect = NSRect(x: 500, y: 962, width: 224, height: 38)
        let retentionRect = OverlayPanelController.fileDragRetentionRect(
            notchRect: notchRect,
            openedWidth: 520
        )

        #expect(retentionRect == NSRect(x: 352, y: 896, width: 520, height: 104))
    }

    @Test
    func islandTabsHaveAFullCapsuleSizedHitTarget() {
        #expect(IslandPanelView.tabHitTargetHeight >= 30)
    }

    @Test
    func openedNotchHeaderFitsClaudeAndCodexOutsidePhysicalNotch() {
        let totalWidth = OverlayPanelController.preferredNotchOpenedPanelWidth
        let physicalNotchWidth: CGFloat = 224
        let horizontalPadding: CGFloat = 16
        let safetyInset: CGFloat = 12
        let controlSpacing: CGFloat = 8
        let contentWidth = totalWidth - (horizontalPadding * 2)
        let rawWingWidth = ((totalWidth - physicalNotchWidth) / 2) - horizontalPadding
        let buttonStripWidth = IslandPanelView.headerControlStripWidth(
            controlCount: 2,
            buttonSize: 22,
            spacing: controlSpacing
        )

        let metrics = IslandPanelView.calculateOpenedHeaderMetrics(
            contentWidth: contentWidth,
            rawLeftWidth: rawWingWidth,
            rawRightWidth: rawWingWidth,
            laneSafetyInset: safetyInset,
            headerButtonsWidth: buttonStripWidth,
            controlSpacing: controlSpacing,
            minimumRightUsageLaneWidth: 58
        )

        #expect(totalWidth == 620)
        #expect(buttonStripWidth == 52)
        #expect(metrics.leftUsageWidth == 170)
        #expect(metrics.rightUsageWidth == 110)
        #expect(metrics.centerGapWidth == physicalNotchWidth + (safetyInset * 2))
    }

    @Test @MainActor
    func transientFileDropPreservesAndRestoresRemindersTab() {
        let model = AppModel()
        let controller = OverlayPanelController()
        controller.model = model
        model.islandActiveTab = .reminders
        model.notchOpen(reason: .click)

        #expect(!controller.canAcceptDroppedFileURLs)

        controller.presentFileDragTarget()

        #expect(model.notchOpenReason == .drag)
        #expect(model.islandActiveTab == .reminders)
        #expect(controller.canAcceptDroppedFileURLs)

        controller.restoreStateBeforeFileDrag()

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .click)
        #expect(model.islandActiveTab == .reminders)
        #expect(!controller.canAcceptDroppedFileURLs)
    }

    @Test @MainActor
    func cancelledFileDropRestoresClosedStateWithoutChangingTab() {
        let model = AppModel()
        let controller = OverlayPanelController()
        controller.model = model
        model.islandActiveTab = .reminders
        model.notchStatus = .closed
        model.notchOpenReason = nil

        controller.presentFileDragTarget()
        controller.restoreStateBeforeFileDrag()

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
        #expect(model.islandActiveTab == .reminders)
    }

    // MARK: - closedIslandHeight (single source of truth for the closed pill)

    @Test
    func notchedHeightTrustsSafeAreaWhenItMatchesTheCutout() {
        // 14" Pro at default scaling: safe area 32, catalog 32.
        let height = NSScreen.computeClosedIslandHeight(
            density: .regular,
            isNotched: true,
            safeAreaInsetsTop: 32,
            catalogNotchHeight: 32,
            menuBarHeight: 32
        )
        #expect(height == 32)
    }

    @Test
    func notchedHeightClampsToTheCatalogCutoutWhenTheMenuBarStandsTaller() {
        // Enlarged menu bar reports a 37pt safe area over a 32pt cutout: the
        // pill must not stand below the physical notch.
        for density in IslandDensity.allCases {
            let height = NSScreen.computeClosedIslandHeight(
                density: density,
                isNotched: true,
                safeAreaInsetsTop: 37,
                catalogNotchHeight: 32,
                menuBarHeight: 37
            )
            #expect(height == 32)
        }
    }

    @Test
    func notchedHeightToleratesOnePointOfCatalogRounding() {
        // A 1pt disagreement is rounding noise; clamping it would open a seam.
        let height = NSScreen.computeClosedIslandHeight(
            density: .compact,
            isNotched: true,
            safeAreaInsetsTop: 33,
            catalogNotchHeight: 32,
            menuBarHeight: 33
        )
        #expect(height == 33)
    }

    @Test
    func notchedHeightNeverGoesBelowTheSafeAreaWhenTheCatalogIsTaller() {
        // Auto-hide menu bar / smaller runtime inset than the catalog: keep
        // the runtime value (matches the old "no visible gap" rule).
        let height = NSScreen.computeClosedIslandHeight(
            density: .regular,
            isNotched: true,
            safeAreaInsetsTop: 34,
            catalogNotchHeight: 37,
            menuBarHeight: 37
        )
        #expect(height == 34)
    }

    @Test
    func notchedHeightFallsBackToTheCatalogWithoutASafeArea() {
        // Auxiliary areas only (no safe-area inset reported).
        let height = NSScreen.computeClosedIslandHeight(
            density: .regular,
            isNotched: true,
            safeAreaInsetsTop: 0,
            catalogNotchHeight: 38,
            menuBarHeight: 24
        )
        #expect(height == 38)
    }

    @Test
    func externalHeightIsTheRealMenuBarNotThePhantom38() {
        let regular = NSScreen.computeClosedIslandHeight(
            density: .regular,
            isNotched: false,
            safeAreaInsetsTop: 0,
            catalogNotchHeight: nil,
            menuBarHeight: 24
        )
        #expect(regular == 24)

        let large = NSScreen.computeClosedIslandHeight(
            density: .regular,
            isNotched: false,
            safeAreaInsetsTop: 0,
            catalogNotchHeight: nil,
            menuBarHeight: 30
        )
        #expect(large == 30)
    }

    @Test
    func externalCompactHeightCapsAt24AndFloorsAt22() {
        let usual = NSScreen.computeClosedIslandHeight(
            density: .compact,
            isNotched: false,
            safeAreaInsetsTop: 0,
            catalogNotchHeight: nil,
            menuBarHeight: 24
        )
        #expect(usual == 24)

        let large = NSScreen.computeClosedIslandHeight(
            density: .compact,
            isNotched: false,
            safeAreaInsetsTop: 0,
            catalogNotchHeight: nil,
            menuBarHeight: 30
        )
        #expect(large == 24)

        let degenerate = NSScreen.computeClosedIslandHeight(
            density: .compact,
            isNotched: false,
            safeAreaInsetsTop: 0,
            catalogNotchHeight: nil,
            menuBarHeight: 0
        )
        #expect(degenerate == 22)
    }

    @Test
    func closedHitAreaWidthFollowsTheDensityMetrics() {
        let regular = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            isNotchedDisplay: true,
            notchStatus: .closed,
            metrics: .regular
        )
        let compact = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            isNotchedDisplay: true,
            notchStatus: .closed,
            metrics: .compact
        )
        // Regular: glyph 24 + padding 14 + gap 8 = 46 (> the 44 floor).
        // Compact: 18 + 10 + 6 = 34 → the 36 floor wins.
        #expect(regular == CGFloat(224 + 46 * 2))
        #expect(compact == CGFloat(224 + 36 * 2))
        #expect(compact < regular)
    }
}
