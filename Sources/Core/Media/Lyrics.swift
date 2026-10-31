import Foundation

/// One lyric line: when it starts in the song, and for captions when it ends.
struct LyricLine: Equatable, Codable, Sendable {
    var start: TimeInterval
    var end: TimeInterval?
    var text: String
}

/// Pure lyric logic: LRCLIB records and matching, LRC parsing and censored-word
/// repair. `TeleprompterService` does the fetching; `Scripts/check-lyrics.sh` tests this.
enum Lyrics {
    /// A timed song's silence (intro, instrumental break): nothing is shown.
    static let rest = ""

    struct Record: Decodable, Sendable {
        let trackName: String
        let artistName: String
        let duration: Double?
        let plainLyrics: String?
        let syncedLyrics: String?
        var instrumental: Bool? = false

        var isSynced: Bool { syncedLyrics?.isEmpty == false }
    }

    private struct SearchResponse: Decodable {
        var records: [Record] = []
        init(from decoder: Decoder) throws {
            var values = try decoder.unkeyedContainer()
            while !values.isAtEnd {
                // Consume each result independently: one malformed community
                // upload must not discard valid lyrics for the same song.
                let recordDecoder = try values.superDecoder()
                if let record = try? Record(from: recordDecoder) { records.append(record) }
            }
        }
    }

    /// LRCLIB search results (an array); malformed entries are skipped one by one.
    static func decodeRecords(_ data: Data) -> [Record] {
        (try? JSONDecoder().decode(SearchResponse.self, from: data))?.records ?? []
    }

    /// LRCLIB's exact lookup (one object), or nil for an error body.
    static func decodeRecord(_ data: Data) -> Record? {
        try? JSONDecoder().decode(Record.self, from: data)
    }

    /// The record that is really this song, best first. `strictTiming` is for a song played
    /// from a file (`fittingFile`): a record's timing counts only when it fits the file.
    static func best(_ records: [Record], title: String, artist: String, duration: TimeInterval,
                     strictTiming: Bool = false) -> Record? {
        records
            .map { strictTiming ? fittingFile($0, duration: duration) : $0 }
            .compactMap { record in score(record, title: title, artist: artist, duration: duration).map { (record, $0) } }
            .max { $0.1 < $1.1 }?.0
    }

    /// How far a timed record's length may differ from a local file's: a couple of seconds,
    /// as LRCLIB stores whole seconds and players round a file's length either way.
    static let localTimingTolerance: TimeInterval = 2.5

    /// A song played from a file on this Mac is often another cut than the release LRCLIB
    /// timed (a leak, a demo, a longer intro), so its timing is trusted only when the
    /// record is as long as the file, within `localTimingTolerance`, and no line starts
    /// after the file ends. Otherwise the record keeps only its words, shown untimed:
    /// plain lyrics beat lines at the wrong moments.
    static func fittingFile(_ record: Record, duration: TimeInterval) -> Record {
        guard let synced = record.syncedLyrics, !synced.isEmpty else { return record }
        let lines = parseLRC(synced)
        let lastStart = lines.last { $0.text != rest }?.start ?? 0
        if duration > 0, let recordDuration = record.duration, recordDuration > 0,
           abs(recordDuration - duration) <= localTimingTolerance, lastStart <= duration + 1 {
            return record
        }
        let words = record.plainLyrics?.isEmpty == false
            ? record.plainLyrics
            : lines.map(\.text).filter { $0 != rest }.joined(separator: "\n")
        return Record(trackName: record.trackName, artistName: record.artistName, duration: record.duration,
                      plainLyrics: words, syncedLyrics: nil, instrumental: record.instrumental)
    }

    /// Whether a song's lookup starts again because the player corrected its length. Right
    /// after a skip a reading can carry the new song's name with the previous song's length
    /// (the song key leaves length out), and timed records are matched by length, so a
    /// lookup made with the wrong one rejects them all and settles for plain lyrics or a
    /// stored "none". Once timed lyrics show, the length they matched was right enough.
    static func lengthCorrected(lookedUpWith old: TimeInterval, now new: TimeInterval, showingTimed: Bool) -> Bool {
        !showingTimed && new > 0 && abs(new - old) > localTimingTolerance
    }

