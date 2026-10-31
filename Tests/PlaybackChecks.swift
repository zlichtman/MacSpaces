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
        // Spotify's own cover: track IDs become oEmbed requests, and the 300 px thumbnail code maps to 640 px.
        precondition(SpotifyCovers.oEmbedURL(trackID: "spotify:track:4uLU6hMCjMI75M1A2tKUQC")?.absoluteString
                     == "https://open.spotify.com/oembed?url=spotify:track:4uLU6hMCjMI75M1A2tKUQC")
        precondition(SpotifyCovers.oEmbedURL(trackID: "spotify:local:Artist:Album:Song:180") == nil, "Local files have no Spotify cover")
        precondition(SpotifyCovers.largeCover("https://i.scdn.co/image/ab67616d00001e02abc")?.absoluteString == "https://i.scdn.co/image/ab67616d0000b273abc")
        // One smooth clock: a reading that agrees with the estimate changes nothing; a
        // seek, pause or new song does.
        var playing = NowPlayingInfo(); playing.title = "Song"; playing.isPlaying = true; playing.elapsed = 10; playing.duration = 200
        var reading = playing; reading.elapsed = 12.1
        precondition(NowPlayingClock.agrees(reading, with: playing, estimate: 12), "Poll jitter does not move the clock")
        reading.elapsed = 12.5
        precondition(!NowPlayingClock.agrees(reading, with: playing, estimate: 12), "A seek in the player moves it")
        reading = playing; reading.elapsed = 12; reading.isPlaying = false
        precondition(!NowPlayingClock.agrees(reading, with: playing, estimate: 12), "Pausing publishes")
        reading = playing; reading.elapsed = 12; reading.title = "Next"
        precondition(!NowPlayingClock.agrees(reading, with: playing, estimate: 12), "A new song publishes")
        // Polling slows when nothing on screen needs the position, and hurries for a missing cover.
        precondition(NowPlayingClock.pollInterval(playing: true, watched: true) < NowPlayingClock.pollInterval(playing: true, watched: false))
        precondition(NowPlayingClock.pollInterval(playing: true, watched: false) < NowPlayingClock.pollInterval(playing: false, watched: false))
        precondition(NowPlayingClock.pollInterval(playing: false, watched: false, awaitingCover: true) <= 0.3)
        // Reused polling scripts compile once and still run correctly.
        let first = AppleScriptRunner.runSynchronously("return 6 * 7", reuse: true)
        let second = AppleScriptRunner.runSynchronously("return 6 * 7", reuse: true)
        precondition(!first.failed && first.descriptor?.int32Value == 42 && second.descriptor?.int32Value == 42)
        precondition(abs(second.midpoint.timeIntervalSinceNow) < 5, "The read time is when the script ran")
        covers()
        titles()
        localFiles()
        print("Playback checks passed: seek bounds, non-finite values, source/capability updates, wrong-player prevention, artwork lookup matching, Spotify covers, local-file covers (spotify:local IDs, Spotify's index and watched folders, file matching), cover look, display titles, artist credits, clock anchoring and polling")
    }

    /// The same cover at another size (or recompressed) is the same picture, so it swaps
    /// without a second fade; another cover, even a similar dark one, is not.
    static func covers() {
        func picture(_ seed: UInt64, side: Int, shift: Int = 0) -> NSImage {
            let image = NSImage(size: NSSize(width: side, height: side))
            image.lockFocus()
            var state = seed
            let cell = CGFloat(side) / 40
            for y in 0..<40 {
                for x in 0..<40 {
                    state = state &* 6364136223846793005 &+ 1442695040888963407
                    let noise = CGFloat(state >> 56) / 255
                    let base = CGFloat((x + y + shift) % 40) / 40
                    NSColor(calibratedRed: base * 0.4 + noise * 0.2, green: noise * 0.25, blue: 0.15 + base * 0.2, alpha: 1).setFill()
                    NSRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell + 0.5, height: cell + 0.5).fill()
                }
            }
            image.unlockFocus()
            return image
        }
        func recompressed(_ image: NSImage) -> NSImage {
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            return NSImage(data: bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6])!)!
        }
        let small = picture(1, side: 300), large = recompressed(picture(1, side: 640))
        precondition(CoverLook.same(small, large), "Spotify's 640 px copy of the 300 px cover is the same picture")
        precondition(CoverLook.same(small, small) && CoverLook.same(nil, nil))
        precondition(!CoverLook.same(small, nil) && !CoverLook.same(nil, small), "A cover and the placeholder differ")
        for shift in [8, 20] {
            precondition(!CoverLook.same(small, picture(2, side: 300, shift: shift)), "Another dark cover in the same colours differs")
        }
    }

    /// Songs Spotify plays from files on this Mac: the local ID, Spotify's index of local
    /// files and watched folders (built here in the layout Spotify 1.2 writes), and matching
    /// a track to its file. Better no cover than another song's.
    static func localFiles() {
        // spotify:local:Artist:Album:Title:Seconds, "+" for spaces, other characters percent-encoded.
        let bodies = SpotifyLocalTrack(uri: "spotify:local:Kendrick+Lamar:Unreleased:Bodies:155")
        precondition(bodies == SpotifyLocalTrack(artist: "Kendrick Lamar", album: "Unreleased", title: "Bodies", seconds: 155))
        precondition(bodies?.id == "Kendrick Lamar|Unreleased|Bodies|155", "Covers are cached by the local ID")
        let escaped = SpotifyLocalTrack(uri: "spotify:local:AC%2FDC:Live%3A+1991:Thunder%2Bstruck+%28Live%29:312")
        precondition(escaped?.artist == "AC/DC" && escaped?.album == "Live: 1991" && escaped?.title == "Thunder+struck (Live)" && escaped?.seconds == 312,
                     "Escaped colons, slashes and plus signs stay inside their field")
        let bare = SpotifyLocalTrack(uri: "spotify:local:::Voice+Memo:")
        precondition(bare?.artist == "" && bare?.album == "" && bare?.title == "Voice Memo" && bare?.seconds == nil, "Untagged files have empty fields")
        precondition(SpotifyLocalTrack(uri: "spotify:track:4uLU6hMCjMI75M1A2tKUQC") == nil, "Streamed tracks are not local")
        precondition(SpotifyLocalTrack(uri: "spotify:local:Artist:Album::10") == nil && SpotifyLocalTrack(uri: "spotify:local:Artist") == nil)

        // Spotify's index (`local-files.bnk`): "SPCO", a name, then per file the title, artist,
        // album (0x09 strings), seconds (0x10 varint), a few fields and the absolute path.
        func varint(_ value: Int) -> [UInt8] {
            var value = value, out: [UInt8] = []
            repeat { var byte = UInt8(value & 0x7f); value >>= 7; if value > 0 { byte |= 0x80 }; out.append(byte) } while value > 0
            return out
        }
        func text(_ string: String) -> [UInt8] { [0x09] + varint(string.utf8.count) + Array(string.utf8) }
        func record(_ title: String, _ artist: String, _ album: String, _ seconds: Int, _ path: String, extra: [UInt8] = []) -> [UInt8] {
            text(title) + text(artist) + text(album) + [0x10] + varint(seconds) + [0xb0, 0x01, 0x00, 0x08, 0x00, 0x08] + extra
                + [0x08, 0xcc, 0xd5, 0x8d, 0xd7, 0x06, 0x2c, 0x01] + varint(path.utf8.count) + Array(path.utf8)
                + [0x08, 0x00, 0x08, 0x00, 0x08, 0xc0, 0x9d, 0xe1, 0x01, 0x08, 0x01, 0x78, 0x78, 0x04]
        }
        let root = "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Music/Local Files"
        var index = Array("SPCO".utf8) + [0x13, 0, 0, 0, 0, 0x11] + Array("LocalFilesStorage".utf8) + [0xe3, 0x1f, 0x60, 0x2d, 0x94, 0x00]
        index += record("Westwood Freestyle (2009)", "Eminem & Mr. Porter", "Freestyles", 509, "\(root)/Eminem/Westwood Freestyle (2009).m4a")
        index += record("Westwood Freestyle (2010)", "Eminem, Royce da 5'9\" & Mr. Porter", "Freestyles", 524, "\(root)/Eminem/Westwood Freestyle (2010).m4a")
        index += record("6:16 in LA", "Kendrick Lamar", "Unreleased", 224, "\(root)/Kendrick Lamar/6-16 in LA.m4a")
        index += record("Bodies", "Kendrick Lamar", "Unreleased", 155, "\(root)/Kendrick Lamar/Bodies.m4a", extra: [0xa1, 0x4a])
        index += record("One Way / Stolen Dance", "Twenty One Pilots", "Unreleased", 253, "\(root)/Twenty One Pilots/One Way - Stolen Dance.m4a")
        index += record("Intro", "Demo", "Tape", 60, "\(root)/Demo/Intro.m4a") + record("Intro", "Demo", "Tape", 75, "\(root)/Demo/Intro (1).m4a")
        index += [0x78, 0x78, 0x00, 0x00]
        let entries = SpotifyLocalFiles.entries(inIndex: Data(index))
        precondition(entries.count == 7, "Every record is read, extra fields and all (got \(entries.count))")
        precondition(entries[3] == .init(title: "Bodies", artist: "Kendrick Lamar", album: "Unreleased", seconds: 155,
                                         path: "\(root)/Kendrick Lamar/Bodies.m4a"))
        precondition(entries[1].artist == "Eminem, Royce da 5'9\" & Mr. Porter")
        precondition(SpotifyLocalFiles.entries(inIndex: Data("not an index".utf8)).isEmpty && SpotifyLocalFiles.entries(inIndex: Data()).isEmpty)
        precondition(SpotifyLocalFiles.entries(inIndex: Data(index.prefix(90))).isEmpty, "A cut-off record is skipped, not misread")

        func file(_ track: SpotifyLocalTrack?, _ list: [SpotifyLocalFiles.Entry] = entries) -> String? {
            track.flatMap { SpotifyLocalFiles.match($0, in: list) }.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        }
        precondition(file(bodies) == "Bodies.m4a", "Zach's Bodies matches its file")
        precondition(file(SpotifyLocalTrack(uri: "spotify:local:kendrick+lamar:UNRELEASED:bodies:156")) == "Bodies.m4a", "Case and a second of rounding don't count")
        precondition(file(SpotifyLocalTrack(uri: "spotify:local:Kendrick+Lamar:Unreleased:Bodies:")) == "Bodies.m4a", "No length in the ID still matches")
        precondition(file(SpotifyLocalTrack(uri: "spotify:local:Kendrick+Lamar:Unreleased:Bodies:140")) == nil, "Another length is another file")
        precondition(file(SpotifyLocalTrack(uri: "spotify:local:Kendrick+Lamar:Untitled+Unmastered.:Bodies:155")) == nil, "Another album is another song")
        precondition(file(SpotifyLocalTrack(uri: "spotify:local:Mac+Miller:Unreleased:Bodies:155")) == nil, "Another artist is another song")
        precondition(file(SpotifyLocalTrack(uri: "spotify:local:Kendrick+Lamar:Unreleased:6%3A16+in+LA:224")) == "6-16 in LA.m4a", "The title, not the file name, is matched")
        precondition(file(SpotifyLocalTrack(uri: "spotify:local:Eminem+%26+Mr.+Porter:Freestyles:Westwood+Freestyle+%282010%29:509")) == nil,
                     "Brackets count: the 2010 freestyle is not the 2009 one")
        precondition(file(SpotifyLocalTrack(uri: "spotify:local:Eminem+%26+Mr.+Porter:Freestyles:Westwood+Freestyle+%282009%29:509")) == "Westwood Freestyle (2009).m4a")
        precondition(file(SpotifyLocalTrack(uri: "spotify:local:Twenty+One+Pilots:Unreleased:One+Way+%2F+Stolen+Dance:253")) == "One Way - Stolen Dance.m4a")
        precondition(file(SpotifyLocalTrack(uri: "spotify:local:Demo:Tape:Intro:")) == nil, "Two files that both fit give no cover")
        precondition(file(SpotifyLocalTrack(uri: "spotify:local:Demo:Tape:Intro:60")) == "Intro.m4a", "The length tells them apart")
        precondition(file(bodies, []) == nil)

        // The folders Spotify watches (`watch-sources.bnk`): a gzip member after a short header.
        let inflated = Data([0x04, 0x01] + varint(root.utf8.count) + Array(root.utf8)
            + [0x08, 0x01, 0x08, 0x01, 0x78, 0x10, 0x00, 0x14, 0x01, 0x05] + Array("Users".utf8) + [0x14, 0x01, 0x04] + Array("LIFE".utf8)
            + [0x15, 0x64, 0x01, 0x0e] + Array("Kendrick Lamar".utf8) + [0x0a] + Array("Bodies.m4a".utf8))
        let deflated = try! (inflated as NSData).compressed(using: .zlib) as Data
        let bnk = Data(Array("SPCO".utf8) + [0x0e, 0, 0, 0, 0x02, 0x0c] + Array("WatchSources".utf8) + [0x61, 0x04]
            + [0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x13] + Array(deflated) + [0, 0, 0, 0, 0, 0, 0, 0])
        let payload = SpotifyLocalFiles.deflatePayload(inBnk: bnk)
        precondition(payload == deflated, "The gzip header and trailer are dropped")
        let roundTrip = try! (payload! as NSData).decompressed(using: .zlib) as Data
        precondition(SpotifyLocalFiles.sourceFolders(inWatchSources: roundTrip) == [root], "Only the watched folder's absolute path is a source")
        precondition(SpotifyLocalFiles.deflatePayload(inBnk: Data("SPCO".utf8)) == nil)

        // Not in the index yet: the file by name in a watched folder.
        let paths = ["\(root)/Kendrick Lamar/Bodies.m4a", "\(root)/Kendrick Lamar/Black Friday (with J. Cole).m4a",
                     "\(root)/Kendrick Lamar/Black Friday.m4a", "\(root)/Mixes/Bodies.mp3", "\(root)/Notes/Prayer.txt",
                     "\(root)/Unreleased/03 Prayer.m4a", "\(root)/Remixes/Kendrick Lamar - N95.flac",
                     "\(root)/A/Song.m4a", "\(root)/B/Song.mp3"]
        func found(_ uri: String) -> String? {
            SpotifyLocalTrack(uri: uri).flatMap { SpotifyLocalFiles.matchPath($0, in: paths) }
                .map { String($0.dropFirst(root.count + 1)) }
        }
        precondition(found("spotify:local:Kendrick+Lamar:Unreleased:Bodies:155") == "Kendrick Lamar/Bodies.m4a", "The artist's folder wins over another Bodies")
        precondition(found("spotify:local:Kendrick+Lamar:Unreleased:Black+Friday:235") == "Kendrick Lamar/Black Friday.m4a", "A featured version is another song")
        precondition(found("spotify:local:Kendrick+Lamar:Unreleased:Black+Friday+%28with+J.+Cole%29:428") == "Kendrick Lamar/Black Friday (with J. Cole).m4a")
        precondition(found("spotify:local:Kendrick+Lamar:Unreleased:Prayer:321") == "Unreleased/03 Prayer.m4a", "A track number before the title counts; other files don't")
        precondition(found("spotify:local:Kendrick+Lamar:Remixes:N95:200") == "Remixes/Kendrick Lamar - N95.flac", "So does the artist before it")
        precondition(found("spotify:local:Nobody:Nothing:Song:100") == nil, "Two files with the same name and no other clue give none")
        precondition(found("spotify:local:Kendrick+Lamar:Unreleased:Sing+About+Me:600") == nil)
    }

    /// Release details move out of the headline; names that only look like them stay.
    static func titles() {
        func check(_ raw: String, _ name: String, _ detail: String?) {
            let title = TrackTitle(raw)
            precondition(title.name == name && title.detail == detail, "\(raw) → \(title.name) | \(title.detail ?? "nil")")
        }
        check("Wonderwall - Remastered", "Wonderwall", "Remastered")
        check("There Is a Light That Never Goes Out - 2017 Master", "There Is a Light That Never Goes Out", "2017 Master")
        check("I Don't Owe You Anything - 2011 Remaster", "I Don't Owe You Anything", "2011 Remaster")
        check("The Scenic Route (with Rick Ross & Anderson .Paak)", "The Scenic Route", "with Rick Ross & Anderson .Paak")
        check("Song (feat. Someone) - Radio Edit", "Song", "feat. Someone · Radio Edit")
        check("Maps [Live]", "Maps", "Live")
        check("Cherry Soda (and the happy medium)", "Cherry Soda (and the happy medium)", nil)
        check("Sight of You", "Sight of You", nil)
        check("Anti-Hero", "Anti-Hero", nil)
        check("Love Song - Love Song", "Love Song - Love Song", nil)
        check("(Remastered)", "(Remastered)", nil)
        // Albums drop their edition details so the artist line fits.
        precondition(TrackTitle.album("Hidden in Pieces: Live at the Royal Albert Hall") == "Hidden in Pieces")
        precondition(TrackTitle.album("(What's The Story) Morning Glory? (Deluxe Remastered Edition)") == "(What's The Story) Morning Glory?")
        precondition(TrackTitle.album("Seasons - Single") == "Seasons" && TrackTitle.album("Mouthful - EP") == "Mouthful")
        precondition(TrackTitle.album("The Queen Is Dead (Deluxe Edition)") == "The Queen Is Dead")
        // Every source, sorted into the same fields.
        let maps = TrackMetadata(title: "Maps - Live at the Royal Albert Hall", artist: "Yeah Yeah Yeahs",
                                 album: "Hidden in Pieces: Live at the Royal Albert Hall")
        precondition(maps.song == "Maps" && maps.artist == "Yeah Yeah Yeahs" && maps.versions == ["Live"]
                     && maps.album == "Hidden in Pieces" && maps.byline == "Yeah Yeah Yeahs · Hidden in Pieces")
        let featuring = TrackMetadata(title: "The Scenic Route (with Rick Ross & Anderson .Paak)", artist: "Dr. Dre", album: "Compton")
        precondition(featuring.song == "The Scenic Route" && featuring.featured == ["Rick Ross & Anderson .Paak"]
                     && featuring.artistLine == "Dr. Dre" && featuring.featuredLabel == "Rick Ross & Anderson .Paak")
        let inArtist = TrackMetadata(title: "Work", artist: "Rihanna feat. Drake", album: "ANTI")
        precondition(inArtist.artist == "Rihanna" && inArtist.featured == ["Drake"] && inArtist.byline == "Rihanna · ANTI")
        let many = TrackMetadata(title: "Song (feat. B)", artist: "A, B & C", album: "Song - Single")
        precondition(many.artist == "A, B & C" && many.featured.isEmpty && many.album == nil, "No repeats; a single's album is the song")
        credits()
        precondition(TrackMetadata(title: "I Don't Owe You Anything - 2011 Remaster", artist: "The Smiths", album: "The Smiths").versions
                     == ["Remastered 2011"])
        precondition(TrackMetadata(title: "Wonderwall - Remastered", artist: "Oasis", album: "x").versions == ["Remastered"])
        precondition(TrackMetadata(title: "Sight of You", artist: "Pale Saints", album: "Mrs. Dolphin").byline == "Pale Saints · Mrs. Dolphin")
        precondition(TrackTitle.album("Mrs. Dolphin") == "Mrs. Dolphin" && TrackTitle.album("Songs: Ohia") == "Songs: Ohia",
                     "A colon in a real name stays")
    }

    /// Artist credits: the main artist stays whole, featured artists come out of the
    /// artist or the title, and "Stage - Real Name" is one artist. Display only.
    static func credits() {
        func check(_ title: String, _ artist: String, _ album: String = "x",
                   song: String, main: String, featured: String?, line: String? = nil) {
            let m = TrackMetadata(title: title, artist: artist, album: album)
            precondition(m.song == song && m.artistLine == main && m.featuredLabel == featured
                         && (line == nil || m.byline == line),
                         "\(title) | \(artist) → \(m.song) | \(m.artistLine) | \(m.featuredLabel ?? "nil") | \(m.byline)")
        }
        // What the player sends for Boy Harsher's "Autonomy" (from the lyrics cache).
        check("Autonomy (Ft. Lucy - Cooper B. Handy)", "Boy Harsher", "The Runner (Original Soundtrack)",
              song: "Autonomy", main: "Boy Harsher", featured: "Lucy", line: "Boy Harsher · The Runner")
        check("Autonomy", "Boy Harsher feat. Lucy - Cooper B. Handy", "The Runner (Original Soundtrack)",
              song: "Autonomy", main: "Boy Harsher", featured: "Lucy", line: "Boy Harsher · The Runner")
        // Every way of writing a feature.
        check("Song", "A ft. B", song: "Song", main: "A", featured: "B")
        check("Song", "A Ft B", song: "Song", main: "A", featured: "B")
        check("Song", "A featuring B", song: "Song", main: "A", featured: "B")
        check("Song", "A (feat. B)", song: "Song", main: "A", featured: "B")
        check("Song", "A (with B)", song: "Song", main: "A", featured: "B")
        check("Song", "A [ft. B & C]", song: "Song", main: "A", featured: "B & C")
        check("Song feat. B", "A", song: "Song", main: "A", featured: "B")
        check("Song (with B)", "A", song: "Song", main: "A", featured: "B")
        check("Song (feat. B)", "A feat. B", song: "Song", main: "A", featured: "B")
        check("Song (feat. C)", "A feat. B", song: "Song", main: "A", featured: "B & C")
        // Band names are never split, and their own words aren't features.
        check("The Boxer", "Simon & Garfunkel", "Bridge over Troubled Water",
              song: "The Boxer", main: "Simon & Garfunkel", featured: nil, line: "Simon & Garfunkel · Bridge over Troubled Water")
        check("September", "Earth, Wind & Fire", song: "September", main: "Earth, Wind & Fire", featured: nil)
        check("Song", "Crosby, Stills, Nash & Young", song: "Song", main: "Crosby, Stills, Nash & Young", featured: nil)
        check("Dog Days Are Over", "Florence + The Machine", song: "Dog Days Are Over", main: "Florence + The Machine", featured: nil)
        check("Song", "Boy with a Coin", song: "Song", main: "Boy with a Coin", featured: nil)
        check("Song", "Daft Punk", song: "Song", main: "Daft Punk", featured: nil)
        check("Song", "Sleater-Kinney", song: "Song", main: "Sleater-Kinney", featured: nil)
        check("Song", "Jay-Z feat. Alicia Keys", song: "Song", main: "Jay-Z", featured: "Alicia Keys")
        check("Get Lucky", "Daft Punk feat. Pharrell Williams & Nile Rodgers", song: "Get Lucky", main: "Daft Punk",
              featured: "Pharrell Williams & Nile Rodgers")
        check("Song (feat. Simon & Garfunkel)", "A", song: "Song", main: "A", featured: "Simon & Garfunkel")
        check("Song (feat. Earth, Wind & Fire)", "A", song: "Song", main: "A", featured: "Earth, Wind & Fire")
        // Titles that only look like features.
        check("Dancing with Myself", "Billy Idol", song: "Dancing with Myself", main: "Billy Idol", featured: nil)
        check("6 Foot 7 Foot", "Lil Wayne", song: "6 Foot 7 Foot", main: "Lil Wayne", featured: nil)
        check("Ten Ft. Tall", "Wavves", song: "Ten Ft. Tall", main: "Wavves", featured: nil)
        check("Feat. of Clay", "A", song: "Feat. of Clay", main: "A", featured: nil)
        // "Stage - Real Name" is one artist; the tag keeps the stage name.
        precondition(ArtistCredit.short("Lucy - Cooper B. Handy") == "Lucy")
        precondition(ArtistCredit.short("Lucy - Cooper B. Handy & Drake") == "Lucy & Drake")
        precondition(ArtistCredit("Lucy - Cooper B. Handy").main == "Lucy - Cooper B. Handy", "The main credit is shown as written")
        // Soundtrack albums lose the "(Original Soundtrack)" so the line fits; real names stay.
        precondition(TrackTitle.album("Drive (Original Motion Picture Soundtrack)") == "Drive")
        precondition(TrackTitle.album("Soundtrack to a Generation") == "Soundtrack to a Generation")
    }
}
