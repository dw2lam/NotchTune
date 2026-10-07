import AppKit
import Observation

/// State behind the Music tab's empty state: what the selected player can
/// play, and the act of playing it.
///
/// - Apple Music: library playlists + recently played songs read over
///   ScriptingBridge (only while Music runs), cached on disk so they're still
///   offered when Music is closed; search goes to Music's own library search.
/// - Spotify: its scripting can play a URI but can't list anything, so the
///   list is NotchTune's own: links the user pinned and tracks it has seen
///   playing (each one's `spotify:` URI).
///
/// Rendering never launches a player: reads happen only while it's running.
/// Picking an item is the one explicit action that may start it (hidden, in
/// the background).
@MainActor
@Observable
final class MusicLibraryBrowser {
    enum Section: String, CaseIterable, Identifiable, Sendable {
        /// Apple Music "Playlists", Spotify "Pinned".
        case collections
        /// Apple Music "Songs" (recently played), Spotify "Recent".
        case songs

        var id: String { rawValue }

        func title(for player: MusicPlayerKind) -> String {
            switch (self, player) {
            case (.collections, .appleMusic): "Playlists"
            case (.songs, .appleMusic): "Songs"
            case (.collections, .spotify): "Pinned"
            case (.songs, .spotify): "Recent"
            }
        }
    }

    enum PinOutcome: Equatable {
        case pinned(MusicLibraryItem)
        case alreadyPinned(MusicLibraryItem)
        case shortLink
        case invalid
    }

    private(set) var player: MusicPlayerKind?
    var section: Section = .collections
    /// Search text; `nil` while the search field is closed.
    private(set) var query: String?
    private(set) var isPlayerRunning = false
    private(set) var isLoadingLibrary = false
    private(set) var isSearchingLibrary = false
    /// The item whose play command is in flight.
    private(set) var pendingItemID: String?
    /// Short, transient feedback ("Couldn't start …", "Pinned …").
    private(set) var statusMessage: String?
    private(set) var artwork: [String: NSImage] = [:]

    private(set) var appleMusicLibrary: MusicLibrarySnapshot
    private(set) var spotifyPins: [MusicLibraryItem]
    private(set) var spotifyHistory: [MusicLibraryItem]
    private(set) var librarySearchResults: [MusicLibraryItem]?

    /// Library reads younger than this are reused on appear.
    @ObservationIgnored var staleInterval: TimeInterval = 120
    @ObservationIgnored var searchDebounce: Duration = .milliseconds(300)

    @ObservationIgnored private let store: MusicLibraryStore
    @ObservationIgnored private let makeBackend: (MusicPlayerKind) -> any MusicLibraryBackend
    @ObservationIgnored private let metadataResolver: (any SpotifyLinkMetadataResolving)?
    @ObservationIgnored private(set) var backend: (any MusicLibraryBackend)?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var artworkRequested: Set<String> = []
    @ObservationIgnored private var workspaceObservers: [any NSObjectProtocol] = []

    init(
        player: MusicPlayerKind?,
        store: MusicLibraryStore,
        metadataResolver: (any SpotifyLinkMetadataResolving)? = SpotifyOEmbedResolver(),
        makeBackend: @escaping (MusicPlayerKind) -> any MusicLibraryBackend = MusicLibraryBrowser.liveBackend
    ) {
        self.store = store
        self.makeBackend = makeBackend
        self.metadataResolver = metadataResolver
        appleMusicLibrary = store.archive.appleMusic ?? .empty
        spotifyPins = store.archive.spotifyPins
        spotifyHistory = store.archive.spotifyHistory
        setPlayer(player)
        observeWorkspace()
    }

    nonisolated static func liveBackend(for kind: MusicPlayerKind) -> any MusicLibraryBackend {
        switch kind {
        case .appleMusic: AppleMusicLibraryBackend()
        case .spotify: SpotifyLibraryBackend()
        }
    }

    // MARK: Lists

