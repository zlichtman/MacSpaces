import Foundation

/// A song Spotify plays from a file on this Mac. Spotify names it
/// "spotify:local:Artist:Album:Title:Seconds", each field URL-encoded with "+" for spaces;
/// it shares no cover (its artwork link is empty and oEmbed knows nothing of it).
struct SpotifyLocalTrack: Equatable, Hashable {
    var artist: String
    var album: String
    var title: String
    /// Whole seconds, as Spotify writes them; nil when the URI leaves it out.
    var seconds: Int?

    init(artist: String, album: String, title: String, seconds: Int?) {
        self.artist = artist; self.album = album; self.title = title; self.seconds = seconds
    }

    init?(uri: String) {
        let prefix = "spotify:local:"
        guard uri.hasPrefix(prefix) else { return nil }
        let fields = uri.dropFirst(prefix.count).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 3 else { return nil }
        func decoded(_ field: String) -> String {
            let spaced = field.replacingOccurrences(of: "+", with: " ")
            return spaced.removingPercentEncoding ?? spaced
        }
        artist = decoded(fields[0])
        album = decoded(fields[1])
        title = decoded(fields[2])
        seconds = fields.count > 3 ? Int(fields[3]) : nil
        guard !title.isEmpty else { return nil }
    }

    /// The cache key: the track's identity as Spotify's local ID spells it.
    var id: String { "\(artist)|\(album)|\(title)|\(seconds.map(String.init) ?? "")" }
}

/// Finds the file a local track plays from, in Spotify's own index of local files
/// (`local-files.bnk` in each `Users/<name>-user` folder) or, failing that, among the
/// files in the folders Spotify watches (`watch-sources.bnk`). Both are Spotify's private
/// formats, read tolerantly: anything that doesn't parse is skipped, and no match keeps
/// the placeholder. Pure, so the checks can run it on samples.
enum SpotifyLocalFiles {
    struct Entry: Equatable {
        var title: String
        var artist: String
        var album: String
        var seconds: Int
        var path: String
    }

    /// The audio files Spotify plays from local folders.
    static let audioExtensions: Set<String> = ["mp3", "m4a", "m4p", "mp4", "aac", "flac", "wav", "aif", "aiff", "alac"]

    /// How far the seconds may differ: Spotify rounds, players report fractions.
    static let secondsTolerance = 2

    // MARK: Spotify's index

    /// Each record is three tagged strings (0x09, a varint length, UTF-8: title, artist,
    /// album), a tagged varint (0x10: seconds), a few fields, then the file's absolute path
    /// as another length-prefixed string.
    static func entries(inIndex data: Data) -> [Entry] {
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes.starts(with: Array("SPCO".utf8)) else { return [] }
        var entries: [Entry] = []
        var index = 4
        while index < bytes.count {
            guard let (title, afterTitle) = taggedString(bytes, at: index), !title.isEmpty,
                  let (artist, afterArtist) = taggedString(bytes, at: afterTitle),
                  let (album, afterAlbum) = taggedString(bytes, at: afterArtist),
                  afterAlbum < bytes.count, bytes[afterAlbum] == 0x10,
                  let (seconds, afterSeconds) = varint(bytes, at: afterAlbum + 1),
                  let (path, afterPath) = absolutePath(bytes, from: afterSeconds, within: 48) else {
                index += 1
                continue
            }
            entries.append(Entry(title: title, artist: artist, album: album, seconds: seconds, path: path))
            index = afterPath
        }
        return entries
    }

    /// The folders Spotify watches for local files: the absolute paths in `watch-sources.bnk`'s
    /// gzip payload (already inflated by the caller).
    static func sourceFolders(inWatchSources inflated: Data) -> [String] {
        let bytes = [UInt8](inflated)
        var folders: [String] = []
        var index = 0
        while index < bytes.count {
            if let (path, end) = absolutePath(bytes, from: index, within: 1), !folders.contains(path) {
                folders.append(path)
                index = end
            } else {
                index += 1
            }
        }
        return folders
    }

