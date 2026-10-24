import Foundation

@main struct LyricsChecks {
    static func main() async {
        records()
        matching()
        repair()
        timeline()
        await cache()
        print("Lyrics checks passed: record decoding, song matching, LRC rests and offsets, uncensoring, line timing and the disk cache")
    }

    static func records() {
        let search = Data(#"[{"trackName":"Paul","artistName":"Big Thief","duration":184,"syncedLyrics":"[00:01.00]Fixture"},{"trackName":"Paul","artistName":"Big Thief","duration":null,"plainLyrics":"Fixture"},{"trackName":"Paul","artistName":"Big Thief","plainLyrics":"Fixture"},{"trackName":null,"artistName":"Big Thief","duration":184},{"trackName":"Another","artistName":"Artist","duration":200}]"#.utf8)
        let records = Lyrics.decodeRecords(search)
        precondition(records.count == 4 && records[0].duration == 184 && records[1].duration == nil && records[2].duration == nil
                     && records[3].trackName == "Another", "Null or malformed results do not discard valid search matches")
        precondition(Lyrics.decodeRecords(Data(#"{"error":"unavailable"}"#.utf8)).isEmpty)
        let exact = Lyrics.decodeRecord(Data(#"{"id":1,"trackName":"Paul","artistName":"Big Thief","duration":184,"syncedLyrics":"[00:01.00]Fixture"}"#.utf8))
        precondition(exact?.isSynced == true, "The exact lookup returns one record")
        precondition(Lyrics.decodeRecord(Data(#"{"code":404,"name":"TrackNotFound","message":"Failed to find specified track"}"#.utf8)) == nil,
                     "A not-found body is no record")
    }

    static func matching() {
        // Lyrics: only this song, and timed lyrics only from a cut of the same length.
        let exact = Lyrics.score(title: "Maps", artist: "Yeah Yeah Yeahs", duration: 220, synced: true, hasLyrics: true,
                                 title: "Maps", artist: "Yeah Yeah Yeahs", duration: 219.6)
        let otherCut = Lyrics.score(title: "Maps (Live)", artist: "Yeah Yeah Yeahs", duration: 262, synced: true, hasLyrics: true,
                                    title: "Maps", artist: "Yeah Yeah Yeahs", duration: 219.6)
        precondition(exact != nil && otherCut.map { $0 < exact! } ?? true, "The same-length recording wins")
        precondition(Lyrics.score(title: "Mapping", artist: "Someone Else", duration: 220, synced: true, hasLyrics: true,
                                  title: "Maps", artist: "Yeah Yeah Yeahs", duration: 220) == nil, "A different song is rejected")
        precondition(Lyrics.score(title: "Seasons - Remastered 2024", artist: "Suki Waterhouse", duration: 200, synced: false, hasLyrics: true,
                                  title: "Seasons", artist: "Suki Waterhouse, Friend", duration: 201) != nil, "Edition suffixes and features still match")
        precondition(Lyrics.score(title: "Maps", artist: "Yeah Yeah Yeahs", duration: 262, synced: true, hasLyrics: true,
                                  title: "Maps", artist: "Yeah Yeah Yeahs", duration: 220) == nil, "Incompatible timed lyrics are rejected, even when alone")
        precondition(Lyrics.score(title: "Maps (feat. Yeah Yeah Yeahs)", artist: "Other Artist/Yeah Yeah Yeahs", duration: 220, synced: true, hasLyrics: true,
                                  title: "Maps", artist: "Yeah Yeah Yeahs", duration: 220) == nil, "A featured artist cannot replace the lead artist")
        precondition(Lyrics.score(title: "Maps Again", artist: "Yeah Yeah Yeahs", duration: 220, synced: true, hasLyrics: true,
                                  title: "Maps", artist: "Yeah Yeah Yeahs", duration: 220) == nil, "A title prefix is not the same song")
        // Other languages: the artist or title in another script or spelling still matches the right song.
        precondition(Lyrics.score(title: "Бумеранг", artist: "Vtoroi Ka", duration: 149, synced: false, hasLyrics: true,
                                  title: "Бумеранг", artist: "Второй Ка", duration: 149) != nil, "Cyrillic artist matches its Latin spelling")
        precondition(Lyrics.score(title: "Bumerang", artist: "Второй Ка", duration: 149, synced: false, hasLyrics: true,
                                  title: "Бумеранг", artist: "Второй Ка", duration: 149) != nil, "A transliterated title matches")
        precondition(Lyrics.score(title: "Titi Me Pregunto", artist: "Bad Bunny", duration: 243, synced: true, hasLyrics: true,
                                  title: "Tití Me Preguntó", artist: "Bad Bunny", duration: 243) != nil, "Accents don't matter")
        precondition(Lyrics.score(title: "Бумеранг", artist: "Слава", duration: 193, synced: true, hasLyrics: true,
                                  title: "Бумеранг", artist: "Второй Ка", duration: 149) == nil, "Another artist's song of the same name is rejected")
        precondition(Lyrics.cleanedTrackTitle("Here Comes The Sun - 2019 Mix") == "Here Comes The Sun")
        precondition(Lyrics.cleanedTrackTitle("The Scenic Route (with Rick Ross & Anderson .Paak)") == "The Scenic Route")
        // Of several uploads, the one this long wins.
        let uploads = Lyrics.decodeRecords(Data(#"[{"trackName":"Kiss Them for Me","artistName":"Siouxsie and the Banshees","duration":586,"syncedLyrics":"[00:01.00]a"},{"trackName":"Kiss Them for Me","artistName":"Siouxsie and the Banshees","duration":277,"syncedLyrics":"[00:01.00]b"},{"trackName":"Kiss Them For Me","artistName":"Siouxsie And The Banshees","duration":264,"plainLyrics":"c"}]"#.utf8))
        precondition(Lyrics.best(uploads, title: "Kiss Them For Me", artist: "Siouxsie and the Banshees", duration: 278)?.syncedLyrics == "[00:01.00]b")
    }

    static func repair() {
        // Blanked-out words in LRCLIB lines come back from the full lyrics; real dashes stay.
        let full = "The weather ain't been bad If you're into masochistic bullshit It's bullshit, all of it I said no".split(separator: " ").map(String.init)
        precondition(Lyrics.uncensor("The weather ain't been bad if you're into masochistic -", using: full)
                     == "The weather ain't been bad if you're into masochistic bullshit")
        precondition(Lyrics.uncensor("It's b******t, all of it", using: full) == "It's bullshit, all of it")
        precondition(Lyrics.uncensor("I said - no", using: full) == "I said - no", "A dash used as punctuation stays")
        let lrc = Lyrics.parseLRC("[offset:+500]\n[00:01.00]\n[00:10.00]First\n[00:20.00]\n[00:21.00]\n[00:30.00]Second")
        precondition(lrc.map(\.text) == ["First", Lyrics.rest, "Second"] && abs(lrc[0].start - 9.5) < 0.001,
                     "Breaks become one rest and the offset shifts lines")
        let plain = Lyrics.lines(fromPlain: "One\n\nTwo\nThree\nFour", duration: 200)
        precondition(plain.map(\.start) == [0, 50, 100, 150], "Plain lyrics spread over the song, blank lines dropped")
    }

    static func timeline() {
        let lines = Lyrics.parseLRC("[00:10.00]First\n[00:14.00]Second\n[00:20.00]\n[00:30.00]Third")
            .map { LyricLine(start: $0.start, end: nil, text: $0.text) }
        let song = LyricTimeline(lines: lines, timed: true, duration: 40)
        // The intro shows nothing; the first line arrives a beat early.
        let intro = song.position(at: 5)
        precondition(intro.index == nil && intro.current == Lyrics.rest && intro.upcoming == "First")
        precondition(song.position(at: 10 - LyricTimeline.lead - 0.01).current == Lyrics.rest)
        precondition(song.position(at: 10 - LyricTimeline.lead).current == "First", "A sung line shows the lead early")
        // A rest clears exactly on time, so the outgoing line isn't cut short.
        precondition(song.position(at: 19.9).current == "Second", "No lead before a rest")
        precondition(song.position(at: 20).current == Lyrics.rest && song.position(at: 20).upcoming == "Third")
        // Karaoke spans: to the next line, and the last line to the song's end.
        precondition(song.position(at: 11).span == 10...14)
        precondition(song.position(at: 35).span == 30...40, "The last line fills until the song ends")
        precondition(song.position(at: 25).span == nil, "Rests have no span")
        precondition(abs(LyricTimeline.progress(of: 10...14, at: 12) - 0.5) < 0.0001)
        precondition(LyricTimeline.progress(of: nil, at: 12) == 1, "Untimed lyrics show filled")
        // One timer per change: the next change is exactly the next line or rest.
        precondition(song.nextChange(after: 5) == 10 - LyricTimeline.lead)
        precondition(song.nextChange(after: 16) == 20)
        precondition(song.nextChange(after: 31) == nil)
        // A repeated line is a new position (its own index), so it turns over.
        let chorus = LyricTimeline(lines: [LyricLine(start: 0, text: "Kiss them for me"), LyricLine(start: 4, text: "Kiss them for me")],
                                   timed: true, duration: 10)
        precondition(chorus.position(at: 1).index != chorus.position(at: 5).index)
        // Captions end on their own.
        let captions = LyricTimeline(lines: [LyricLine(start: 1, end: 3, text: "Hello"), LyricLine(start: 8, end: 9, text: "Again")],
                                     timed: true, duration: 20)
        precondition(captions.position(at: 2).current == "Hello" && captions.position(at: 4).current == Lyrics.rest)
        precondition(captions.nextChange(after: 2) == 3)
        // Untimed lyrics have no intro.
        let untimed = LyricTimeline(lines: Lyrics.lines(fromPlain: "A\nB", duration: 100), timed: false, duration: 100)
        precondition(untimed.position(at: 0).current == "A" && untimed.position(at: 0).span == nil)
        // Typewriter finishes early in the line, never slower than 1.1 s.
        precondition(TypewriterTiming.typed(at: 10, span: 10...14) == 0)
        precondition(TypewriterTiming.typed(at: 11.2, span: 10...14) == 1)
        precondition(abs(TypewriterTiming.typed(at: 10.3, span: 10...11) - 0.5) < 0.0001, "A short line types in 60% of its time")
    }

    static func cache() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lyrics-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("lyrics.json")
        let timed = LyricsCache.Entry(lines: [LyricLine(start: 1, text: "Line")], timed: true, saved: Date())
        let writer = LyricsCache(url: url)
        await writer.store(timed, for: "track|A|B|C")
        await writer.store(.init(lines: [], timed: false, saved: Date()), for: "track|none")
        await writer.save()
        let reader = LyricsCache(url: url)
        let restored = await reader.entry(for: "track|A|B|C"), none = await reader.entry(for: "track|none")
        precondition(restored?.lines == timed.lines, "Entries survive a relaunch")
        precondition(none?.lines.isEmpty == true)
        let old = Date().addingTimeInterval(-30 * 86_400)
        precondition(!LyricsCache.Entry(lines: timed.lines, timed: true, saved: old).isStale(), "Timed lyrics stay")
        precondition(LyricsCache.Entry(lines: timed.lines, timed: false, saved: old).isStale(), "Plain lyrics are looked up again")
        precondition(LyricsCache.Entry(lines: [], timed: false, saved: Date().addingTimeInterval(-2 * 86_400)).isStale(), "None found expires in a day")
        precondition(!LyricsCache.Entry(lines: [], timed: false, saved: Date()).isStale())
        let bounded = LyricsCache(url: nil)
        for index in 0...LyricsCache.limit {
            await bounded.store(.init(lines: timed.lines, timed: true, saved: Date(timeIntervalSince1970: Double(index))), for: "\(index)")
        }
        let oldest = await bounded.entry(for: "0"), newest = await bounded.entry(for: "\(LyricsCache.limit)")
        precondition(oldest == nil && newest != nil, "The oldest songs leave first")
    }
}