    /// Playlists (Apple Music) or pins (Spotify, most recently played first).
    var collections: [MusicLibraryItem] {
        switch player {
        case .appleMusic: appleMusicLibrary.playlists
        case .spotify: MusicPlaybackHistory.sortedByRecency(spotifyPins)
        case nil: []
        }
    }

    /// Recently played songs (Apple Music library / Spotify as seen by NotchTune).
    var songs: [MusicLibraryItem] {
        switch player {
        case .appleMusic: appleMusicLibrary.songs
        case .spotify: spotifyHistory
        case nil: []
        }
    }

    var isSearchActive: Bool { query != nil }

    var trimmedQuery: String {
        query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// What the list shows right now.
    var visibleItems: [MusicLibraryItem] {
        let needle = trimmedQuery
        guard !needle.isEmpty else {
            return section == .collections ? collections : songs
        }
        let matchingCollections = collections.filter { $0.matches(needle) }
        let matchingSongs = librarySearchResults ?? songs.filter { $0.matches(needle) }
        var seen = Set<String>()
        return (matchingCollections + matchingSongs).filter { seen.insert($0.id).inserted }
    }

    var hasAnyContent: Bool { !collections.isEmpty || !songs.isEmpty }

    var canReadLibrary: Bool { backend?.canReadLibrary ?? false }

    // MARK: Player selection

    func setPlayer(_ kind: MusicPlayerKind?) {
        guard kind != player || backend == nil else { return }
        refreshTask?.cancel()
        searchTask?.cancel()
        player = kind
        backend = kind.map(makeBackend)
        section = .collections
        query = nil
        librarySearchResults = nil
        pendingItemID = nil
        statusMessage = nil
        artwork = [:]
        artworkRequested = []
        isPlayerRunning = backend?.isPlayerRunning() ?? false
    }

    // MARK: Loading

    /// Called when the empty state appears. Reads the library only if the
    /// player is ALREADY running and the cached read is stale.
    func activate(now: Date = .now) {
        isPlayerRunning = backend?.isPlayerRunning() ?? false
        guard isPlayerRunning, canReadLibrary else { return }
        let age = now.timeIntervalSince(appleMusicLibrary.fetchedAt)
        if age > staleInterval || (appleMusicLibrary.playlists.isEmpty && appleMusicLibrary.songs.isEmpty) {
            refreshLibrary()
        }
    }

    /// Re-reads the library if the player runs (no-op otherwise).
    func refreshLibrary() {
        guard let backend, backend.canReadLibrary, backend.isPlayerRunning() else { return }
        refreshTask?.cancel()
        isLoadingLibrary = true
        let kind = backend.kind
        refreshTask = Task { [weak self] in
            let snapshot = await backend.fetchLibrary()
            guard let self, !Task.isCancelled, self.player == kind else { return }
            self.isLoadingLibrary = false
            guard let snapshot else { return }
            self.applyLibrary(snapshot)
        }
    }

    /// Explicit "Load Library" for a closed Apple Music: start it in the
    /// background, then read.
    func loadLibraryLaunchingPlayer() {
        guard let backend, backend.canReadLibrary, !isLoadingLibrary else { return }
        isLoadingLibrary = true
        let kind = backend.kind
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let launched = await MusicPlayerProcess.launchInBackground(kind) != nil
            var snapshot: MusicLibrarySnapshot?
            if launched {
                // A cold Music answers before its library has loaded.
                for attempt in 0..<5 where snapshot?.playlists.isEmpty ?? true {
                    if attempt > 0 { try? await Task.sleep(for: .milliseconds(900)) }
                    snapshot = await backend.fetchLibrary()
                }
            }
            guard let self, !Task.isCancelled, self.player == kind else { return }
            self.isLoadingLibrary = false
            self.isPlayerRunning = backend.isPlayerRunning()
            if let snapshot {
                self.applyLibrary(snapshot)
            } else {
                self.flash("Couldn't open \(kind.displayName)")
            }
        }
    }

