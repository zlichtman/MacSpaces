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
        mood()
        scenes()
        stickers()
        await cache()
        print("Lyrics checks passed: record decoding, song matching, local-file timing and embedded lyrics (LRC variants, karaoke SYLT, stray stamps, other cuts), the no-lyrics layout, timing nudges, LRC rests and offsets, uncensoring, line timing, Mood treatments, Scenes subjects and pacing, Fluent Emoji matching, and the disk cache")
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

    static func mood() {
        // Pace: words a second over the sung span; untimed lyrics have none and count as medium.
        precondition(MoodTreatment.wordsPerSecond(words: 8, span: 10...12) == 4)
        precondition(MoodTreatment.wordsPerSecond(words: 6, span: nil) == nil)
        precondition(MoodTreatment.wordsPerSecond(words: 3, span: 5...5) == 6, "A zero-length span counts as half a second")
        precondition(MoodTreatment.wordCount("Hold on, hold on - I'm coming") == 6, "Punctuation alone is no word")
        // The choice: short lines with feeling sweep; then feeling picks the family and pace the member.
        precondition(MoodTreatment.choose(sentiment: 0, wordsPerSecond: 2, wordCount: 1) == .sweep, "One word sweeps")
        precondition(MoodTreatment.choose(sentiment: 0.6, wordsPerSecond: 2, wordCount: 3) == .sweep)
        precondition(MoodTreatment.choose(sentiment: 0.1, wordsPerSecond: 2, wordCount: 3) == .aurora, "Three plain words don't")
        precondition(MoodTreatment.choose(sentiment: -0.7, wordsPerSecond: 1.2, wordCount: 7) == .haze, "Sad and slow")
        precondition(MoodTreatment.choose(sentiment: -0.7, wordsPerSecond: 2, wordCount: 7) == .rain)
        precondition(MoodTreatment.choose(sentiment: -0.7, wordsPerSecond: 4.5, wordCount: 9) == .rain, "Sad beats fast")
        precondition(MoodTreatment.choose(sentiment: 0.5, wordsPerSecond: 2, wordCount: 7) == .bloom)
        precondition(MoodTreatment.choose(sentiment: 0.8, wordsPerSecond: 4, wordCount: 9) == .embers, "Warm and fast")
        precondition(MoodTreatment.choose(sentiment: 0, wordsPerSecond: 4, wordCount: 9) == .pulse)
        precondition(MoodTreatment.choose(sentiment: 0.1, wordsPerSecond: 1.2, wordCount: 6) == .drift)
        precondition(MoodTreatment.choose(sentiment: 0, wordsPerSecond: 2.4, wordCount: 6) == .aurora)
        precondition(MoodTreatment.choose(sentiment: 0, wordsPerSecond: nil, wordCount: 9) == .aurora, "Untimed lyrics are medium pace")
        precondition(MoodTreatment.choose(sentiment: 0.5, wordsPerSecond: nil, wordCount: 9) == .bloom)
        precondition(MoodTreatment.choose(sentiment: -0.5, wordsPerSecond: nil, wordCount: 9) == .rain)
        // Every treatment is reachable.
        var reached = Set<MoodTreatment>()
        for sentiment in [-0.8, 0, 0.8] {
            for pace in [1.0, 2.2, 4.0] { reached.insert(MoodTreatment.choose(sentiment: sentiment, wordsPerSecond: pace, wordCount: 8)) }
        }
        reached.insert(MoodTreatment.choose(sentiment: 0, wordsPerSecond: 2, wordCount: 1))
        precondition(reached == Set(MoodTreatment.allCases), "Unreached: \(Set(MoodTreatment.allCases).subtracting(reached))")
        // Sentiment: the model's neutral middle (-0.5) is re-centred to 0; sad words tip a line to Rain.
        precondition(MoodTreatment.calibrated(raw: -0.5, line: "Here comes the sun") == 0)
        precondition(MoodTreatment.calibrated(raw: nil, line: "Maps") == 0, "No score is neutral")
        precondition(MoodTreatment.calibrated(raw: 0.6, line: "It's a beautiful day") > 0.3)
        precondition(MoodTreatment.calibrated(raw: 1, line: "Yes") == 1 && MoodTreatment.calibrated(raw: -1, line: "No") < -0.3)
        let crying = MoodTreatment.calibrated(raw: -0.6, line: "I'm crying in the rain")
        precondition(MoodTreatment.choose(sentiment: crying, wordsPerSecond: 2, wordCount: 5) == .rain)
        precondition(MoodTreatment.calibrated(raw: -0.4, line: "Lonely, I'm so lonely") <= -0.3)
        precondition(MoodTreatment.choose(sentiment: MoodTreatment.calibrated(raw: -0.6, line: "We danced all night under the stars"),
                                          wordsPerSecond: 2, wordCount: 7) == .aurora, "A plain line the model calls negative isn't sad")
        // Tempo and the line's hit follow the pace within bounds; untimed lyrics move at the medium pace.
        precondition(MoodTreatment.tempo(wordsPerSecond: 0.2) == 0.75 && MoodTreatment.tempo(wordsPerSecond: 12) == 1.35)
        precondition(MoodTreatment.tempo(wordsPerSecond: nil) == MoodTreatment.tempo(wordsPerSecond: MoodTreatment.mediumPace))
        precondition(MoodTreatment.tempo(wordsPerSecond: 4) > MoodTreatment.tempo(wordsPerSecond: 2))
        precondition(MoodTreatment.hitStrength(wordsPerSecond: 0.5) == 0.6 && MoodTreatment.hitStrength(wordsPerSecond: 9) == 1)
        precondition(MoodTreatment.hitStrength(wordsPerSecond: 4) > MoodTreatment.hitStrength(wordsPerSecond: 2))
        // Words: syllables weight the onsets, so a long word holds the line longer than "a".
        precondition(MoodTreatment.syllables("a") == 1 && MoodTreatment.syllables("morning") == 2 && MoodTreatment.syllables("summer") == 2)
        precondition(MoodTreatment.syllables("make") == 1, "A silent e")
        precondition(MoodTreatment.syllables("beautiful") == 3 && MoodTreatment.syllables("rhythm") == 1 && MoodTreatment.syllables("Hmm") == 1)
        let onsets = MoodTreatment.wordOnsets(["You", "make", "the", "morning", "feel"], sung: 3)
        precondition(onsets.count == 5 && onsets[0] == 0 && onsets == onsets.sorted() && onsets.last! < 3, "In order, within the line")
        precondition(abs(onsets[4] - onsets[3] - 2 * (onsets[1] - onsets[0])) < 0.0001, "Two syllables take twice as long as one")
        precondition(MoodTreatment.wordOnsets([], sung: 3).isEmpty)
        // Delays from now, against the song's clock: the first word lands as its span starts.
        let delays = MoodTreatment.wordDelays(words: ["Hold", "the", "line"], span: 10...13, songTime: 9.75)!
        precondition(abs(delays[0] - 0.25) < 0.0001 && delays[2] < 3 && delays == delays.sorted())
        precondition(MoodTreatment.wordDelays(words: ["Hold"], span: nil, songTime: 4) == nil, "Untimed lyrics have no word timing")
        precondition(MoodTreatment.wordDelays(words: ["Hold", "on"], span: 10...12, songTime: 11.5)!.first! < 0, "Words already sung are past")
        // Real lines through the whole path, as the Music page reads them.
        let fast = MoodTreatment.wordsPerSecond(words: MoodTreatment.wordCount("We were running through the streets and we were laughing"),
                                                span: 30...32.5)
        precondition(MoodTreatment.choose(sentiment: 0, wordsPerSecond: fast, wordCount: 10) == .pulse)
    }

    static func scenes() {
        // One naming word draws its subject; the headline wins a tie, then the subject named first.
        precondition(LyricSubject.vote("Coins in my pocket and we're spending it all", hero: "spending") == .money)
        precondition(LyricSubject.vote("Headlights on the highway, heading west", hero: "Headlights") == .drive)
        precondition(LyricSubject.vote("Dancing queen, young and sweet", hero: "Dancing") == .dance, "The headline breaks a tie")
        precondition(LyricSubject.vote("Rain on the roses", hero: "roses") == .rose)
        precondition(LyricSubject.vote("Roses in the rain", hero: "Roses") == .rose)
        precondition(LyricSubject.vote("We drove the long road under the stars", hero: "stars") == .stars, "Common words don't outvote a name")
        precondition(LyricSubject.vote("Tonight in the dark of the night", hero: "Tonight") == .moon, "Three common words agree")
        precondition(LyricSubject.vote("It's five o'clock somewhere", hero: "somewhere") == .time, "Apostrophes drop")
        // Common words alone, and words that usually mean something else, draw nothing.
        for (line, hero) in [("I love you", "love"), ("Call it love, love, love", "love"), ("I lost my mind", "lost"),
                             ("I rose above it all", "above"), ("Drive me crazy", "crazy"), ("Running out of time", "Running"),
                             ("Ring ring, it's me again", "again"), ("Can you see me", "see"), ("Hold on", "Hold")] {
            precondition(LyricSubject.vote(line, hero: hero) == nil, "\(line) draws nothing")
        }
        // Real vocabulary across genres; ambiguous slang needs local context.
        let vocabulary: [(String, String, LyricSubject)] = [
            ("Smoke hit my brain, I can feel it in my eyelids(yo-yo-yo-yo-yo", "eyelids", .smoke),
            ("Sipping on that lean, a rebellious child(rebellious child)", "rebellious", .cup),
            ("Sip from my cup", "cup", .cup), ("Purple in my cup", "Purple", .cup),
            ("Sprite in the styrofoam", "styrofoam", .cup), ("My styrofoam cup", "cup", .cup), ("Sippin on lean", "Sippin", .cup),
            ("Pull up in my whip", "whip", .drive), ("Riding in the coupe", "coupe", .drive),
            ("Benz parked outside", "outside", .drive), ("Truck rolling past", "Truck", .drive),
            ("Guap in my pocket", "pocket", .money), ("Counting racks all evening", "racks", .money),
            ("Bands on bands", "bands", .money), ("Getting bread every day", "bread", .money),
            ("Counting cheese", "cheese", .money), ("Chasing the bag", "bag", .money),
            ("Counting stacks", "stacks", .money), ("Stack that cash", "Stack", .money),
            ("Ice on my wrist", "Ice", .diamond), ("Gold chain on my neck", "chain", .diamond),
            ("Drip with diamonds on my wrist", "Drip", .diamond), ("Jewellery catching light", "Jewellery", .diamond),
            ("Back in the hood", "hood", .city), ("On the block", "block", .city), ("These streets remember", "remember", .city),
            ("In the club", "club", .dance), ("Party till tomorrow", "tomorrow", .dance),
            ("Sneakers on the pavement", "Sneakers", .sneakers), ("Fresh kicks on my feet", "kicks", .sneakers),
            ("Wearing my chucks", "chucks", .sneakers), ("Lace up my trainers", "trainers", .sneakers),
            ("Guitar beside the bed", "Guitar", .guitar), ("Sixstring ringing out", "Sixstring", .guitar),
            ("Take the mic", "mic", .microphone), ("Karaoke till tomorrow", "Karaoke", .microphone),
            ("Blunt in the ashtray", "Blunt", .smoke), ("Roll a joint", "joint", .smoke), ("A spliff by the doorway", "spliff", .smoke),
        ]
        for (line, hero, subject) in vocabulary {
            precondition(LyricSubject.vote(line, hero: hero) == subject, "\(line) should draw \(subject)")
        }
        precondition(LyricSubject.vote("Rain, sipping on lean", hero: "lean") == .cup,
                     "The contextual headline breaks a tie even if its supporting word came first")
        let ambiguous = [
            "Lean on me", "I lean into you", "Sipping tea", "A cup of coffee", "Sip the water", "Purple is your colour",
            "Bread and cheese in a bag", "Counting bags of flour", "Stack my books", "Rubber bands on the table",
            "The bands played all evening", "Counting dishes on the racks", "Whip the cream", "Whip me into shape",
            "Ice in the water", "The ice is melting", "Chain me to the past", "A bicycle chain on the floor",
            "Drip from the faucet", "A block of cheese", "Block out the noise", "The hood of my jacket",
            "We started a book club", "Swing the golf club", "Baby girl, shawty, stay with me",
            "I will be blunt", "Weed the garden", "A joint in my knee", "Styrofoam on the ceiling",
            "She kicks me when I'm down", "Personal trainers at the gym", "He chucks it away",
            "I hold on (money cash diamonds)", "Say it again [smoke]", "Lean on me (sipping from a cup)",
        ]
        for line in ambiguous {
            let hero = LyricSubject.words(Lyrics.asides(line).sung).last ?? ""
            precondition(LyricSubject.vote(line, hero: hero) == nil, "\(line) should stay plain")
        }
        precondition(LyricSubject.vote("Rain falls softly (cash cash cash)", hero: "cash") == .rain,
                     "Ad-libs cannot outvote the sung line")
        precondition(LyricSubject.vote("(Smoke)", hero: "Smoke") == .smoke, "An entirely bracketed line is still sung")
        precondition(LyricSubject.vote("Chasing the bag, baking bread", hero: "bread") == nil,
                     "Literal food context wins over slang")
        // A broken heart needs "heart" and a breaking word within three words.
        precondition(LyricSubject.vote("Don't go breaking my heart", hero: "breaking") == .heartbreak)
        precondition(LyricSubject.vote("My heart is broken", hero: "broken") == .heartbreak)
        precondition(LyricSubject.vote("The broken window filled my heart with fear", hero: "window") == .heart)
        precondition(LyricSubject.vote("Heartache tonight", hero: "Heartache") == .heartbreak)
        // Every subject has an anchor for the meaning fallback, and no word names two subjects.
        precondition(LyricSubject.allCases.allSatisfy { LyricSubject.anchors[$0] != nil && LyricSubject.strong[$0] != nil })
        let named = LyricSubject.strong.values.flatMap { $0 }
        precondition(Set(named).count == named.count, "A naming word belongs to one subject")
        precondition(LyricSubject.listed("coins") && LyricSubject.listed("tonight") && LyricSubject.listed("lean") && LyricSubject.listed("bag") && !LyricSubject.listed("lilac"))

        precondition(LyricSubject.meaningExcluded.contains(.cup), "A mug or teacup must not infer purple drink")
        precondition(LyricSubject.vote("Cold frozen ice", hero: "frozen") == .snow, "Literal ice still supports winter")

        // Pacing: the scene enters, acts and settles within 70% of the line, faster for fast singing.
        let fast = LyricChoreography.timing(span: 10...12, words: 9)       // 4.5 words a second
        let slow = LyricChoreography.timing(span: 10...15, words: 6)       // 1.2 words a second
        let untimed = LyricChoreography.timing(span: nil, words: 6)
        precondition(fast.entrance < slow.entrance && fast.action < slow.action && fast.exit < slow.exit, "Fast songs snap")
        precondition(fast.settled <= 2 * 0.7 + 0.0001 && slow.settled <= 5 * 0.7, "Settles before the line ends")
        precondition(untimed.tempo == MoodTreatment.tempo(wordsPerSecond: nil), "Untimed lyrics move at a medium pace")
        precondition(abs(untimed.settled - 1.9 / untimed.tempo) < 0.0001, "An untimed line isn't squeezed")
        let short = LyricChoreography.timing(span: 3...3.6, words: 2)
        precondition(short.entrance >= 0.25 && short.action >= 0.4, "A very short line keeps a readable floor")
        precondition((0.3...0.7).contains(fast.exit) && (0.3...0.7).contains(slow.exit))
        // Beats map to seconds: 0…1 the entrance, 1…2 the action, monotonic and clamped.
        precondition(slow.seconds(atBeat: 0) == 0 && slow.seconds(atBeat: 1) == slow.entrance)
        precondition(abs(slow.seconds(atBeat: 2) - slow.settled) < 0.0001 && slow.seconds(atBeat: 3) == slow.seconds(atBeat: 2))
        precondition(slow.seconds(atBeat: 0.9) < slow.seconds(atBeat: 1.1))
    }

    static func stickers() {
        let index = try! StickerIndex(data: try! Data(contentsOf: URL(fileURLWithPath: "Sources/Resources/sticker-index.json")))
        precondition(index.emoji.count > 1_000, "The whole Fluent set is in the catalog")
        // Every picture the tables name exists, and every curated subject ships its own.
        for name in StickerMatch.mentioned { precondition(index.contains(name), "\(name) is not a Fluent Emoji") }
        precondition(Set(StickerMatch.subjectEmoji.keys) == Set(LyricSubject.allCases))
        for (subject, _) in StickerMatch.subjectEmoji {
            let path = "Sources/Resources/Scenes/scene-\(subject.rawValue)"
            precondition(FileManager.default.fileExists(atPath: path + ".webp") || FileManager.default.fileExists(atPath: path + ".png"),
                         "\(subject) ships its picture")
        }
        // Files come only from Microsoft's GitHub over https, with spaces encoded.
        let wings = index.named("Money with wings")!
        precondition(index.stillURL(wings)?.absoluteString
                     == "https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets/Money%20with%20wings/3D/money_with_wings_3d.png")
        precondition(index.animatedURL(index.named("Fire")!)?.host == "media.githubusercontent.com" && index.animatedURL(wings) == nil)
        precondition(index.emoji.allSatisfy { index.stillURL($0) != nil }, "Every emoji has a still to download")
        // Plurals and possessives.
        precondition(StickerMatch.stems("roses").contains("rose") && StickerMatch.stems("cherries").contains("cherry")
                     && StickerMatch.stems("boxes").contains("box") && StickerMatch.stems("moneys").contains("money")
                     && StickerMatch.stems("octopuss").contains("octopus"))

        // Lines and the poster's headline (its longest word) → the emoji they show.
        let drawn: [(String, String, String)] = [
            // Curated subjects keep their pictures, slang and context included.
            ("Cash in my pocket and we're spending it all", "spending", "Money with wings"),
            ("Sipping on that lean, a rebellious child(rebellious child)", "rebellious", "Cup with straw"),
            ("Pull up in my whip", "whip", "Automobile"), ("Ice on my wrist", "wrist", "Gem stone"),
            ("Don't go breaking my heart", "breaking", "Broken heart"), ("Dancer in the dark", "Dancer", "Mirror ball"),
            ("Lay your cards down on the table", "table", "Joker"), ("Your guitar is leaning by the bed", "leaning", "Guitar"),
            ("Your phone is ringing on the table", "ringing", "Mobile phone"),
            ("Smoke hit my brain, I can feel it in my eyelids(yo-yo-yo-yo-yo", "eyelids", "Fog"),
            // A sharper picture within a subject.
            ("A bottle of champagne on ice", "champagne", "Bottle with popping cork"),
            ("Pour a little whiskey in my glass", "whiskey", "Tumbler glass"), ("Sunset boulevard", "boulevard", "Sunset"),
            ("Thunder rolling in the distance", "distance", "Cloud with lightning and rain"), ("Fire truck", "truck", "Fire engine"),
            ("Coins in my pocket", "pocket", "Coin"), ("Cigarette on the balcony", "Cigarette", "Cigarette"),
            // Two-word names sung together.
            ("Shooting stars across the sky tonight", "Shooting", "Shooting star"), ("Ice cream melting in July", "melting", "Ice cream"),
            ("I saw a black cat cross the road", "cross", "Black cat"), ("Full moon rising", "rising", "Full moon"),
            ("Hot dog at the ball game", "game", "Hot dog"), ("Video games", "games", "Video game"),
            // Any other concrete word, plurals and possessives undone.
            ("Wild horses running through the valley", "running", "Horse"), ("Butterflies in my stomach every time", "Butterflies", "Butterfly"),
            ("You're a snake in the grass", "grass", "Snake"), ("Eating peaches by the lake", "peaches", "Peach"),
            ("We drank coffee till the sun came up", "coffee", "Hot beverage"), ("The ghost of you is in my room", "ghost", "Ghost"),
            ("Like a candle in the wind", "candle", "Candle"), ("Teddy bear on the bed", "Teddy", "Teddy bear"),
            ("The wolf is at the door", "door", "Wolf"), ("Rainbow after the storm", "Rainbow", "Rainbow"),
            ("A tornado in my head", "tornado", "Tornado"), ("The volcano erupts in my chest", "volcano", "Volcano"),
            ("Sunflowers turning to the light", "Sunflowers", "Sunflower"), ("Octopus's garden", "Octopus's", "Octopus"),
            ("Your lips taste like strawberries", "strawberries", "Strawberry"), ("Take the train back home to you", "train", "Train"),
            ("Riding on my motorcycle all night", "motorcycle", "Motorcycle"), ("Turn up the radio", "radio", "Radio"),
            ("Headphones on, world off", "Headphones", "Headphone"), ("The piano in the corner", "corner", "Musical keyboard"),
            ("Selfie in the mirror", "mirror", "Mirror"), ("Knife in my back", "Knife", "Kitchen knife"),
            ("Bubblegum and cotton candy", "Bubblegum", "Candy"), ("Snake eyes", "Snake", "Snake"),
            ("Kiss me under the mistletoe", "mistletoe", "Kiss mark"), ("Write me a letter when you're gone", "letter", "Love letter"),
            ("Glass of milk before bed", "before", "Glass of milk"), ("Lightning strikes twice", "Lightning", "High voltage"),
            // Shared names told apart by the line, or by a usual picture.
            ("Christmas lights on the tree", "Christmas", "Christmas tree"), ("Apples falling from the tree", "falling", "Red apple"),
            ("Map of the world", "world", "World map"), ("Under the palm trees", "Under", "Palm tree"),
            ("The vampire bites at night", "vampire", "Person vampire"), ("Gold medal in my hand", "medal", "1st place medal"),
            ("You're a firework", "firework", "Fireworks"), ("Wise old owl", "Wise", "Owl"),
        ]
        for (line, hero, emoji) in drawn {
            let picked = StickerMatch.pick(line, hero: hero, in: index)
            precondition(picked == emoji, "\(line) should show \(emoji), not \(picked ?? "nothing")")
        }
        // The Scenes capture lines (`StickerLyricCaptures`) show their subject's bundled picture.
        let captured: [(String, String, LyricSubject)] = [
            ("All the money I saved is on the shelf", "shelf", .money), ("Slowly you broke my heart in two", "Slowly", .heartbreak),
            ("The whole crowd is singing our name tonight", "tonight", .crowd), ("Roses on the windowsill in May", "windowsill", .rose),
            ("Dancing till the last of us goes home", "Dancing", .dance), ("My heartbeat keeps on calling out to you", "heartbeat", .heart),
            ("The fire keeps burning into the morning", "morning", .fire), ("Raindrops falling softly on the pavement", "Raindrops", .rain),
            ("Sunshine spilling through the open curtains", "curtains", .sun), ("Moonlight follows every step you take", "Moonlight", .moon),
            ("Starlight scattered all along the way", "scattered", .stars), ("The ocean carries everything away", "carries", .ocean),
            ("City lights are coming on below", "coming", .city), ("Wear your crown and keep your head up", "crown", .crown),
            ("Diamonds catching every little ray", "catching", .diamond), ("Raise your wine and say it once again", "again", .drink),
            ("Fresh kicks on my feet, laces tied", "laces", .sneakers), ("Take the mic and tell them how it feels", "feels", .microphone),
            ("The clock keeps ticking on the wall", "ticking", .time), ("Airplane taking off into the blue", "Airplane", .plane),
            ("Coming home to find you waiting there", "waiting", .home), ("Teardrops running slowly down your cheek", "Teardrops", .tears),
            ("The vinyl plays our favourite melody", "favourite", .music), ("Snowflakes settle softly on the ground", "Snowflakes", .snow),
            ("Your eyes have said it all before", "before", .eyes),
        ]
        for (line, hero, subject) in captured {
            precondition(StickerMatch.pick(line, hero: hero, in: index) == StickerMatch.subjectEmoji[subject], "\(line) shows \(subject)")
        }
        // The headline's own emoji beats a curated word elsewhere in the line; ties go to the curated one.
        precondition(StickerMatch.pick("Tent under the stars", hero: "stars", in: index) == "Glowing star")
        precondition(StickerMatch.pick("Snake eyes", hero: "Snake", in: index) == "Snake")
        // Better none than wrong: everyday words, idioms, other senses, slang and filler draw nothing.
        let plain = [
            "I can't stop thinking about you", "You make me feel so alive", "We were young and wild and free",
            "Every breath you take", "I'm on top of the world", "Shake it off, shake it off", "Just the way you are",
            "We found love in a hopeless place", "Hello from the other side", "Can't feel my face when I'm with you",
            "Old town road", "Back in black", "Sweet child of mine", "You spin me right round", "Hips don't lie",
            "Under pressure, pushing down on me", "Rolling in the deep", "No scrubs, no love", "I'm the man, I'm the man",
            "Keep your head up", "Get low, get low", "Drop it like it's hot", "Gold digger", "No cap in my rap",
            "Bear with me", "Watch me whip, watch me nae nae", "Roll with it", "Lost track of time",
            "In the palm of your hand", "She leaves in the morning", "Jump around", "Shoot your shot", "Gun in my hand",
            "Bullets in the chamber", "Let my guard down", "Off the hook", "Raise a flag", "Cut me deep",
            "On board with you", "Fan of your love", "Score another one", "Set me free", "Leaves are falling",
            "Honey, sugar, baby", "Girl you know it's true", "Living on a prayer", "Born to run", "It's my life",
            "Pills in my pocket", "Lucky charm", "Stairway to heaven", "Welcome to the jungle", "Knight in shining armor",
            "I hold on (cash diamonds)", "Lean on me", "Bread and cheese in a bag", "Whip the cream", "Chain me to the past",
            "Put a ring on it", "Pepper spray", "Watch on my wrist", "Hat trick", "Light it up",
            "Quit it cold turkey", "Break a leg out there", "Kick the bucket", "Bad blood between us",
        ]
        for line in plain {
            let hero = StickerMatch.words(line).max { $0.count < $1.count } ?? ""
            let picked = StickerMatch.pick(line, hero: hero, in: index)
            precondition(picked == nil, "\(line) should show nothing, not \(picked!)")
        }
        // Faces and figures only for words that name them: an emotion or a gesture draws nothing.
        for word in ["angry", "smile", "laughing", "running", "dancing", "pray", "clap", "hand", "face", "person"] {
            precondition(StickerMatch.candidate(word, line: [word], in: index) == nil, "\(word) names no sticker")
        }
        precondition(StickerMatch.candidate("astronaut", line: [], in: index)?.emoji == "Astronaut")
        precondition(StickerMatch.candidate("singer", line: [], in: index)?.emoji == "Singer")
        // Microsoft's keywords count only as another name for the thing.
        for word in ["proud", "idea", "freedom", "danger", "lazy", "wall", "travel", "table"] {
            precondition(StickerMatch.candidate(word, line: [word], in: index) == nil, "\(word) is only a keyword")
        }
        precondition(StickerMatch.candidate("burger", line: [], in: index)?.emoji == "Hamburger")
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
