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

/// Where a cover sits on the Music page's shelf, by how far it is from the centre in songs.
struct SongShelfPose: Equatable {
    var x: CGFloat
    var scale: CGFloat
    var opacity: Double

    /// The covers drawn each side of the centre.
    static let reach = 5

    init(distance: CGFloat, side: CGFloat) {
        let near = max(-1, min(1, distance)), far = distance - near
        x = (near * 0.72 + far * 0.26) * side
        scale = 1 - 0.2 * abs(near) - 0.05 * abs(far)
        opacity = Double(max(0, min(1, 1 - (abs(distance) - 3) / 1.5)))
    }

    /// A position on a shelf of `count` songs, kept on it.
    static func clamped(_ position: CGFloat, count: Int) -> CGFloat {
        max(0, min(CGFloat(max(0, count - 1)), position))
    }
}

/// One playlist on the All shelf, as far as it has been read.
struct SongShelfSection: Equatable {
    var songs = 0
    /// Its first page has come back.
    var read = false
    var more = false
    /// Its divider and songs. A playlist that turned out empty takes no room.
    var rows: Int { read && songs == 0 && !more ? 0 : 1 + songs }
}

/// What the All shelf reads next, so it asks Spotify only for what you're about to see: the
/// playlist you've stopped on, more of it near the end of what's read, and a playlist coming up
/// within `ahead` songs. Never one behind you, so reading doesn't move what you're looking at.
enum SongShelfPlan {
    static let ahead = 12

    static func next(_ sections: [SongShelfSection], focus: Int) -> Int? {
        var start = 0
        for (index, section) in sections.enumerated() {
            let end = start + section.rows
            if start > focus + ahead { return nil }
            if end > focus {
                if !section.read { return index }
                if section.more, focus + ahead >= end { return index }
            }
            start = end
        }
        return nil
    }
}
