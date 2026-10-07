import AppKit
import Foundation
import Testing
@testable import NotchTuneApp

// MARK: - Fakes

/// Records every call; never touches a real player.
final class FakeMusicLibraryBackend: MusicLibraryBackend, @unchecked Sendable {
    let kind: MusicPlayerKind
    let canReadLibrary: Bool

    private let lock = NSLock()
    private var _running: Bool
    private var _snapshot: MusicLibrarySnapshot?
    private var _searchResults: [MusicLibraryItem]
    private var _fetchCount = 0
    private var _searchQueries: [String] = []
    private var _played: [MusicLibraryItem] = []
    private var _artworkRequests: [String] = []
    private var _playSucceeds = true
    private var _launchesOnPlay = true

    init(
        kind: MusicPlayerKind,
        running: Bool,
        snapshot: MusicLibrarySnapshot? = nil,
        searchResults: [MusicLibraryItem] = []
    ) {
        self.kind = kind
        canReadLibrary = kind == .appleMusic
        _running = running
        _snapshot = snapshot
        _searchResults = searchResults
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var running: Bool {
        get { locked { _running } }
        set { locked { _running = newValue } }
    }
    var playSucceeds: Bool {
        get { locked { _playSucceeds } }
        set { locked { _playSucceeds = newValue } }
    }
    var fetchCount: Int { locked { _fetchCount } }
    var searchQueries: [String] { locked { _searchQueries } }
    var played: [MusicLibraryItem] { locked { _played } }
    var artworkRequests: [String] { locked { _artworkRequests } }

    func isPlayerRunning() -> Bool { running }

    func fetchLibrary() async -> MusicLibrarySnapshot? {
        locked {
            guard _running, canReadLibrary else { return nil }
            _fetchCount += 1
            return _snapshot
        }
    }

    func searchLibrary(_ query: String) async -> [MusicLibraryItem]? {
        locked {
            guard _running, canReadLibrary else { return nil }
            _searchQueries.append(query)
            return _searchResults
        }
    }

    func artworkData(for item: MusicLibraryItem) async -> Data? {
        locked {
            _artworkRequests.append(item.id)
            guard _running else { return nil }
            return MusicHarnessSamples.coverPNG(seed: item.id)
        }
    }

    func play(_ item: MusicLibraryItem) async -> Bool {
        locked {
            _played.append(item)
            if _launchesOnPlay { _running = true }
            return _playSucceeds
        }
    }
}

struct FakeSpotifyResolver: SpotifyLinkMetadataResolving {
    var title: String
    var artworkURL: URL?

    func resolve(_ link: SpotifyLink.Parsed) async -> (title: String, artworkURL: URL?)? {
        (title, artworkURL)
    }
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private let samplePlaylists = [
    MusicLibraryItem(id: "P1", kind: .playlist, title: "Late Night Drive", subtitle: "Playlist"),
    MusicLibraryItem(id: "P2", kind: .smartPlaylist, title: "Recently Added", subtitle: "Smart Playlist"),
]
private let sampleSongs = [
    MusicLibraryItem(id: "S1", kind: .song, title: "Midnight City", subtitle: "M83"),
    MusicLibraryItem(id: "S2", kind: .song, title: "Nights", subtitle: "Frank Ocean"),
]

// MARK: - Browser

@MainActor
struct MusicLibraryBrowserTests {
    private func makeBrowser(
        player: MusicPlayerKind?,
        backend: FakeMusicLibraryBackend,
        archive: MusicLibraryArchive = MusicLibraryArchive(),
        resolver: (any SpotifyLinkMetadataResolving)? = nil
    ) -> MusicLibraryBrowser {
        let browser = MusicLibraryBrowser(
            player: player,
            store: MusicLibraryStore(fileURL: nil, seed: archive),
            metadataResolver: resolver,
            makeBackend: { _ in backend }
        )
        browser.searchDebounce = .zero
        return browser
    }

    @Test
    func renderingAClosedPlayerNeverReadsTheLibrary() async {
        let backend = FakeMusicLibraryBackend(
            kind: .appleMusic, running: false,
            snapshot: MusicLibrarySnapshot(playlists: samplePlaylists, songs: sampleSongs, fetchedAt: .now)
        )
        let browser = makeBrowser(player: .appleMusic, backend: backend)

        browser.activate()
        browser.refreshLibrary()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(backend.fetchCount == 0)
        #expect(!browser.isPlayerRunning)
        #expect(!browser.isLoadingLibrary)
        #expect(browser.collections.isEmpty)
    }

