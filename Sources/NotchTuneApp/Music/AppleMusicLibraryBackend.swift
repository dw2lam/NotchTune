import AppKit
import ScriptingBridge

/// Reads the Music.app library over ScriptingBridge for the empty Music tab.
///
/// Every call runs on one private serial queue against the RUNNING Music
/// process, addressed by pid (`SBApplication(processIdentifier:)`): if Music
/// isn't running the call returns `nil` instead of launching it, and a pid
/// that died mid-call just fails. Bulk reads use `arrayByApplyingSelector`
/// (one Apple Event per property for the whole list).
final class AppleMusicLibraryBackend: MusicLibraryBackend, @unchecked Sendable {
    let kind = MusicPlayerKind.appleMusic
    let canReadLibrary = true

    static let recentSongLimit = 40
    static let searchResultLimit = 30

    private let queue = DispatchQueue(label: "app.notchtune.music.library.apple", qos: .userInitiated)
    /// Touched only on `queue`.
    private var scriptingTarget: (pid: pid_t, app: SBApplication)?

    func isPlayerRunning() -> Bool {
        MusicPlayerProcess.isRunning(bundleID: kind.bundleID)
    }

    // MARK: Library

    func fetchLibrary() async -> MusicLibrarySnapshot? {
        await withRunningMusic { app in
            guard let source = Self.librarySource(of: app) else { return nil }
            let playlists = Self.readPlaylists(in: source)
            let songs = Self.readRecentSongs(in: source)
            return MusicLibrarySnapshot(playlists: playlists, songs: songs, fetchedAt: .now)
        }
    }

