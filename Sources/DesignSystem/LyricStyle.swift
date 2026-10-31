import Foundation

/// How the Music page sets the current lyric. Every style takes the theme's
/// accent and ink, so it suits any palette. Retired styles (2.46's Stanza
/// stage, Waterformed and Psychedelic bloom, 3.22's Neon) read back as the default. `stickers`
/// is shown as Scenes; its saved value stays so the choice carries over.
enum LyricStyle: String, CaseIterable, Identifiable, Codable {
    case classic, poster, mood, choreography, stickers, karaoke, typewriter
    case cinema, departure

    var id: String { rawValue }

    /// Styles whose motion follows the song's clock within a line.
    var followsSong: Bool { self == .karaoke || self == .typewriter }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .poster: return "Poster"
        case .mood: return "Mood"
        case .choreography: return "Choreography"
        case .stickers: return "Scenes"
        case .karaoke: return "Karaoke"
        case .typewriter: return "Typewriter"
        case .cinema: return "Cinema"
        case .departure: return "Departure"
        }
    }

    var summary: String {
        switch self {
        case .classic: return "One line, with the next just below."
        case .poster: return "Bold type. One word takes the lead."
        case .mood: return "Atmosphere that moves with the line."
        case .choreography: return "Words arrive one step at a time."
        case .stickers: return "Little scenes inspired by the words."
        case .karaoke: return "Colour sweeps through the line."
        case .typewriter: return "Letters appear as the line is sung."
        case .cinema: return "Wide-screen words. A slow close-up."
        case .departure: return "Letters turn. The next line is calling."
        }
    }
}