    @Test
    func closedPlayerStillOffersTheCachedLibrary() {
        let backend = FakeMusicLibraryBackend(kind: .appleMusic, running: false)
        let cached = MusicLibrarySnapshot(playlists: samplePlaylists, songs: sampleSongs, fetchedAt: .now)
        let browser = makeBrowser(player: .appleMusic, backend: backend, archive: MusicLibraryArchive(appleMusic: cached))

        browser.activate()

        #expect(browser.collections == samplePlaylists)
        #expect(browser.songs == sampleSongs)
        #expect(backend.fetchCount == 0)
    }

    @Test
    func runningPlayerWithStaleCacheIsReadOnceAndCached() async {
        let fresh = MusicLibrarySnapshot(playlists: samplePlaylists, songs: sampleSongs, fetchedAt: .now)
        let backend = FakeMusicLibraryBackend(kind: .appleMusic, running: true, snapshot: fresh)
        let store = MusicLibraryStore(fileURL: nil)
        let browser = MusicLibraryBrowser(
            player: .appleMusic, store: store, metadataResolver: nil, makeBackend: { _ in backend }
        )

        browser.activate()
        await waitUntil { !browser.isLoadingLibrary }

        #expect(backend.fetchCount == 1)
        #expect(browser.collections == samplePlaylists)
        #expect(store.archive.appleMusic == fresh)

        // Fresh cache: appearing again doesn't re-read.
        browser.activate()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(backend.fetchCount == 1)
    }

    @Test
    func playingFromAClosedPlayerGoesThroughTheBackendAndClearsPending() async {
        let backend = FakeMusicLibraryBackend(kind: .appleMusic, running: false, snapshot: .empty)
        let cached = MusicLibrarySnapshot(playlists: samplePlaylists, songs: [], fetchedAt: .now)
        let browser = makeBrowser(player: .appleMusic, backend: backend, archive: MusicLibraryArchive(appleMusic: cached))

        browser.play(samplePlaylists[0])
        #expect(browser.pendingItemID == "P1")
        // A second pick while the first is in flight is ignored.
        browser.play(samplePlaylists[1])
        await waitUntil { browser.pendingItemID == nil }

        #expect(backend.played.map(\.id) == ["P1"])
        #expect(browser.isPlayerRunning)
        #expect(browser.statusMessage == nil)
    }

    @Test
    func failedPlayFlashesAMessage() async {
        let backend = FakeMusicLibraryBackend(kind: .spotify, running: true)
        backend.playSucceeds = false
        let pin = MusicLibraryItem(id: "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M", kind: .playlist, title: "Hits", subtitle: "Playlist")
        let browser = makeBrowser(player: .spotify, backend: backend, archive: MusicLibraryArchive(spotifyPins: [pin]))

        browser.play(pin)
        await waitUntil { browser.pendingItemID == nil }

        #expect(browser.statusMessage?.contains("Hits") == true)
        #expect(browser.collections.first?.lastPlayedAt == nil)
    }

    @Test
    func playingASpotifyPinFloatsItToTheTop() async {
        let backend = FakeMusicLibraryBackend(kind: .spotify, running: true)
        let first = MusicLibraryItem(id: "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M", kind: .playlist, title: "A", subtitle: "Playlist")
        let second = MusicLibraryItem(id: "spotify:album:79dL7FLiJFOO0EoehUHQBv", kind: .album, title: "B", subtitle: "Album")
        let browser = makeBrowser(player: .spotify, backend: backend, archive: MusicLibraryArchive(spotifyPins: [first, second]))

        browser.play(second)
        await waitUntil { browser.pendingItemID == nil }

        #expect(browser.collections.map(\.id) == [second.id, first.id])
    }

    @Test
    func librarySearchGoesToTheRunningPlayer() async {
        let hit = MusicLibraryItem(id: "S9", kind: .song, title: "Night Owl", subtitle: "Galimatias")
        let backend = FakeMusicLibraryBackend(kind: .appleMusic, running: true, searchResults: [hit])
        let cached = MusicLibrarySnapshot(playlists: samplePlaylists, songs: sampleSongs, fetchedAt: .now)
        let browser = makeBrowser(player: .appleMusic, backend: backend, archive: MusicLibraryArchive(appleMusic: cached))

        browser.beginSearch()
        browser.updateQuery("night")
        await waitUntil { !browser.isSearchingLibrary }

        #expect(backend.searchQueries == ["night"])
        // Matching playlists first, then the library's own search results.
        #expect(browser.visibleItems.map(\.id) == ["P1", "S9"])
    }

