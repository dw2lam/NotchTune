import os
import SwiftUI
import Combine
import Observation

let musicConnectedAppDefaultsKey = "music.connectedApp"

@MainActor
@Observable
final class MusicPlayerManager {
    static let connectedAppKey = musicConnectedAppDefaultsKey
    static let noPlaybackPositionPlaceholder = "--:--"

    private var musicApp: (any MusicPlayerProtocol)!
    private var playerAppProvider: MusicPlayerAppProvider!
    @ObservationIgnored private let harness: MusicHarnessOverride?

    /// What the empty state offers to play from the selected player.
    let library: MusicLibraryBrowser

    var name: String { musicApp.appName }
    var isRunning: Bool { musicApp.isRunning() }

    let notificationSubject = PassthroughSubject<MusicAlertItem, Never>()

    // Track state
    var track = PlayerTrack()
    var isPlaying = false
    var isLoved = false

    // Seeker
    var seekerPosition: CGFloat = 0
    var isDraggingPlaybackPositionView = false

    // Playback settings
    var shuffleIsOn = false
    var shuffleContextEnabled = false
    var repeatIsOn = false
    var repeatContextEnabled = false

    // Playback time
    var formattedDuration = MusicPlayerManager.noPlaybackPositionPlaceholder
    var formattedPlaybackPosition = MusicPlayerManager.noPlaybackPositionPlaceholder

    // Connected app name for display
    var connectedAppName: String { musicApp.appName }

    var onTrackChange: ((PlayerTrack) -> Void)?
    var onPlaybackStateChange: ((Bool) -> Void)?
    var onAlbumArtUpdated: ((PlayerTrack) -> Void)?

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var timerCancellable: AnyCancellable?
    @ObservationIgnored private var userDefaultsObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var albumArtFetchGeneration: UInt64 = 0

    init(harness: MusicHarnessOverride? = .current) {
        self.harness = harness
        let store: MusicLibraryStore
        let makeBackend: (MusicPlayerKind) -> any MusicLibraryBackend
        if let harness {
            store = MusicLibraryStore(fileURL: nil, seed: harness.seedArchive)
            makeBackend = { MusicHarnessLibraryBackend(kind: $0, override: harness) }
        } else {
            store = MusicLibraryStore(fileURL: MusicLibraryStore.defaultFileURL())
            makeBackend = MusicLibraryBrowser.liveBackend
        }
        library = MusicLibraryBrowser(
            player: harness?.player ?? MusicPlayerKind.selected(),
            store: store,
            metadataResolver: harness == nil ? SpotifyOEmbedResolver() : nil,
            makeBackend: makeBackend
        )
        if let harness {
            if let section = harness.section { library.section = section }
            if let query = harness.query {
                library.beginSearch()
                library.updateQuery(query)
            }
        }
        playerAppProvider = MusicPlayerAppProvider(notificationSubject: notificationSubject, harness: harness)
        setupMusicApp()
        playStateOrTrackDidChange(nil)
    }

    // MARK: - Setup

    private func setupMusicApp() {
        musicApp = playerAppProvider.getPlayerApp()
        setupObservers()
    }