    /// Lyrics saved in a music file (an MP4 `©lyr` tag or an ID3 `USLT` frame, sometimes
    /// written as LRC, or an ID3 `SYLT` frame's lines): timed when they carry timestamps,
    /// otherwise spread over the song like any plain lyrics. Text counts as LRC only when
    /// most of its lines start with a timestamp (a lyric that mentions "[10:30]" is not
    /// LRC), and timed lines are kept only when they fit the file: lines that run on past
    /// its end were timed to another cut, so they show untimed.
    static func embeddedLines(_ text: String?, synced: [(start: TimeInterval, text: String)] = [],
                              duration: TimeInterval) -> (lines: [LyricLine], timed: Bool) {
        func fitting(_ lines: [(start: TimeInterval, text: String)]) -> (lines: [LyricLine], timed: Bool) {
            let lastStart = lines.last { $0.text != rest }?.start ?? 0
            if duration > 0, lastStart > duration + 1 {
                return (Self.lines(fromPlain: lines.map(\.text).filter { $0 != rest }.joined(separator: "\n"), duration: duration), false)
            }
            return (lines.map { LyricLine(start: $0.start, end: nil, text: $0.text) }, true)
        }
        if synced.contains(where: { $0.text != rest }) { return fitting(synced) }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return ([], false) }
        // LRC header lines ("[ar:Artist]", "[offset:+200]") without a timestamp are not lyrics.
        let body = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { $0.range(of: #"^\s*\[[A-Za-z]+:[^\]]*\]\s*$"#, options: .regularExpression) == nil }
        let stamped = body.filter { $0.range(of: "^\\s*" + lrcStamp, options: .regularExpression) != nil }
        if stamped.count * 2 >= body.count {
            let timed = parseLRC(text)
            if timed.contains(where: { $0.text != rest }) { return fitting(timed) }
        }
        // A few stray timestamps don't make it timed; they're dropped from the words.
        let plain = body.map { $0.replacingOccurrences(of: "^\\s*(?:" + lrcStamp + "\\s*)+", with: "", options: .regularExpression) }
            .joined(separator: "\n")
        return (lines(fromPlain: plain, duration: duration), false)
    }

    /// The lines of an ID3v2 `SYLT` frame's body: an encoding byte, a language, a
    /// timestamp format (only 2, milliseconds, is read), a content type and a descriptor,
    /// then each line's text and its 32-bit start. Nil for anything else.
    static func parseSYLT(_ data: Data) -> [(start: TimeInterval, text: String)]? {
        let bytes = [UInt8](data)
        guard bytes.count > 6, bytes[4] == 2, bytes[0] <= 3 else { return nil }
        let encoding = bytes[0]
        let wide = encoding == 1 || encoding == 2
        /// A terminated string from `start`, and where the bytes after it begin.
        func string(from start: Int) -> (String, Int)? {
            var end = start
            if wide {
                while end + 1 < bytes.count, !(bytes[end] == 0 && bytes[end + 1] == 0) { end += 2 }
                guard end + 1 < bytes.count else { return nil }
                let body = Data(bytes[start..<end])
                let decoded = encoding == 1 ? String(data: body, encoding: .utf16) : String(data: body, encoding: .utf16BigEndian)
                return decoded.map { ($0, end + 2) }
            }
            while end < bytes.count, bytes[end] != 0 { end += 1 }
            guard end < bytes.count else { return nil }
            let body = Data(bytes[start..<end])
            let decoded = encoding == 3 ? String(data: body, encoding: .utf8) : String(data: body, encoding: .isoLatin1)
            return decoded.map { ($0, end + 1) }
        }
        guard let descriptor = string(from: 6) else { return nil }
        var index = descriptor.1
        var entries: [(start: TimeInterval, text: String)] = []
        while index < bytes.count, let (line, next) = string(from: index), next + 4 <= bytes.count {
            let stamp = bytes[next..<next + 4].reduce(0) { $0 << 8 | Int($1) }
            entries.append((TimeInterval(stamp) / 1000, line))
            index = next + 4
        }
        // Stable time order: syllables stamped alike keep the file's order.
        entries = entries.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element)
        var lines: [(start: TimeInterval, text: String)] = []
        // Karaoke taggers store a syllable or word per entry and mark where each line
        // starts with a newline (before its first syllable, or after the last one's). Then
        // the entries are joined into lines; otherwise each entry is a line.
        func breaks(_ text: String, atEnd: Bool) -> Bool {
            guard let edge = atEnd ? text.last : text.first else { return false }
            return edge == "\n" || edge == "\r" || edge == "\r\n"
        }
        let marked = entries.contains { breaks($0.text, atEnd: false) || breaks($0.text, atEnd: true) }
        if marked {
            var current: (start: TimeInterval, text: String)?
            var breakAfter = true
            for entry in entries {
                let opens = breakAfter || breaks(entry.text, atEnd: false)
                breakAfter = breaks(entry.text, atEnd: true)
                let piece = entry.text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
                if opens {
                    if let done = current { lines.append(done) }
                    current = (entry.start, piece)
                } else {
                    current?.text += piece
                }
            }
            if let done = current { lines.append(done) }
        } else {
            lines = entries
        }
        lines = lines.map { line in
            let words = line.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return (line.start, words.isEmpty ? rest : words)
        }
        while lines.first?.text == rest { lines.removeFirst() }
        return lines.contains { $0.text != rest } ? lines : nil
    }