    @Test
    func searchWhileClosedFiltersTheCacheWithoutTouchingThePlayer() {
        let backend = FakeMusicLibraryBackend(kind: .appleMusic, running: false)
        let cached = MusicLibrarySnapshot(playlists: samplePlaylists, songs: sampleSongs, fetchedAt: .now)
        let browser = makeBrowser(player: .appleMusic, backend: backend, archive: MusicLibraryArchive(appleMusic: cached))

        browser.beginSearch()
        browser.updateQuery("night")

        #expect(backend.searchQueries.isEmpty)
        #expect(!browser.isSearchingLibrary)
        #expect(browser.visibleItems.map(\.id) == ["P1", "S1", "S2"])

        browser.endSearch()
        #expect(!browser.isSearchActive)
        #expect(browser.visibleItems == samplePlaylists)
    }

    @Test
    func sectionsSwitchBetweenCollectionsAndSongs() {
        let backend = FakeMusicLibraryBackend(kind: .appleMusic, running: false)
        let cached = MusicLibrarySnapshot(playlists: samplePlaylists, songs: sampleSongs, fetchedAt: .now)
        let browser = makeBrowser(player: .appleMusic, backend: backend, archive: MusicLibraryArchive(appleMusic: cached))

        #expect(browser.visibleItems == samplePlaylists)
        browser.section = .songs
        #expect(browser.visibleItems == sampleSongs)
        #expect(MusicLibraryBrowser.Section.collections.title(for: .spotify) == "Pinned")
        #expect(MusicLibraryBrowser.Section.songs.title(for: .appleMusic) == "Songs")
    }

    @Test
    func spotifyHistoryRecordsObservedTracksOnly() {
        let backend = FakeMusicLibraryBackend(kind: .spotify, running: true)
        let browser = makeBrowser(player: .spotify, backend: backend)

        var track = PlayerTrack()
        track.title = "Midnight City"
        track.artist = "M83"
        track.album = "Hurry Up"
        track.playbackURI = "spotify:track:6GyFP1nfCDB8lbD2bG0Hq9"
        track.artworkURL = URL(string: "https://i.scdn.co/image/abc")
        browser.recordNowPlaying(track, at: Date(timeIntervalSince1970: 100))

        var ad = PlayerTrack()
        ad.title = "Advertisement"
        ad.playbackURI = "spotify:ad:000000012c8a0e7d00000000"
        browser.recordNowPlaying(ad)

        var noURI = PlayerTrack()
        noURI.title = "Unknown"
        browser.recordNowPlaying(noURI)

        // Re-observing the same track (pause / resume) keeps its first stamp.
        browser.recordNowPlaying(track, at: Date(timeIntervalSince1970: 500))

        #expect(browser.songs.count == 1)
        #expect(browser.songs[0].id == "spotify:track:6GyFP1nfCDB8lbD2bG0Hq9")
        #expect(browser.songs[0].subtitle == "M83")
        #expect(browser.songs[0].artworkURL?.absoluteString == "https://i.scdn.co/image/abc")
        #expect(browser.songs[0].lastPlayedAt == Date(timeIntervalSince1970: 100))

        browser.forget(browser.songs[0])
        #expect(browser.songs.isEmpty)
    }

    @Test
    func appleMusicDoesNotKeepAHistory() {
        let backend = FakeMusicLibraryBackend(kind: .appleMusic, running: true)
        let browser = makeBrowser(player: .appleMusic, backend: backend)
        var track = PlayerTrack()
        track.title = "Song"
        track.playbackURI = "spotify:track:6GyFP1nfCDB8lbD2bG0Hq9"
        browser.recordNowPlaying(track)
        #expect(browser.spotifyHistory.isEmpty)
    }

