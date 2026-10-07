import AppKit
import Combine
import SwiftUI

/// Harness-only stand-ins for the Music tab, so captures are deterministic and
/// never talk to the real Music / Spotify (no Apple Events, no launches, no
/// sound, no writes to the real library cache).
///
/// Active only for harness runs (`NOTCHTUNE_HARNESS_SCENARIO`) that set at
/// least one of:
/// - `NOTCHTUNE_HARNESS_MUSIC_PLAYER=appleMusic|spotify` (default: the
///   player selected in Settings, else Apple Music)
/// - `NOTCHTUNE_HARNESS_MUSIC_STATE=closed|idle|playing|noart`
///   (closed = app not running, idle = running with nothing loaded,
///   noart = playing a track without artwork; default closed)
/// - `NOTCHTUNE_HARNESS_SAMPLE_LIBRARY=1` (fake playlists / songs / pins)
/// - `NOTCHTUNE_HARNESS_MUSIC_SECTION=collections|songs`
/// - `NOTCHTUNE_HARNESS_MUSIC_QUERY=<text>` (opens the search field)
struct MusicHarnessOverride: Equatable, Sendable {
    enum PlaybackState: String, Sendable {
        case closed
        case idle
        case playing
        case noArt = "noart"
    }

    var player: MusicPlayerKind
    var state: PlaybackState
    var seedsSampleLibrary: Bool
    var section: MusicLibraryBrowser.Section?
    var query: String?

    static let current = MusicHarnessOverride(environment: ProcessInfo.processInfo.environment)

    init?(environment: [String: String], defaults: UserDefaults = .standard) {
        guard environment["NOTCHTUNE_HARNESS_SCENARIO"] != nil else { return nil }
        let keys = [
            "NOTCHTUNE_HARNESS_MUSIC_PLAYER",
            "NOTCHTUNE_HARNESS_MUSIC_STATE",
            "NOTCHTUNE_HARNESS_SAMPLE_LIBRARY",
            "NOTCHTUNE_HARNESS_MUSIC_SECTION",
            "NOTCHTUNE_HARNESS_MUSIC_QUERY",
        ]
        guard keys.contains(where: { environment[$0] != nil }) else { return nil }

        player = environment["NOTCHTUNE_HARNESS_MUSIC_PLAYER"].flatMap(Self.playerValue)
            ?? MusicPlayerKind.selected(in: defaults)
            ?? .appleMusic
        state = environment["NOTCHTUNE_HARNESS_MUSIC_STATE"]
            .flatMap { PlaybackState(rawValue: $0.lowercased()) } ?? .closed
        seedsSampleLibrary = ["1", "true", "yes", "on"].contains(
            environment["NOTCHTUNE_HARNESS_SAMPLE_LIBRARY"]?.lowercased() ?? ""
        )
        section = environment["NOTCHTUNE_HARNESS_MUSIC_SECTION"]
            .flatMap { MusicLibraryBrowser.Section(rawValue: $0.lowercased()) }
        query = environment["NOTCHTUNE_HARNESS_MUSIC_QUERY"]
    }

    private static func playerValue(_ raw: String) -> MusicPlayerKind? {
        switch raw.lowercased() {
        case "applemusic", "apple", "music": .appleMusic
        case "spotify": .spotify
        default: nil
        }
    }

    var isPlayerRunning: Bool { state != .closed }

    /// What the in-memory library store starts with.
    var seedArchive: MusicLibraryArchive {
        guard seedsSampleLibrary else { return MusicLibraryArchive() }
        return MusicLibraryArchive(
            appleMusic: player == .appleMusic ? MusicHarnessSamples.appleMusicLibrary : nil,
            spotifyPins: player == .spotify ? MusicHarnessSamples.spotifyPins : [],
            spotifyHistory: player == .spotify ? MusicHarnessSamples.spotifyHistory : []
        )
    }

    static let sampleTrack: PlayerTrack = {
        var track = PlayerTrack()
        track.title = "Midnight City"
        track.artist = "M83"
        track.album = "Hurry Up, We're Dreaming"
        track.duration = 243
        return track
    }()
}

/// Fake `MusicPlayerProtocol` for harness runs.
final class MusicHarnessPlayer: MusicPlayerProtocol {
    var notificationSubject: PassthroughSubject<MusicAlertItem, Never>
    let override: MusicHarnessOverride

