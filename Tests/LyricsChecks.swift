import Foundation

@main struct LyricsChecks {
    static func main() async {
        records()
        matching()
        localFiles()
        repair()
        adLibs()
        timeline()
        noLyricsLayout()
        await cache()
        print("Lyrics checks passed: record decoding, song matching, local-file timing and embedded lyrics (LRC variants, karaoke SYLT, stray stamps, other cuts), the no-lyrics layout, timing nudges, LRC rests and offsets, uncensoring, line timing and the disk cache")
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

    static func localFiles() {
        // A file is often another cut than the release LRCLIB timed ("Bodies": every upload
        // is 60–149 s, the file 155.36 s): its timing counts only when the lengths agree.
        func record(_ duration: Double?, synced: String? = "[00:03.82]Line one\n[01:15.55]Line two", plain: String? = "Line one\nLine two") -> Lyrics.Record {
            Lyrics.Record(trackName: "Bodies", artistName: "Kendrick Lamar", duration: duration, plainLyrics: plain, syncedLyrics: synced)
        }
        let uploads = [record(135), record(149), record(60)]
        let loose = Lyrics.best(uploads, title: "Bodies", artist: "Kendrick Lamar", duration: 155.36)
        precondition(loose?.isSynced == true && loose?.duration == 149, "Streamed songs keep the nearest timed cut")
        let strict = Lyrics.best(uploads, title: "Bodies", artist: "Kendrick Lamar", duration: 155.36, strictTiming: true)
        precondition(strict != nil && strict?.isSynced == false && strict?.plainLyrics == "Line one\nLine two",
                     "A local file whose length matches no timed upload gets the words, untimed")
        let fitting = Lyrics.best(uploads + [record(155)], title: "Bodies", artist: "Kendrick Lamar", duration: 155.36, strictTiming: true)
        precondition(fitting?.isSynced == true && fitting?.duration == 155, "An upload as long as the file keeps its timing")
        precondition(Lyrics.fittingFile(record(157.5), duration: 155.36).isSynced, "Within the tolerance")
        precondition(!Lyrics.fittingFile(record(158), duration: 155.36).isSynced, "Outside the tolerance")
        precondition(!Lyrics.fittingFile(record(nil), duration: 155.36).isSynced, "An upload of unknown length can't be trusted for a file")
        precondition(!Lyrics.fittingFile(record(155), duration: 0).isSynced, "Nor can a file of unknown length")
        precondition(!Lyrics.fittingFile(record(70, synced: "[00:03.00]a\n[01:20.00]b"), duration: 70).isSynced,
                     "A line after the file's end means another cut, whatever the stored length")
        let wordsOnly = Lyrics.fittingFile(record(149, plain: nil), duration: 155.36)
        precondition(wordsOnly.plainLyrics == "Line one\nLine two" && !wordsOnly.isSynced, "Without plain text, the LRC's words stand in")
        let untimed = Lyrics.lines(from: strict!, fallbackDuration: 155.36)
        precondition(untimed.count == 2 && untimed[1].start > 70, "Untimed words spread over the file")
        // Stricter timing never lets another song in.
        precondition(Lyrics.best([Lyrics.Record(trackName: "Bodies", artistName: "Someone Else", duration: 155, plainLyrics: "x", syncedLyrics: nil)],
                                 title: "Bodies", artist: "Kendrick Lamar", duration: 155, strictTiming: true) == nil)

        // Lyrics saved in the file: LRC text is timed, header tags dropped; plain text is untimed.
        let lrc = Lyrics.embeddedLines("[ar:Kendrick Lamar]\n[ti:Bodies]\n[00:04.00]First\n[00:09.50]Second\n[00:20.00]", duration: 155)
        precondition(lrc.timed && lrc.lines.map(\.text) == ["First", "Second", Lyrics.rest] && lrc.lines[1].start == 9.5, "Embedded LRC keeps its timing")
        let plain = Lyrics.embeddedLines("[ar:Kendrick Lamar]\nFirst line\n\nSecond line\n", duration: 100)
        precondition(!plain.timed && plain.lines.map(\.text) == ["First line", "Second line"] && plain.lines[1].start == 50, "Plain embedded lyrics are untimed")
        precondition(Lyrics.embeddedLines("  \n", duration: 100).lines.isEmpty && Lyrics.embeddedLines(nil, duration: 100).lines.isEmpty)
        // ID3 SYLT: encoding, language, format 2 (ms), content type, descriptor, then text + 32-bit start.
        func stamp(_ ms: UInt32) -> [UInt8] { [UInt8(ms >> 24 & 0xff), UInt8(ms >> 16 & 0xff), UInt8(ms >> 8 & 0xff), UInt8(ms & 0xff)] }
        var utf8: [UInt8] = [3] + Array("eng".utf8) + [2, 1] + Array("Lyrics".utf8) + [0]
        utf8 += Array("Second".utf8) + [0] + stamp(9500) + Array("First".utf8) + [0] + stamp(4000) + [0] + stamp(20000)
        let sylt = Lyrics.parseSYLT(Data(utf8))
        precondition(sylt?.map(\.text) == ["First", "Second", Lyrics.rest] && sylt?.first?.start == 4, "SYLT lines in time order")
        var utf16: [UInt8] = [1] + Array("eng".utf8) + [2, 1, 0xff, 0xfe, 0, 0]
        utf16 += [0xff, 0xfe] + Array("Hé".utf16).flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] } + [0, 0] + stamp(1500)
        precondition(Lyrics.parseSYLT(Data(utf16))?.first.map { $0.text == "Hé" && $0.start == 1.5 } == true, "UTF-16 SYLT")
        precondition(Lyrics.parseSYLT(Data([3] + Array("eng".utf8) + [1, 1, 0] + Array("A".utf8) + [0] + stamp(10))) == nil, "MPEG-frame stamps are not read")
        precondition(Lyrics.parseSYLT(Data([3, 0x65])) == nil && Lyrics.parseSYLT(Data()) == nil, "Truncated frames give nothing")
        let fromSYLT = Lyrics.embeddedLines("plain words", synced: sylt ?? [], duration: 155)
        precondition(fromSYLT.timed && fromSYLT.lines.first?.text == "First", "Timed lines beat plain text")

