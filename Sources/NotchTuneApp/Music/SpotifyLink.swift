import Foundation

/// Turns whatever Spotify's Share → Copy link produces (or a raw URI) into a
/// playable `spotify:` URI. Pure and offline.
enum SpotifyLink {
    struct Parsed: Equatable, Sendable {
        var uri: String
        var kind: MusicLibraryItem.Kind
        var id: String

        /// The canonical `open.spotify.com` page (used for the title lookup).
        var webURL: URL? {
            URL(string: "https://open.spotify.com/\(Self.pathComponent(for: kind))/\(id)")
        }

        fileprivate static func pathComponent(for kind: MusicLibraryItem.Kind) -> String {
            switch kind {
            case .playlist, .smartPlaylist: "playlist"
            case .album: "album"
            case .artist: "artist"
            case .song: "track"
            case .episode: "episode"
            case .show: "show"
            }
        }
    }

    private static let kindsByType: [String: MusicLibraryItem.Kind] = [
        "playlist": .playlist,
        "album": .album,
        "artist": .artist,
        "track": .song,
        "episode": .episode,
        "show": .show,
    ]

    /// `true` for share links that only redirect (`spotify.link/…`): they
    /// can't be resolved without a network round-trip.
    static func isShortLink(_ text: String) -> Bool {
        let host = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased()
        return host == "spotify.link" || host == "spoti.fi" || host?.hasSuffix(".app.link") == true
    }

    static func parse(_ text: String) -> Parsed? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("spotify:") {
            return parseURI(trimmed)
        }

        var candidate = trimmed
        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }
        guard let components = URLComponents(string: candidate),
              let host = components.host?.lowercased(),
              host == "open.spotify.com" || host == "play.spotify.com" else {
            return nil
        }
        let segments = components.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        return parse(segments: segments)
    }

    private static func parseURI(_ uri: String) -> Parsed? {
        let parts = uri.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        // spotify:<type>:<id> or legacy spotify:user:<name>:playlist:<id>
        guard parts.count >= 3, parts[0].lowercased() == "spotify" else { return nil }
        // Local files (`spotify:local:artist:album:title:secs`) and ads aren't
        // replayable by URI.
        guard !["local", "ad"].contains(parts[1].lowercased()) else { return nil }
        return parse(segments: Array(parts.dropFirst()))
    }

    /// Finds the last `<type>/<id>` pair, skipping locale (`intl-de`),
    /// `embed` and legacy `user/<name>` prefixes.
    private static func parse(segments: [String]) -> Parsed? {
        guard segments.count >= 2 else { return nil }
        for index in stride(from: segments.count - 2, through: 0, by: -1) {
            let type = segments[index].lowercased()
            guard let kind = kindsByType[type] else { continue }
            let id = segments[index + 1]
            guard isValidID(id) else { return nil }
            return Parsed(uri: "spotify:\(type):\(id)", kind: kind, id: id)
        }
        return nil
    }

    private static func isValidID(_ id: String) -> Bool {
        (16...32).contains(id.count) && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

/// Optional, best-effort title + cover lookup for a pinned Spotify link via
/// Spotify's public oEmbed endpoint (no account, no token). Pinning never
/// depends on it: offline, the pin keeps a generic title.
protocol SpotifyLinkMetadataResolving: Sendable {
    func resolve(_ link: SpotifyLink.Parsed) async -> (title: String, artworkURL: URL?)?
}

struct SpotifyOEmbedResolver: SpotifyLinkMetadataResolving {
    private struct Response: Decodable {
        var title: String?
        var thumbnail_url: String?
    }

    func resolve(_ link: SpotifyLink.Parsed) async -> (title: String, artworkURL: URL?)? {
        guard let page = link.webURL,
              var components = URLComponents(string: "https://open.spotify.com/oembed") else { return nil }
        components.queryItems = [URLQueryItem(name: "url", value: page.absoluteString)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let title = decoded.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        return (title, decoded.thumbnail_url.flatMap(URL.init(string:)))
    }
}