    static func score(_ record: Record, title: String, artist: String, duration: TimeInterval) -> Double? {
        let hasLyrics = record.isSynced || record.plainLyrics?.isEmpty == false || record.instrumental == true
        return score(title: record.trackName, artist: record.artistName, duration: record.duration ?? 0,
                     synced: record.isSynced, hasLyrics: hasLyrics,
                     title: title, artist: artist, duration: duration)
    }

    /// How well a record matches the playing track, or nil when it's a different
    /// song (title or artist don't match) or has no lyrics at all.
    static func score(
        title recordTitle: String, artist recordArtist: String, duration recordDuration: Double,
        synced: Bool, hasLyrics: Bool,
        title: String, artist: String, duration: TimeInterval
    ) -> Double? {
        guard hasLyrics else { return nil }
        let wantedTitle = normalized(cleanedTrackTitle(title))
        let foundTitle = normalized(cleanedTrackTitle(recordTitle))
        var value = 0.0
        if foundTitle == wantedTitle {
            value += 6
        } else if similar(latin(cleanedTrackTitle(title)), latin(cleanedTrackTitle(recordTitle))) {
            // The same title in another script or spelling ("Bumerang" / "Бумеранг").
            value += 4
        } else {
            return nil
        }

        let wantedArtist = normalized(cleanedArtist(artist))
        let wantedPrimary = normalized(primaryArtist(artist))
        let foundArtist = normalized(recordArtist)
        if foundArtist == wantedArtist {
            value += 5
        } else if !wantedPrimary.isEmpty,
                  normalized(primaryArtist(recordArtist)) == wantedPrimary {
            // A shared lead artist is valid; appearing only in the featured
            // credits is not evidence that this is the playing artist's song.
            value += 3
        } else if similar(latin(cleanedArtist(artist)), latin(recordArtist))
                    || similar(latin(primaryArtist(artist)), latin(recordArtist)) {
            // The artist written in Latin letters, or transliterated differently
            // ("Второй Ка" is "Vtoroi Ka" on LRCLIB; ICU says "Vtoroj Ka").
            value += 3
        } else {
            return nil
        }

        // Timed lyrics from another cut of the song (radio edit, live, extended
        // intro) drift by the length difference, so length decides between them.
        let gap = duration > 0 && recordDuration > 0 ? abs(recordDuration - duration) : nil
        if synced, let gap, gap >= 15 { return nil }
        if let gap {
            switch gap {
            case ..<2.5: value += 4
            case ..<6: value += 2
            case ..<15: value += 0
            default: value -= synced ? 8 : 2
            }
        }
        if synced, gap.map({ $0 < 15 }) ?? true { value += 3 }
        return value
    }