    func setupObservers() {
        cleanupObservers()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(playStateOrTrackDidChange),
            name: NSNotification.Name(rawValue: musicApp.appNotification),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleConnectedAppChange()
            }
        }
    }

    private func cleanupObservers() {
        DistributedNotificationCenter.default().removeObserver(self)
        cancellables.removeAll()
        if let userDefaultsObserver {
            NotificationCenter.default.removeObserver(userDefaultsObserver)
        }
        userDefaultsObserver = nil
    }

    private func handleConnectedAppChange() {
        // Harness runs pin a fake player; Settings changes don't apply.
        guard harness == nil else { return }
        let currentApp = UserDefaults.standard.string(forKey: musicConnectedAppDefaultsKey) ?? "none"
        let newAppName: String
        switch currentApp {
        case "spotify":    newAppName = "Spotify"
        case "appleMusic": newAppName = "Apple Music"
        default:           newAppName = "None"
        }
        guard newAppName != connectedAppName else { return }
        setupMusicApp()
        library.setPlayer(MusicPlayerKind(appName: connectedAppName))
        playStateOrTrackDidChange(nil)
    }

    // MARK: - Notification handlers

    @objc func playStateOrTrackDidChange(_ sender: NSNotification?) {
        let musicAppKilled = sender?.userInfo?["Player State"] as? String == "Stopped"
        let isRunningFromNotification = !musicAppKilled && isRunning

        if musicAppKilled || !musicApp.isRunning() {
            track = PlayerTrack()
            timerCancellable?.cancel()
            timerCancellable = nil
            return
        }

        getPlayState()
        updateFormattedDuration()

        let notificationTrack = musicApp.getTrackInfo()
        if track == notificationTrack { return }

        getPlaybackSettingInfo()
        getNewSongInfo()
        noteObservedTrack()
        onTrackChange?(track)
        _ = isRunningFromNotification
    }

    /// A new track started: remember it for the empty state's "Recent" list
    /// (Spotify only; one extra Apple Event per track change, never per poll).
    private func noteObservedTrack() {
        guard !track.isEmpty(), library.player == .spotify,
              let identity = musicApp.currentTrackIdentity() else { return }
        track.playbackURI = identity.playbackURI
        track.artworkURL = identity.artworkURL
        library.recordNowPlaying(track)
    }

    // MARK: - Media & Playback

    private func getPlayState() {
        let current = musicApp.isPlaying
        if current != isPlaying {
            isPlaying = current
            onPlaybackStateChange?(isPlaying)
        }
    }

    func getPlaybackSettingInfo() {
        shuffleIsOn = musicApp.shuffleIsOn
        shuffleContextEnabled = musicApp.shuffleContextEnabled
        repeatContextEnabled = musicApp.repeatContextEnabled
    }

    func getNewSongInfo() {
        let polled = musicApp.getTrackInfo()
        var updatedPolled = polled
        updatedPolled.clearAlbumArt()

        withAnimation(MusicConstants.mainAnimation) {
            getCurrentSeekerPosition()
            track = updatedPolled
        }
        if !updatedPolled.isEmpty() {
            fetchAlbumArt(for: updatedPolled)
        }
        updateFormattedDuration()
    }

    func fetchAlbumArt(for expectedTrack: PlayerTrack? = nil, retryCount: Int = 5) {
        albumArtFetchGeneration &+= 1
        let generation = albumArtFetchGeneration
        let expected = expectedTrack ?? track

        musicApp.getAlbumArt { result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard generation == self.albumArtFetchGeneration else { return }
                guard self.track.matchesMetadata(expected) else { return }

                if let result {
                    self.updateAlbumArt(newAlbumArt: result)
                } else if retryCount > 0 {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard generation == self.albumArtFetchGeneration else { return }
                    guard self.track.matchesMetadata(expected) else { return }
                    self.fetchAlbumArt(for: expected, retryCount: retryCount - 1)
                }
            }
        }
    }

    func updateAlbumArt(newAlbumArt: MusicFetchedAlbumArt) {
        withAnimation {
            track.avgAlbumColor = Color(nsColor: newAlbumArt.nsImage.musicAverageColor ?? .gray)
            track.nsAlbumArt = newAlbumArt.nsImage
            track.albumArt = newAlbumArt.image
            track.artworkVersion &+= 1
        }
        onAlbumArtUpdated?(track)
    }

    // MARK: - Controls

    func togglePlayPause() {
        isPlaying = !isPlaying
        musicApp.playPause()
        onPlaybackStateChange?(isPlaying)
    }

    func previousTrack() {
        if track.isPodcast {
            seekerPosition = seekerPosition - MusicConstants.podcastRewindDurationSec
            seekTrack()
        } else {
            musicApp.previousTrack()
        }
    }

    func nextTrack() {
        if track.isPodcast {
            seekerPosition = seekerPosition + MusicConstants.podcastRewindDurationSec
            seekTrack()
        } else {
            musicApp.nextTrack()
        }
    }

    func toggleLoveTrack() { isLoved = musicApp.toggleLoveTrack() }
    func setShuffle() { shuffleIsOn = musicApp.setShuffle(shuffleIsOn: shuffleIsOn) }
    func setRepeat() { repeatIsOn = musicApp.setRepeat(repeatIsOn: repeatIsOn) }

    // MARK: - Seeker

    func getCurrentSeekerPosition() {
        guard musicApp.isRunning(), !isDraggingPlaybackPositionView else { return }
        seekerPosition = musicApp.getCurrentSeekerPosition()
        updateFormattedPlaybackPosition()
    }

    func seekTrack() { musicApp.seekTrack(seekerPosition: seekerPosition) }

    func updateFormattedPlaybackPosition() {
        guard musicApp.playerPosition != nil, !isDraggingPlaybackPositionView else { return }
        formattedPlaybackPosition = formattedTimestamp(seekerPosition)
    }

    func updateFormattedDuration() { formattedDuration = formattedTimestamp(track.duration) }

    func draggingPlaybackPosition() { formattedPlaybackPosition = formattedTimestamp(seekerPosition) }

    // MARK: - Timer

    func startTimer() {
        guard musicApp.isRunning() else { return }
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                // Always poll track / play-state (drives resume + the album-art
                // flip). While paused the seeker/volume/settings are frozen, so
                // skip those Apple Events — they'd return identical values.
                self.pollForTrackChanges()
                guard self.isPlaying else { return }
                self.getCurrentSeekerPosition()
                self.getPlaybackSettingInfo()
            }
    }

    func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func pollForTrackChanges() {
        guard musicApp.isRunning() else { return }
        let current = musicApp.isPlaying
        if current != isPlaying {
            isPlaying = current
            onPlaybackStateChange?(isPlaying)
        }
        let polled = musicApp.getTrackInfo()
        guard polled.title != track.title || polled.artist != track.artist ||
              polled.album != track.album || polled.duration != track.duration else { return }
        
        var updatedPolled = polled
        updatedPolled.clearAlbumArt()

        withAnimation(MusicConstants.mainAnimation) {
            track = updatedPolled
        }
        noteObservedTrack()
        onTrackChange?(updatedPolled)
        updateFormattedDuration()
        if !updatedPolled.isEmpty() {
            fetchAlbumArt(for: updatedPolled)
        }
    }

    // MARK: - Open music app

    func openMusicApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: musicApp.appPath, configuration: configuration)
    }

    // MARK: - Connected app

    func switchToAppleMusic() {
        UserDefaults.standard.set("appleMusic", forKey: Self.connectedAppKey)
    }

    func switchToSpotify() {
        UserDefaults.standard.set("spotify", forKey: Self.connectedAppKey)
    }

    func switchToNone() {
        UserDefaults.standard.set("none", forKey: Self.connectedAppKey)
    }

    var isMusicEnabled: Bool { connectedAppName != "None" }

    /// The selected player, `nil` for None.
    var playerKind: MusicPlayerKind? { MusicPlayerKind(appName: connectedAppName) }

    /// A real track is loaded in a running player. When false the Music tab
    /// shows the "Nothing playing" chooser instead of transport controls.
    var hasNowPlaying: Bool {
        isMusicEnabled && !track.isEmpty() && isRunning
    }

    /// Whether the current track's real cover has arrived.
    var hasAlbumArt: Bool {
        track.nsAlbumArt.size.width > 0 && track.nsAlbumArt.size.height > 0
    }

    var isSpotifyAvailable: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Spotify.app")
    }

    // MARK: - Helpers

    func isLikeAuthorized() -> Bool { musicApp.isLikeAuthorized }

    private func formattedTimestamp(_ number: CGFloat) -> String {
        let formatter: DateComponentsFormatter = number >= 3600
            ? .musicPlaybackTimeWithHours : .musicPlaybackTime
        return formatter.string(from: Double(number)) ?? Self.noPlaybackPositionPlaceholder
    }
}

