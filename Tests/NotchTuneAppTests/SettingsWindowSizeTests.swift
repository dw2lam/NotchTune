import AppKit
import SwiftUI
import Testing
@testable import NotchTuneApp

@MainActor
struct SettingsWindowSizeTests {
    /// The size each pane makes the Settings content ask for. The window uses
    /// `.windowResizability(.contentSize)`, so a pane that asks for more
    /// resizes (and shifts) the window when you switch to it.
    private func measure() async -> [(SettingsTab, min: CGSize, ideal: CGSize)] {
        let model = AppModel()
        let controller = NSHostingController(rootView: SettingsView(model: model))
        controller.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 860, height: 640),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.contentViewController = controller
        var results: [(SettingsTab, min: CGSize, ideal: CGSize)] = []
        for tab in SettingsTab.allCases {
            NotificationCenter.default.post(name: .notchTuneSelectSettingsTab, object: tab.rawValue)
            try? await Task.sleep(for: .milliseconds(150))
            controller.view.layoutSubtreeIfNeeded()
            let min = controller.sizeThatFits(in: CGSize(width: 1, height: 1))
            let ideal = controller.view.fittingSize
            results.append((tab, min, ideal))
        }
        window.close()
        return results
    }

    @Test
    func everyPaneAsksForTheSameWindowSize() async {
        let results = await measure()
        let first = results[0]
        for r in results.dropFirst() {
            #expect(r.min.width == first.min.width, "\(r.0.rawValue) min width \(r.min.width) ≠ \(first.min.width)")
            #expect(r.ideal.width == first.ideal.width, "\(r.0.rawValue) ideal width \(r.ideal.width) ≠ \(first.ideal.width)")
        }
    }

    @Test
    func thePaneColumnSitsWhereThePaneWidthPutsItNotTheScrollView() {
        // Placed from the pane's outer width only, so a legacy scroll bar
        // (mouse attached, long panes only) can't move it: narrow panes
        // fill edge to edge, wide ones centre a capped column.
        let cap = SettingsMetrics.contentMaxWidth + SettingsMetrics.paneHorizontalPadding * 2
        #expect(SettingsMetrics.columnWidth(forPaneWidth: 600) == 600)
        #expect(SettingsMetrics.columnLeadingInset(forPaneWidth: 600) == 0)
        #expect(SettingsMetrics.columnWidth(forPaneWidth: 1000) == cap)
        #expect(SettingsMetrics.columnLeadingInset(forPaneWidth: 1000) == (1000 - cap) / 2)
    }
}
