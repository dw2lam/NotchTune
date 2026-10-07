import AppKit
import CoreGraphics
import ScriptingBridge
import ImageIO
import UniformTypeIdentifiers

/// Per-player access to "things to play" for the empty Music tab.
///
/// Contract: nothing here may launch the player as a side effect. Reads only
/// ever talk to an already-running player (addressed by pid, so a stale
/// reference can't relaunch it). Only `play(_:)`, an explicit user action,
/// may start the app.
protocol MusicLibraryBackend: AnyObject, Sendable {
    var kind: MusicPlayerKind { get }
    /// Whether the player's library can be read (Apple Music yes, Spotify no:
    /// its AppleScript dictionary can play a URI but can't list anything).
    var canReadLibrary: Bool { get }
    /// Process check only (no Apple Events).
    func isPlayerRunning() -> Bool
    /// Playlists + recent songs; `nil` when the player isn't running.
    func fetchLibrary() async -> MusicLibrarySnapshot?
    /// Library search; `nil` when the player isn't running or can't search.
    func searchLibrary(_ query: String) async -> [MusicLibraryItem]?
    /// Small PNG artwork for `item`; `nil` when unavailable or not running.
    func artworkData(for item: MusicLibraryItem) async -> Data?
    /// Explicit user action: launch the player in the background if needed,
    /// then start `item`. Returns whether the play command was delivered.
    func play(_ item: MusicLibraryItem) async -> Bool
}

// MARK: - Process helpers

enum MusicPlayerProcess {
    static func runningPID(bundleID: String) -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { !$0.isTerminated }?
            .processIdentifier
    }

    static func isRunning(bundleID: String) -> Bool {
        runningPID(bundleID: bundleID) != nil
    }

    /// Starts the player hidden and without taking focus (the user asked to
    /// play something from the notch, not to switch apps). Resolves to the
    /// pid once the app has finished launching, `nil` on failure/timeout.
    static func launchInBackground(_ kind: MusicPlayerKind, timeout: TimeInterval = 20) async -> pid_t? {
        if let pid = runningPID(bundleID: kind.bundleID) { return pid }
        guard let url = kind.appURL else { return nil }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        guard let app = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration) else {
            return nil
        }
        let pid = app.processIdentifier
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if let running = NSRunningApplication(processIdentifier: pid), running.isFinishedLaunching {
                return pid
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return nil
    }

    /// Opens the full app in front (the "Open Apple Music" affordance).
    @MainActor
    static func openApp(_ kind: MusicPlayerKind) {
        guard let url = kind.appURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

// MARK: - Scripting errors

/// Swallows failed Apple Events (no current track, a pid that just quit, a
/// library still loading…) so they come back as `nil` instead of ever
/// surfacing as an Objective-C exception on the scripting queue.
final class MusicScriptingErrorSink: NSObject, SBApplicationDelegate, @unchecked Sendable {
    static let shared = MusicScriptingErrorSink()

    func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: any Error) -> Any? {
        nil
    }
}

extension SBApplication {
    /// A scripting handle on an ALREADY-RUNNING process. Addressing by pid
    /// means a later event can't relaunch the app if it quits meanwhile.
    static func runningInstance(pid: pid_t, timeoutSeconds: Int = 15) -> SBApplication? {
        guard let app = SBApplication(processIdentifier: pid) else { return nil }
        app.delegate = MusicScriptingErrorSink.shared
        app.timeout = timeoutSeconds * 60 // ticks
        return app
    }
}

// MARK: - Artwork helpers

enum MusicArtworkRendering {
    /// Downscales `image` to a `side`-pixel square PNG (aspect-fill). Uses
    /// CoreGraphics only, so it's safe off the main thread.
    static func thumbnailPNG(from image: NSImage, side: Int = 96) -> Data? {
        guard image.isKind(of: NSImage.self),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return thumbnailPNG(from: cgImage, side: side)
    }

    static func thumbnailPNG(from cgImage: CGImage, side: Int = 96) -> Data? {
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }
        let scale = max(CGFloat(side) / width, CGFloat(side) / height)
        let drawSize = CGSize(width: width * scale, height: height * scale)
        let origin = CGPoint(x: (CGFloat(side) - drawSize.width) / 2, y: (CGFloat(side) - drawSize.height) / 2)
        context.draw(cgImage, in: CGRect(origin: origin, size: drawSize))
        guard let thumbnail = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// Remote cover loader (Spotify artwork URLs), cached in memory.
actor MusicRemoteArtworkLoader {
    static let shared = MusicRemoteArtworkLoader()

    private var cache: [URL: Data] = [:]

    func data(for url: URL) async -> Data? {
        if let cached = cache[url] { return cached }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let thumbnail = MusicArtworkRendering.thumbnailPNG(from: image) else {
            return nil
        }
        if cache.count > 200 { cache.removeAll() }
        cache[url] = thumbnail
        return thumbnail
    }
}
