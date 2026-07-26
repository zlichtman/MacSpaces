import AppKit

/// Player-agnostic snapshot of what is currently playing.
struct NowPlayingInfo: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var isPlaying: Bool = false
    var artwork: NSImage?
    var duration: TimeInterval = 0
    var elapsed: TimeInterval = 0
    var sourceURL: URL?
    var subtitleText: String = ""

    var hasTrack: Bool { !title.isEmpty }

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.isPlaying == rhs.isPlaying
            && abs(lhs.duration - rhs.duration) < 0.5
            && abs(lhs.elapsed - rhs.elapsed) < 0.5
            && lhs.sourceURL == rhs.sourceURL
            && lhs.subtitleText == rhs.subtitleText
            && (lhs.artwork == nil) == (rhs.artwork == nil)
    }
}

enum NowPlayingCommand: Equatable {
    case togglePlayPause
    case nextTrack
    case previousTrack
    case seek(to: TimeInterval)
}

protocol NowPlayingProvider {
    var isAvailable: Bool { get }
    func fetchNowPlaying(_ completion: @escaping (NowPlayingInfo?) -> Void)
    func send(_ command: NowPlayingCommand)
}
