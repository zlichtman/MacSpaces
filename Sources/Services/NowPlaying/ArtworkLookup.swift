import AppKit

/// Album covers for players that don't hand theirs over (Spotify when macOS's
/// now-playing info is unavailable to MacSpaces and its AppleScript gives none,
/// some browsers). Looks the album up on Apple's iTunes Search, then Deezer's, both public: only
/// the artist and album (or title) are sent, no account is used. A cover is
/// accepted only when the artist and album both match, so a wrong cover never shows.
final class ArtworkLookup {
    static let shared = ArtworkLookup()

    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private var pending = Set<String>()
    private var misses = Set<String>()
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    static func key(artist: String, album: String, title: String) -> String {
        "\(normalized(artist))|\(normalized(album.isEmpty ? title : album))"
    }

    func cached(artist: String, album: String, title: String) -> NSImage? {
        cache.object(forKey: Self.key(artist: artist, album: album, title: title) as NSString)
    }

    /// Calls back on the main queue with the cover, or nil when none matches.
    func fetch(artist: String, album: String, title: String, completion: @escaping (NSImage?) -> Void) {
        let key = Self.key(artist: artist, album: album, title: title)
        guard !artist.isEmpty, !(album.isEmpty && title.isEmpty) else { completion(nil); return }
        if let image = cache.object(forKey: key as NSString) { completion(image); return }
        lock.lock()
        let skip = misses.contains(key) || !pending.insert(key).inserted
        lock.unlock()
        guard !skip else { completion(nil); return }
        search(Source.allCases, artist: artist, album: album, title: title) { [weak self] image in
            self?.finish(key, image: image, completion: completion)
        }
    }

    /// Apple's catalog first, then Deezer's (both public and keyless); the first
    /// source with a matching cover wins.
    enum Source: CaseIterable { case iTunes, deezer }

    private func search(_ sources: [Source], artist: String, album: String, title: String, completion: @escaping (NSImage?) -> Void) {
        guard let source = sources.first, let url = Self.searchURL(source, artist: artist, album: album, title: title) else {
            completion(nil); return
        }
        let next = Array(sources.dropFirst())
        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { completion(nil); return }
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            guard let cover = Self.pick(Self.candidates(source, json), artist: artist, name: album.isEmpty ? title : album) else {
                self.search(next, artist: artist, album: album, title: title, completion: completion)
                return
            }
            self.session.dataTask(with: cover) { [weak self] data, _, _ in
                if let image = data.flatMap(NSImage.init(data:)) { completion(image) }
                else { self?.search(next, artist: artist, album: album, title: title, completion: completion) }
            }.resume()
        }.resume()
    }

    private func finish(_ key: String, image: NSImage?, completion: @escaping (NSImage?) -> Void) {
        lock.lock()
        pending.remove(key)
        if image == nil { misses.insert(key) }
        lock.unlock()
        if let image { cache.setObject(image, forKey: key as NSString) }
        DispatchQueue.main.async { completion(image) }
    }

    static func searchURL(_ source: Source, artist: String, album: String, title: String) -> URL? {
        switch source {
        case .iTunes:
            var components = URLComponents(string: "https://itunes.apple.com/search")
            components?.queryItems = [
                URLQueryItem(name: "term", value: "\(artist) \(album.isEmpty ? title : album)"),
                URLQueryItem(name: "entity", value: album.isEmpty ? "song" : "album"),
                URLQueryItem(name: "limit", value: "10"),
            ]
            return components?.url
        case .deezer:
            var components = URLComponents(string: album.isEmpty ? "https://api.deezer.com/search" : "https://api.deezer.com/search/album")
            let query = album.isEmpty ? "artist:\"\(artist)\" track:\"\(title)\"" : "artist:\"\(artist)\" album:\"\(album)\""
            components?.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "10")]
            return components?.url
        }
    }

    /// (artist, album or song name, cover URL) from a source's search response.
    static func candidates(_ source: Source, _ json: [String: Any]?) -> [(artist: String, name: String, cover: String)] {
        switch source {
        case .iTunes:
            return (json?["results"] as? [[String: Any]] ?? []).compactMap { result in
                guard let artist = result["artistName"] as? String,
                      let name = (result["collectionName"] ?? result["trackName"]) as? String,
                      let small = result["artworkUrl100"] as? String else { return nil }
                return (artist, name, small.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
            }
        case .deezer:
            return (json?["data"] as? [[String: Any]] ?? []).compactMap { item in
                guard let artist = (item["artist"] as? [String: Any])?["name"] as? String,
                      let name = item["title"] as? String else { return nil }
                let cover = (item["cover_xl"] ?? (item["album"] as? [String: Any])?["cover_xl"]) as? String
                return cover.map { (artist, name, $0) }
            }
        }
    }

    /// The first candidate whose artist and album (or song) match.
    static func pick(_ candidates: [(artist: String, name: String, cover: String)], artist: String, name: String) -> URL? {
        let wantedArtist = normalized(artist), wantedName = normalized(name)
        guard !wantedArtist.isEmpty, !wantedName.isEmpty else { return nil }
        for candidate in candidates {
            let theirArtist = normalized(candidate.artist)
            guard theirArtist == wantedArtist || theirArtist.hasPrefix(wantedArtist + " "),
                  normalized(candidate.name) == wantedName else { continue }
            return URL(string: candidate.cover)
        }
        return nil
    }

    /// Case, accents, punctuation and edition suffixes (" - Single", "(Deluxe Edition)",
    /// "[Remastered]") don't count.
    static func normalized(_ text: String) -> String {
        var value = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
        for pattern in [#"\s*[\(\[][^\)\]]*[\)\]]"#, #"\s+-\s+(single|ep|deluxe.*|remaster.*|expanded.*)$"#] {
            value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        value = value.replacingOccurrences(of: "&", with: "and")
        value = String(value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " })
        if value.hasPrefix("the ") { value.removeFirst(4) }
        return value.split(separator: " ").joined(separator: " ")
    }
}