    @Test
    func pinningALinkResolvesItsTitle() async {
        let backend = FakeMusicLibraryBackend(kind: .spotify, running: false)
        let browser = makeBrowser(
            player: .spotify,
            backend: backend,
            resolver: FakeSpotifyResolver(title: "Today's Top Hits", artworkURL: URL(string: "https://i.scdn.co/image/x"))
        )

        let outcome = browser.pin(link: "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc")
        guard case let .pinned(item) = outcome else {
            Issue.record("expected a pin, got \(outcome)")
            return
        }
        #expect(item.id == "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M")
        #expect(item.title == "Spotify Playlist")

        await waitUntil { browser.collections.first?.title == "Today's Top Hits" }
        #expect(browser.collections.first?.title == "Today's Top Hits")
        #expect(browser.collections.first?.artworkURL?.absoluteString == "https://i.scdn.co/image/x")
        // Pinning never launches or talks to Spotify.
        #expect(backend.played.isEmpty)

        guard case .alreadyPinned = browser.pin(link: "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M") else {
            Issue.record("expected alreadyPinned")
            return
        }
        #expect(browser.pin(link: "https://spotify.link/abc123") == .shortLink)
        #expect(browser.pin(link: "https://example.com/playlist/37i9dQZF1DXcBWIGoYBM5M") == .invalid)
        #expect(browser.collections.count == 1)

        browser.unpin(browser.collections[0])
        #expect(browser.collections.isEmpty)
    }

    @Test
    func pinWithoutResolverKeepsAGenericTitle() {
        let backend = FakeMusicLibraryBackend(kind: .spotify, running: false)
        let browser = makeBrowser(player: .spotify, backend: backend)
        browser.pin(link: "spotify:album:79dL7FLiJFOO0EoehUHQBv")
        #expect(browser.collections.first?.title == "Spotify Album")
        #expect(browser.collections.first?.kind == .album)
    }

    @Test
    func switchingPlayersResetsTransientState() {
        let backend = FakeMusicLibraryBackend(kind: .appleMusic, running: false)
        let browser = makeBrowser(player: .appleMusic, backend: backend)
        browser.section = .songs
        browser.beginSearch()
        browser.updateQuery("x")

        browser.setPlayer(.spotify)

        #expect(browser.player == .spotify)
        #expect(browser.section == .collections)
        #expect(!browser.isSearchActive)

        browser.setPlayer(nil)
        #expect(browser.collections.isEmpty)
        #expect(browser.backend == nil)
    }

    @Test
    func playerStartingRetriesMissingArtwork() {
        let backend = FakeMusicLibraryBackend(kind: .spotify, running: false)
        let browser = makeBrowser(player: .spotify, backend: backend)
        let before = browser.artworkGeneration

        browser.activate()
        #expect(browser.artworkGeneration == before)

        backend.running = true
        browser.activate()
        #expect(browser.isPlayerRunning)
        #expect(browser.artworkGeneration == before + 1)
    }

    @Test
    func artworkLoadsOnceFromARunningPlayer() async {
        let backend = FakeMusicLibraryBackend(kind: .appleMusic, running: false)
        let cached = MusicLibrarySnapshot(playlists: samplePlaylists, songs: [], fetchedAt: .now)
        let browser = makeBrowser(player: .appleMusic, backend: backend, archive: MusicLibraryArchive(appleMusic: cached))
        let item = samplePlaylists[0]

        // Closed: the backend answers nil; the miss is retried later.
        browser.requestArtwork(for: item)
        await waitUntil { backend.artworkRequests.count == 1 }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(browser.artwork[item.id] == nil)

        backend.running = true
        browser.requestArtwork(for: item)
        await waitUntil { browser.artwork[item.id] != nil }
        #expect(browser.artwork[item.id] != nil)

        browser.requestArtwork(for: item)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(backend.artworkRequests.count == 2)
    }

    @Test
    func switchingPlayersMidReadDoesNotLeaveTheLibraryLoadingOrSearching() async {
        let apple = GatedMusicLibraryBackend(kind: .appleMusic)
        let spotify = FakeMusicLibraryBackend(kind: .spotify, running: false)
        let browser = MusicLibraryBrowser(
            player: .appleMusic,
            store: MusicLibraryStore(fileURL: nil),
            metadataResolver: nil,
            makeBackend: { kind -> any MusicLibraryBackend in kind == .appleMusic ? apple : spotify }
        )
        browser.searchDebounce = .zero

        browser.refreshLibrary()
        browser.beginSearch()
        browser.updateQuery("night")
        #expect(browser.isLoadingLibrary)
        #expect(browser.isSearchingLibrary)

        // Settings → Music: Spotify, then back, while Music is still answering.
        browser.setPlayer(.spotify)
        browser.setPlayer(.appleMusic)
        apple.release()
        try? await Task.sleep(for: .milliseconds(50))

        // The abandoned reads must not leave spinners (and the "Load Library"
        // guard) stuck on.
        #expect(!browser.isLoadingLibrary)
        #expect(!browser.isSearchingLibrary)
    }
}

/// A running Apple Music whose reads hang until `release()` (a big library,
/// a cold start), so a test can act while one is in flight.
final class GatedMusicLibraryBackend: MusicLibraryBackend, @unchecked Sendable {
    let kind: MusicPlayerKind
    let canReadLibrary = true

