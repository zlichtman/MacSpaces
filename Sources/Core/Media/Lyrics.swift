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

    /// The record that is really this song, best first.
    static func best(_ records: [Record], title: String, artist: String, duration: TimeInterval) -> Record? {
        records
            .compactMap { record in score(record, title: title, artist: artist, duration: duration).map { (record, $0) } }
            .max { $0.1 < $1.1 }?.0
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

    static func cleanedTrackTitle(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"\s*[\(\[]\s*(?:feat\.?|featuring|with)\b.*?[\)\]]\s*"#,
            #"\s*[\(\[][^\)\]]*(?:remaster|radio edit|single edit|live|acoustic|mono|stereo|version|mix)[^\)\]]*[\)\]]\s*"#,
            #"\s+[-–—]\s+.*(?:remaster|radio edit|single edit|live|acoustic|mono|stereo|version|mix).*$"#,
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

    /// Timed lines from LRC text. Blank timestamps mark instrumental breaks and
    /// become one empty line per break; an `[offset:]` tag shifts every line.
    static func parseLRC(_ synced: String) -> [(start: TimeInterval, text: String)] {
        let stamp = try? NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        let offsetTag = try? NSRegularExpression(pattern: #"^\s*\[offset:\s*([+-]?\d+)\s*\]"#, options: .caseInsensitive)
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
                .trimmingCharacters(in: .whitespacesAndNewlines)
            for match in matches where match.numberOfRanges >= 3 {
                guard let minutes = Double(line.substring(with: match.range(at: 1))),
                      let seconds = Double(line.substring(with: match.range(at: 2))) else { continue }
                parsed.append((minutes * 60 + seconds, text.isEmpty ? rest : text))
            }
        }
        parsed.sort { $0.start < $1.start }
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
            .filter { !$0.isEmpty } ?? []
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

/// How much of a line Typewriter has typed: it starts as the line is sung and
/// finishes within the first 60% of the line (never slower than 1.1 s), so the
/// words are all there while they're still being sung.
enum TypewriterTiming {
    static func typed(at elapsed: TimeInterval, span: ClosedRange<TimeInterval>) -> Double {
        let length = min(1.1, max(0.25, 0.6 * (span.upperBound - span.lowerBound)))
        return min(1, max(0, (elapsed - span.lowerBound) / length))
    }
}
