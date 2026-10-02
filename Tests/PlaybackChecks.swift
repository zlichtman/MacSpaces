import AppKit
import Foundation

@main struct PlaybackChecks {
    static func main() {
        precondition(PlaybackValidation.seek(-2, duration: 100) == 0)
        precondition(PlaybackValidation.seek(150, duration: 100) == 100)
        precondition(PlaybackValidation.seek(32, duration: 100) == 32)
        for duration in [0.0, -1, .nan, .infinity] {
            precondition(PlaybackValidation.seek(1, duration: duration) == nil)
        }
        precondition(PlaybackValidation.seek(.nan, duration: 100) == nil)
        precondition(PlaybackValidation.seek(.infinity, duration: 100) == nil)
        var a = NowPlayingInfo()
        a.title = "Track"
        var b = a
        b.capabilities = [.playPause]
        precondition(a != b, "Capability changes must update the UI")
        b = a; b.sourceName = "Spotify"
        precondition(a != b, "Source changes must update the UI")
        var cover = a; cover.artist = "Artist"; cover.album = "Album"; cover.sourceName = "Spotify"
        var partial = cover; partial.album = ""; partial.sourceName = "System player"
        precondition(cover.matchesArtworkTrack(partial), "Sparse system metadata should retain the same cover")
        partial.artist = "Another artist"
        precondition(!cover.matchesArtworkTrack(partial), "Never borrow artwork across artists")
        partial = cover; partial.album = "Different album"
        precondition(!cover.matchesArtworkTrack(partial), "Never borrow a different album cover")
        partial = cover; partial.sourceName = "Music"
        precondition(!cover.matchesArtworkTrack(partial), "Known different players remain separate")
        precondition(NowPlayingCommand.seek(to: 1).capability == .seek)
        precondition(NowPlayingCommand.nextTrack.capability == .next)
        precondition(NowPlayingInfo().capabilities.isEmpty)
        // No player has been selected through a snapshot. A command must not
        // fall back to another running app, and must not request Automation.
        var rejectedUnselected = false
        AppleScriptProvider().send(.togglePlayPause) { result in
            if case .failure(.unavailable) = result { rejectedUnselected = true }
        }
        precondition(rejectedUnselected)
        var rejectedBrowser = false
        BrowserMediaProvider(transport: MediaRemoteProvider()).send(.nextTrack) { result in
            if case .failure(.unavailable) = result { rejectedBrowser = true }
        }
        precondition(rejectedBrowser, "Browser commands must not target an unrelated system player")
        print("Playback checks passed: seek bounds, non-finite values, source/capability updates, and wrong-player prevention")
    }
}
