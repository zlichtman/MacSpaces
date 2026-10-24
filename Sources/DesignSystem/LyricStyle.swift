import Foundation

/// How the Music page sets the current lyric. Every style takes the theme's
/// accent and ink, so it suits any palette. Retired styles (2.46's Stanza
/// stage, Waterformed and Psychedelic bloom) read back as Classic.
enum LyricStyle: String, CaseIterable, Identifiable, Codable {
    case classic, poster, choreography, stickers, karaoke, typewriter

    var id: String { rawValue }

    /// Styles whose motion follows the song's clock within a line.
    var followsSong: Bool { self == .karaoke || self == .typewriter }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .poster: return "Poster"
        case .choreography: return "Choreography"
        case .stickers: return "Stickers"
        case .karaoke: return "Karaoke"
        case .typewriter: return "Typewriter"
        }
    }

    var summary: String {
        switch self {
        case .classic: return "The current line in the accent colour, the next one beneath."
        case .poster: return "The line's boldest word set large, like a gig poster."
        case .choreography: return "Each word steps into place in turn."
        case .stickers: return "Poster, with a little animation when a line mentions a heart, a map, the rain, fire, the stars and more."
        case .karaoke: return "The line fills in with your accent colour over the time it's sung."
        case .typewriter: return "Each line types itself out as it's sung, with a blinking cursor."
        }
    }
}