    private func applyLibrary(_ snapshot: MusicLibrarySnapshot) {
        appleMusicLibrary = snapshot
        store.update { $0.appleMusic = snapshot }
        // Rows whose artwork failed while the player was closed may succeed now.
        artworkRequested = Set(artwork.keys)
    }

    // MARK: Search

    func beginSearch() {
        guard query == nil else { return }
        query = ""
    }

    func endSearch() {
        searchTask?.cancel()
        query = nil
        librarySearchResults = nil
        isSearchingLibrary = false
    }

    func updateQuery(_ text: String) {
        guard query != text else { return }
        query = text
        searchTask?.cancel()
        librarySearchResults = nil
        isSearchingLibrary = false
        let needle = trimmedQuery
        guard !needle.isEmpty, let backend, backend.canReadLibrary, backend.isPlayerRunning() else { return }
        isSearchingLibrary = true
        let debounce = searchDebounce
        let kind = backend.kind
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let results = await backend.searchLibrary(needle)
            guard let self, !Task.isCancelled, self.player == kind, self.trimmedQuery == needle else { return }
            self.isSearchingLibrary = false
            self.librarySearchResults = results
        }
    }

    // MARK: Playback

    func play(_ item: MusicLibraryItem) {
        guard let backend, pendingItemID == nil else { return }
        pendingItemID = item.id
        statusMessage = nil
        let kind = backend.kind
        let wasRunning = backend.isPlayerRunning()
        Task { [weak self] in
            let delivered = await backend.play(item)
            guard let self, self.player == kind else { return }
            self.pendingItemID = nil
            self.isPlayerRunning = backend.isPlayerRunning()
            if delivered {
                self.notePlayed(item)
            } else {
                self.flash("Couldn't play \u{201C}\(item.title)\u{201D}")
            }
            if !wasRunning, self.isPlayerRunning {
                self.refreshLibrary()
            }
        }
    }

    func openPlayerApp() {
        guard let player else { return }
        MusicPlayerProcess.openApp(player)
    }

    private func notePlayed(_ item: MusicLibraryItem, at date: Date = .now) {
        guard player == .spotify else { return }
        if let index = spotifyPins.firstIndex(where: { $0.id == item.id }) {
            spotifyPins[index].lastPlayedAt = date
            persistSpotify()
        }
    }

    // MARK: Spotify history

    /// Records a track the player was seen playing (Spotify only — Apple
    /// Music's library already knows what was played).
    func recordNowPlaying(_ track: PlayerTrack, at date: Date = .now) {
        guard player == .spotify,
              let item = Self.spotifyHistoryItem(for: track) else { return }
        if spotifyHistory.first?.id == item.id {
            // Same track re-observed (pause/resume): keep the original stamp.
            if spotifyHistory[0].title != item.title || spotifyHistory[0].artworkURL != item.artworkURL {
                spotifyHistory[0].title = item.title
                spotifyHistory[0].subtitle = item.subtitle
                spotifyHistory[0].artworkURL = item.artworkURL ?? spotifyHistory[0].artworkURL
                persistSpotify()
            }
            return
        }
        spotifyHistory = MusicPlaybackHistory.recording(item, into: spotifyHistory, playedAt: date)
        persistSpotify()
    }

    static func spotifyHistoryItem(for track: PlayerTrack) -> MusicLibraryItem? {
        guard let uri = track.playbackURI,
              let parsed = SpotifyLink.parse(uri),
              parsed.kind == .song || parsed.kind == .episode,
              !track.title.isEmpty else { return nil }
        let subtitle = [track.artist, track.album]
            .filter { !$0.isEmpty }
            .first ?? parsed.kind.label
        return MusicLibraryItem(
            id: parsed.uri,
            kind: parsed.kind,
            title: track.title,
            subtitle: subtitle,
            artworkURL: track.artworkURL
        )
    }

    func forget(_ item: MusicLibraryItem) {
        spotifyHistory.removeAll { $0.id == item.id }
        persistSpotify()
    }

    func clearSpotifyHistory() {
        spotifyHistory = []
        persistSpotify()
    }

    // MARK: Spotify pins

    func isPinned(_ item: MusicLibraryItem) -> Bool {
        spotifyPins.contains { $0.id == item.id }
    }

    @discardableResult
    func pin(link text: String) -> PinOutcome {
        if SpotifyLink.isShortLink(text) {
            flash("Short links can't be read — copy the full open.spotify.com link")
            return .shortLink
        }
        guard let parsed = SpotifyLink.parse(text) else {
            flash("That isn't a Spotify link")
            return .invalid
        }
        if let existing = spotifyPins.first(where: { $0.id == parsed.uri }) {
            section = .collections
            flash("Already pinned")
            return .alreadyPinned(existing)
        }
        let known = spotifyHistory.first { $0.id == parsed.uri }
        let item = MusicLibraryItem(
            id: parsed.uri,
            kind: parsed.kind,
            title: known?.title ?? "Spotify \(parsed.kind.label)",
            subtitle: known?.subtitle ?? parsed.kind.label,
            artworkURL: known?.artworkURL
        )
        spotifyPins.insert(item, at: 0)
        section = .collections
        persistSpotify()
        resolveMetadata(for: parsed)
        return .pinned(item)
    }

    @discardableResult
    func pin(_ item: MusicLibraryItem) -> PinOutcome {
        guard player == .spotify else { return .invalid }
        if let existing = spotifyPins.first(where: { $0.id == item.id }) {
            return .alreadyPinned(existing)
        }
        var pinned = item
        pinned.lastPlayedAt = nil
        spotifyPins.insert(pinned, at: 0)
        persistSpotify()
        return .pinned(pinned)
    }

    func unpin(_ item: MusicLibraryItem) {
        spotifyPins.removeAll { $0.id == item.id }
        persistSpotify()
    }

    private func resolveMetadata(for link: SpotifyLink.Parsed) {
        guard let metadataResolver else { return }
        Task { [weak self] in
            guard let resolved = await metadataResolver.resolve(link) else { return }
            guard let self, let index = self.spotifyPins.firstIndex(where: { $0.id == link.uri }) else { return }
            self.spotifyPins[index].title = resolved.title
            if let artworkURL = resolved.artworkURL {
                self.spotifyPins[index].artworkURL = artworkURL
            }
            self.persistSpotify()
        }
    }

    private func persistSpotify() {
        let pins = spotifyPins
        let history = spotifyHistory
        store.update {
            $0.spotifyPins = pins
            $0.spotifyHistory = history
        }
    }

    // MARK: Artwork

    /// Loads a row's cover once. Remote covers (Spotify) load any time;
    /// library artwork (Apple Music) is only readable from a RUNNING player
    /// (the backend answers `nil` instead of launching it), so a miss while
    /// it's closed is retried after it starts.
    func requestArtwork(for item: MusicLibraryItem) {
        guard artwork[item.id] == nil, !artworkRequested.contains(item.id) else { return }
        artworkRequested.insert(item.id)
        let backend = backend
        let kind = player
        Task { [weak self] in
            var data: Data?
            if let url = item.artworkURL {
                data = await MusicRemoteArtworkLoader.shared.data(for: url)
            } else if let backend {
                data = await backend.artworkData(for: item)
            }
            guard let self, self.player == kind else { return }
            if let data, let image = NSImage(data: data) {
                self.artwork[item.id] = image
            } else if item.artworkURL == nil, !(backend?.isPlayerRunning() ?? false) {
                self.artworkRequested.remove(item.id)
            }
        }
    }

    // MARK: Status

    func flash(_ message: String) {
        statusTask?.cancel()
        statusMessage = message
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }

    // MARK: Workspace

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .bundleIdentifier
                MainActor.assumeIsolated {
                    guard let self, let bundleID, bundleID == self.player?.bundleID else { return }
                    self.isPlayerRunning = self.backend?.isPlayerRunning() ?? false
                }
            }
            workspaceObservers.append(token)
        }
    }
}