    func searchLibrary(_ query: String) async -> [MusicLibraryItem]? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return await withRunningMusic { app in
            guard let source = Self.librarySource(of: app),
                  let library = Self.libraryPlaylist(in: source) else { return nil }
            let raw = library.searchFor?(trimmed, only: .all) as AnyObject?
            let tracks: [AnyObject]
            if let list = raw as? NSArray {
                tracks = list.map { $0 as AnyObject }
            } else if let single = raw as? SBObject {
                tracks = [single]
            } else {
                tracks = []
            }
            return tracks.prefix(Self.searchResultLimit).compactMap { object in
                guard let track = object as? SBObject else { return nil }
                return Self.songItem(from: track)
            }
        }
    }

    func artworkData(for item: MusicLibraryItem) async -> Data? {
        await withRunningMusic { app in
            guard let object = Self.object(for: item, in: app) else { return nil }
            let artworks: SBElementArray? = item.kind.isCollection
                ? (object as MusicPlaylist).artworks?()
                : (object as MusicTrack).artworks?()
            guard let artworks, artworks.count > 0,
                  let artwork = artworks.object(at: 0) as? SBObject,
                  let image = (artwork as MusicArtwork).data,
                  image.isKind(of: NSImage.self) else {
                return nil
            }
            return MusicArtworkRendering.thumbnailPNG(from: image)
        }
    }

    // MARK: Playback

    func play(_ item: MusicLibraryItem) async -> Bool {
        let wasRunning = isPlayerRunning()
        if !wasRunning {
            guard await MusicPlayerProcess.launchInBackground(kind) != nil else { return false }
        }
        // A cold Music can take a moment before its library answers.
        let attempts = wasRunning ? 1 : 6
        for attempt in 0..<attempts {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(800))
            }
            let delivered = await withRunningMusic { app -> Bool? in
                guard let object = Self.object(for: item, in: app) else { return nil }
                (object as MusicGenericMethods).playOnce?(false)
                return true
            }
            if delivered == true { return true }
        }
        return false
    }

    // MARK: Queue plumbing

    private func withRunningMusic<T: Sendable>(_ body: @escaping @Sendable (MusicApplication) -> T?) async -> T? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.runAgainstRunningMusic(body))
            }
        }
    }

    private func runAgainstRunningMusic<T>(_ body: (MusicApplication) -> T?) -> T? {
        guard let pid = MusicPlayerProcess.runningPID(bundleID: kind.bundleID) else {
            scriptingTarget = nil
            return nil
        }
        let app: SBApplication
        if let scriptingTarget, scriptingTarget.pid == pid {
            app = scriptingTarget.app
        } else {
            // A big library's bulk read can take a few seconds.
            guard let created = SBApplication.runningInstance(pid: pid, timeoutSeconds: 15) else { return nil }
            app = created
            scriptingTarget = (pid, created)
        }
        return body(app as MusicApplication)
    }

    // MARK: Reading

    private static func librarySource(of app: MusicApplication) -> MusicSource? {
        guard let sources = app.sources?() else { return nil }
        for index in 0..<sources.count {
            guard let source = sources.object(at: index) as? SBObject else { continue }
            if (source as MusicSource).kind == .library { return source }
        }
        return sources.count > 0 ? sources.object(at: 0) as? SBObject : nil
    }

    private static func libraryPlaylist(in source: MusicSource) -> MusicPlaylist? {
        guard let playlists = source.libraryPlaylists?(), playlists.count > 0 else { return nil }
        return playlists.object(at: 0) as? SBObject
    }

    /// User playlists (made by hand) first, then Apple Music playlists added
    /// to the library, then smart playlists. Folders and the built-in special
    /// lists (Library, Music, Purchased, Genius) are skipped.
    private static func readPlaylists(in source: MusicSource) -> [MusicLibraryItem] {
        var regular: [MusicLibraryItem] = []
        var smart: [MusicLibraryItem] = []
        var subscribed: [MusicLibraryItem] = []

        if let userPlaylists = source.userPlaylists?() {
            let names = bulk(userPlaylists, "name")
            let ids = bulk(userPlaylists, "persistentID")
            let smartFlags = bulk(userPlaylists, "smart")
            let specialKinds = bulk(userPlaylists, "specialKind")
            let durations = bulk(userPlaylists, "duration")
            if names.count == ids.count {
                for index in names.indices {
                    guard let name = names[index] as? String, !name.isEmpty,
                          let id = ids[index] as? String, !id.isEmpty else { continue }
                    let special = value(specialKinds, at: index).flatMap(fourCharCode)
                    guard MusicPlaylistFilter.includes(specialKind: special) else { continue }
                    let isSmart = (value(smartFlags, at: index) as? NSNumber)?.boolValue ?? false
                    let seconds = (value(durations, at: index) as? NSNumber)?.intValue ?? 0
                    let kind: MusicLibraryItem.Kind = isSmart ? .smartPlaylist : .playlist
                    let item = MusicLibraryItem(
                        id: id,
                        kind: kind,
                        title: name,
                        subtitle: MusicPlaylistFilter.subtitle(kind: kind, durationSeconds: seconds)
                    )
                    if isSmart { smart.append(item) } else { regular.append(item) }
                }
            }
        }

        if let subscriptionPlaylists = source.subscriptionPlaylists?() {
            let names = bulk(subscriptionPlaylists, "name")
            let ids = bulk(subscriptionPlaylists, "persistentID")
            if names.count == ids.count {
                for index in names.indices {
                    guard let name = names[index] as? String, !name.isEmpty,
                          let id = ids[index] as? String, !id.isEmpty else { continue }
                    subscribed.append(MusicLibraryItem(
                        id: id, kind: .playlist, title: name, subtitle: "Apple Music Playlist"
                    ))
                }
            }
        }

        var seen = Set<String>()
        return (regular + subscribed + smart).filter { seen.insert($0.id).inserted }
    }

    /// The library's most recently played songs (falling back to the most
    /// recently added when nothing has a play date yet).
    private static func readRecentSongs(in source: MusicSource) -> [MusicLibraryItem] {
        guard let library = libraryPlaylist(in: source),
              let tracks = library.tracks?(), tracks.count > 0 else { return [] }

        var indices = MusicRecency.topIndices(dates: bulk(tracks, "playedDate"), limit: recentSongLimit)
        if indices.isEmpty {
            indices = MusicRecency.topIndices(dates: bulk(tracks, "dateAdded"), limit: recentSongLimit)
        }
        let total = tracks.count
        return indices.compactMap { index in
            guard index < total, let track = tracks.object(at: index) as? SBObject else { return nil }
            return songItem(from: track)
        }
    }

    private static func songItem(from track: SBObject) -> MusicLibraryItem? {
        let song = track as MusicTrack
        guard let id = song.persistentID, !id.isEmpty,
              let name = song.name, !name.isEmpty else { return nil }
        let artist = song.artist ?? ""
        return MusicLibraryItem(id: id, kind: .song, title: name, subtitle: artist.isEmpty ? "Song" : artist)
    }

    /// Resolves an item back to a live reference by persistent ID.
    private static func object(for item: MusicLibraryItem, in app: MusicApplication) -> SBObject? {
        let predicate = NSPredicate(format: "persistentID == %@", item.id)
        let source = librarySource(of: app)
        let candidates: SBElementArray?
        if item.kind.isCollection {
            candidates = source?.playlists?() ?? app.playlists?()
        } else if let source, let library = libraryPlaylist(in: source) {
            candidates = library.tracks?()
        } else {
            candidates = nil
        }
        guard let candidates, let filtered = whose(candidates, predicate), filtered.count > 0 else {
            return nil
        }
        return filtered.object(at: 0) as? SBObject
    }

    /// `filteredArrayUsingPredicate:` sent directly so the result stays a
    /// lazy `SBElementArray` (a `whose` clause evaluated by Music). Swift's
    /// bridged `filtered(using:)` would copy it into an `[Any]`, fetching
    /// every element.
    private static func whose(_ elements: SBElementArray, _ predicate: NSPredicate) -> SBElementArray? {
        elements.perform(NSSelectorFromString("filteredArrayUsingPredicate:"), with: predicate)?
            .takeUnretainedValue() as? SBElementArray
    }

    private static func bulk(_ elements: SBElementArray, _ property: String) -> [Any] {
        elements.array(byApplying: NSSelectorFromString(property))
    }

    private static func value(_ values: [Any], at index: Int) -> Any? {
        values.indices.contains(index) ? values[index] : nil
    }

    private static func fourCharCode(_ value: Any) -> AEKeyword? {
        if let number = value as? NSNumber { return number.uint32Value }
        if let descriptor = value as? NSAppleEventDescriptor { return descriptor.enumCodeValue }
        return nil
    }
}