    private let lock = NSLock()
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(kind: MusicPlayerKind) {
        self.kind = kind
    }

    func release() {
        let pending: [CheckedContinuation<Void, Never>] = lock.withLock {
            released = true
            defer { waiters.removeAll() }
            return waiters
        }
        pending.forEach { $0.resume() }
    }

    private func waitForRelease() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                if released { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func isPlayerRunning() -> Bool { true }

    func fetchLibrary() async -> MusicLibrarySnapshot? {
        await waitForRelease()
        return MusicLibrarySnapshot(playlists: [], songs: [], fetchedAt: .now)
    }

    func searchLibrary(_ query: String) async -> [MusicLibraryItem]? {
        await waitForRelease()
        return []
    }

    func artworkData(for item: MusicLibraryItem) async -> Data? { nil }
    func play(_ item: MusicLibraryItem) async -> Bool { false }
}

// MARK: - Pure rules

struct SpotifyLinkTests {
    @Test
    func parsesShareLinksAndURIs() {
        let cases: [(String, String, MusicLibraryItem.Kind)] = [
            ("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=1a2b3c", "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M", .playlist),
            ("open.spotify.com/album/79dL7FLiJFOO0EoehUHQBv", "spotify:album:79dL7FLiJFOO0EoehUHQBv", .album),
            ("https://open.spotify.com/intl-de/track/6GyFP1nfCDB8lbD2bG0Hq9", "spotify:track:6GyFP1nfCDB8lbD2bG0Hq9", .song),
            ("https://open.spotify.com/user/spotify/playlist/37i9dQZF1DXcBWIGoYBM5M", "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M", .playlist),
            ("https://open.spotify.com/embed/artist/4tZwfgrHOc3mvqYlEYSvVi", "spotify:artist:4tZwfgrHOc3mvqYlEYSvVi", .artist),
            ("  spotify:show:5CfCWKI5pZ28U0uOzXkDHe  ", "spotify:show:5CfCWKI5pZ28U0uOzXkDHe", .show),
            ("spotify:user:someone:playlist:37i9dQZF1DXcBWIGoYBM5M", "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M", .playlist),
            ("https://open.spotify.com/episode/512ojhOuo1ktJprKbVcKyQ", "spotify:episode:512ojhOuo1ktJprKbVcKyQ", .episode),
        ]
        for (text, uri, kind) in cases {
            let parsed = SpotifyLink.parse(text)
            #expect(parsed?.uri == uri, "\(text)")
            #expect(parsed?.kind == kind, "\(text)")
        }
    }

    @Test
    func rejectsWhatIsNotAPlayableSpotifyLink() {
        for text in [
            "",
            "hello",
            "https://example.com/playlist/37i9dQZF1DXcBWIGoYBM5M",
            "https://open.spotify.com/playlist/",
            "https://open.spotify.com/playlist/not-an-id!",
            "spotify:ad:000000012c8a0e7d00000000",
            "spotify:local:Artist:Album:Title:200",
            "https://open.spotify.com/genre/0JQ5DAqbMKFQ00XGBls6ym",
        ] {
            #expect(SpotifyLink.parse(text) == nil, "\(text)")
        }
    }

    @Test
    func recognisesShortLinksAndBuildsWebURLs() {
        #expect(SpotifyLink.isShortLink("https://spotify.link/AbCdEf"))
        #expect(!SpotifyLink.isShortLink("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"))
        #expect(
            SpotifyLink.parse("spotify:track:6GyFP1nfCDB8lbD2bG0Hq9")?.webURL?.absoluteString
                == "https://open.spotify.com/track/6GyFP1nfCDB8lbD2bG0Hq9"
        )
    }
}

struct MusicPlaybackHistoryTests {
    private func item(_ id: String) -> MusicLibraryItem {
        MusicLibraryItem(id: id, kind: .song, title: id, subtitle: "")
    }