    init(override: MusicHarnessOverride, notificationSubject: PassthroughSubject<MusicAlertItem, Never>) {
        self.override = override
        self.notificationSubject = notificationSubject
    }

    var appName: String { override.player.displayName }
    var appPath: URL { override.player.appURL ?? override.player.fallbackAppURL }
    var appNotification: String { "" }
    var bundleId: String { override.player.bundleID }
    var defaultAlbumArt: NSImage { NSImage() }

    var playerPosition: Double? { override.state == .playing || override.state == .noArt ? 81 : nil }
    var isPlaying: Bool { override.state == .playing || override.state == .noArt }
    var volume: CGFloat { 50 }
    var isLikeAuthorized: Bool { false }
    var shuffleIsOn: Bool { false }
    var shuffleContextEnabled: Bool { true }
    var repeatContextEnabled: Bool { true }
    var playbackSeekerEnabled: Bool { true }

    func getTrackInfo() -> PlayerTrack {
        switch override.state {
        case .closed, .idle: PlayerTrack()
        case .playing, .noArt: MusicHarnessOverride.sampleTrack
        }
    }

    func getAlbumArt(completion: @escaping @Sendable (MusicFetchedAlbumArt?) -> Void) {
        guard override.state == .playing else {
            completion(nil)
            return
        }
        let image = MusicHarnessSamples.albumArt()
        completion(MusicFetchedAlbumArt(image: Image(nsImage: image), nsImage: image))
    }

    func playPause() {}
    func previousTrack() {}
    func nextTrack() {}
    func toggleLoveTrack() -> Bool { false }
    func setShuffle(shuffleIsOn: Bool) -> Bool { shuffleIsOn }
    func setRepeat(repeatIsOn: Bool) -> Bool { repeatIsOn }
    func getCurrentSeekerPosition() -> Double { playerPosition ?? 0 }
    func seekTrack(seekerPosition: CGFloat) {}
    func setVolume(volume: Int) {}
    func isRunning() -> Bool { override.isPlayerRunning }
}

/// Fake library backend for harness runs: sample content, generated covers,
/// and a `play` that does nothing.
final class MusicHarnessLibraryBackend: MusicLibraryBackend, @unchecked Sendable {
    let kind: MusicPlayerKind
    let override: MusicHarnessOverride

    init(kind: MusicPlayerKind, override: MusicHarnessOverride) {
        self.kind = kind
        self.override = override
    }

    var canReadLibrary: Bool { kind == .appleMusic }

    func isPlayerRunning() -> Bool { override.isPlayerRunning }

    func fetchLibrary() async -> MusicLibrarySnapshot? {
        guard canReadLibrary, isPlayerRunning() else { return nil }
        guard override.seedsSampleLibrary else { return .empty }
        var snapshot = MusicHarnessSamples.appleMusicLibrary
        snapshot.fetchedAt = .now
        return snapshot
    }

    func searchLibrary(_ query: String) async -> [MusicLibraryItem]? {
        guard canReadLibrary, isPlayerRunning(), override.seedsSampleLibrary else { return nil }
        return MusicHarnessSamples.appleMusicLibrary.songs.filter { $0.matches(query) }
    }

    func artworkData(for item: MusicLibraryItem) async -> Data? {
        MusicHarnessSamples.coverPNG(seed: item.id)
    }

    func play(_ item: MusicLibraryItem) async -> Bool {
        try? await Task.sleep(for: .milliseconds(300))
        return true
    }
}

