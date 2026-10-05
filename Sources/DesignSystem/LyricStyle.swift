import Foundation

/// How the Music page sets the current lyric. Every style takes the theme's
/// accent and ink, so it suits any palette. Retired styles (2.46's Stanza
/// stage, Waterformed and Psychedelic bloom) read back as Classic.
enum LyricStyle: String, CaseIterable, Identifiable, Codable {
    case classic, poster, choreography

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .poster: return "Poster"
        case .choreography: return "Choreography"
        }
    }

    var summary: String {
        switch self {
        case .classic: return "The current line in the accent colour, the next one beneath."
        case .poster: return "The line's boldest word set large, like a gig poster."
        case .choreography: return "Each word steps into place in turn."
        }
    }
}