    @Test
    func recordingMovesToFrontDedupesAndCaps() {
        var history: [MusicLibraryItem] = []
        for id in ["a", "b", "c"] {
            history = MusicPlaybackHistory.recording(item(id), into: history, capacity: 3)
        }
        #expect(history.map(\.id) == ["c", "b", "a"])

        history = MusicPlaybackHistory.recording(item("a"), into: history, capacity: 3)
        #expect(history.map(\.id) == ["a", "c", "b"])

        history = MusicPlaybackHistory.recording(item("d"), into: history, capacity: 3)
        #expect(history.map(\.id) == ["d", "a", "c"])
        #expect(history.allSatisfy { $0.lastPlayedAt != nil })
    }

    @Test
    func sortsPlayedFirstThenOriginalOrder() {
        var a = item("a"); a.lastPlayedAt = Date(timeIntervalSince1970: 10)
        var b = item("b"); b.lastPlayedAt = Date(timeIntervalSince1970: 20)
        let c = item("c")
        let d = item("d")
        #expect(MusicPlaybackHistory.sortedByRecency([c, a, d, b]).map(\.id) == ["b", "a", "c", "d"])
    }
}

struct MusicPlaylistRulesTests {
    @Test
    func skipsFoldersAndBuiltInLists() {
        #expect(MusicPlaylistFilter.includes(specialKind: nil))
        #expect(MusicPlaylistFilter.includes(specialKind: MusicESpK.none.rawValue))
        #expect(!MusicPlaylistFilter.includes(specialKind: MusicESpK.folder.rawValue))
        #expect(!MusicPlaylistFilter.includes(specialKind: MusicESpK.music.rawValue))
        #expect(!MusicPlaylistFilter.includes(specialKind: MusicESpK.library.rawValue))
        #expect(!MusicPlaylistFilter.includes(specialKind: MusicESpK.genius.rawValue))
    }

    @Test
    func formatsPlaylistSubtitles() {
        #expect(MusicPlaylistFilter.subtitle(kind: .playlist, durationSeconds: 0) == "Playlist")
        #expect(MusicPlaylistFilter.subtitle(kind: .playlist, durationSeconds: 8040) == "Playlist · 2 hr 14 min")
        #expect(MusicPlaylistFilter.subtitle(kind: .smartPlaylist, durationSeconds: 7200) == "Smart Playlist · 2 hr")
        #expect(MusicPlaylistFilter.subtitle(kind: .playlist, durationSeconds: 20) == "Playlist · 1 min")
    }

    @Test
    func picksTheMostRecentDatesIgnoringMissingValues() {
        let dates: [Any] = [
            Date(timeIntervalSince1970: 30),
            NSNull(),
            Date(timeIntervalSince1970: 50),
            "missing value",
            Date(timeIntervalSince1970: 10),
        ]
        #expect(MusicRecency.topIndices(dates: dates, limit: 2) == [2, 0])
        #expect(MusicRecency.topIndices(dates: [NSNull()], limit: 5).isEmpty)
    }
}

@MainActor
struct MusicLibraryStoreTests {
    @Test
    func roundTripsThroughDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchtune-music-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")

        let store = MusicLibraryStore(fileURL: url)
        let pin = MusicLibraryItem(id: "spotify:album:79dL7FLiJFOO0EoehUHQBv", kind: .album, title: "Currents", subtitle: "Album")
        store.update {
            $0.spotifyPins = [pin]
            $0.appleMusic = MusicLibrarySnapshot(playlists: samplePlaylists, songs: [], fetchedAt: Date(timeIntervalSince1970: 1_000))
        }
        #expect(FileManager.default.fileExists(atPath: url.path))

        let reloaded = MusicLibraryStore(fileURL: url)
        #expect(reloaded.archive.spotifyPins == [pin])
        #expect(reloaded.archive.appleMusic?.playlists == samplePlaylists)
        #expect(reloaded.archive.spotifyHistory.isEmpty)
    }

