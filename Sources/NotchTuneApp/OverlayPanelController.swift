import AppKit
import Combine
import os
import QuartzCore
import SwiftUI
import NotchTuneCore

@MainActor
final class OverlayPanelController {
    private struct FileDragPresentationSnapshot {
        let notchStatus: NotchStatus
        let openReason: NotchOpenReason?
        let surface: IslandSurface
        let activeTab: IslandTab
    }

    // Opened-panel widths only — the closed pill is unaffected. Wide enough for
    // multiple agent usage chips in the header: on notched displays the lanes
    // flanking the physical notch get the extra room; external/top-bar displays
    // get one continuous row.
    nonisolated static let preferredNotchOpenedPanelWidth: CGFloat = 620
    private static let preferredTopBarOpenedPanelWidth: CGFloat = 640
    private static let preferredNotificationPanelWidth: CGFloat = 620
    private static let openedContentWidthPadding: CGFloat = 0
    private static let openedContentBottomPadding: CGFloat = 0
    private static let openedRowSpacing: CGFloat = 0
    // Content padding top + scroll padding + v8 list header/footer + bottom inset.
    // Rows are now full-width scan rows, so the old inter-card spacing is gone.
    private static let openedContentVerticalInsets: CGFloat = 92
    private static let notificationMeasuredContentPadding: CGFloat = 8
    private static let notificationEstimatedVerticalInsets: CGFloat = 36
    private static let openedEmptyStateHeight: CGFloat = 200
    nonisolated private static let fileDragTargetHeight: CGFloat = 104
    private static let questionCardBaseHeight: CGFloat = 110
    private static let questionCardMaxHeight: CGFloat = 420

    private var panel: NotchPanel?
    private var eventMonitors = NotchEventMonitors()
    private var hoverTimer: DispatchWorkItem?
    private var hoverCancelGrace: DispatchWorkItem?
    private var isFileDragNearNotch = false
    private var acceptedCurrentFileDrop = false
    private var fileDragEndGeneration: UInt64 = 0
    private var fileDragPresentationSnapshot: FileDragPresentationSnapshot?
    private var fileDragWatchTask: Task<Void, Never>?

    /// Set when the island auto-collapses on mouse-leave; suppresses an
    /// immediate hover-reopen while the cursor lingers over the notch (which
    /// would otherwise interrupt the close animation). Cleared once the cursor
    /// leaves the closed-surface area, so a deliberate re-hover still works.
    private var suppressHoverOpenAfterCollapse = false
    weak var model: AppModel?
    private(set) var notchRect: NSRect = .zero

    var isVisible: Bool {
        panel?.isVisible == true
    }

    nonisolated static func shouldActivatePanel(for reason: NotchOpenReason?) -> Bool {
        reason == .click
    }

    nonisolated static func shouldWakePanelForFileDrag(
        pasteboardChangeCountAtMouseDown: Int,
        currentPasteboardChangeCount: Int,
        hasFileURLs: Bool
    ) -> Bool {
        hasFileURLs && currentPasteboardChangeCount != pasteboardChangeCountAtMouseDown
    }

    func availableDisplayOptions() -> [OverlayDisplayOption] {
        OverlayDisplayResolver.availableDisplayOptions()
    }

