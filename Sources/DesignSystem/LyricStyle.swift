import Foundation

/// How the Music page sets the current lyric, in either look. Both take the theme's accent and
/// ink, so they suit any palette. Every retired style (Classic, Mood, Scenes, Karaoke and the rest,
/// removed at the owner's request) reads back as the default, Poster.
enum LyricStyle: String, CaseIterable, Identifiable, Codable {
    case poster, terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .poster: return "Poster"
        case .terminal: return "Terminal"
        }
    }
}