        // LRC as taggers write it: colon or comma fractions, milliseconds, no fraction,
        // enhanced word stamps, and a decimal offset.
        let variants = Lyrics.parseLRC("[00:04:50]Colon\n[00:06,25]Comma\n[00:08.125]Millis\n[00:10]Whole\n[00:12.00]<00:12.00>Word <00:12.40>by <00:12.80>word")
        precondition(variants.map(\.text) == ["Colon", "Comma", "Millis", "Whole", "Word by word"], "Every LRC stamp variant reads, word stamps dropped")
        precondition(variants.map(\.start) == [4.5, 6.25, 8.125, 10, 12], "Fractions are fractions of a second")
        precondition(Lyrics.parseLRC("[offset:+500.0]\n[00:10.00]Sooner").first?.start == 9.5, "A positive offset shows lines sooner")
        precondition(Lyrics.parseLRC("[offset:-250]\n[00:10.00]Later").first?.start == 10.25, "A negative offset later")
        precondition(Lyrics.parseLRC("[00:10.00]First\n[00:10.00]Second").map(\.text) == ["First", "Second"], "Lines stamped alike keep their order")
        let colonEmbedded = Lyrics.embeddedLines("[ti:Song]\n[00:04:00]One\n[00:09:50]Two", duration: 120)
        precondition(colonEmbedded.timed && colonEmbedded.lines.map(\.start) == [4, 9.5], "Embedded colon-stamped LRC is timed, not shown with its stamps")
        // Plain embedded text that only mentions a time is plain, and stray stamps leave the words.
        let mention = Lyrics.embeddedLines("Meet me at the station\n[10:30] on the platform\nWe never said goodbye\nAnd the train pulled out", duration: 200)
        precondition(!mention.timed && mention.lines.count == 4 && mention.lines[1].text == "on the platform",
                     "A lyric with one timestamp is not LRC")
        precondition(Lyrics.lines(fromPlain: "[Chorus]\nSung line\n[Verse 2: Someone]\nAnother", duration: 100).map(\.text) == ["Sung line", "Another"],
                     "Section labels aren't lyrics")
        // Embedded timed lyrics that run past the file's end came from another cut: untimed.
        let otherCut = Lyrics.embeddedLines("[00:05.00]Early\n[03:40.00]Past the end", duration: 150)
        precondition(!otherCut.timed && otherCut.lines.map(\.text) == ["Early", "Past the end"], "Embedded LRC longer than the file shows untimed")
        let longSYLT = Lyrics.embeddedLines(nil, synced: [(5, "Early"), (220, "Late")], duration: 150)
        precondition(!longSYLT.timed, "So does a SYLT frame longer than the file")
        precondition(Lyrics.embeddedLines("[00:05.00]a\n[02:30.50]b", duration: 150).timed, "Within a second of the end still fits")
        // Karaoke SYLT: a syllable per entry, each line opened by a newline.
        var karaoke: [UInt8] = [3] + Array("eng".utf8) + [2, 1, 0]
        for (text, ms) in [("\nHel", 1000), ("lo ", 1300), ("world", 1600), ("\nSec", 4000), ("ond", 4400)] as [(String, UInt32)] {
            karaoke += Array(text.utf8) + [0] + stamp(ms)
        }
        let joined = Lyrics.parseSYLT(Data(karaoke))
        precondition(joined?.map(\.text) == ["Hello world", "Second"] && joined?.map(\.start) == [1, 4], "Karaoke syllables join into lines")
        var trailing: [UInt8] = [3] + Array("eng".utf8) + [2, 1, 0]
        for (text, ms) in [("One ", 1000), ("line\n", 1500), ("Two", 3000)] as [(String, UInt32)] {
            trailing += Array(text.utf8) + [0] + stamp(ms)
        }
        precondition(Lyrics.parseSYLT(Data(trailing))?.map(\.text) == ["One line", "Two"], "A trailing newline ends the line")