    @Test
    func inMemoryStoreNeverWrites() {
        let store = MusicLibraryStore(fileURL: nil)
        store.update { $0.spotifyHistory = sampleSongs }
        #expect(store.archive.spotifyHistory == sampleSongs)
        #expect(store.fileURL == nil)
    }
}

// MARK: - Harness override + manager

@MainActor
struct MusicPlayerIconTests {
    @Test
    func aMissingPlayerIsNotLookedUpOnEveryRender() {
        MusicPlayerIcon.resetForTests()
        defer { MusicPlayerIcon.resetForTests() }
        var lookups = 0
        MusicPlayerIcon.resolveAppURL = { _ in
            lookups += 1
            return nil
        }

        let start = Date()
        for frame in 0..<20 {
            #expect(MusicPlayerIcon.icon(for: .spotify, now: start.addingTimeInterval(Double(frame) / 60)) == nil)
        }
        #expect(lookups == 1)

        // Installed meanwhile: picked up once the miss has aged out.
        MusicPlayerIcon.resolveAppURL = { _ in
            lookups += 1
            return URL(fileURLWithPath: "/System/Applications/Music.app")
        }
        let later = start.addingTimeInterval(MusicPlayerIcon.missRetryInterval + 1)
        #expect(MusicPlayerIcon.icon(for: .spotify, now: later) != nil)
        #expect(MusicPlayerIcon.icon(for: .spotify, now: later) != nil)
        #expect(lookups == 2)
    }
}

struct MusicHarnessOverrideTests {
    @Test
    func onlyAppliesToHarnessRunsThatAskForIt() {
        #expect(MusicHarnessOverride(environment: [:]) == nil)
        #expect(MusicHarnessOverride(environment: ["NOTCHTUNE_HARNESS_MUSIC_STATE": "idle"]) == nil)
        #expect(MusicHarnessOverride(environment: ["NOTCHTUNE_HARNESS_SCENARIO": "sessionList"]) == nil)
    }

    @Test
    func parsesPlayerStateAndSamples() throws {
        let override = try #require(MusicHarnessOverride(environment: [
            "NOTCHTUNE_HARNESS_SCENARIO": "sessionList",
            "NOTCHTUNE_HARNESS_MUSIC_PLAYER": "Spotify",
            "NOTCHTUNE_HARNESS_MUSIC_STATE": "noart",
            "NOTCHTUNE_HARNESS_SAMPLE_LIBRARY": "1",
            "NOTCHTUNE_HARNESS_MUSIC_SECTION": "songs",
            "NOTCHTUNE_HARNESS_MUSIC_QUERY": "night",
        ]))
        #expect(override.player == .spotify)
        #expect(override.state == .noArt)
        #expect(override.isPlayerRunning)
        #expect(override.seedsSampleLibrary)
        #expect(override.section == .songs)
        #expect(override.query == "night")
        #expect(!override.seedArchive.spotifyPins.isEmpty)
        #expect(override.seedArchive.appleMusic == nil)
    }

    @Test
    func defaultsToAClosedPlayer() throws {
        let override = try #require(MusicHarnessOverride(environment: [
            "NOTCHTUNE_HARNESS_SCENARIO": "sessionList",
            "NOTCHTUNE_HARNESS_MUSIC_PLAYER": "appleMusic",
        ]))
        #expect(override.state == .closed)
        #expect(!override.isPlayerRunning)
        #expect(!override.seedsSampleLibrary)
        #expect(override.seedArchive == MusicLibraryArchive())
    }
}

@MainActor
struct MusicPlayerManagerEmptyStateTests {
    private func manager(_ state: MusicHarnessOverride.PlaybackState, player: String = "appleMusic") throws -> MusicPlayerManager {
        let override = try #require(MusicHarnessOverride(environment: [
            "NOTCHTUNE_HARNESS_SCENARIO": "sessionList",
            "NOTCHTUNE_HARNESS_MUSIC_PLAYER": player,
            "NOTCHTUNE_HARNESS_MUSIC_STATE": state.rawValue,
        ]))
        return MusicPlayerManager(harness: override)
    }

    @Test
    func nothingPlayingWhenThePlayerIsClosedOrIdle() throws {
        for state in [MusicHarnessOverride.PlaybackState.closed, .idle] {
            let manager = try manager(state)
            #expect(manager.isMusicEnabled)
            #expect(!manager.hasNowPlaying, "\(state)")
            #expect(manager.playerKind == .appleMusic)
            #expect(manager.library.player == .appleMusic)
        }
    }

    @Test
    func aLoadedTrackShowsTransportControls() throws {
        let playing = try manager(.noArt, player: "spotify")
        #expect(playing.hasNowPlaying)
        #expect(!playing.hasAlbumArt)
        #expect(playing.library.player == .spotify)
    }
}