    private func applyOverlayCollectionBehavior(to panel: NSPanel) {
        // Omit `.fullScreenAuxiliary` so the overlay stays on desktop spaces and
        // does not float above native fullscreen apps.
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]
    }

    @discardableResult
    func ensurePanel(model: AppModel, preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        self.model = model
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        applyOverlayCollectionBehavior(to: panel)
        let diagnostics = positionPanel(panel, preferredScreenID: preferredScreenID, animated: false)

        if model.isOverlayDisplayFullscreen {
            setPanelHiddenForFullscreen(true)
        } else {
            setPanelHiddenForFullscreen(false)
            panel.orderFrontRegardless()
        }

        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false
        startEventMonitoring()
        return diagnostics
    }

    func show(model: AppModel, preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        self.model = model
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        applyOverlayCollectionBehavior(to: panel)
        let diagnostics = positionPanel(panel, preferredScreenID: preferredScreenID, animated: true)

        if model.isOverlayDisplayFullscreen {
            setPanelHiddenForFullscreen(true)
        } else {
            setPanelHiddenForFullscreen(false)
            presentPanel(panel, activates: Self.shouldActivatePanel(for: model.notchOpenReason))
        }

        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        startEventMonitoring()
        return diagnostics
    }

    func hide() {
        panel?.ignoresMouseEvents = true
        panel?.acceptsMouseMovedEvents = false
    }

    func orderOutPanel() {
        setPanelHiddenForFullscreen(true)
    }

    func setPanelHiddenForFullscreen(_ hidden: Bool) {
        guard let panel else { return }

        if hidden {
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
            panel.acceptsMouseMovedEvents = false
            panel.orderOut(nil)
            stopEventMonitoring()
        } else {
            panel.alphaValue = 1
        }
    }

    func setInteractive(_ interactive: Bool) {
        guard let panel else {
            return
        }

        panel.ignoresMouseEvents = !interactive
        panel.acceptsMouseMovedEvents = interactive

        if interactive {
            guard model?.isOverlayDisplayFullscreen != true else { return }
            setPanelHiddenForFullscreen(false)
            presentPanel(panel, activates: Self.shouldActivatePanel(for: model?.notchOpenReason))
        }
    }

    func reposition(preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        guard let panel else {
            return placementDiagnostics(preferredScreenID: preferredScreenID)
        }

        return positionPanel(panel, preferredScreenID: preferredScreenID, animated: true)
    }

    func placementDiagnostics(preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        let panelSize = panel?.frame.size ?? OverlayDisplayResolver.defaultPanelSize
        return OverlayDisplayResolver.diagnostics(preferredScreenID: preferredScreenID, panelSize: panelSize)
    }

    // MARK: - Panel creation

    private func makePanel(model: AppModel) -> NotchPanel {
        let screen = resolveTargetScreen() ?? NSScreen.screens.first
        let windowFrame = screen.map { panelFrame(for: model, on: $0) } ?? .zero

        let panel = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .statusBar
        panel.sharingType = .readOnly
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = false
        // `.stationary` keeps the overlay pinned during the macOS Sonoma+
        // "click wallpaper to reveal desktop" gesture (and Mission Control
        // / Show Desktop). Without it the panel slides off-screen with the
        // user's other windows — on built-in notch displays it disappears
        // below the menu bar, and on external displays it falls out of the
        // top bar entirely.
        applyOverlayCollectionBehavior(to: panel)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = true

        let hostingView = NotchHostingView(rootView: IslandPanelView(model: model))
        hostingView.notchController = self
        panel.contentView = hostingView

        computeNotchRect(screen: resolveTargetScreen())
        return panel
    }

    // MARK: - Positioning

    @discardableResult
    private func positionPanel(
        _ panel: NSPanel,
        preferredScreenID: String?,
        animated: Bool
    ) -> OverlayPlacementDiagnostics? {
        guard let screen = resolveTargetScreen(preferredScreenID: preferredScreenID) else {
            return nil
        }

        let windowFrame = panelFrame(for: model, on: screen)

        // The window is ALWAYS opened-size, so the closed↔open morph never
        // resizes it — that transition is pure SwiftUI inside a fixed window.
        // The window only resizes when the *opened* content height changes
        // (switching tabs, the session list growing/shrinking). Those resizes
        // are therefore safe to animate: there's no SwiftUI open/close spring
        // running to collide with. SwiftUI relayout tracks the window each
        // frame (GeometryReader), so the glass + content morph height in step
        // with the window. Open/close, first present, and display moves still
        // snap instantly (see `shouldAnimateResize`).
        if panel.frame != windowFrame {
            if animated, shouldAnimateResize(panel: panel, to: windowFrame) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.panelResizeAnimationDuration
                    context.timingFunction = Self.panelResizeTimingFunction
                    context.allowsImplicitAnimation = true
                    panel.animator().setFrame(windowFrame, display: true)
                }
            } else {
                panel.setFrame(windowFrame, display: true)
            }
        }
        computeNotchRect(screen: screen)

        return OverlayDisplayResolver.diagnostics(
            preferredScreenID: preferredScreenID,
            panelSize: panel.frame.size
        )
    }

    /// How long the opened panel takes to morph to a new height. Tuned to sit
    /// just under the SwiftUI tab-content transition (`.smooth(0.35)`) so the
    /// window and its content settle together.
    private static let panelResizeAnimationDuration: TimeInterval = 0.34

    /// A soft decelerating curve (no overshoot) so the height settles like a
    /// liquid surface rather than a linear slide.
    private static let panelResizeTimingFunction =
        CAMediaTimingFunction(controlPoints: 0.22, 0.85, 0.25, 1)

    /// A frame change is safe to animate only when the island is already open
    /// and on-screen and *only its height* is changing. That isolates content /
    /// tab height changes (which should morph) from the open/close transition
    /// (which doesn't resize the window), the first present (panel not yet
    /// visible), and display moves (which change width / x) — all of which must
    /// snap instantly.
    private func shouldAnimateResize(panel: NSPanel, to newFrame: NSRect) -> Bool {
        guard panel.isVisible,
              model?.notchStatus == .opened,
              model?.isOverlayDisplayFullscreen != true else {
            return false
        }
        let current = panel.frame
        return abs(current.width - newFrame.width) < 0.5
            && abs(current.minX - newFrame.minX) < 0.5
            && abs(current.height - newFrame.height) >= 0.5
    }

    private func presentPanel(_ panel: NSPanel, activates: Bool) {
        if activates {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
            // Make the panel key even on hover/notification opens (without
            // activating the app — it's a .nonactivatingPanel, so the user's
            // active app keeps keyboard focus). Liquid Glass renders its
            // inactive "frosted" appearance in a non-key window and only flips
            // to the real, backdrop-refracting material once the window is key.
            // Without this, the glass stayed frosted until the user clicked.
            panel.makeKey()
        }
    }

    private func computeNotchRect(screen: NSScreen?) {
        guard let screen else {
            notchRect = .zero
            return
        }

        let notchSize = screen.notchSize
        let screenFrame = screen.frame
        let notchX = screenFrame.midX - notchSize.width / 2
        let notchY = screenFrame.maxY - notchSize.height
        notchRect = NSRect(x: notchX, y: notchY, width: notchSize.width, height: notchSize.height)
    }

    private func resolveTargetScreen(preferredScreenID: String? = nil) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let preferredScreenID,
           let screen = screens.first(where: { screenID(for: $0) == preferredScreenID }) {
            return screen
        }

        return NSScreen.main ?? screens[0]
    }

    private func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return screen.localizedName
    }

    // MARK: - Mouse event monitoring

    private func startEventMonitoring() {
        if model?.disablesOverlayEventMonitoringDuringHarness == true {
            return
        }

        guard !eventMonitors.isActive else { return }

        eventMonitors.start { [weak self] location in
            self?.handleMouseMoved(location)
        } mouseDownHandler: { [weak self] location in
            self?.handleMouseDown(location)
        } fileDragHandler: { [weak self] location, mouseDownChangeCount, currentChangeCount, hasFileURLs in
            self?.handleFileDragMoved(
                location,
                pasteboardChangeCountAtMouseDown: mouseDownChangeCount,
                currentPasteboardChangeCount: currentChangeCount,
                hasFileURLs: hasFileURLs
            )
        } fileDragEndedHandler: { [weak self] in
            self?.fileDragEnded()
        }
    }

    private func stopEventMonitoring() {
        eventMonitors.stop()
        fileDragWatchTask?.cancel()
        fileDragWatchTask = nil
    }

    private func handleMouseMoved(_ screenLocation: NSPoint) {
        guard let model else { return }
        guard !model.isOverlayDisplayFullscreen else { return }

        let inClosedSurfaceArea = isPointInClosedSurfaceArea(screenLocation)

        if inClosedSurfaceArea {
            model.notePointerInsideClosedArea()
        } else {
            model.notePointerExitedClosedArea()
        }

        if model.notchStatus == .closed && inClosedSurfaceArea {
            // Only auto-expand on hover if the island is NOT in its auto-hidden "inactive" state.
            // When auto-hidden (peeking), the user must click to expand.
            if !model.shouldCollapseClosedNotch {
                scheduleHoverOpen()
            } else {
                cancelHoverOpen()
            }
        } else if model.notchStatus == .closed && !inClosedSurfaceArea {
            cancelHoverOpen()
            // Cursor left the notch after an auto-collapse — re-arm hover-open.
            suppressHoverOpenAfterCollapse = false
        }

        let shouldTrackNotificationPointer = model.notchStatus == .opened
            && model.notchOpenReason == .notification
            && model.showsNotificationCard

        if shouldTrackNotificationPointer || model.shouldAutoCollapseOnMouseLeave {
            if isPointInExpandedArea(screenLocation) {
                model.notePointerInsideIslandSurface()
            } else {
                let wasOpened = model.notchStatus == .opened
                model.handlePointerExitedIslandSurface()
                // If that auto-collapsed the island, don't let the cursor still
                // sitting over the notch immediately re-hover it open mid-close.
                if wasOpened && model.notchStatus != .opened {
                    suppressHoverOpenAfterCollapse = true
                }
            }
        }
    }

    /// Watches the mouse while the left button is held. AppKit's global event
    /// monitors receive NO mouseDragged events once a drag-and-drop session is
    /// active (the WindowServer drag loop swallows them), so this poll is the
    /// only reliable way to notice a file drag approaching the closed notch.
    /// Runs solely while the button is down; each tick is a changeCount read
    /// until the drag pasteboard actually changes.
    private func beginFileDragWatch() {
        fileDragWatchTask?.cancel()
        let baseline = NSPasteboard(name: .drag).changeCount
        Self.dragLog.debug("watch started, baseline=\(baseline)")
        fileDragWatchTask = Task { @MainActor [weak self] in
            var announcedDrag = false
            var tickCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, !Task.isCancelled else { return }
                guard NSEvent.pressedMouseButtons & 1 == 1 else {
                    if announcedDrag { Self.dragLog.debug("watch ended (button up)") }
                    self.fileDragEnded()
                    self.fileDragWatchTask = nil
                    return
                }
                let pasteboard = NSPasteboard(name: .drag)
                // Stale drag data stays readable BETWEEN drags, so a live drag
                // is "content readable AND changeCount moved past the
                // mouseDown baseline". Finder writes concrete file URLs; Dock
                // stacks / browsers write file promises.
                let canReadURLs = pasteboard.canReadObject(
                    forClasses: [NSURL.self],
                    options: [.urlReadingFileURLsOnly: true]
                )
                let canReadPromises = pasteboard.canReadObject(
                    forClasses: [NSFilePromiseReceiver.self]
                )
                tickCount &+= 1
                if tickCount % 12 == 0 {
                    let names = (pasteboard.types ?? []).map(\.rawValue).joined(separator: ",")
                    Self.dragLog.debug("held: count=\(pasteboard.changeCount) baseline=\(baseline) urls=\(canReadURLs) promises=\(canReadPromises) types=[\(names)]")
                }
                let hasFileURLs = (canReadURLs || canReadPromises) && pasteboard.changeCount != baseline
                guard hasFileURLs else { continue }
                if !announcedDrag {
                    announcedDrag = true
                    let loc = NSEvent.mouseLocation
                    Self.dragLog.debug("file drag detected at (\(loc.x), \(loc.y))")
                }
                _ = self.updateFileDrag(screenLocation: NSEvent.mouseLocation, hasFileURLs: true)
            }
        }
    }

    static let dragLog = Logger(subsystem: "app.notchtune.dev", category: "filedrag")

    private func handleMouseDown(_ screenLocation: NSPoint) {
        guard let model else { return }
        guard !model.isOverlayDisplayFullscreen else { return }

        beginFileDragWatch()

        let inClosedSurfaceArea = isPointInClosedSurfaceArea(screenLocation)

        if model.notchStatus == .closed && inClosedSurfaceArea {
            cancelHoverOpenImmediately()
            model.notchOpen(reason: .click)
        } else if model.notchStatus == .opened {
            if !isPointInExpandedArea(screenLocation) {
                // Onboarding's live appearance preview pins the island open —
                // clicks in the wizard window must not collapse it.
                guard !model.overlay.keepsIslandOpenForPreview else { return }
                model.notchClose()
                repostMouseDown(at: screenLocation)
            } else if model.notchOpenReason != .click {
                // Passive hover/drag opens do not make the non-activating panel
                // key. Promote an intentional inside click before SwiftUI
                // handles it so text fields and editors can receive focus.
                model.notchOpen(reason: .click, surface: model.islandSurface)
            }
        }
    }

    // MARK: - File drag shelf

    private func handleFileDragMoved(
        _ screenLocation: NSPoint,
        pasteboardChangeCountAtMouseDown: Int,
        currentPasteboardChangeCount: Int,
        hasFileURLs: Bool
    ) {
        guard Self.shouldWakePanelForFileDrag(
            pasteboardChangeCountAtMouseDown: pasteboardChangeCountAtMouseDown,
            currentPasteboardChangeCount: currentPasteboardChangeCount,
            hasFileURLs: hasFileURLs
        ) else { return }

        // Closed panels are click-through, so AppKit cannot route the first
        // native draggingEntered callback to the hosting view. Wake the panel
        // from global drag motion; subsequent updates and the drop itself are
        // still validated by NotchHostingView's NSDraggingDestination methods.
        _ = updateFileDrag(screenLocation: screenLocation, hasFileURLs: true)
    }

    fileprivate func updateFileDrag(screenLocation: NSPoint, hasFileURLs: Bool) -> Bool {
        guard let model, !model.isOverlayDisplayFullscreen, hasFileURLs else { return false }

        if model.notchStatus == .opened,
           model.notchOpenReason != .drag,
           model.islandActiveTab == .myspace {
            return true
        }

        guard let closedRect = closedSurfaceRect(for: model) else { return false }

        let activationRect = Self.fileDragActivationRect(closedSurfaceRect: closedRect)
        let retentionRect = Self.fileDragRetentionRect(
            notchRect: notchRect,
            openedWidth: openedPanelWidth(for: resolveTargetScreen())
        )
        let isInsideTarget = Self.shouldPresentFileDragTarget(
            hasFileURLs: hasFileURLs,
            screenLocation: screenLocation,
            activationRect: activationRect,
            retentionRect: retentionRect,
            isAlreadyPresenting: isFileDragNearNotch
        )

        guard isInsideTarget else {
            if isFileDragNearNotch {
                fileDragEndGeneration &+= 1
                restoreStateBeforeFileDrag()
                isFileDragNearNotch = false
                acceptedCurrentFileDrop = false
            }
            // Approach phase: the drag is near but not on the notch. Hint that
            // the shelf is ready instead of opening.
            let hintRect = Self.fileDragHintRect(closedSurfaceRect: closedRect)
            let inHintZone = Self.rectContainsIncludingEdges(hintRect, point: screenLocation)
            Self.dragLog.debug("update loc=(\(screenLocation.x),\(screenLocation.y)) closed=\(String(describing: closedRect)) hint=\(String(describing: hintRect)) inHint=\(inHintZone) status=\(String(describing: model.notchStatus))")
            setFileDragHint(model.notchStatus == .closed && inHintZone)
            return false
        }

        setFileDragHint(false)
        fileDragEndGeneration &+= 1
        guard !isFileDragNearNotch else { return true }

        isFileDragNearNotch = true
        acceptedCurrentFileDrop = false
        presentFileDragTarget()
        return true
    }

    /// Toggle the closed pill's "ready to catch this file" hint. Entering the
    /// hint zone also hops the character once — a nudge, not an open.
    private func setFileDragHint(_ active: Bool) {
        guard let model, model.isFileDragHintReady != active else { return }
        model.isFileDragHintReady = active
        if active {
            model.nudgeTrigger = UUID()
        }
    }

    fileprivate func fileDragExited() {
        setFileDragHint(false)
        guard isFileDragNearNotch else { return }
        fileDragEndGeneration &+= 1
        if !acceptedCurrentFileDrop {
            restoreStateBeforeFileDrag()
        }
        isFileDragNearNotch = false
        acceptedCurrentFileDrop = false
        fileDragPresentationSnapshot = nil
    }

    fileprivate func fileDragEnded() {
        setFileDragHint(false)
        guard isFileDragNearNotch else { return }
        fileDragEndGeneration &+= 1
        let generation = fileDragEndGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, generation == self.fileDragEndGeneration else { return }
            if !self.acceptedCurrentFileDrop,
               self.model?.notchOpenReason == .drag {
                self.restoreStateBeforeFileDrag()
            }
            self.isFileDragNearNotch = false
            self.acceptedCurrentFileDrop = false
            self.fileDragPresentationSnapshot = nil
        }
    }

    func presentFileDragTarget() {
        guard let model else { return }
        if fileDragPresentationSnapshot == nil {
            fileDragPresentationSnapshot = FileDragPresentationSnapshot(
                notchStatus: model.notchStatus,
                openReason: model.notchOpenReason,
                surface: model.islandSurface,
                activeTab: model.islandActiveTab
            )
        }
        model.notchOpen(reason: .drag, surface: model.islandSurface)
    }

    func restoreStateBeforeFileDrag() {
        guard let model, let snapshot = fileDragPresentationSnapshot else { return }
        fileDragPresentationSnapshot = nil
        model.islandActiveTab = snapshot.activeTab

        if snapshot.notchStatus == .opened {
            model.notchOpen(
                reason: snapshot.openReason ?? .click,
                surface: snapshot.surface
            )
        } else {
            model.notchClose()
        }
    }

    var canAcceptDroppedFileURLs: Bool {
        guard let model else { return false }
        return model.notchOpenReason == .drag || model.islandActiveTab == .myspace
    }

    fileprivate func acceptDroppedFileURLs(_ urls: [URL]) -> Bool {
        guard let model, canAcceptDroppedFileURLs, !urls.isEmpty else { return false }
        do {
            try model.myspaceStore.holdFiles(urls)
            acceptedCurrentFileDrop = true
            fileDragEndGeneration &+= 1
            fileDragPresentationSnapshot = nil
            model.islandActiveTab = .myspace
            model.notchOpen(reason: .click)
            model.lastActionMessage = "Held \(urls.count) file\(urls.count == 1 ? "" : "s") in Myspace."
            return true
        } catch {
            model.lastActionMessage = "Could not hold file: \(error.localizedDescription)"
            return false
        }
    }

    /// Dock/stack drags (and some apps) deliver FILE PROMISES instead of
    /// concrete URLs — receive them into a scratch directory, then hold the
    /// received files like any other drop.
    fileprivate func acceptPromisedFiles(_ receivers: [NSFilePromiseReceiver]) -> Bool {
        guard model != nil, canAcceptDroppedFileURLs, !receivers.isEmpty else { return false }

        acceptedCurrentFileDrop = true
        fileDragEndGeneration &+= 1
        fileDragPresentationSnapshot = nil

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTune-promised-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let group = DispatchGroup()
        let queue = OperationQueue()
        nonisolated(unsafe) var received: [URL] = []
        let lock = NSLock()

        for receiver in receivers {
            group.enter()
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: queue) { url, error in
                if error == nil {
                    lock.lock()
                    received.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, let model = self.model, !received.isEmpty else {
                self?.model?.lastActionMessage = "Could not receive the dropped files."
                return
            }
            do {
                try model.myspaceStore.holdFiles(received)
                model.islandActiveTab = .myspace
                model.notchOpen(reason: .click)
                model.lastActionMessage = "Held \(received.count) file\(received.count == 1 ? "" : "s") in Myspace."
            } catch {
                model.lastActionMessage = "Could not hold file: \(error.localizedDescription)"
            }
            try? FileManager.default.removeItem(at: destination)
        }
        return true
    }

    // MARK: - Hover expansion

    /// Grace period before a hover-open timer is cancelled.  Prevents
    /// mouse jitter at the notch edge from resetting the delay.
    private static let hoverCancelGracePeriod: TimeInterval = 0.1

    private func scheduleHoverOpen() {
        // Suppressed right after an auto-collapse until the cursor leaves the
        // notch, so a lingering cursor doesn't interrupt the close animation.
        guard !suppressHoverOpenAfterCollapse else { return }

        // Mouse re-entered during grace period — just revoke the cancel.
        hoverCancelGrace?.cancel()
        hoverCancelGrace = nil

        guard model != nil else { return }

        guard hoverTimer == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self, let model = self.model else { return }
            self.performHoverOpen(model)
            self.hoverTimer = nil
        }

        hoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + AppModel.hoverOpenDelay, execute: item)
    }

    private func performHoverOpen(_ model: AppModel) {
        guard model.notchStatus == .closed else { return }

        if model.hapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(
                NSHapticFeedbackManager.FeedbackPattern.alignment,
                performanceTime: .now
            )
        }

        model.notchOpen(reason: .hover)
    }

    private func cancelHoverOpen() {
        guard hoverTimer != nil else { return }

        // Don't cancel immediately — allow a short grace period so that
        // mouse jitter at the notch edge doesn't restart the timer.
        guard hoverCancelGrace == nil else { return }

        let grace = DispatchWorkItem { [weak self] in
            self?.hoverTimer?.cancel()
            self?.hoverTimer = nil
            self?.hoverCancelGrace = nil
        }

        hoverCancelGrace = grace
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.hoverCancelGracePeriod,
            execute: grace
        )
    }

    /// Cancel without grace period — used for click-to-open where the
    /// hover timer must not fire after the click already opened the panel.
    private func cancelHoverOpenImmediately() {
        hoverCancelGrace?.cancel()
        hoverCancelGrace = nil
        hoverTimer?.cancel()
        hoverTimer = nil
    }

    // MARK: - Hit testing geometry

    func isPointInClosedSurfaceArea(_ screenPoint: NSPoint) -> Bool {
        guard let model else { return false }

        if let closedSurfaceRect = closedSurfaceRect(for: model) {
            return Self.rectContainsIncludingEdges(closedSurfaceRect, point: screenPoint)
        }

        let expandedNotch = notchRect.insetBy(dx: -20, dy: -10)
        return Self.rectContainsIncludingEdges(expandedNotch, point: screenPoint)
    }

    func isPointInExpandedArea(_ screenPoint: NSPoint) -> Bool {
        guard let model, model.notchStatus == .opened else {
            return isPointInClosedSurfaceArea(screenPoint)
        }

        guard let panel else {
            return false
        }

        // The window is always at opened size, but the visible content area
        // is the inner content rect (excluding shadow insets).
        guard let contentRect = contentRect(for: model, in: panel.frame) else {
            return false
        }

        return Self.rectContainsIncludingEdges(contentRect, point: screenPoint)
    }

    func openedPanelWidth(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return Self.preferredTopBarOpenedPanelWidth }
        let preferredWidth = screen.safeAreaInsets.top > 0
            ? Self.preferredNotchOpenedPanelWidth
            : Self.preferredTopBarOpenedPanelWidth
        return max(360, min(preferredWidth, screen.visibleFrame.width - 32))
    }

    func notificationPanelWidth(for screen: NSScreen?) -> CGFloat {
        guard let screen else {
            return Self.preferredNotificationPanelWidth
        }

        return min(Self.preferredNotificationPanelWidth, screen.visibleFrame.width - 32)
    }

    func contentRect(for model: AppModel, in bounds: NSRect) -> NSRect? {
        let insets = panelShadowInsets
        return NSRect(
            x: bounds.minX + insets.horizontal,
            y: bounds.minY + insets.bottom,
            width: max(0, bounds.width - (insets.horizontal * 2)),
            height: max(0, bounds.height - insets.bottom)
        )
    }

    nonisolated static func closedSurfaceRect(
        notchRect: NSRect,
        closedWidth: CGFloat
    ) -> NSRect {
        let cx = notchRect.midX
        return NSRect(
            x: cx - closedWidth / 2,
            y: notchRect.minY,
            width: closedWidth,
            height: notchRect.height
        )
    }

    nonisolated static func rectContainsIncludingEdges(_ rect: NSRect, point: NSPoint) -> Bool {
        point.x >= rect.minX
            && point.x <= rect.maxX
            && point.y >= rect.minY
            && point.y <= rect.maxY
    }

    /// The hit zone that actually opens the drop target: the closed surface
    /// itself plus a small tolerance so edge pixels still count.
    nonisolated static func fileDragActivationRect(closedSurfaceRect: NSRect) -> NSRect {
        closedSurfaceRect.insetBy(dx: -6, dy: -4)
    }

    /// The approach zone around the notch. A file drag inside it makes the
    /// closed pill hint (nudge + slight grow) that it's ready to catch the
    /// file, WITHOUT opening — only the activation rect opens.
    nonisolated static func fileDragHintRect(closedSurfaceRect: NSRect) -> NSRect {
        closedSurfaceRect.insetBy(dx: -96, dy: -64)
    }

    nonisolated static func shouldPresentFileDragTarget(
        hasFileURLs: Bool,
        screenLocation: NSPoint,
        activationRect: NSRect,
        retentionRect: NSRect,
        isAlreadyPresenting: Bool
    ) -> Bool {
        guard hasFileURLs else { return false }
        return rectContainsIncludingEdges(activationRect, point: screenLocation)
            || (isAlreadyPresenting
                && rectContainsIncludingEdges(retentionRect, point: screenLocation))
    }

    nonisolated static func fileDragRetentionRect(
        notchRect: NSRect,
        openedWidth: CGFloat
    ) -> NSRect {
        NSRect(
            x: notchRect.midX - openedWidth / 2,
            y: notchRect.maxY - fileDragTargetHeight,
            width: openedWidth,
            height: fileDragTargetHeight
        )
    }

    /// Hit-area width of the v6 closed pill.
    ///
    /// - On a MacBook (physical notch present) the pill is locked to
    ///   `44 + notchWidth + 44`, per the v6 design spec.
    /// - On an external display the width is content-driven; we return a
    ///   generous fixed hit-area so hover / click detection works without
    ///   the controller having to introspect live session state.
    nonisolated static func closedPanelWidth(
        notchWidth: CGFloat,
        isNotchedDisplay: Bool,
        notchStatus: NotchStatus
    ) -> CGFloat {
        let popBonus: CGFloat = notchStatus == .popping ? 18 : 0
        if isNotchedDisplay {
            return notchWidth + (IslandChromeMetrics.notchedClosedWingReserve() * 2) + popBonus
        }
        return 360 + popBonus
    }

    private func closedSurfaceRect(for model: AppModel) -> NSRect? {
        guard let screen = resolveTargetScreen() else {
            return nil
        }

        let closedWidth = closedPanelWidth(for: model, on: screen)
        return Self.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )
    }

    private func panelFrame(for model: AppModel?, on screen: NSScreen) -> NSRect {
        let size = panelSize(for: model, on: screen)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Always returns the maximum (opened) panel size so the window never
    /// needs to resize.  All visual transitions are driven purely by SwiftUI
    /// inside this fixed-size window.
    private func panelSize(for model: AppModel?, on screen: NSScreen) -> CGSize {
        let insets = panelShadowInsets

        guard let model else {
            return CGSize(
                width: openedPanelWidth(for: screen) + Self.openedContentWidthPadding + (insets.horizontal * 2),
                height: screen.notchSize.height + Self.openedEmptyStateHeight + Self.openedContentBottomPadding + insets.bottom
            )
        }

        let panelWidth = openedPanelWidth(for: screen)
        let contentHeight = openedContentHeight(for: model)
        // Use at least the empty-state height so the window doesn't shrink
        // when sessions come and go while opened.
        let height = screen.notchSize.height + max(contentHeight, Self.openedEmptyStateHeight) + Self.openedContentBottomPadding + insets.bottom

        return CGSize(
            width: panelWidth + Self.openedContentWidthPadding + (insets.horizontal * 2),
            height: height
        )
    }

    /// Constant insets — always opened size since the window never shrinks.
    private var panelShadowInsets: (horizontal: CGFloat, bottom: CGFloat) {
        (
            horizontal: IslandChromeMetrics.openedShadowHorizontalInset,
            bottom: IslandChromeMetrics.openedShadowBottomInset
        )
    }

    private func closedPanelWidth(for model: AppModel, on screen: NSScreen) -> CGFloat {
        let notchWidth = screen.notchSize.width
        let isNotched = screen.isNotchedScreen
        return Self.closedPanelWidth(
            notchWidth: notchWidth,
            isNotchedDisplay: isNotched,
            notchStatus: model.notchStatus
        )
    }

    private func openedContentHeight(for model: AppModel) -> CGFloat {
        let actionableID = model.islandSurface.sessionID
        let isNotificationMode = model.notchOpenReason == .notification && actionableID != nil

        if model.notchOpenReason == .drag {
            return Self.fileDragTargetHeight
        }

        if isNotificationMode {
            let tabBarHeight: CGFloat = 36
            // Use SwiftUI-measured height when available (accurate after first render).
            if model.measuredNotificationContentHeight > 0 {
                return model.measuredNotificationContentHeight + Self.notificationMeasuredContentPadding + tabBarHeight
            }
            // First render: estimate from the actionable session's content so the
            // initial window is close to the final size. This avoids a large blank
            // panel flash (the previous 500pt fallback) and reduces the chance of
            // a measurement→reposition cycle.
            if let actionableID,
               let session = model.state.session(id: actionableID) {
                let rowHeight = session.estimatedIslandRowHeight(at: Date.now)
                let bodyHeight = actionableBodyHeight(for: session, model: model)
                return rowHeight + bodyHeight + Self.notificationEstimatedVerticalInsets + tabBarHeight
            }
            return 300 + tabBarHeight
        }

        if model.islandActiveTab == .music {
            // Estimated height for music content:
            // 150 (image) + 16 (top) + 10 (bottom) + 42 (tab bar + breathing room) + 8 (spacing) + 8 (margin).
            return 150 + 16 + 10 + 42 + 8 + 8
        }

        if model.islandActiveTab == .myspace {
            let tabBarHeight: CGFloat = 36
            if model.measuredMyspaceContentHeight > 0 {
                return min(520, model.measuredMyspaceContentHeight + tabBarHeight + 8)
            }
            return 250
        }

        if model.islandActiveTab == .reminders {
            let tabBarHeight: CGFloat = 36
            if model.measuredRemindersContentHeight > 0 {
                return min(520, model.measuredRemindersContentHeight + tabBarHeight + 8)
            }
            return 230
        }

        let now = Date.now
        let visibleSessions = model.islandListSessions

        if visibleSessions.isEmpty {
            return Self.openedEmptyStateHeight
        }

        if model.islandActiveTab == .agents, model.measuredAgentsContentHeight > 0 {
            // Agents tab uses measured height + tab bar height + notch header height
            let tabBarHeight: CGFloat = 36 // Estimated tab bar height
            return model.measuredAgentsContentHeight + tabBarHeight + 12
        }

        let rowHeights = visibleSessions.map { session -> CGFloat in
            if session.id == actionableID {
                return session.estimatedIslandRowHeight(at: now)
                    + actionableBodyHeight(for: session, model: model)
            }
            return session.estimatedIslandRowHeight(at: now)
        }

        let rowsHeight = rowHeights.reduce(CGFloat.zero, +)
        let spacingHeight = CGFloat(max(0, rowHeights.count - 1)) * Self.openedRowSpacing
        let listHeight = rowsHeight + spacingHeight
        
        return listHeight + Self.openedContentVerticalInsets
    }

    /// Additional height for the actionable session's inline action area.
    private func actionableBodyHeight(for session: AgentSession, model: AppModel) -> CGFloat {
        switch session.phase {
        case .waitingForApproval:
            return 118
        case .waitingForAnswer:
            return questionCardHeight(for: session.questionPrompt) - 44
        case .completed:
            return completionBodyHeight(for: session, model: model)
        case .running:
            return 0
        }
    }

    /// Height of the inline completion expansion area (not the old full-card height).
    private func completionBodyHeight(for session: AgentSession, model: AppModel) -> CGFloat {
        let headerHeight: CGFloat = 44

        let text = (session.completionAssistantMessageText ?? session.summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return headerHeight
        }

        let availableWidth = Self.preferredNotificationPanelWidth - 96
        let font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let markdownHeight = min(260, ceil(textSize.height) + 20)
        // Reply input: divider (1) + input bar padding+content (~52)
        let replyInputHeight: CGFloat = TerminalTextSender.canReply(to: session, enabled: model.completionReplyEnabled) ? 53 : 0
        return headerHeight + 1 + markdownHeight + replyInputHeight
    }

    /// Estimates the question card height based on prompt content (question count,
    /// option count per question, and whether the prompt title is shown).
    private func questionCardHeight(for prompt: QuestionPrompt?) -> CGFloat {
        guard let prompt else {
            return Self.questionCardBaseHeight
        }

        let questions = prompt.questions.isEmpty && !prompt.options.isEmpty
            ? [
                QuestionPromptItem(
                    question: prompt.title,
                    header: "",
                    options: prompt.options.map { QuestionOption(label: $0) }
                ),
            ]
            : prompt.questions

        guard !questions.isEmpty else {
            return Self.questionCardBaseHeight
        }

        // Card chrome: outer padding + submit button.
        // When the prompt title is suppressed (single question whose title
        // matches the question text), reduce chrome because the body carries it.
        let titleSuppressed = questions.count == 1
            && prompt.title == questions.first?.question
        let chromeHeight: CGFloat = titleSuppressed ? 82 : 102
        var contentHeight: CGFloat = 0

        for question in questions {
            if questions.count > 1 {
                contentHeight += 16 // header
            }
            contentHeight += 20 // question text
            contentHeight += CGFloat(question.options.count) * 38 // option rows
        }

        // Inter-question spacing (only between questions, not after the last).
        contentHeight += CGFloat(max(0, questions.count - 1)) * 10

        let estimated = chromeHeight + contentHeight
        return min(Self.questionCardMaxHeight, max(Self.questionCardBaseHeight, estimated))
    }

    // MARK: - Event reposting

    private func repostMouseDown(at screenPoint: NSPoint) {
        let flippedY = NSScreen.screens.first.map { $0.frame.height - screenPoint.y } ?? screenPoint.y

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: screenPoint.x, y: flippedY),
            mouseButton: .left
        ) else { return }

        event.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard let upEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: CGPoint(x: screenPoint.x, y: flippedY),
                mouseButton: .left
            ) else { return }
            upEvent.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - NotchPanel

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - NotchHostingView

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var notchController: OverlayPanelController?

    override var isOpaque: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        // Ensure the panel is key before SwiftUI processes the click.
        // With nonactivatingPanel, hover-opened panels aren't key, so
        // SwiftUI Button may consume the first click for key acquisition
        // instead of firing its action.
        window?.makeKey()
        super.mouseDown(with: event)
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        // Concrete file URLs (Finder/desktop) AND file promises (Dock stacks,
        // browsers, Photos) — promise drags never carry .fileURL.
        registerForDraggedTypes(
            [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map(NSPasteboard.PasteboardType.init)
        )
        configureTransparency()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller = notchController,
              let model = controller.model else {
            return nil
        }

        guard let contentRect = controller.contentRect(for: model, in: bounds),
              contentRect.contains(point) else {
            return nil
        }

        return super.hitTest(point) ?? self
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        fileDragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        fileDragOperation(for: sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        notchController?.fileDragExited()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        notchController?.fileDragEnded()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        if !urls.isEmpty {
            return notchController?.acceptDroppedFileURLs(urls) ?? false
        }
        let receivers = sender.draggingPasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self]
        ) as? [NSFilePromiseReceiver] ?? []
        return notchController?.acceptPromisedFiles(receivers) ?? false
    }

    private func fileDragOperation(for sender: any NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(from: sender)
        let hasPromises = sender.draggingPasteboard.canReadObject(
            forClasses: [NSFilePromiseReceiver.self]
        )
        guard let notchController,
              notchController.updateFileDrag(
                screenLocation: screenLocation(for: sender),
                hasFileURLs: !urls.isEmpty || hasPromises
              ) else {
            return []
        }
        return .copy
    }

    private func fileURLs(from sender: any NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    private func screenLocation(for sender: any NSDraggingInfo) -> NSPoint {
        window?.convertPoint(toScreen: sender.draggingLocation) ?? sender.draggingLocation
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTransparency()
    }

    private func configureTransparency() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        // NSHostingView wraps content in internal NSScrollViews.
        // SwiftUI may recreate them when the view tree changes (e.g.
        // AutoHeightScrollView toggling between scroll/non-scroll mode),
        // so we must re-disable on every layout pass.
        // Guard: only modify properties when they differ to avoid
        // triggering additional layout passes that could loop.
        disableInternalScrollers(in: self)
    }

    private func disableInternalScrollers(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
            if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            return
        }
        for child in view.subviews {
            disableInternalScrollers(in: child)
        }
    }
}

