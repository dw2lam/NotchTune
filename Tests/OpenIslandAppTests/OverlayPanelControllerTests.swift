import AppKit
import Testing
@testable import OpenIslandApp

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
        #expect(width == CGFloat(224 + (IslandChromeMetrics.notchedClosedWingReserve() * 2)))
    }

    @Test
    func notchedWingReserveGrowsForDenseAgentTiles() {
        let reserve = IslandChromeMetrics.notchedClosedWingReserve(rightSlotWidth: 38)
        #expect(reserve > IslandChromeMetrics.notchedClosedMinimumWingReserve)
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
        #expect(width == CGFloat(224 + (IslandChromeMetrics.notchedClosedWingReserve() * 2) + 18))
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

    // MARK: - islandClosedHeight

    @Test
    func islandClosedHeightClampsToNotchHeightWhenSmallerThanMenuBar() {
        // Simulates MacBook Air M2: physical notch ≈ 34 pt, menu bar reserved ≈ 37 pt.
        // Must return 34 (the smaller value) so the island sits flush with the notch.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 34, topStatusBarHeight: 37)
        #expect(height == 34)
    }

    @Test
    func islandClosedHeightUsesNotchHeightEvenWhenMenuBarIsShorter() {
        // When menu bar reserved < notch (e.g. auto-hide menu bar), the island must
        // still match the physical notch height to avoid a visible gap.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 37, topStatusBarHeight: 34)
        #expect(height == 37)
    }

    @Test
    func islandClosedHeightFallsBackToMenuBarHeightOnNonNotchScreen() {
        // Non-notch screen: safeAreaInsets.top == 0, fall back to topStatusBarHeight.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 0, topStatusBarHeight: 24)
        #expect(height == 24)
    }
}
