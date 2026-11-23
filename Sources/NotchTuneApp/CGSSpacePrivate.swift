import CoreGraphics
import Foundation

// Private CoreGraphics Spaces APIs (SPI). Stable across recent macOS releases;
// used by space utilities such as WhichSpace, Spaceman, and alt-tab-macos.

typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: CGSConnectionID) -> CFArray

@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ connection: CGSConnectionID, _ mask: Int32, _ windowIDs: CFArray) -> CFArray?

@_silgen_name("CGSAddWindowsToSpaces")
func CGSAddWindowsToSpaces(_ connection: CGSConnectionID, _ windowIDs: CFArray, _ spaceIDs: CFArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
func CGSRemoveWindowsFromSpaces(_ connection: CGSConnectionID, _ windowIDs: CFArray, _ spaceIDs: CFArray)

@_silgen_name("CGSSpaceCreate")
func CGSSpaceCreate(_ connection: CGSConnectionID, _ flag: Int32, _ options: CFDictionary?) -> UInt64

@_silgen_name("CGSSpaceSetAbsoluteLevel")
func CGSSpaceSetAbsoluteLevel(_ connection: CGSConnectionID, _ space: UInt64, _ level: Int32)

@_silgen_name("CGSShowSpaces")
func CGSShowSpaces(_ connection: CGSConnectionID, _ spaceIDs: CFArray)

enum ManagedSpaceType: Int {
    case user = 0
    case fullscreenLegacy = 1
    case system = 2
    case fullscreen = 4
    case tiled = 5

    var isFullscreen: Bool {
        switch self {
        case .fullscreen, .fullscreenLegacy:
            return true
        case .user, .system, .tiled:
            return false
        }
    }
}

enum CGSSpaceQuery {
    static func currentSpaceType(on displayUUID: String?) -> ManagedSpaceType? {
        let connection = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            return nil
        }

        if let displayUUID,
           let display = displays.first(where: { ($0["Display Identifier"] as? String) == displayUUID }),
           let current = display["Current Space"] as? [String: Any],
           let rawType = current["type"] as? Int,
           let type = ManagedSpaceType(rawValue: rawType) {
            return type
        }

        // Single-display fallback when UUID matching fails.
        if displays.count == 1,
           let current = displays[0]["Current Space"] as? [String: Any],
           let rawType = current["type"] as? Int,
           let type = ManagedSpaceType(rawValue: rawType) {
            return type
        }

        return nil
    }
}

// MARK: - Window membership

extension CGSSpaceQuery {
    /// Current, other and user Spaces: every Space the window is on.
    private static let allSpacesMask: Int32 = 0x7

    /// Every Space on one display, fullscreen ones included: what a fresh
    /// `.canJoinAllSpaces` window is on.
    static func spaceIDs(on displayUUID: String?) -> [Int] {
        guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] else {
            return []
        }
        let display = displays.first { ($0["Display Identifier"] as? String) == displayUUID }
            ?? (displays.count == 1 ? displays[0] : nil)
        let spaces = display?["Spaces"] as? [[String: Any]] ?? []
        return spaces.compactMap { $0["ManagedSpaceID"] as? Int }
    }

    static func spaceIDs(forWindow windowNumber: Int) -> Set<Int> {
        let ids = CGSCopySpacesForWindows(CGSMainConnectionID(), allSpacesMask, [windowNumber] as CFArray)
        return Set(ids as? [Int] ?? [])
    }

    static func addWindow(_ windowNumber: Int, toSpaces spaceIDs: [Int]) {
        CGSAddWindowsToSpaces(CGSMainConnectionID(), [windowNumber] as CFArray, spaceIDs as CFArray)
    }

    /// The display's Spaces a `.canJoinAllSpaces` window has been dropped
    /// from. Empty when either list is unknown: an SPI failure must not
    /// re-add the window on every check.
    nonisolated static func missingSpaces(windowSpaces: Set<Int>, displaySpaces: [Int]) -> [Int] {
        guard !windowSpaces.isEmpty else { return [] }
        return displaySpaces.filter { !windowSpaces.contains($0) }
    }
}

// MARK: - Notch layer

/// A private Space above every desktop, owned by this process (the window
/// server drops it when the app quits). A window in it isn't on any desktop:
/// swiping between desktops, Mission Control edits and fullscreen apps can't
/// slide it, strand it on one desktop, or drop it from the others.
///
/// Off by default: while the layer is shown, the Dock never gets the
/// trackpad's desktop-swipe gesture, so three- and four-finger swipes stop
/// switching desktops (#10). Opt in with `overlay.desktopLayer.private`.
enum NotchWindowLayer {
    /// Just above the desktops. Kept low on purpose: the notch hides while
    /// the screen is locked as well (`OverlayUICoordinator`), so agent
    /// sessions never show on the lock screen.
    private static let absoluteLevel: Int32 = 1
    static let defaultsKey = "overlay.desktopLayer.private"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? false
    }

    private static let space: UInt64? = {
        let connection = CGSMainConnectionID()
        let space = CGSSpaceCreate(connection, 0x1, nil)
        guard space != 0 else { return nil }
        CGSSpaceSetAbsoluteLevel(connection, space, absoluteLevel)
        CGSShowSpaces(connection, [space] as CFArray)
        return space
    }()

    /// Moves the window into the layer, out of every desktop. False when the
    /// layer is off or couldn't be made: the window stays on the desktops.
    @discardableResult
    static func attach(windowNumber: Int) -> Bool {
        guard isEnabled, windowNumber > 0, let space else { return false }
        let connection = CGSMainConnectionID()
        CGSAddWindowsToSpaces(connection, [windowNumber] as CFArray, [space] as CFArray)
        let desktops = Array(CGSSpaceQuery.spaceIDs(forWindow: windowNumber))
        if !desktops.isEmpty {
            CGSRemoveWindowsFromSpaces(connection, [windowNumber] as CFArray, desktops as CFArray)
        }
        return true
    }
}