    /// The gzip member inside a `.bnk` file, without its header and trailer, ready for
    /// raw DEFLATE (`NSData.decompressed(using: .zlib)`).
    static func deflatePayload(inBnk data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard let start = (0..<max(0, bytes.count - 1)).first(where: { bytes[$0] == 0x1f && bytes[$0 + 1] == 0x8b }),
              start + 10 <= bytes.count, bytes[start + 2] == 8 else { return nil }
        let flags = bytes[start + 3]
        var offset = start + 10
        if flags & 4 != 0 {   // FEXTRA
            guard offset + 2 <= bytes.count else { return nil }
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        for flag: UInt8 in [8, 16] where flags & flag != 0 {   // FNAME, FCOMMENT
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 2 != 0 { offset += 2 }   // FHCRC
        let end = bytes.count - 8
        guard offset < end else { return nil }
        return Data(bytes[offset..<end])
    }

    // MARK: Matching

    /// The index entry for a track: the same title and artist, the same album when both
    /// name one, and the same length within `secondsTolerance` when both know it. Several
    /// equally good entries for different files are ambiguous, and give none.
    static func match(_ track: SpotifyLocalTrack, in entries: [Entry]) -> Entry? {
        let title = normalized(track.title), artist = normalized(track.artist), album = normalized(track.album)
        let found = entries.filter { entry in
            guard normalized(entry.title) == title else { return false }
            let theirArtist = normalized(entry.artist), theirAlbum = normalized(entry.album)
            if !artist.isEmpty, !theirArtist.isEmpty, theirArtist != artist { return false }
            if !album.isEmpty, !theirAlbum.isEmpty, theirAlbum != album { return false }
            if let seconds = track.seconds, seconds > 0, entry.seconds > 0,
               abs(entry.seconds - seconds) > secondsTolerance { return false }
            return true
        }
        let paths = Set(found.map(\.path))
        return paths.count == 1 ? found.first : nil
    }

    /// The file in a folder listing that is this track: its name is the title, maybe after
    /// a track number ("03 Bodies", "1-03 - Bodies") or the artist ("Kendrick Lamar - Bodies").
    /// A file in a folder named for the artist or album beats one that isn't; a tie gives none.
    /// The caller checks the length against the file before trusting it.
    static func matchPath(_ track: SpotifyLocalTrack, in paths: [String]) -> String? {
        let title = normalized(track.title), artist = normalized(track.artist), album = normalized(track.album)
        guard !title.isEmpty else { return nil }
        var best: (score: Int, paths: [String]) = (0, [])
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let stem = normalized(url.deletingPathExtension().lastPathComponent)
            let named = stem == title || stem == "\(artist) \(title)"
                || stem.range(of: #"^\d{1,3}( \d{1,3})? "#, options: .regularExpression).map { String(stem[$0.upperBound...]) == title } == true
            guard named else { continue }
            let folders = url.deletingLastPathComponent().pathComponents.suffix(3).map(normalized)
            var score = 1
            if !artist.isEmpty, folders.contains(artist) { score += 2 }
            if !album.isEmpty, folders.contains(album) { score += 1 }
            if score > best.score { best = (score, [path]) } else if score == best.score { best.paths.append(path) }
        }
        return best.paths.count == 1 ? best.paths[0] : nil
    }

    /// Case, accents and punctuation don't count; "&" is "and". Brackets stay, so
    /// "Freestyle (2009)" and "Freestyle (2010)" remain different songs.
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "&", with: " and ")
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    // MARK: Reading the format

    private static func varint(_ bytes: [UInt8], at start: Int) -> (Int, Int)? {
        var value = 0, shift = 0, index = start
        while index < bytes.count, shift < 35 {
            let byte = bytes[index]
            value |= Int(byte & 0x7f) << shift
            index += 1
            if byte & 0x80 == 0 { return (value, index) }
            shift += 7
        }
        return nil
    }

    private static func taggedString(_ bytes: [UInt8], at start: Int) -> (String, Int)? {
        guard start < bytes.count, bytes[start] == 0x09,
              let (length, body) = varint(bytes, at: start + 1), length <= 1024, body + length <= bytes.count,
              let text = String(bytes: bytes[body..<body + length], encoding: .utf8),
              !text.unicodeScalars.contains(where: { $0.value < 0x20 }) else { return nil }
        return (text, body + length)
    }

    /// The first length-prefixed absolute path starting within `window` bytes of `start`.
    private static func absolutePath(_ bytes: [UInt8], from start: Int, within window: Int) -> (String, Int)? {
        for offset in start..<min(start + window, bytes.count) {
            guard let (length, body) = varint(bytes, at: offset), length > 1, length <= 4096,
                  body < bytes.count, bytes[body] == 0x2f, body + length <= bytes.count,
                  let path = String(bytes: bytes[body..<body + length], encoding: .utf8),
                  !path.unicodeScalars.contains(where: { $0.value < 0x20 }) else { continue }
            return (path, body + length)
        }
        return nil
    }
}
