import AppKit
import SwiftUI
import Foundation

struct HarnessLaunchConfiguration {
    let scenario: IslandDebugScenario?
    let presentOverlay: Bool
    let shouldStartBridge: Bool
    let shouldPerformBootAnimation: Bool
    let captureDelay: TimeInterval?
    let autoExitAfter: TimeInterval?
    let artifactDirectoryURL: URL?
    /// Pins the closed-island density for this run without touching the
    /// persisted preference (`NOTCHTUNE_HARNESS_ISLAND_DENSITY=regular|compact`).
    let islandDensity: IslandDensity?
    /// Seeds sample Claude + Codex usage so the header usage cycler renders
    /// (`NOTCHTUNE_HARNESS_SAMPLE_USAGE=1`).
    let seedsSampleUsage: Bool
    /// Opens on this tab (`NOTCHTUNE_HARNESS_TAB=agents|music|myspace|reminders`).
    let tab: IslandTab?
    /// Paints a sample album cover behind the Music tab so captures show the
    /// album-art tint without a real player (`NOTCHTUNE_HARNESS_SAMPLE_TRACK=1`).
    let seedsSampleTrack: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        scenario = Self.scenarioValue(from: environment["NOTCHTUNE_HARNESS_SCENARIO"])
        islandDensity = Self.densityValue(from: environment["NOTCHTUNE_HARNESS_ISLAND_DENSITY"])
        tab = environment["NOTCHTUNE_HARNESS_TAB"].flatMap { IslandTab(rawValue: $0.lowercased()) }
        seedsSampleTrack = Self.boolValue(
            environment["NOTCHTUNE_HARNESS_SAMPLE_TRACK"],
            default: false
        )
        seedsSampleUsage = Self.boolValue(
            environment["NOTCHTUNE_HARNESS_SAMPLE_USAGE"],
            default: false
        )
        presentOverlay = Self.boolValue(
            environment["NOTCHTUNE_HARNESS_PRESENT_OVERLAY"],
            default: false
        )
        shouldStartBridge = Self.boolValue(
            environment["NOTCHTUNE_HARNESS_START_BRIDGE"],
            default: true
        )
        shouldPerformBootAnimation = Self.boolValue(
            environment["NOTCHTUNE_HARNESS_BOOT_ANIMATION"],
            default: true
        )
        captureDelay = Self.timeIntervalValue(
            from: environment["NOTCHTUNE_HARNESS_CAPTURE_DELAY_SECONDS"]
        )
        autoExitAfter = Self.timeIntervalValue(
            from: environment["NOTCHTUNE_HARNESS_AUTO_EXIT_SECONDS"]
        )
        artifactDirectoryURL = Self.directoryURLValue(
            from: environment["NOTCHTUNE_HARNESS_ARTIFACT_DIR"]
        )
    }

    private static func scenarioValue(from rawValue: String?) -> IslandDebugScenario? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        return IslandDebugScenario.allCases.first { scenario in
            scenario.rawValue.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    private static func densityValue(from rawValue: String?) -> IslandDensity? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        return IslandDensity.allCases.first { density in
            density.rawValue.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    private static func boolValue(_ rawValue: String?, default defaultValue: Bool) -> Bool {
        guard let rawValue else {
            return defaultValue
        }

        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return defaultValue
        }

        return switch normalized {
        case "1", "true", "yes", "on":
            true
        case "0", "false", "no", "off":
            false
        default:
            defaultValue
        }
    }

    private static func timeIntervalValue(from rawValue: String?) -> TimeInterval? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = TimeInterval(normalized),
              seconds > 0 else {
            return nil
        }

        return seconds
    }

    private static func directoryURLValue(from rawValue: String?) -> URL? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: normalized, isDirectory: true)
    }
}

/// Harness runs must not disturb the person using the Mac: every window is
/// placed far off-screen and the app never activates or takes focus. The
/// recorder still captures the windows (the window server renders them
/// wherever they sit).
enum HarnessHeadless {
    static let isActive: Bool = {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NOTCHTUNE_HARNESS_ONSCREEN"] != "1" else { return false }
        // Harness scenarios, and unit tests that create a real overlay panel
        // (`notchOpen` in AppModel tests) — neither may put windows on screen.
        return environment["NOTCHTUNE_HARNESS_SCENARIO"] != nil || isRunningTests
    }()

    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName.hasSuffix("xctest")
    }

    /// Marketing captures (`NOTCHTUNE_HARNESS_SHOWCASE=1`): clean sessions,
    /// no "install hooks" banner.
    static let isShowcase: Bool = ProcessInfo.processInfo.environment["NOTCHTUNE_HARNESS_SHOWCASE"] == "1"

    /// Horizontal shift that parks harness windows beyond every display.
    static let offscreenOffsetX: CGFloat = 60_000

    /// Hides every non-overlay window (Settings, onboarding) from the user:
    /// titled windows can't live off-screen (AppKit pulls them back onto a
    /// display), so they drop BELOW the desktop instead and ignore the mouse.
    /// A single-window capture still renders them in full.
    @MainActor
    static func parkAppWindows() {
        guard isActive else { return }
        let belowDesktop = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        for window in NSApp.windows where !(window is NSPanel) && window.level != belowDesktop {
            window.animationBehavior = .none
            window.level = belowDesktop
            window.ignoresMouseEvents = true
            // SwiftUI scene windows (the Settings scene auto-opens at launch)
            // are closed outright; the harness's own hidden windows stay.
            if hostedWindowIDs.contains(window.identifier?.rawValue ?? "") {
                window.orderBack(nil)
            } else {
                window.orderOut(nil)
            }
        }
    }

    /// Identifiers of the windows `openHiddenWindow` creates.
    static let hostedWindowIDs: Set<String> = ["settings", "onboarding"]

    /// Opens `rootView` in a titled window created BELOW the desktop (never
    /// visible, never key), for the recorder to capture.
    @MainActor
    @discardableResult
    static func openHiddenWindow<Content: View>(id: String, title: String, size: NSSize, rootView: Content) -> NSWindow {
        let controller = NSHostingController(rootView: rootView)
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.contentViewController = controller
        window.setContentSize(size)
        window.center()
        window.orderBack(nil)
        return window
    }
}
