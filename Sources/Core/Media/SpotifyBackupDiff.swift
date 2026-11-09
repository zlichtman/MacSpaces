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

    /// The songs in one backup CSV (`SpotifyCSV.songHeader`), skipping its header.
    static func rows(csv: String, playlist: String, playlistID: String? = nil) -> [SpotifyBackupSong] {
        SpotifyCSV.rows(csv).dropFirst().compactMap { row in
            guard row.count >= SpotifyCSV.songHeader.count else { return nil }
            return SpotifyBackupSong(title: row[0], artists: row[1], album: row[2], isrc: row[4], link: row[5],
                                     playlist: playlist, playlistID: playlistID)
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

/// Where a sleeve stands in the Music page's Shelf, by how far it is from the front in
/// songs. The front one stands up out of the crate; the ones behind it step back to the left,
/// smaller and shaded; one flipped past tips forward towards you and is gone by the next song.
/// Depth is drawn with scale, shade and a squashed height, never 3D.
struct SongShelfPose: Equatable {
    /// Across from the front sleeve, in sleeve widths (negative is to the left, further back).
    var x: CGFloat
    /// How far it rises, in sleeve heights: all stand on one line, so only a hovered one rises.
    var lift: CGFloat
    var scale: CGFloat
    /// Its height as it tips towards you: 1 standing, less as it falls forward.
    var tip: CGFloat
    /// How much darker it is, back in the crate.
    var shade: Double
    var opacity: Double

    /// The sleeves drawn behind the front one.
    static let reach = 5

    init(distance: CGFloat) {
        if distance >= 0 {
            let near = min(distance, 1), far = distance - near
            x = -(near * 0.24 + far * 0.13)
            lift = 0
            scale = 1 - 0.07 * near - 0.04 * far
            tip = 1
            shade = Double(min(0.5, 0.2 * near + 0.08 * far))
            opacity = Double(max(0, min(1, 1 - (distance - 3.5) / 1.5)))
        } else {
            let gone = min(1, -distance)
            x = 0.1 * gone
            lift = 0
            scale = 1
            tip = 1 - 0.7 * gone
            shade = 0
            opacity = Double(max(0, 1 - gone * 1.5))
        }
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
