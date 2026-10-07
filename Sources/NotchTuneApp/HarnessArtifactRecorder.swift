import AppKit
import ApplicationServices
import Foundation

struct HarnessArtifactReport: Codable {
    struct AccessibilitySummary: Codable {
        let labels: [String]
        let buttonLabels: [String]
        let textValues: [String]
    }

    struct AccessibilityNode: Codable {
        let typeName: String
        let role: String?
        let subrole: String?
        let label: String?
        let value: String?
        let children: [AccessibilityNode]
    }

    struct WindowArtifact: Codable {
        let kind: String
        let title: String
        let frame: RectSnapshot
        let imagePath: String
        let accessibilityPath: String?
        let accessibilitySummary: AccessibilitySummary?
    }

    struct RectSnapshot: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ rect: NSRect) {
            x = rect.origin.x
            y = rect.origin.y
            width = rect.size.width
            height = rect.size.height
        }
    }

    struct OverlaySnapshot: Codable {
        let screenID: String
        let screenName: String
        let selectionSummary: String
        let mode: String
        let screenFrame: RectSnapshot
        let visibleFrame: RectSnapshot
        let overlayFrame: RectSnapshot
        let safeAreaInsets: EdgeInsetsSnapshot
    }

    struct EdgeInsetsSnapshot: Codable {
        let top: Double
        let left: Double
        let bottom: Double
        let right: Double

        init(_ insets: NSEdgeInsets) {
            top = insets.top
            left = insets.left
            bottom = insets.bottom
            right = insets.right
        }
    }

    struct SessionSnapshot: Codable {
        let id: String
        let tool: String
        let phase: String
        let attachmentState: String
        let title: String
        let summary: String
    }

    let scenario: String?
    let presentOverlay: Bool
    let startedBridge: Bool
    let performedBootAnimation: Bool
    let capturedAt: Date
    let launchToCaptureSeconds: Double
    let windows: [WindowArtifact]
    let overlay: OverlaySnapshot?
    let sessionCount: Int
    let liveSessionCount: Int
    let attentionCount: Int
    let selectedSessionID: String?
    let islandSurface: String
    let notchStatus: String
    let runtime: HarnessRuntimeArtifacts?
    let sessions: [SessionSnapshot]
}

