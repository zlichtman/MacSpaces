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
        // Covers looked up for players that give none: only an exact artist and album match counts.
        let itunes = ArtworkLookup.candidates(.iTunes, ["results": [
            ["artistName": "Ty Dolla $ign", "collectionName": "Here Come the Runts", "artworkUrl100": "https://example.com/wrong/100x100bb.jpg"],
            ["artistName": "AWOLNATION", "collectionName": "Here Come the Runts (Deluxe Edition)", "artworkUrl100": "https://example.com/right/100x100bb.jpg"],
        ]])
        precondition(ArtworkLookup.pick(itunes, artist: "AWOLNATION", name: "Here Come The Runts")?.absoluteString
                     == "https://example.com/right/600x600bb.jpg", "Matching artist and album, edition suffix ignored, at 600 px")
        precondition(ArtworkLookup.pick(itunes, artist: "Kendrick Lamar", name: "Here Come the Runts") == nil,
                     "Another artist's album with the same name is never used")
        let deezer = ArtworkLookup.candidates(.deezer, ["data": [
            ["title": "Here Come the Runts", "artist": ["name": "AWOLNATION"], "cover_xl": "https://example.com/dz.jpg"],
        ]])
        precondition(ArtworkLookup.pick(deezer, artist: "Awolnation", name: "here come the runts")?.absoluteString == "https://example.com/dz.jpg",
                     "Deezer's album results match the same way")
        let song = ArtworkLookup.candidates(.deezer, ["data": [["title": "Reptilia", "artist": ["name": "The Strokes"], "album": ["cover_xl": "https://example.com/r.jpg"]]]])
        precondition(ArtworkLookup.pick(song, artist: "Strokes", name: "Reptilia") != nil, "Songs without an album match by title")
        precondition(ArtworkLookup.normalized("Beyoncé & Jay-Z") == ArtworkLookup.normalized("beyonce and jayz"))
        precondition(ArtworkLookup.searchURL(.deezer, artist: "A", album: "B", title: "C")?.absoluteString.contains("search/album") == true)
        print("Playback checks passed: seek bounds, non-finite values, source/capability updates, wrong-player prevention and artwork lookup matching")
    }
}
