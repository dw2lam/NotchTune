import Foundation

/// Something the empty Music tab can start playing: a playlist, album,
/// artist, song… from the selected player.
struct MusicLibraryItem: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case playlist
        case smartPlaylist
        case album
        case artist
        case song
        case episode
        case show

        var isCollection: Bool { self != .song && self != .episode }

        /// SF Symbol for the artwork placeholder.
        var placeholderSymbol: String {
            switch self {
            case .playlist, .smartPlaylist: "music.note.list"
            case .album: "square.stack"
            case .artist: "music.mic"
            case .song: "music.note"
            case .episode, .show: "mic"
            }
        }

        /// Short noun for subtitles ("Playlist", "Album"…).
        var label: String {
            switch self {
            case .playlist: "Playlist"
            case .smartPlaylist: "Smart Playlist"
            case .album: "Album"
            case .artist: "Artist"
            case .song: "Song"
            case .episode: "Episode"
            case .show: "Podcast"
            }
        }
    }

    /// Player-native handle: an Apple Music persistent ID (hex) or a
    /// `spotify:` URI. Doubles as the identity.
    var id: String
    var kind: Kind
    var title: String
    var subtitle: String
    /// Remote cover (Spotify). Apple Music artwork is read from the app.
    var artworkURL: URL?
    /// Last time NotchTune saw / started it playing.
    var lastPlayedAt: Date?

    init(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String,
        artworkURL: URL? = nil,
        lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.lastPlayedAt = lastPlayedAt
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(needle)
            || subtitle.localizedCaseInsensitiveContains(needle)
    }
}

/// What a player's library looked like the last time NotchTune read it.
/// Cached so the empty state can offer it while the player is closed.
struct MusicLibrarySnapshot: Codable, Equatable, Sendable {
    var playlists: [MusicLibraryItem]
    var songs: [MusicLibraryItem]
    var fetchedAt: Date

    static let empty = MusicLibrarySnapshot(playlists: [], songs: [], fetchedAt: .distantPast)
}

/// Pure list rules for the NotchTune-kept "recently played" history.
enum MusicPlaybackHistory {
    static let defaultCapacity = 40

    /// Moves `item` to the front (stamped `playedAt`), dropping any older
    /// entry with the same id, and trims the list to `capacity`.
    static func recording(
        _ item: MusicLibraryItem,
        into history: [MusicLibraryItem],
        playedAt: Date = .now,
        capacity: Int = defaultCapacity
    ) -> [MusicLibraryItem] {
        var stamped = item
        stamped.lastPlayedAt = playedAt
        var updated = history.filter { $0.id != item.id }
        updated.insert(stamped, at: 0)
        if updated.count > capacity {
            updated.removeLast(updated.count - capacity)
        }
        return updated
    }

    /// Most recently played first; never-played entries keep their order
    /// after the played ones.
    static func sortedByRecency(_ items: [MusicLibraryItem]) -> [MusicLibraryItem] {
        items.enumerated().sorted { lhs, rhs in
            switch (lhs.element.lastPlayedAt, rhs.element.lastPlayedAt) {
            case let (l?, r?) where l != r: return l > r
            case (.some, .none): return true
            case (.none, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }
        .map(\.element)
    }
}