        // A per-song nudge: steps, clamps, resets and forgets the oldest songs first.
        var saved = LyricNudge.adjusted([:], key: "local|a", by: LyricNudge.step)
        saved = LyricNudge.adjusted(saved, key: "local|a", by: LyricNudge.step)
        precondition(LyricNudge.value(in: saved, key: "local|a") == 1 && LyricNudge.value(in: saved, key: "other") == 0)
        precondition(LyricNudge.value(in: LyricNudge.adjusted(saved, key: "local|a", by: -1), key: "local|a") == 0
                     && (LyricNudge.adjusted(saved, key: "local|a", by: -1)["values"] as? [String: Double])?.isEmpty == true,
                     "Back to zero forgets the song")
        precondition(LyricNudge.value(in: LyricNudge.adjusted(saved, key: "local|a", by: nil), key: "local|a") == 0, "Reset")
        precondition(LyricNudge.value(in: LyricNudge.adjusted([:], key: "k", by: 99), key: "k") == LyricNudge.limit, "Clamped")
        var many: [String: Any] = [:]
        for index in 0...LyricNudge.capacity { many = LyricNudge.adjusted(many, key: "song\(index)", by: 0.5) }
        precondition(LyricNudge.value(in: many, key: "song0") == 0 && LyricNudge.value(in: many, key: "song\(LyricNudge.capacity)") == 0.5
                     && (many["order"] as? [String])?.count == LyricNudge.capacity, "The oldest nudge goes first")
        precondition(LyricNudge.label(0.5) == "0.5 s earlier" && LyricNudge.label(-2) == "2 s later")
        precondition(LyricNudge.value(in: nil, key: "x") == 0)
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

    static func adLibs() {
        let child = Lyrics.asides("Sipping on that lean, a rebellious child(rebellious child)")
        precondition(child.sung == "Sipping on that lean, a rebellious child" && child.asides == ["rebellious child"],
                     "An ad-lib glued to a word comes off it")
        let open = Lyrics.asides("I can feel it in my eyelids(yo-yo-yo-yo-yo")
        precondition(open.sung == "I can feel it in my eyelids" && open.asides == ["yo-yo-yo-yo-yo"], "An unclosed ad-lib runs to the end")
        precondition(Lyrics.asides("(Ooh, ooh)").sung == "Ooh, ooh", "A line that's all ad-lib is sung")
        precondition(Lyrics.asides("Plain line").asides.isEmpty && Lyrics.asides("Plain line").sung == "Plain line")
        precondition(Lyrics.asides("[Chorus] hold on").sung == "hold on")
    }

