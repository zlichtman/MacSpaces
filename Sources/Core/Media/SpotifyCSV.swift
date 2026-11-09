import Foundation

/// CSV for Spotify backups: one row per song, quoted where needed, and safe to open in a
/// spreadsheet (a field starting with =, +, - or @ gets a leading apostrophe so it isn't
/// run as a formula).
enum SpotifyCSV {
    static let songHeader = ["Title", "Artists", "Album", "Added", "ISRC", "Spotify link"]
    static let playlistHeader = ["Playlist", "Owner", "Songs", "Spotify link"]

    static func field(_ value: String) -> String {
        var text = value
        if let first = text.first, "=+-@".contains(first) { text = "'" + text }
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func line(_ fields: [String]) -> String { fields.map(field).joined(separator: ",") }

    static func document(header: [String], rows: [[String]]) -> String {
        ([line(header)] + rows.map(line)).joined(separator: "\r\n") + "\r\n"
    }

    /// The rows of a document `document` wrote, with each field back as it was given.
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var quoted = false
        var scalars = text.unicodeScalars.makeIterator()
        var next = scalars.next()
        func take() -> String {
            let value = String(field)
            if value.count >= 2, value.first == "'", let second = value.dropFirst().first, "=+-@".contains(second) { return String(value.dropFirst()) }
            return value
        }
        while let scalar = next {
            next = scalars.next()
            if quoted {
                if scalar == "\"" {
                    if next == "\"" { field.append(scalar); next = scalars.next() } else { quoted = false }
                } else {
                    field.append(scalar)
                }
            } else if scalar == "\"" {
                quoted = true
            } else if scalar == "," {
                row.append(take()); field = String.UnicodeScalarView()
            } else if scalar == "\n" || scalar == "\r" {
                if scalar == "\r", next == "\n" { next = scalars.next() }
                row.append(take()); field = String.UnicodeScalarView()
                rows.append(row); row = []
            } else {
                field.append(scalar)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(take()); rows.append(row) }
        return rows
    }

    /// A file name for a playlist: no slashes or colons, never empty or hidden.
    static func fileName(_ name: String) -> String {
        let cleaned = name.map { "/:\\".contains($0) ? "-" : $0 }.reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return String((cleaned.isEmpty ? "Untitled" : cleaned).prefix(120))
    }
}
