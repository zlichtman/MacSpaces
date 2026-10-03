import AppKit

/// Player-agnostic snapshot of what is currently playing.
struct NowPlayingInfo: Equatable {
    var sourceName = ""
    /// Owning app when the provider knows it; MediaRemote reports none.
    var sourceBundleID: String?
    var capabilities: Set<PlaybackCapability> = []
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

    /// System metadata may omit an album or URL, but conflicting identity must
    /// never borrow the previous track's cover.
    func matchesArtworkTrack(_ other: NowPlayingInfo) -> Bool {
        hasTrack && other.hasTrack && title == other.title && artist == other.artist
            && (album.isEmpty || other.album.isEmpty || album == other.album)
            && (sourceURL == nil || other.sourceURL == nil || sourceURL == other.sourceURL)
            && (sourceName == other.sourceName || sourceName == "System player" || other.sourceName == "System player")
    }
    static let artworkDidLoad = Notification.Name("MacSpaces.NowPlayingArtworkDidLoad")

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.sourceName == rhs.sourceName
            && lhs.sourceBundleID == rhs.sourceBundleID
            && lhs.capabilities == rhs.capabilities
            && lhs.title == rhs.title
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
    var capability: PlaybackCapability {
        switch self {
        case .togglePlayPause: return .playPause
        case .previousTrack: return .previous
        case .nextTrack: return .next
        case .seek: return .seek
        }
    }
}

protocol NowPlayingProvider {
    var isAvailable: Bool { get }
    func fetchNowPlaying(_ completion: @escaping (NowPlayingInfo?) -> Void)
    func send(_ command: NowPlayingCommand, completion: @escaping (Result<Void, PlaybackCommandError>) -> Void)
}
