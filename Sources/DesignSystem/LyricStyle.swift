import Foundation

/// How the Music page sets the current lyric. Every style takes the theme's
/// accent and ink, so it suits any palette; animated styles move only while
/// theme effects may animate, and hold still under Reduce Motion.
enum LyricStyle: String, CaseIterable, Identifiable, Codable {
    case classic, poster, stanza, choreography, waterformed, bloom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .poster: return "Lyric poster"
        case .stanza: return "Stanza stage"
        case .choreography: return "Phrase choreography"
        case .waterformed: return "Waterformed"
        case .bloom: return "Psychedelic bloom"
        }
    }

    var summary: String {
        switch self {
        case .classic: return "The current line in the accent colour, the next one beneath."
        case .poster: return "The line's boldest word set large, like a gig poster."
        case .stanza: return "The lines before and after, rolling past a spotlight."
        case .choreography: return "Each word steps into place in turn."
        case .waterformed: return "Letters riding a slow swell above their reflection."
        case .bloom: return "Shifting colour that glows and blooms."
        }
    }

    /// Styles that move on their own between lines.
    var isAnimated: Bool { self == .waterformed || self == .bloom }
}