// MARK: - NotchEventMonitors

@MainActor
final class NotchEventMonitors {
    private var globalMoveMonitor: Any?
    private var localMoveMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?
    private var globalDragEndMonitor: Any?
    private var localDragEndMonitor: Any?
    private var lastMoveTime: TimeInterval = 0

    var isActive: Bool { globalMoveMonitor != nil }

    func start(
        mouseMoveHandler: @MainActor @escaping @Sendable (NSPoint) -> Void,
        mouseDownHandler: @MainActor @escaping @Sendable (NSPoint) -> Void,
        fileDragHandler: @MainActor @escaping @Sendable (NSPoint, Int, Int, Bool) -> Void,
        fileDragEndedHandler: @MainActor @escaping @Sendable () -> Void
    ) {
        let throttleInterval: TimeInterval = 0.05

        nonisolated(unsafe) var sharedLastMove: TimeInterval = 0
        nonisolated(unsafe) var dragPasteboardChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount

        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastMove >= throttleInterval else { return }
            sharedLastMove = now
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseMoveHandler(location) }
        }

        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastMove >= throttleInterval else { return event }
            sharedLastMove = now
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseMoveHandler(location) }
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            dragPasteboardChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDownHandler(location) }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            dragPasteboardChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            let location = NSEvent.mouseLocation
            Task { @MainActor in mouseDownHandler(location) }
            return event
        }

        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in
            let pasteboard = NSPasteboard(name: .drag)
            let currentChangeCount = pasteboard.changeCount
            let mouseDownChangeCount = dragPasteboardChangeCountAtMouseDown
            let hasFileURLs = currentChangeCount != mouseDownChangeCount
                && pasteboard.canReadObject(
                    forClasses: [NSURL.self],
                    options: [.urlReadingFileURLsOnly: true]
                )
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                fileDragHandler(location, mouseDownChangeCount, currentChangeCount, hasFileURLs)
            }
        }

        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { event in
            let pasteboard = NSPasteboard(name: .drag)
            let currentChangeCount = pasteboard.changeCount
            let mouseDownChangeCount = dragPasteboardChangeCountAtMouseDown
            let hasFileURLs = currentChangeCount != mouseDownChangeCount
                && pasteboard.canReadObject(
                    forClasses: [NSURL.self],
                    options: [.urlReadingFileURLsOnly: true]
                )
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                fileDragHandler(location, mouseDownChangeCount, currentChangeCount, hasFileURLs)
            }
            return event
        }

        globalDragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            dragPasteboardChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            Task { @MainActor in fileDragEndedHandler() }
        }

        localDragEndMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            dragPasteboardChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            Task { @MainActor in fileDragEndedHandler() }
            return event
        }
    }

    func stop() {
        if let m = globalMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = localMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = localClickMonitor { NSEvent.removeMonitor(m) }
        if let m = globalDragMonitor { NSEvent.removeMonitor(m) }
        if let m = localDragMonitor { NSEvent.removeMonitor(m) }
        if let m = globalDragEndMonitor { NSEvent.removeMonitor(m) }
        if let m = localDragEndMonitor { NSEvent.removeMonitor(m) }
        globalMoveMonitor = nil
        localMoveMonitor = nil
        globalClickMonitor = nil
        localClickMonitor = nil
        globalDragMonitor = nil
        localDragMonitor = nil
        globalDragEndMonitor = nil
        localDragEndMonitor = nil
    }
}

