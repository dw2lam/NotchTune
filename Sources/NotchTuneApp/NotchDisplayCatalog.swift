import AppKit

/// Catalog of every notched-Mac chassis since the M1 Pro/Max redesign.
///
/// Runtime geometry (`safeAreaInsets`, `auxiliaryTopLeft/RightArea`) is always
/// authoritative — it tracks the user's scaled resolution exactly. This catalog
/// exists for the cases the runtime APIs can't cover:
///  1. a sane fallback when macOS reports a top safe-area inset but no
///     auxiliary areas (otherwise the "notch" degenerates to the full screen),
///  2. answering "does this model have a notch" from the model identifier,
///  3. documentation + tests for the supported notch fleet.
///
/// Notched chassis map (built-in panel, native px → default scaled pt):
/// ┌───────────────────────────────┬───────────────┬─────────────┬────────────┐
/// │ Chassis                       │ Native px     │ Default pt  │ Model IDs  │
/// ├───────────────────────────────┼───────────────┼─────────────┼────────────┤
/// │ MacBook Pro 14" (M1 Pro/Max)  │ 3024×1964     │ 1512×982    │ MacBookPro18,3 18,4 │
/// │ MacBook Pro 16" (M1 Pro/Max)  │ 3456×2234     │ 1728×1117   │ MacBookPro18,1 18,2 │
/// │ MacBook Air 13.6" (M2)        │ 2560×1664     │ 1280×832    │ Mac14,2    │
/// │ MacBook Pro 14" (M2 Pro/Max)  │ 3024×1964     │ 1512×982    │ Mac14,5 14,9 │
/// │ MacBook Pro 16" (M2 Pro/Max)  │ 3456×2234     │ 1728×1117   │ Mac14,6 14,10 │
/// │ MacBook Air 15.3" (M2)        │ 2880×1864     │ 1440×932    │ Mac14,15   │
/// │ MacBook Pro 14" (M3 family)   │ 3024×1964     │ 1512×982    │ Mac15,3 15,6 15,8 15,10 │
/// │ MacBook Pro 16" (M3 Pro/Max)  │ 3456×2234     │ 1728×1117   │ Mac15,7 15,9 15,11 │
/// │ MacBook Air 13.6" (M3)        │ 2560×1664     │ 1280×832    │ Mac15,12   │
/// │ MacBook Air 15.3" (M3)        │ 2880×1864     │ 1440×932    │ Mac15,13   │
/// │ MacBook Pro 14" (M4 family)   │ 3024×1964     │ 1512×982    │ Mac16,1 16,6 16,8 │
/// │ MacBook Pro 16" (M4 Pro/Max)  │ 3456×2234     │ 1728×1117   │ Mac16,5 16,7 │
/// │ MacBook Air 13.6" (M4)        │ 2560×1664     │ 1280×832    │ Mac16,12   │
/// │ MacBook Air 15.3" (M4)        │ 2880×1864     │ 1440×932    │ Mac16,13   │
/// │ MacBook Pro 14" (M5)          │ 3024×1964     │ 1512×982    │ Mac17,*    │
/// └───────────────────────────────┴───────────────┴─────────────┴────────────┘
/// Not notched: every pre-2021 chassis and the 13" Touch Bar Pros
/// (MacBookPro17,1 = 13" M1, Mac14,7 = 13" M2).
///
/// The camera housing is ~200pt wide at default scaling on every chassis;
/// in points it scales linearly with the chosen desktop width. Heights:
/// the menu-bar/notch strip is 32pt on Pros, 30pt on Airs (default scaling).
enum NotchDisplayCatalog {
    struct Chassis: Equatable, Sendable {
        let name: String
        let defaultPointWidth: CGFloat
        let defaultPointHeight: CGFloat
        let notchWidthAtDefault: CGFloat
        let notchHeightAtDefault: CGFloat
    }

    static let chassis: [Chassis] = [
        Chassis(name: "MacBook Pro 14\"", defaultPointWidth: 1512, defaultPointHeight: 982, notchWidthAtDefault: 200, notchHeightAtDefault: 32),
        Chassis(name: "MacBook Pro 16\"", defaultPointWidth: 1728, defaultPointHeight: 1117, notchWidthAtDefault: 200, notchHeightAtDefault: 32),
        Chassis(name: "MacBook Air 13.6\"", defaultPointWidth: 1280, defaultPointHeight: 832, notchWidthAtDefault: 195, notchHeightAtDefault: 30),
        Chassis(name: "MacBook Air 15.3\"", defaultPointWidth: 1440, defaultPointHeight: 932, notchWidthAtDefault: 195, notchHeightAtDefault: 30),
    ]

    /// Model-identifier prefixes that always ship a notched built-in display.
    /// Exact IDs are listed where a prefix family mixes notched and un-notched
    /// machines (Mac14,* and Mac15,* include desktops and the 13" Touch Bar Pro).
    static let notchedModelIdentifiers: Set<String> = [
        // 2021 14"/16"
        "MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4",
        // 2022–2023 M2 generation
        "Mac14,2", "Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10", "Mac14,15",
        // 2023–2024 M3 generation
        "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10",
        "Mac15,11", "Mac15,12", "Mac15,13",
        // 2024–2025 M4 generation
        "Mac16,1", "Mac16,5", "Mac16,6", "Mac16,7", "Mac16,8", "Mac16,12", "Mac16,13",
    ]

    /// Later generations (M5+) keep the notch on every MacBook chassis, so any
    /// future `Mac17,*`+ MacBook identifier is treated as notched.
    static func hasNotch(modelIdentifier: String) -> Bool {
        if notchedModelIdentifiers.contains(modelIdentifier) {
            return true
        }
        // Mac17,* onward: Apple has not shipped a notch-less MacBook since the
        // Touch Bar 13" retired; treat unknown future MacBook IDs as notched.
        if let family = modelIdentifier.split(separator: ",").first,
           family.hasPrefix("Mac"),
           let generation = Int(family.dropFirst(3)),
           generation >= 17 {
            return true
        }
        return false
    }

    /// The Mac's model identifier (e.g. "Mac16,1") via sysctl.
    static func currentModelIdentifier() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    /// Best-effort notch size for a screen when the runtime auxiliary areas are
    /// unavailable. Matches the chassis by aspect-compatible point width and
    /// scales the default-resolution notch linearly with the chosen desktop
    /// width (the physical cutout is fixed; its point size tracks scaling).
    static func estimatedNotchSize(forPointWidth pointWidth: CGFloat) -> CGSize {
        let match = chassis.min { lhs, rhs in
            abs(lhs.defaultPointWidth - pointWidth) < abs(rhs.defaultPointWidth - pointWidth)
        } ?? chassis[0]
        let scale = pointWidth / match.defaultPointWidth
        return CGSize(
            width: (match.notchWidthAtDefault * scale).rounded(),
            height: match.notchHeightAtDefault
        )
    }
}