@MainActor
enum HarnessArtifactRecorder {
    static func record(
        configuration: HarnessLaunchConfiguration,
        model: AppModel,
        launchedAt: Date,
        runtimeMonitor: HarnessRuntimeMonitor? = nil,
        fileManager: FileManager = .default
    ) throws {
        guard let directoryURL = configuration.artifactDirectoryURL else {
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var windows: [HarnessArtifactReport.WindowArtifact] = []
        for window in orderedVisibleWindows() {
            guard let imageData = snapshotPNGData(for: window) else {
                continue
            }

            let imageName = imageFileName(for: window, ordinal: windows.count + 1)
            let imageURL = directoryURL.appendingPathComponent(imageName)
            try imageData.write(to: imageURL)
            if ProcessInfo.processInfo.environment["NOTCHTUNE_HARNESS_COMPOSITED"] == "1",
               let composited = compositedPNGData(for: window) {
                try composited.write(to: directoryURL.appendingPathComponent(
                    imageName.replacingOccurrences(of: ".png", with: "-composited.png")))
            }

            let accessibilityFileName = accessibilityFileName(for: window, ordinal: windows.count + 1)
            let viewAccessibilitySnapshot = snapshotViewAccessibilityTree(for: window)
            let accessibilitySnapshot = snapshotAXTree(for: window) ?? viewAccessibilitySnapshot
            if let accessibilitySnapshot {
                let accessibilityURL = directoryURL.appendingPathComponent(accessibilityFileName)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(accessibilitySnapshot).write(to: accessibilityURL)
            }

            windows.append(
                HarnessArtifactReport.WindowArtifact(
                    kind: windowKind(for: window),
                    title: window.title,
                    frame: .init(window.frame),
                    imagePath: imageName,
                    accessibilityPath: accessibilitySnapshot == nil ? nil : accessibilityFileName,
                    accessibilitySummary: mergedAccessibilitySummary(
                        primary: accessibilitySnapshot,
                        secondary: viewAccessibilitySnapshot
                    )
                )
            )
        }

        let captureSeconds = Date().timeIntervalSince(launchedAt)
        let runtimeArtifacts = try runtimeMonitor?.writeArtifacts(
            to: directoryURL,
            launchToCaptureSeconds: captureSeconds,
            fileManager: fileManager
        )

        let report = HarnessArtifactReport(
            scenario: configuration.scenario?.rawValue,
            presentOverlay: configuration.presentOverlay,
            startedBridge: configuration.shouldStartBridge,
            performedBootAnimation: configuration.shouldPerformBootAnimation,
            capturedAt: .now,
            launchToCaptureSeconds: captureSeconds,
            windows: windows,
            overlay: overlaySnapshot(from: model.overlayPlacementDiagnostics),
            sessionCount: model.sessions.count,
            liveSessionCount: model.liveSessionCount,
            attentionCount: model.liveAttentionCount,
            selectedSessionID: model.selectedSessionID,
            islandSurface: surfaceDescription(model.islandSurface),
            notchStatus: notchStatusDescription(model.notchStatus),
            runtime: runtimeArtifacts,
            sessions: model.sessions.map {
                HarnessArtifactReport.SessionSnapshot(
                    id: $0.id,
                    tool: $0.tool.rawValue,
                    phase: $0.phase.rawValue,
                    attachmentState: $0.attachmentState.rawValue,
                    title: $0.title,
                    summary: $0.summary
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let reportURL = directoryURL.appendingPathComponent("report.json")
        try encoder.encode(report).write(to: reportURL)
    }

    private static func orderedVisibleWindows() -> [NSWindow] {
        NSApp.windows
            .filter { window in
                window.isVisible && recognizedWindowKind(for: window) != nil
            }
            .sorted { lhs, rhs in
                lhs.frame.maxY > rhs.frame.maxY
            }
    }

    private static func snapshotPNGData(for window: NSWindow) -> Data? {
        window.displayIfNeeded()
        guard let contentView = window.contentView else {
            return nil
        }

        contentView.layoutSubtreeIfNeeded()
        let bounds = contentView.bounds.integral
        guard bounds.width > 0,
              bounds.height > 0,
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }

        bitmap.size = bounds.size
        contentView.cacheDisplay(in: bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Settings / onboarding windows opened by the harness, captured as the
    /// window server composites them (materials, shadows) into
    /// `settings.png` / `onboarding.png`.
    static func recordAppWindows(to directoryURL: URL) {
        for window in NSApp.windows where window.isVisible && !(window is NSPanel) {
            // SwiftUI `Window(id:)` scenes carry their id in the identifier;
            // the title follows the selected pane, so it can't be matched.
            // Headless runs capture only the harness's own hidden windows
            // (SwiftUI's scene windows are closed and never drawn there).
            let identifier = window.identifier?.rawValue ?? ""
            let name: String
            if identifier == "harness-settings" || (!HarnessHeadless.isActive && identifier.contains("settings")) {
                name = "settings"
            } else if identifier == "harness-onboarding" || (!HarnessHeadless.isActive && identifier.contains("onboarding")) {
                name = "onboarding"
            } else {
                continue
            }
            guard let data = compositedPNGData(for: window) else { continue }
            try? data.write(to: directoryURL.appendingPathComponent("\(name).png"))
        }
    }

    /// `NOTCHTUNE_HARNESS_FILMSTRIP=1`: close the notch, then sample the
    /// window at ~30 fps while it opens and again while it closes, into
    /// `<artifacts>/filmstrip/{open,close}-NN.png`. Captures run off the main
    /// thread so they don't stall the animation they're sampling.
    static func recordFilmstrip(model: AppModel, directoryURL: URL) {
        guard let window = orderedVisibleWindows().first else { return }
        let windowNumber = UInt32(window.windowNumber)
        // `.null` = the window's own bounds, wherever it sits. A screen rect
        // computed from the frame came back blank once headless runs parked
        // the panel beyond every display (+60000pt): screen-space capture
        // only covers display area. Ignoring framing keeps every frame the
        // window's exact, fixed size, so frames stay aligned.
        let bounds = CGRect.null
        let dir = directoryURL.appendingPathComponent("filmstrip", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        model.notchClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            captureBurst(windowNumber: windowNumber, bounds: bounds, directory: dir, prefix: "open")
            model.notchOpen(reason: .click)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                captureBurst(windowNumber: windowNumber, bounds: bounds, directory: dir, prefix: "close")
                model.notchClose()
            }
        }
    }

    nonisolated private static func captureBurst(
        windowNumber: UInt32,
        bounds: CGRect,
        directory: URL,
        prefix: String,
        frames: Int = 27,
        interval: TimeInterval = 1.0 / 30.0
    ) {
        DispatchQueue.global(qos: .userInteractive).async {
            typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
            guard let handle = dlopen(nil, RTLD_NOW),
                  let sym = dlsym(handle, "CGWindowListCreateImage") else { return }
            let capture = unsafeBitCast(sym, to: Fn.self)
            let start = Date()
            var images: [(Int, CGImage)] = []
            for index in 0..<frames {
                let target = start.addingTimeInterval(Double(index) * interval)
                let wait = target.timeIntervalSinceNow
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                // optionIncludingWindow = 1 << 3; boundsIgnoreFraming = 1 << 0
                // | bestResolution = 1 << 3.
                if let image = capture(bounds, 1 << 3, windowNumber, (1 << 0) | (1 << 3))?.takeRetainedValue() {
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    images.append((ms, image))
                }
            }
            for (offset, entry) in images.enumerated() {
                let data = NSBitmapImageRep(cgImage: entry.1).representation(using: .png, properties: [:])
                let name = String(format: "%@-%02d-%04dms.png", prefix, offset, entry.0)
                try? data?.write(to: directory.appendingPathComponent(name))
            }
        }
    }

    private static func compositedPNGData(for window: NSWindow) -> Data? {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen(nil, RTLD_NOW),
              let sym = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let fn = unsafeBitCast(sym, to: Fn.self)
        // optionIncludingWindow = 1 << 3, bestResolution = 1 << 3 image option
        guard let image = fn(.null, 1 << 3, UInt32(window.windowNumber), 1 << 3)?.takeRetainedValue() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    private static func imageFileName(for window: NSWindow, ordinal: Int) -> String {
        let baseName: String
        switch recognizedWindowKind(for: window) ?? "window" {
        case "overlay":
            baseName = "overlay"
        default:
            baseName = "window-\(ordinal)"
        }

        return "\(baseName).png"
    }

    private static func accessibilityFileName(for window: NSWindow, ordinal: Int) -> String {
        let baseName: String
        switch recognizedWindowKind(for: window) ?? "window" {
        case "overlay":
            baseName = "overlay"
        default:
            baseName = "window-\(ordinal)"
        }

        return "\(baseName).ax.json"
    }

    private static func windowKind(for window: NSWindow) -> String {
        recognizedWindowKind(for: window) ?? "window"
    }

    private static func recognizedWindowKind(for window: NSWindow) -> String? {
        if window is NSPanel {
            return window.frame.width >= 120 ? "overlay" : nil
        }

        return nil
    }

    private static func overlaySnapshot(
        from diagnostics: OverlayPlacementDiagnostics?
    ) -> HarnessArtifactReport.OverlaySnapshot? {
        guard let diagnostics else {
            return nil
        }

        return HarnessArtifactReport.OverlaySnapshot(
            screenID: diagnostics.targetScreenID,
            screenName: diagnostics.targetScreenName,
            selectionSummary: diagnostics.selectionSummary,
            mode: diagnostics.mode.rawValue,
            screenFrame: .init(diagnostics.screenFrame),
            visibleFrame: .init(diagnostics.visibleFrame),
            overlayFrame: .init(diagnostics.overlayFrame),
            safeAreaInsets: .init(diagnostics.safeAreaInsets)
        )
    }

    private static func surfaceDescription(_ surface: IslandSurface) -> String {
        switch surface {
        case .sessionList(actionableSessionID: nil):
            "sessionList"
        case let .sessionList(actionableSessionID: sessionID?):
            "sessionList:actionable(\(sessionID))"
        }
    }

    private static func notchStatusDescription(_ status: NotchStatus) -> String {
        switch status {
        case .closed:
            "closed"
        case .opened:
            "opened"
        case .popping:
            "popping"
        }
    }

    private static func snapshotViewAccessibilityTree(for window: NSWindow) -> HarnessArtifactReport.AccessibilityNode? {
        window.displayIfNeeded()

        if let contentView = window.contentView,
            let node = snapshotAccessibilityNode(from: contentView, fallbackChildren: contentView.subviews) {
            return node
        }

        return snapshotAccessibilityNode(from: window, fallbackChildren: [])
    }

    private static func mergedAccessibilitySummary(
        primary: HarnessArtifactReport.AccessibilityNode?,
        secondary: HarnessArtifactReport.AccessibilityNode?
    ) -> HarnessArtifactReport.AccessibilitySummary? {
        let roots = [primary, secondary].compactMap { $0 }
        guard roots.isEmpty == false else {
            return nil
        }

        var labels = Set<String>()
        var buttonLabels = Set<String>()
        var textValues = Set<String>()

        for root in roots {
            collectAccessibilityStrings(
                from: root,
                labels: &labels,
                buttonLabels: &buttonLabels,
                textValues: &textValues
            )
        }

        return HarnessArtifactReport.AccessibilitySummary(
            labels: labels.sorted(),
            buttonLabels: buttonLabels.sorted(),
            textValues: textValues.sorted()
        )
    }

    private static func snapshotAccessibilityNode(
        from rawElement: Any,
        fallbackChildren: [Any] = [],
        depth: Int = 0
    ) -> HarnessArtifactReport.AccessibilityNode? {
        guard depth <= 16 else {
            return nil
        }

        if let object = rawElement as? NSObject {
            let viewChildren = (rawElement as? NSView)?.subviews ?? []
            let rawAccessibilityChildren = selectorArrayValue("accessibilityChildren", on: object) ?? []
            let rawChildren: [Any]
            if rawAccessibilityChildren.isEmpty == false {
                rawChildren = rawAccessibilityChildren
            } else if viewChildren.isEmpty == false {
                rawChildren = viewChildren
            } else {
                rawChildren = fallbackChildren
            }
            let children = rawChildren.compactMap {
                snapshotAccessibilityNode(from: $0, depth: depth + 1)
            }

            var label = selectorStringValue("accessibilityLabel", on: object)
            var value = selectorStringValue("accessibilityValue", on: object)
            var role = selectorStringValue("accessibilityRole", on: object)
            let subrole = selectorStringValue("accessibilitySubrole", on: object)

            if let button = rawElement as? NSButton {
                label = label ?? trimmedString(button.title)
                role = role ?? "AXButton"
            } else if let textField = rawElement as? NSTextField {
                value = value ?? trimmedString(textField.stringValue)
                role = role ?? "AXStaticText"
            } else if let control = rawElement as? NSControl {
                value = value ?? trimmedString(control.stringValue)
            }

            if label == nil,
               value == nil,
               role == nil,
               subrole == nil,
               children.isEmpty {
                return nil
            }

            return HarnessArtifactReport.AccessibilityNode(
                typeName: String(describing: type(of: rawElement)),
                role: role,
                subrole: subrole,
                label: label,
                value: value,
                children: children
            )
        }

        if let view = rawElement as? NSView {
            let children = view.subviews.compactMap {
                snapshotAccessibilityNode(from: $0, depth: depth + 1)
            }

            if children.isEmpty {
                return nil
            }

            return HarnessArtifactReport.AccessibilityNode(
                typeName: String(describing: type(of: rawElement)),
                role: nil,
                subrole: nil,
                label: nil,
                value: nil,
                children: children
            )
        }

        return nil
    }

    private static func snapshotAXTree(for window: NSWindow) -> HarnessArtifactReport.AccessibilityNode? {
        let applicationElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        guard let axWindows = copyAXElementArrayValue(
            of: applicationElement,
            attribute: kAXWindowsAttribute as CFString
        ) else {
            return nil
        }

        let targetFrame = window.frame
        let targetTitle = trimmedString(window.title)
        let matchingWindow = axWindows.min { lhs, rhs in
            axWindowScore(for: lhs, targetFrame: targetFrame, targetTitle: targetTitle)
                < axWindowScore(for: rhs, targetFrame: targetFrame, targetTitle: targetTitle)
        }

        guard let matchingWindow else {
            return nil
        }

        var visited = Set<AXUIElement>()
        return snapshotAXNode(from: matchingWindow, visited: &visited)
    }

    private static func axWindowScore(
        for element: AXUIElement,
        targetFrame: NSRect,
        targetTitle: String?
    ) -> CGFloat {
        let frame = axFrame(for: element) ?? .zero
        let title = copyStringValue(of: element, attribute: kAXTitleAttribute as CFString)

        var score = abs(frame.origin.x - targetFrame.origin.x)
            + abs(frame.origin.y - targetFrame.origin.y)
            + abs(frame.size.width - targetFrame.size.width)
            + abs(frame.size.height - targetFrame.size.height)

        if targetTitle != nil, targetTitle == title {
            score -= 1000
        }

        return score
    }

    private static func snapshotAXNode(
        from element: AXUIElement,
        depth: Int = 0,
        visited: inout Set<AXUIElement>
    ) -> HarnessArtifactReport.AccessibilityNode? {
        // The AX graph isn't a tree: the application element turns up again
        // below the window, and re-walking it (every window, every menu) to
        // depth 16 stalled each capture for about a minute. Visit each
        // element once.
        guard depth <= 16, visited.insert(element).inserted else {
            return nil
        }

        let children = copyAXElementArrayValue(
            of: element,
            attribute: kAXChildrenAttribute as CFString
        )?.compactMap { snapshotAXNode(from: $0, depth: depth + 1, visited: &visited) } ?? []

        let role = copyStringValue(of: element, attribute: kAXRoleAttribute as CFString)
        let subrole = copyStringValue(of: element, attribute: kAXSubroleAttribute as CFString)
        let label = firstNonEmpty(
            copyStringValue(of: element, attribute: kAXTitleAttribute as CFString),
            copyStringValue(of: element, attribute: kAXDescriptionAttribute as CFString),
            copyStringValue(of: element, attribute: kAXHelpAttribute as CFString)
        )
        let value = stringValue(
            from: copyAttributeValue(of: element, attribute: kAXValueAttribute as CFString)
        )

        if role == nil,
           subrole == nil,
           label == nil,
           value == nil,
           children.isEmpty {
            return nil
        }

        return HarnessArtifactReport.AccessibilityNode(
            typeName: "AXUIElement",
            role: role,
            subrole: subrole,
            label: label,
            value: value,
            children: children
        )
    }

    private static func accessibilitySummary(
        from root: HarnessArtifactReport.AccessibilityNode
    ) -> HarnessArtifactReport.AccessibilitySummary {
        var labels = Set<String>()
        var buttonLabels = Set<String>()
        var textValues = Set<String>()

        collectAccessibilityStrings(
            from: root,
            labels: &labels,
            buttonLabels: &buttonLabels,
            textValues: &textValues
        )

        return HarnessArtifactReport.AccessibilitySummary(
            labels: labels.sorted(),
            buttonLabels: buttonLabels.sorted(),
            textValues: textValues.sorted()
        )
    }

    private static func collectAccessibilityStrings(
        from node: HarnessArtifactReport.AccessibilityNode,
        labels: inout Set<String>,
        buttonLabels: inout Set<String>,
        textValues: inout Set<String>
    ) {
        if let label = trimmedString(node.label) {
            labels.insert(label)
            if node.role?.localizedCaseInsensitiveContains("button") == true {
                buttonLabels.insert(label)
            }
        }

        if let value = trimmedString(node.value) {
            textValues.insert(value)
        }

        for child in node.children {
            collectAccessibilityStrings(
                from: child,
                labels: &labels,
                buttonLabels: &buttonLabels,
                textValues: &textValues
            )
        }
    }

    private static func trimmedString(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringValue(from rawValue: Any?) -> String? {
        switch rawValue {
        case let string as String:
            return trimmedString(string)
        case let attributed as NSAttributedString:
            return trimmedString(attributed.string)
        case let number as NSNumber:
            return number.stringValue
        case let value?:
            return trimmedString(String(describing: value))
        case nil:
            return nil
        }
    }

    private static func selectorStringValue(_ selectorName: String, on object: NSObject) -> String? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else {
            return nil
        }

        return stringValue(from: object.perform(selector)?.takeUnretainedValue())
    }

    private static func selectorArrayValue(_ selectorName: String, on object: NSObject) -> [Any]? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else {
            return nil
        }

        return object.perform(selector)?.takeUnretainedValue() as? [Any]
    }

    private static func copyAttributeValue(
        of element: AXUIElement,
        attribute: CFString
    ) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }

        return value
    }

    private static func copyStringValue(
        of element: AXUIElement,
        attribute: CFString
    ) -> String? {
        stringValue(from: copyAttributeValue(of: element, attribute: attribute))
    }

    private static func copyAXElementArrayValue(
        of element: AXUIElement,
        attribute: CFString
    ) -> [AXUIElement]? {
        copyAttributeValue(of: element, attribute: attribute) as? [AXUIElement]
    }

    private static func axFrame(for element: AXUIElement) -> NSRect? {
        guard let positionRef = copyAttributeValue(
            of: element,
            attribute: kAXPositionAttribute as CFString
        ),
        let sizeRef = copyAttributeValue(
            of: element,
            attribute: kAXSizeAttribute as CFString
        ),
        CFGetTypeID(positionRef) == AXValueGetTypeID(),
        CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }

        let positionValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(positionValue) == .cgPoint,
              AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetType(sizeValue) == .cgSize,
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }

        return NSRect(origin: position, size: size)
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.first(where: { value in
            guard let value else {
                return false
            }
            return value.isEmpty == false
        }) ?? nil
    }
}