// MARK: - NSScreen notch size helper

extension NSScreen {
    var isNotchedScreen: Bool {
        safeAreaInsets.top > 0
            || auxiliaryTopLeftArea?.isEmpty == false
            || auxiliaryTopRightArea?.isEmpty == false
    }

    /// Simulated notch width used on non-notch (external) displays.
    /// Sized close to a real MacBook notch (~200pt) so the closed island
    /// doesn't feel disproportionately wide when the black rectangle is
    /// fully visible (not hidden behind a physical notch).
    static let externalDisplayNotchWidth: CGFloat = 190
    static let externalDisplayNotchHeight: CGFloat = 38

    var notchSize: CGSize {
        guard isNotchedScreen else {
            return CGSize(
                width: Self.externalDisplayNotchWidth,
                height: Self.externalDisplayNotchHeight
            )
        }

        let notchHeight = islandClosedHeight

        // Authoritative: the auxiliary areas track the exact cutout at the
        // user's current scaled resolution, on every notched chassis.
        if let left = auxiliaryTopLeftArea?.width, left > 0,
           let right = auxiliaryTopRightArea?.width, right > 0 {
            return CGSize(width: frame.width - left - right + 4, height: notchHeight)
        }

        // Fallback: macOS reported a top safe-area inset without auxiliary
        // areas — estimate from the notched-chassis catalog instead of
        // degenerating to the full screen width.
        let estimated = NotchDisplayCatalog.estimatedNotchSize(forPointWidth: frame.width)
        return CGSize(width: estimated.width, height: notchHeight)
    }

