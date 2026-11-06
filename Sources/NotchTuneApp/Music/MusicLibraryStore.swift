import Foundation

/// On-disk memory for the empty Music tab, kept locally in
/// `~/Library/Application Support/NotchTune/Music/library.json`:
/// - the last Apple Music library read (so playlists show while Music is closed)
/// - Spotify pins (links the user pasted) and the Spotify tracks NotchTune
///   has seen playing.
/// Nothing leaves the Mac.
struct MusicLibraryArchive: Codable, Equatable, Sendable {
    var appleMusic: MusicLibrarySnapshot?
    var spotifyPins: [MusicLibraryItem] = []
    var spotifyHistory: [MusicLibraryItem] = []

    init(
        appleMusic: MusicLibrarySnapshot? = nil,
        spotifyPins: [MusicLibraryItem] = [],
        spotifyHistory: [MusicLibraryItem] = []
    ) {
        self.appleMusic = appleMusic
        self.spotifyPins = spotifyPins
        self.spotifyHistory = spotifyHistory
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appleMusic = try container.decodeIfPresent(MusicLibrarySnapshot.self, forKey: .appleMusic)
        // Pins are what the user typed in; one bad entry can't cost the rest.
        let pins = try container.decodeIfPresent([LossyElement<MusicLibraryItem>].self, forKey: .spotifyPins) ?? []
        spotifyPins = pins.compactMap(\.value)
        let history = try container.decodeIfPresent([LossyElement<MusicLibraryItem>].self, forKey: .spotifyHistory) ?? []
        spotifyHistory = history.compactMap(\.value)
    }
}

@MainActor
final class MusicLibraryStore {
    /// `nil` keeps everything in memory (tests, harness runs).
    let fileURL: URL?
    private(set) var archive: MusicLibraryArchive

    init(fileURL: URL?, seed: MusicLibraryArchive = MusicLibraryArchive()) {
        self.fileURL = fileURL
        guard let fileURL else {
            archive = seed
            return
        }

        let outcome = RecoverableJSONFile(url: fileURL).load(
            decode: { data in
                .init(value: try JSONDecoder.musicLibrary.decode(MusicLibraryArchive.self, from: data), isComplete: true)
            },
            merge: { survivors, _ in survivors }
        )
        switch outcome {
        case let .intact(decoded), let .recovered(decoded):
            archive = decoded
        case .missing, .lost:
            archive = seed
        }
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        return applicationSupport
            .appendingPathComponent("NotchTune", isDirectory: true)
            .appendingPathComponent("Music", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    func update(_ mutate: (inout MusicLibraryArchive) -> Void) {
        var updated = archive
        mutate(&updated)
        guard updated != archive else { return }
        archive = updated
        save()
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try RecoverableJSONFile(url: fileURL).write(JSONEncoder.musicLibrary.encode(archive))
        } catch {
            // Best effort: losing the cache only costs a re-read / re-pin.
        }
    }
}

private extension JSONEncoder {
    static var musicLibrary: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var musicLibrary: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