/// Pure rules for which Music playlists the empty state offers.
enum MusicPlaylistFilter {
    /// Built-in lists that aren't "a playlist you'd pick": the whole
    /// library, folders, Genius, Purchased.
    static let excludedSpecialKinds: Set<AEKeyword> = [
        MusicESpK.folder.rawValue,
        MusicESpK.genius.rawValue,
        MusicESpK.library.rawValue,
        MusicESpK.music.rawValue,
        MusicESpK.purchasedMusic.rawValue,
    ]

    static func includes(specialKind: AEKeyword?) -> Bool {
        guard let specialKind else { return true }
        return !excludedSpecialKinds.contains(specialKind)
    }

    static func subtitle(kind: MusicLibraryItem.Kind, durationSeconds: Int) -> String {
        guard durationSeconds > 0 else { return kind.label }
        return "\(kind.label) · \(formattedDuration(durationSeconds))"
    }

    static func formattedDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) hr \(minutes) min" : "\(hours) hr"
        }
        return "\(max(1, minutes)) min"
    }
}

enum MusicRecency {
    /// Indices of the `limit` most recent dates (newest first); entries
    /// without a date (missing value / NSNull) are ignored.
    static func topIndices(dates: [Any], limit: Int) -> [Int] {
        dates.enumerated()
            .compactMap { index, value -> (Int, Date)? in
                guard let date = value as? Date, date > .distantPast else { return nil }
                return (index, date)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