    var topStatusBarHeight: CGFloat {
        let reservedTopInset = max(0, frame.maxY - visibleFrame.maxY)
        if reservedTopInset > 0 {
            return reservedTopInset
        }

        if safeAreaInsets.top > 0 {
            return safeAreaInsets.top
        }

        return 24
    }

    var islandClosedHeight: CGFloat {
        NSScreen.computeIslandClosedHeight(
            safeAreaInsetsTop: safeAreaInsets.top,
            topStatusBarHeight: topStatusBarHeight
        )
    }

    /// Pure helper so the height selection logic can be unit-tested without real screen hardware.
    ///
    /// On notch screens, use `safeAreaInsetsTop` directly — the island must match the
    /// physical notch height exactly so it sits flush with the notch bottom edge.
    /// Previously this used `min(safeAreaInsetsTop, topStatusBarHeight)`, but when the
    /// menu bar reserved area is smaller than the notch (e.g. auto-hide menu bar, or
    /// certain display configurations), the island ended up shorter than the physical
    /// notch, leaving a visible gap.
    /// On non-notch screens (`safeAreaInsetsTop == 0`), use `topStatusBarHeight` directly.
    static func computeIslandClosedHeight(
        safeAreaInsetsTop: CGFloat,
        topStatusBarHeight: CGFloat
    ) -> CGFloat {
        if safeAreaInsetsTop > 0 {
            return safeAreaInsetsTop
        }
        return topStatusBarHeight
    }
}
