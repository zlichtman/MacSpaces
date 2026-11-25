import Foundation

/// One saved occurrence of a song in a backup. The playlist is part of its identity, so a song
/// taken out of one playlist but kept in another still shows as a change.
struct SpotifyBackupSong: Hashable, Sendable {
    var title: String
    var artists: String
    var album: String
    var isrc: String
    var link: String
    var playlist: String
    var playlistID: String?
    /// The album art, when the backup saved it (from 4.33). Not part of what makes it a change.
    var cover: URL? = nil

    /// The songs in one backup CSV (`SpotifyCSV.songHeader`), skipping its header.
    static func rows(csv: String, playlist: String, playlistID: String? = nil) -> [SpotifyBackupSong] {
        SpotifyCSV.rows(csv).dropFirst().compactMap { row in
            guard row.count >= SpotifyCSV.songColumnsBeforeCover else { return nil }
            return SpotifyBackupSong(title: row[0], artists: row[1], album: row[2], isrc: row[4], link: row[5],
                                     playlist: playlist, playlistID: playlistID,
                                     cover: row.count > 6 && !row[6].isEmpty ? URL(string: row[6]) : nil)
        }
    }

    fileprivate var song: String { link.isEmpty ? "\(title)|\(artists)" : link }

    fileprivate var playlistName: String {
        playlist.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    fileprivate var collection: String { playlistID.map { "id:\($0)" } ?? playlistName }
}

/// What changed between two backups. Order isn't compared, so reordering a playlist is no change.
struct SpotifyBackupDiff: Equatable, Sendable {
    struct Group: Equatable, Sendable, Identifiable {
        var playlist: String
        var added: [SpotifyBackupSong]
        var removed: [SpotifyBackupSong]
        var id: String { playlist }
    }

    static let likedSongs = "Liked Songs"

    var added: [SpotifyBackupSong]
    var removed: [SpotifyBackupSong]

    /// Each occurrence matches at most one, so a song in a playlist twice counts twice.
    init(current: [SpotifyBackupSong], previous: [SpotifyBackupSong]) {
        var unmatchedCurrent = Set(current.indices)
        var unmatchedPrevious = Set(previous.indices)

        func match(_ key: (SpotifyBackupSong) -> String?, allowed: (SpotifyBackupSong, SpotifyBackupSong) -> Bool = { _, _ in true }) {
            var buckets: [String: [Int]] = [:]
            for index in previous.indices.reversed() where unmatchedPrevious.contains(index) {
                if let value = key(previous[index]) { buckets[value, default: []].append(index) }
            }
            for index in current.indices where unmatchedCurrent.contains(index) {
                guard let value = key(current[index]), let candidates = buckets[value],
                      let position = candidates.lastIndex(where: { allowed(current[index], previous[$0]) }) else { continue }
                unmatchedCurrent.remove(index)
                unmatchedPrevious.remove(candidates[position])
                buckets[value]?.remove(at: position)
            }
        }
        // The same song in the same playlist, followed through a rename by its ID.
        match { "\($0.song)|\($0.collection)" }
        // A backup without playlist IDs matches by name, but two playlists with different
        // known IDs are never the same one.
        match({ "\($0.song)|\($0.playlistName)" }, allowed: { $0.playlistID == nil || $1.playlistID == nil })
        // Spotify can swap a song's link for the same recording on another release.
        match { $0.isrc.isEmpty ? nil : "\($0.isrc)|\($0.collection)" }

        added = current.indices.filter(unmatchedCurrent.contains).map { current[$0] }
        removed = previous.indices.filter(unmatchedPrevious.contains).map { previous[$0] }
    }

    var isEmpty: Bool { added.isEmpty && removed.isEmpty }

    /// Changes by playlist, by name, with Liked Songs first.
    var groups: [Group] {
        var byName: [String: Group] = [:]
        for song in added { byName[song.playlist, default: Group(playlist: song.playlist, added: [], removed: [])].added.append(song) }
        for song in removed { byName[song.playlist, default: Group(playlist: song.playlist, added: [], removed: [])].removed.append(song) }
        return byName.values.sorted {
            if ($0.playlist == Self.likedSongs) != ($1.playlist == Self.likedSongs) { return $0.playlist == Self.likedSongs }
            return $0.playlist.localizedCaseInsensitiveCompare($1.playlist) == .orderedAscending
        }
    }
}

/// Where a cover stands in the Music page's Shelf, a row of covers, by how far it is from the
/// front one in songs (negative to the left). The front cover is whole; each step out is smaller
/// and fainter, and all stand on one line. The playing song's record slides out to the right of its
/// cover (`record`, 0 in the sleeve to 1 out), pushing the covers on that side along. Flat: size and
/// fade only, never 3D.
struct SongShelfPose: Equatable {
    /// Its middle across from the front cover's, in front-cover widths.
    var x: CGFloat
    var scale: CGFloat
    var opacity: Double

    /// The covers drawn on each side of the front one.
    static let reach = 3
    /// Each cover's size, 0 the front one, then out to `reach` steps away.
    static let sizes: [CGFloat] = [1, 0.66, 0.52, 0.42]
    static let fades: [Double] = [1, 0.8, 0.5, 0]
    /// The space between two covers, in front-cover widths.
    static let gap: CGFloat = 0.07
    /// How far the record shows past its cover's right edge, out, in front-cover widths.
    static let peek: CGFloat = 0.36

    /// The middle of the cover `steps` whole songs to the right of the front one.
    static func centre(_ steps: Int) -> CGFloat {
        var x: CGFloat = 0
        for step in stride(from: 1, through: min(steps, reach), by: 1) { x += sizes[step - 1] / 2 + gap + sizes[step] / 2 }
        return x
    }

    init(distance: CGFloat, record: CGFloat = 0) {
        let away = min(abs(distance), CGFloat(Self.reach))
        let near = Int(away.rounded(.down)), far = min(near + 1, Self.reach), part = away - CGFloat(near)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * part }
        scale = mix(Self.sizes[near], Self.sizes[far])
        opacity = Double(mix(CGFloat(Self.fades[near]), CGFloat(Self.fades[far])))
        let across = mix(Self.centre(near), Self.centre(far))
        // The record pushes along only the covers to its right, by as much as it shows.
        x = distance < 0 ? -across : across + Self.peek * max(0, min(1, record)) * min(1, distance)
    }

    /// A position in a crate of `count` songs, kept in it.
    static func clamped(_ position: CGFloat, count: Int) -> CGFloat {
        max(0, min(CGFloat(max(0, count - 1)), position))
    }
}

/// Where the Shelf goes when the source it shows has no songs (Liked Songs empty, or a playlist
/// Spotify can't find or won't give out): the first playlist, in the menu's order, that has songs
/// and hasn't already come up empty. A playlist whose count isn't known yet is worth a try.
enum SongShelfFallback {
    struct Candidate: Equatable {
        var id: String
        var total: Int?
    }

    static func next(_ playlists: [Candidate], skipping empty: Set<String>) -> String? {
        playlists.first { $0.total != 0 && !empty.contains($0.id) }?.id
    }
}
