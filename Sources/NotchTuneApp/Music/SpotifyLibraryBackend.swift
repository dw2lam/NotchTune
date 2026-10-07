import AppKit
import ScriptingBridge

/// Spotify's AppleScript dictionary can PLAY any `spotify:` URI
/// (`play track "spotify:playlist:…"`) but can't list the user's library, so
/// the Spotify chooser is fed by NotchTune itself (pins + observed history,
/// see `MusicLibraryBrowser`). This backend only plays.
final class SpotifyLibraryBackend: MusicLibraryBackend, @unchecked Sendable {
    let kind = MusicPlayerKind.spotify
    let canReadLibrary = false

    private let queue = DispatchQueue(label: "app.notchtune.music.library.spotify", qos: .userInitiated)

    func isPlayerRunning() -> Bool {
        MusicPlayerProcess.isRunning(bundleID: kind.bundleID)
    }

    func fetchLibrary() async -> MusicLibrarySnapshot? { nil }
    func searchLibrary(_ query: String) async -> [MusicLibraryItem]? { nil }
    func artworkData(for item: MusicLibraryItem) async -> Data? { nil }

    func play(_ item: MusicLibraryItem) async -> Bool {
        let wasRunning = isPlayerRunning()
        if !wasRunning {
            guard await MusicPlayerProcess.launchInBackground(kind) != nil else { return false }
            // Spotify accepts Apple Events a beat before it can honour them.
            try? await Task.sleep(for: .milliseconds(1500))
        }
        let attempts = wasRunning ? 1 : 4
        for attempt in 0..<attempts {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(1200))
            }
            guard await send(uri: item.id) else { continue }
            if wasRunning { return true }
            // Cold start: confirm it actually started before giving up retries.
            try? await Task.sleep(for: .milliseconds(1200))
            if await isPlaying() { return true }
        }
        return false
    }

    private func send(uri: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let pid = MusicPlayerProcess.runningPID(bundleID: MusicConstants.Spotify.bundleID),
                      let app = SBApplication.runningInstance(pid: pid, timeoutSeconds: 5) else {
                    continuation.resume(returning: false)
                    return
                }
                (app as SpotifyApplication).playTrack?(uri, inContext: nil)
                continuation.resume(returning: true)
            }
        }
    }

    private func isPlaying() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let pid = MusicPlayerProcess.runningPID(bundleID: MusicConstants.Spotify.bundleID),
                      let app = SBApplication.runningInstance(pid: pid, timeoutSeconds: 5) else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: (app as SpotifyApplication).playerState == .playing)
            }
        }
    }
}