    static func normalized(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// A name in Latin letters without accents, for comparing across scripts.
    static func latin(_ string: String) -> String {
        normalized(string.applyingTransform(.toLatin, reverse: false) ?? string)
    }

    /// Equal, or at most one edit in five apart (transliterations differ by a
    /// letter or two: j/i/y, kh/h).
    static func similar(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let x = Array(a), y = Array(b)
        guard min(x.count, y.count) >= 3, abs(x.count - y.count) <= max(x.count, y.count) / 5 else { return false }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return Double(previous[y.count]) <= Double(max(x.count, y.count)) / 5
    }

    /// A line split into what's sung and its bracketed ad-libs or backing vocals:
    /// "a rebellious child(rebellious child)" → ("a rebellious child", ["rebellious child"]).
    /// An unclosed bracket runs to the end of the line; a line that is all ad-lib is sung.
    static func asides(_ line: String) -> (sung: String, asides: [String]) {
        var sung = "", asides: [String] = [], current: String?
        for character in line {
            if character == "(" || character == "[" {
                if let open = current, !open.trimmingCharacters(in: .whitespaces).isEmpty { asides.append(open) }
                current = ""; sung += " "
            } else if character == ")" || character == "]" {
                if let open = current, !open.trimmingCharacters(in: .whitespaces).isEmpty { asides.append(open) }
                current = nil; sung += " "
            } else if current != nil {
                current!.append(character)
            } else {
                sung.append(character)
            }
        }
        if let open = current, !open.trimmingCharacters(in: .whitespaces).isEmpty { asides.append(open) }
        let words = sung.split(separator: " ").joined(separator: " ")
        let trimmed = asides.map { $0.trimmingCharacters(in: .whitespaces) }
        return words.isEmpty ? (trimmed.joined(separator: " "), []) : (words, trimmed)
    }

    static func cleanedTrackTitle(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"\s*[\(\[]\s*(?:feat\.?|featuring|with)\b.*?[\)\]]\s*"#,
            #"\s*[\(\[][^\)\]]*(?:remaster|radio edit|single edit|live|acoustic|mono|stereo|version|mix)[^\)\]]*[\)\]]\s*"#,
            #"\s+[-–—]\s+.*(?:remaster|radio edit|single edit|live|acoustic|mono|stereo|version|mix|unplugged|unpeeled|session|demo|edit).*$"#,
            #"\s+(?:feat\.?|featuring)\s+.+$"#,
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanedArtist(_ artist: String) -> String {
        artist.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+(?:feat\.?|featuring)\s+.+$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func primaryArtist(_ artist: String) -> String {
        let cleaned = cleanedArtist(artist)
        for separator in [",", ";", " / ", "/", " & ", " x ", " X "] {
            if let range = cleaned.range(of: separator) {
                let first = cleaned[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if !first.isEmpty { return first }
            }
        }
        return cleaned
    }

    /// Artist/title pairs to try at lyrics.ovh, most specific first, without repeats.
    static func plainCandidates(title: String, artist: String) -> [(artist: String, title: String)] {
        let cleanedTitle = cleanedTrackTitle(title)
        let raw = [
            (artist: cleanedArtist(artist), title: cleanedTitle),
            (artist: primaryArtist(artist), title: cleanedTitle),
            (artist: artist, title: cleanedTitle),
            (artist: artist, title: title),
        ]
        var seen = Set<String>()
        return raw.filter { candidate in
            guard !candidate.artist.isEmpty, !candidate.title.isEmpty else { return false }
            return seen.insert("\(normalized(candidate.artist))|\(normalized(candidate.title))").inserted
        }
    }

    /// One LRC timestamp: "[01:23.45]", and the variants taggers write, "[01:23:45]",
    /// "[01:23,45]", "[01:23.456]" and "[01:23]". Minutes, seconds, then the fraction.
    static let lrcStamp = #"\[(\d+):(\d{1,2})(?:[.:,](\d+))?\]"#

    /// Timed lines from LRC text. Blank timestamps mark instrumental breaks and
    /// become one empty line per break; an `[offset:]` tag (milliseconds, positive
    /// shows lyrics sooner) shifts every line. Enhanced LRC's word stamps
    /// ("<00:12.30>") are dropped from the words.
    static func parseLRC(_ synced: String) -> [(start: TimeInterval, text: String)] {
        let stamp = try? NSRegularExpression(pattern: lrcStamp)
        let offsetTag = try? NSRegularExpression(pattern: #"^\s*\[offset:\s*([+-]?\d+(?:\.\d+)?)\s*\]"#, options: .caseInsensitive)
        var offset: TimeInterval = 0
        var parsed: [(start: TimeInterval, text: String)] = []
        for rawLine in synced.components(separatedBy: .newlines) {
            let line = rawLine as NSString
            let range = NSRange(location: 0, length: line.length)
            if let match = offsetTag?.firstMatch(in: rawLine, range: range),
               let milliseconds = Double(line.substring(with: match.range(at: 1))) {
                // A positive offset shows lyrics sooner.
                offset = milliseconds / 1000
                continue
            }
            let matches = stamp?.matches(in: rawLine, range: range) ?? []
            guard let last = matches.last else { continue }
            let text = line.substring(from: last.range.location + last.range.length)
                .replacingOccurrences(of: #"<\d+:\d{1,2}(?:[.:,]\d+)?>"#, with: " ", options: .regularExpression)
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            for match in matches where match.numberOfRanges >= 4 {
                guard let minutes = Double(line.substring(with: match.range(at: 1))),
                      let seconds = Double(line.substring(with: match.range(at: 2))) else { continue }
                let fraction = match.range(at: 3).location == NSNotFound ? 0 : Double("0." + line.substring(with: match.range(at: 3))) ?? 0
                parsed.append((minutes * 60 + seconds + fraction, text.isEmpty ? rest : text))
            }
        }
        // Stable: lines stamped alike keep their order.
        parsed = parsed.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element)
        var result: [(start: TimeInterval, text: String)] = []
        for entry in parsed {
            // One rest per break, and none before the first sung line (the intro rests anyway).
            if entry.text == rest, result.isEmpty || result.last?.text == rest { continue }
            result.append((max(0, entry.start - offset), entry.text))
        }
        return result
    }

    /// A record's lines: timed when it has LRC, otherwise its plain text spread over the song.
    static func lines(from record: Record, fallbackDuration: TimeInterval) -> [LyricLine] {
        if let synced = record.syncedLyrics, !synced.isEmpty {
            return parseLRC(synced).map { LyricLine(start: $0.start, end: nil, text: $0.text) }
        }
        let duration = fallbackDuration > 0 ? fallbackDuration : (record.duration ?? 0)
        return lines(fromPlain: record.plainLyrics, duration: duration)
    }

    /// Untimed lyrics, spread evenly over the song (there is nothing better to go on).
    static func lines(fromPlain lyrics: String?, duration: TimeInterval) -> [LyricLine] {
        let plain = lyrics?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            // Section labels ("[Chorus]", "[Verse 2: Artist]") aren't sung.
            .filter { !$0.isEmpty && !($0.hasPrefix("[") && $0.hasSuffix("]")) } ?? []
        guard !plain.isEmpty else { return [] }
        let step = duration > 0 ? duration / Double(plain.count) : 4
        return plain.enumerated().map { LyricLine(start: Double($0.offset) * step, end: nil, text: $0.element) }
    }

    /// A blanked-out word: a lone dash, starred letters, dashed letters or a tag.
    static func isCensoredWord(_ word: String) -> Bool {
        let core = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()"))
        if core == "-" || core == "--" || core == "—" { return true }
        if core.contains("*") { return true }
        if core.range(of: #"^[A-Za-z]-{2,}[A-Za-z]?$"#, options: .regularExpression) != nil { return true }
        return ["[censored]", "[bleep]", "(bleep)", "[explicit]"].contains(core.lowercased())
    }

    static func isCensored(_ line: String) -> Bool {
        line.split(separator: " ").contains { isCensoredWord(String($0)) }
    }

    /// Fills each blanked word from the full lyrics: finds the words just before it
    /// (or just after, at the start of a line) and takes the word in its place.
    static func uncensor(_ line: String, using text: [String]) -> String {
        func key(_ word: String) -> String { normalized(word) }
        let plain = text.map(key)
        var tokens = line.split(separator: " ").map(String.init)
        for index in tokens.indices where isCensoredWord(tokens[index]) {
            let hint = tokens[index].filter(\.isLetter).lowercased()
            func fits(_ candidate: String) -> Bool {
                let word = key(candidate)
                guard !word.isEmpty, !isCensoredWord(candidate) else { return false }
                // A dash that's only punctuation: the full text goes straight on to the next word.
                if index + 1 < tokens.count, word == key(tokens[index + 1]) { return false }
                if index > 0, word == key(tokens[index - 1]) { return false }
                return hint.isEmpty || (word.first.map { String($0) } == hint.first.map { String($0) })
            }
            var replacement: String?
            let before = tokens[max(0, index - 3)..<index].map(key).filter { !$0.isEmpty }
            if !before.isEmpty, plain.count > before.count {
                for start in 0...(plain.count - before.count - 1) where Array(plain[start..<start + before.count]) == before {
                    let candidate = text[start + before.count]
                    if fits(candidate) { replacement = candidate; break }
                }
            }
            if replacement == nil {
                let after = tokens[(index + 1)..<min(tokens.count, index + 4)].map(key).filter { !$0.isEmpty }
                if !after.isEmpty, plain.count > after.count {
                    for start in 1...(plain.count - after.count) where Array(plain[start..<start + after.count]) == after {
                        let candidate = text[start - 1]
                        if fits(candidate) { replacement = candidate; break }
                    }
                }
            }
            if let replacement {
                // Keep the line's own trailing punctuation.
                let trailing = String(tokens[index].reversed().prefix { ".,!?;:".contains($0) }.reversed())
                tokens[index] = replacement.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:")) + trailing
            }
        }
        return tokens.joined(separator: " ")
    }
}

/// Which line shows at a moment of the song, and when that next changes.
/// A sung line appears `lead` early, so it can be read as it's sung; a rest
/// (intro, break, a caption's end) clears exactly on time, so the outgoing line
/// is never cut short.
struct LyricTimeline: Equatable, Sendable {
    static let lead: TimeInterval = 0.25

    var lines: [LyricLine] = []
    /// Real timings (LRC or captions); plain lyrics are only spread over the song.
    var timed = false
    var duration: TimeInterval = 0

    struct Position: Equatable {
        /// The line on screen, nil during the intro or a caption gap.
        var index: Int?
        var current: String
        var upcoming: String
        /// The sung span of the current line in song time, for Karaoke and
        /// Typewriter; nil for rests and untimed lyrics.
        var span: ClosedRange<TimeInterval>?
    }

    /// Which line `index` shows from (song time).
    private func showsFrom(_ index: Int) -> TimeInterval {
        let line = lines[index]
        return line.text == Lyrics.rest ? line.start : line.start - Self.lead
    }

    /// When line `index` is no longer sung: the next line, a caption's own end,
    /// or the song's end for the last line.
    func end(of index: Int) -> TimeInterval {
        let line = lines[index]
        var end = index + 1 < lines.count ? lines[index + 1].start : (duration > line.start ? duration : line.start + 5)
        if let own = line.end { end = min(end, own) }
        return max(end, line.start + 0.5)
    }

    func position(at elapsed: TimeInterval) -> Position {
        guard !lines.isEmpty else { return Position(index: nil, current: "", upcoming: "", span: nil) }
        guard let index = lines.indices.last(where: { showsFrom($0) <= elapsed }) else {
            // Before the first line: nothing shows during the intro when timings are real.
            return timed
                ? Position(index: nil, current: Lyrics.rest, upcoming: lines[0].text, span: nil)
                : Position(index: 0, current: lines[0].text, upcoming: lines.count > 1 ? lines[1].text : "", span: nil)
        }
        let line = lines[index]
        let next = lines[(index + 1)...].first { $0.text != Lyrics.rest }?.text ?? ""
        // A caption that has ended leaves the screen until the next one.
        if let own = line.end, elapsed >= own, line.text != Lyrics.rest {
            return Position(index: nil, current: Lyrics.rest, upcoming: next, span: nil)
        }
        let span = timed && line.text != Lyrics.rest ? line.start...end(of: index) : nil
        return Position(index: index, current: line.text, upcoming: next, span: span)
    }

    /// The song time of the next change after `elapsed`, if any.
    func nextChange(after elapsed: TimeInterval) -> TimeInterval? {
        var candidates: [TimeInterval] = lines.indices.map(showsFrom)
        candidates += lines.compactMap(\.end)
        return candidates.filter { $0 > elapsed + 0.001 }.min()
    }

    /// 0…1 through the current line's sung span, for Karaoke.
    static func progress(of span: ClosedRange<TimeInterval>?, at elapsed: TimeInterval) -> Double {
        guard let span else { return 1 }
        return min(1, max(0, (elapsed - span.lowerBound) / max(0.5, span.upperBound - span.lowerBound)))
    }
}

/// When the Music page centres the title for a song without lyrics (`TeleprompterService.showsNoLyrics`).
/// A definite "none" centres it at once; lyrics found keep the lyric layout. While the lookup
/// still runs, the page keeps the layout it had for `grace` (a cached answer, the file's own
/// lyrics or LRCLIB's exact match usually lands well inside it, so a song change between two
/// songs without lyrics never bobs up and back down, and one with lyrics never dips), then
/// shows the lyric layout while it looks. A lookup still unanswered at `deadline` (LRCLIB
/// busy, lyrics.ovh slow, offline) counts as none for the layout; it carries on, and lyrics
/// that arrive later move the title back up.
enum NoLyricsLayout {
    enum Answer: Equatable {
        /// Nothing to answer for: no song, or captions from the player itself.
        case idle
        case looking
        case lyrics
        case none
    }

    static let grace: TimeInterval = 0.6
    static let deadline: TimeInterval = 5

    /// Whether the title is centred `elapsed` seconds into the lookup, given the layout the
    /// page had when it started (`held`).
    static func centred(_ answer: Answer, elapsed: TimeInterval, held: Bool) -> Bool {
        switch answer {
        case .idle, .lyrics: return false
        case .none: return true
        case .looking: return elapsed >= deadline ? true : elapsed < grace ? held : false
        }
    }

    /// Seconds until the layout can next change on its own (only while looking).
    static func nextChange(_ answer: Answer, elapsed: TimeInterval) -> TimeInterval? {
        guard answer == .looking else { return nil }
        if elapsed < grace { return grace - elapsed }
        return elapsed < deadline ? deadline - elapsed : nil
    }
}

/// How much of a line Typewriter has typed: it starts as the line is sung and
/// finishes within the first 60% of the line (never slower than 1.1 s), so the
/// words are all there while they're still being sung.
enum TypewriterTiming {
    static func typed(at elapsed: TimeInterval, span: ClosedRange<TimeInterval>) -> Double {
        let length = min(1.1, max(0.25, 0.6 * (span.upperBound - span.lowerBound)))
        return min(1, max(0, (elapsed - span.lowerBound) / length))
    }
}

/// A song's own lyric timing nudge, set from the Music page's lyric menu (right-click the
/// lyric) when timed lyrics run a little early or late. Positive values show lines sooner.
/// Saved per song in `storageKey` (song key → seconds); songs without one keep LRCLIB's
/// timing, as before. Pure apart from the defaults it's handed.
enum LyricNudge {
    static let storageKey = "media.lyricNudges"
    static let step: TimeInterval = 0.5
    static let limit: TimeInterval = 30
    /// Songs remembered; the oldest nudge set goes first.
    static let capacity = 300

    /// The saved nudges with `key` moved by `delta` (0 resets it), clamped to ±`limit`.
    /// Order is kept in an "order" list so the oldest leave first.
    static func adjusted(_ saved: [String: Any], key: String, by delta: TimeInterval?) -> [String: Any] {
        var values = saved["values"] as? [String: Double] ?? [:]
        var order = (saved["order"] as? [String] ?? []).filter { values[$0] != nil && $0 != key }
        let current = values[key] ?? 0
        let next = delta.map { min(limit, max(-limit, ((current + $0) * 100).rounded() / 100)) } ?? 0
        if next == 0 {
            values[key] = nil
        } else {
            values[key] = next
            order.append(key)
        }
        while order.count > capacity { values[order.removeFirst()] = nil }
        return ["values": values, "order": order]
    }

    static func value(in saved: [String: Any]?, key: String) -> TimeInterval {
        (saved?["values"] as? [String: Double])?[key] ?? 0
    }

    /// "0.5 s earlier", "1 s later".
    static func label(_ seconds: TimeInterval) -> String {
        let amount = abs(seconds)
        let number = amount == amount.rounded() ? String(Int(amount)) : String(format: "%.1f", amount)
        return "\(number) s \(seconds > 0 ? "earlier" : "later")"
    }
}