enum MusicHarnessSamples {
    static let appleMusicLibrary = MusicLibrarySnapshot(
        playlists: [
            MusicLibraryItem(id: "A1", kind: .playlist, title: "Late Night Drive", subtitle: "Playlist · 2 hr 14 min"),
            MusicLibraryItem(id: "A2", kind: .playlist, title: "Deep Focus", subtitle: "Playlist · 3 hr 2 min"),
            MusicLibraryItem(id: "A3", kind: .playlist, title: "Sunday Morning", subtitle: "Playlist · 1 hr 38 min"),
            MusicLibraryItem(id: "A4", kind: .playlist, title: "Gym Rotation", subtitle: "Playlist · 1 hr 5 min"),
            MusicLibraryItem(id: "A5", kind: .playlist, title: "Road Trip '26", subtitle: "Playlist · 4 hr 20 min"),
            MusicLibraryItem(id: "A6", kind: .playlist, title: "Chill Mix", subtitle: "Apple Music Playlist"),
            MusicLibraryItem(id: "A7", kind: .smartPlaylist, title: "Recently Added", subtitle: "Smart Playlist · 6 hr"),
            MusicLibraryItem(id: "A8", kind: .smartPlaylist, title: "Top 25 Most Played", subtitle: "Smart Playlist · 1 hr 41 min"),
        ],
        songs: [
            MusicLibraryItem(id: "S1", kind: .song, title: "Midnight City", subtitle: "M83"),
            MusicLibraryItem(id: "S2", kind: .song, title: "Nights", subtitle: "Frank Ocean"),
            MusicLibraryItem(id: "S3", kind: .song, title: "Redbone", subtitle: "Childish Gambino"),
            MusicLibraryItem(id: "S4", kind: .song, title: "Dreams", subtitle: "Fleetwood Mac"),
            MusicLibraryItem(id: "S5", kind: .song, title: "Electric Feel", subtitle: "MGMT"),
            MusicLibraryItem(id: "S6", kind: .song, title: "Let It Happen", subtitle: "Tame Impala"),
            MusicLibraryItem(id: "S7", kind: .song, title: "Pink + White", subtitle: "Frank Ocean"),
            MusicLibraryItem(id: "S8", kind: .song, title: "Night Owl", subtitle: "Galimatias"),
        ],
        fetchedAt: Date(timeIntervalSince1970: 1_790_000_000)
    )

    static let spotifyPins: [MusicLibraryItem] = [
        MusicLibraryItem(id: "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M", kind: .playlist, title: "Today's Top Hits", subtitle: "Playlist"),
        MusicLibraryItem(id: "spotify:playlist:37i9dQZF1DWWQRwui0ExPn", kind: .playlist, title: "lofi beats", subtitle: "Playlist"),
        MusicLibraryItem(id: "spotify:album:79dL7FLiJFOO0EoehUHQBv", kind: .album, title: "Currents", subtitle: "Album"),
        MusicLibraryItem(id: "spotify:artist:4tZwfgrHOc3mvqYlEYSvVi", kind: .artist, title: "Daft Punk", subtitle: "Artist"),
        MusicLibraryItem(id: "spotify:playlist:37i9dQZEVXcJZyENOWUFo7", kind: .playlist, title: "Discover Weekly", subtitle: "Playlist"),
    ]

    static let spotifyHistory: [MusicLibraryItem] = [
        MusicLibraryItem(id: "spotify:track:6GyFP1nfCDB8lbD2bG0Hq9", kind: .song, title: "Midnight City", subtitle: "M83"),
        MusicLibraryItem(id: "spotify:track:2LlQb7Uoj1kKyGhlkBf9aC", kind: .song, title: "Let It Happen", subtitle: "Tame Impala"),
        MusicLibraryItem(id: "spotify:track:7eJMfftS33KTjuF7lTsMCx", kind: .song, title: "Nights", subtitle: "Frank Ocean"),
        MusicLibraryItem(id: "spotify:track:0wXuerDYiBnERgIpbb3JBR", kind: .song, title: "Redbone", subtitle: "Childish Gambino"),
        MusicLibraryItem(id: "spotify:track:0ofHAoxe9vBkTCp2UQIavz", kind: .song, title: "Dreams", subtitle: "Fleetwood Mac"),
        MusicLibraryItem(id: "spotify:track:3FtYbEfBqAlGO46NUDQSAt", kind: .song, title: "Electric Feel", subtitle: "MGMT"),
    ]

    /// Same strongly coloured square as `AppModel.harnessSampleAlbumArt`.
    static func albumArt() -> NSImage {
        NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
            let gradient = NSGradient(colors: [.systemPink, .systemOrange, .systemTeal])
            gradient?.draw(in: rect, angle: 90)
            return true
        }
    }

    /// A deterministic two-tone gradient cover per id.
    static func coverPNG(seed: String) -> Data? {
        let hash = seed.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
        let hue = CGFloat((hash >> 29) % 997) / 997
        let top = NSColor(hue: hue, saturation: 0.62, brightness: 0.86, alpha: 1)
        let bottom = NSColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.45, alpha: 1)
        let side = 96
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [top.cgColor, bottom.cgColor] as CFArray,
            locations: [0, 1]
        ) else { return nil }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: CGFloat(side)),
            end: CGPoint(x: CGFloat(side), y: 0),
            options: []
        )
        guard let image = context.makeImage() else { return nil }
        return MusicArtworkRendering.thumbnailPNG(from: image)
    }
}