    static func timeline() {
        let lines = Lyrics.parseLRC("[00:10.00]First\n[00:14.00]Second\n[00:20.00]\n[00:30.00]Third")
            .map { LyricLine(start: $0.start, end: nil, text: $0.text) }
        let song = LyricTimeline(lines: lines, timed: true, duration: 40)
        // The intro shows nothing; the first line arrives a beat early.
        let intro = song.position(at: 5)
        precondition(intro.index == nil && intro.current == Lyrics.rest)
        precondition(song.position(at: 10 - LyricTimeline.lead - 0.01).current == Lyrics.rest)
        precondition(song.position(at: 10 - LyricTimeline.lead).current == "First", "A sung line shows the lead early")
        // A rest clears exactly on time, so the outgoing line isn't cut short.
        precondition(song.position(at: 19.9).current == "Second", "No lead before a rest")
        precondition(song.position(at: 20).current == Lyrics.rest)
        // Sung spans: to the next line, and the last line to the song's end.
        precondition(song.position(at: 11).span == 10...14)
        precondition(song.position(at: 35).span == 30...40, "The last line fills until the song ends")
        precondition(song.position(at: 25).span == nil, "Rests have no span")
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
    }

    static func noLyricsLayout() {
        // A definite answer moves the layout at once, either way.
        precondition(NoLyricsLayout.centred(.none, elapsed: 0, held: false), "None centres at once")
        precondition(!NoLyricsLayout.centred(.lyrics, elapsed: 0, held: true), "Lyrics found lift it at once")
        precondition(!NoLyricsLayout.centred(.idle, elapsed: 99, held: true), "Nothing playing never centres")
        // While looking: the previous layout holds for the grace period, then the lyric layout.
        precondition(NoLyricsLayout.centred(.looking, elapsed: 0.2, held: true), "Between two songs without lyrics it stays down")
        precondition(!NoLyricsLayout.centred(.looking, elapsed: 0.2, held: false), "Opening the page never starts centred")
        precondition(!NoLyricsLayout.centred(.looking, elapsed: NoLyricsLayout.grace + 0.1, held: true), "A real wait shows the lyric layout")
        // No answer by the deadline counts as none for the layout.
        precondition(NoLyricsLayout.centred(.looking, elapsed: NoLyricsLayout.deadline, held: false), "A slow lookup still settles")
        precondition(NoLyricsLayout.grace < 1 && NoLyricsLayout.deadline <= 6, "Bounded: an answer within a few seconds")
        precondition(NoLyricsLayout.nextChange(.looking, elapsed: 0.1).map { abs($0 - (NoLyricsLayout.grace - 0.1)) < 0.001 } == true)
        precondition(NoLyricsLayout.nextChange(.looking, elapsed: 1).map { abs($0 - (NoLyricsLayout.deadline - 1)) < 0.001 } == true)
        precondition(NoLyricsLayout.nextChange(.looking, elapsed: 9) == nil && NoLyricsLayout.nextChange(.none, elapsed: 0) == nil)
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
        // LRCLIB's "no match" with lyrics.ovh unreachable is kept, checked again sooner.
        let partial = LyricsCache.Entry(lines: [], timed: false, saved: Date(), recheck: Date().addingTimeInterval(LyricsCache.partialRecheck))
        precondition(!partial.isStale(), "A replay soon after shows the cached none at once")
        precondition(partial.isStale(at: Date().addingTimeInterval(LyricsCache.partialRecheck + 1)), "Then it's looked up again")
        await writer.store(partial, for: "track|partial")
        await writer.save()
        let reread = await LyricsCache(url: url).entry(for: "track|partial")
        precondition(reread?.recheck != nil, "The re-check date survives a relaunch")
        precondition(LyricsCache.Entry(lines: [], timed: false, saved: Date(), recheck: Date()).lines.isEmpty)
        // An older file's entries (no recheck field) still read.
        let legacy = Data(#"{"version":1,"entries":{"track|old":{"lines":[],"timed":false,"saved":0}}}"#.utf8)
        try? legacy.write(to: url)
        let legacyEntry = await LyricsCache(url: url).entry(for: "track|old")
        precondition(legacyEntry != nil && legacyEntry?.recheck == nil, "Entries saved before the field still decode")
        let bounded = LyricsCache(url: nil)
        for index in 0...LyricsCache.limit {
            await bounded.store(.init(lines: timed.lines, timed: true, saved: Date(timeIntervalSince1970: Double(index))), for: "\(index)")
        }
        let oldest = await bounded.entry(for: "0"), newest = await bounded.entry(for: "\(LyricsCache.limit)")
        precondition(oldest == nil && newest != nil, "The oldest songs leave first")
    }
}
