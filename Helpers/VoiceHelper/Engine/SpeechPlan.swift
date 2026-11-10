import Foundation

/// How a script is spoken: the pieces generated one at a time, and the
/// silence after each. Pieces are sentences, with short ones joined onto the
/// next so every call has enough words to settle into the voice; nothing is
/// joined across a paragraph. The pause after a piece follows the writing: a
/// sentence end, a trailing-off "…", a cut-off "—", a line break or a new
/// paragraph (which wins; see `pause(after:endsLine:endsParagraph:)`).
/// Commas, joined sentences and other pauses inside a piece are left to the
/// model, whose own silences there are kept whole.
struct SpeechPlan: Equatable, Sendable {
    struct Unit: Equatable, Sendable {
        let text: String
        /// Seconds of silence after it; zero after the last.
        let pause: Double
    }

    let units: [Unit]

    /// With each piece's own leading and trailing silence trimmed (`Edges`),
    /// these are the whole gaps a listener hears, less about 0.1 s.
    static let sentencePause = 0.28
    static let trailingOffPause = 0.45
    static let cutOffPause = 0.12
    static let lineBreakPause = 0.4
    static let paragraphPause = 0.65
    /// Between the parts of one long sentence (`bounded`): a breath, not an ending.
    static let continuationPause = 0.15

    /// Pieces shorter than this are joined onto the next one.
    static let shortestPiece = 40
    /// A paragraph's last piece shorter than this joins the one before it.
    static let shortestEnding = 20
    /// Characters of whole sentences a passage holds, for an engine that reads
    /// a few sentences at once more naturally than one at a time (Qwen): about
    /// 2–3 sentences, short enough that the voice doesn't drift from the clip.
    static let passageLength = 300

    /// With `passage` above zero, sentences in a line join up to that many
    /// characters (a sentence longer than that stays whole), and the pauses
    /// between them are the model's own. Zero keeps one sentence, or short
    /// ones together, per piece.
    init(_ text: String, passage: Int = 0) {
        var units: [Unit] = []
        for paragraph in Self.paragraphs(in: text) {
            // Each piece, and whether it ends a line (so what's joined after it crosses one).
            var pieces: [(unit: Unit, endsLine: Bool)] = []
            var pending = "", pendingPause = 0.0, pendingEndsLine = false
            for (lineIndex, line) in paragraph.enumerated() {
                let sentences = Self.sentences(in: line)
                for (index, sentence) in sentences.enumerated() {
                    let endsLine = index == sentences.count - 1
                    let pause = Self.pause(after: sentence, endsLine: endsLine,
                                           endsParagraph: endsLine && lineIndex == paragraph.count - 1)
                    let joined = pending.isEmpty ? sentence : Self.joined(pending, sentence, acrossLine: pendingEndsLine)
                    if passage > 0, pending.count >= Self.shortestPiece, joined.count > passage {
                        // The passage is full: it ends at the sentence before.
                        pieces.append((Unit(text: pending, pause: pendingPause), pendingEndsLine))
                        pending = sentence
                    } else {
                        pending = joined
                    }
                    pendingPause = pause
                    pendingEndsLine = endsLine
                    if pending.count >= Self.shortestPiece, passage == 0 || endsLine {
                        pieces.append((Unit(text: pending, pause: pendingPause), endsLine))
                        pending = ""
                    }
                }
            }
            if !pending.isEmpty {
                if pending.count < Self.shortestEnding, let last = pieces.popLast() {
                    pieces.append((Unit(text: Self.joined(last.unit.text, pending, acrossLine: last.endsLine), pause: pendingPause),
                                   pendingEndsLine))
                } else {
                    pieces.append((Unit(text: pending, pause: pendingPause), pendingEndsLine))
                }
            }
            units += pieces.map { $0.unit }
        }
        if let last = units.popLast() { units.append(Unit(text: last.text, pause: 0)) }
        self.units = units
    }

    /// A piece split into parts of at most `maxWords` words and `maxLength`
    /// characters, for a model that drifts on long input. A Chinese, Japanese
    /// or Korean character counts as 3, about how much longer it takes to say,
    /// so text written without spaces is bounded too. All the text is kept, in
    /// order. Where a part has to end before the text does, it ends at the
    /// best boundary in the second half of what fits (`end(of:from:by:)`): a
    /// sentence's end, else a comma, semicolon, colon or dash (or their
    /// full-width forms), else before a word that opens a clause ("and",
    /// "because", "which"). A single word longer than a part is cut, at such
    /// a mark if it has one. Join the parts with `continuationPause`.
    static func bounded(_ text: String, maxWords: Int, maxLength: Int = 160) -> [String] {
        guard maxWords > 0, maxLength > 0 else { return [] }
        let words = text.split(whereSeparator: \.isWhitespace).flatMap { cut(String($0), maxLength: maxLength) }
        var parts: [String] = []
        var start = 0
        while start < words.count {
            // As many words as fit both limits; always at least one.
            var end = start + 1, length = spoken(words[start])
            while end < words.count, end - start < maxWords, length + 1 + spoken(words[end]) <= maxLength {
                length += 1 + spoken(words[end])
                end += 1
            }
            if end < words.count { end = Self.end(of: words, from: start, by: end) }
            // A last part of a word or two would sound clipped (a short styled
            // call can lose its words); leave it at least two more, ending this
            // part at the best boundary before them.
            if (1...2).contains(words.count - end), end - start > 4,
               words[(end - 2)...].reduce(-1, { $0 + 1 + spoken($1) }) <= maxLength {
                end = Self.end(of: words, from: start, by: end - 2)
            }
            parts.append(words[start..<end].joined(separator: " "))
            start = end
        }
        return parts
    }

    /// Where a part from `start` that may run to `limit` (exclusive) should
    /// end: after the last sentence end in its second half, else after the
    /// last breath mark there, else before the last clause-opening word there,
    /// else at `limit`.
    private static func end(of words: [String], from start: Int, by limit: Int) -> Int {
        let half = start + (limit - start) / 2
        if let stop = (half..<limit).last(where: { endsSentence(words[$0]) }) { return stop + 1 }
        if let breath = (half..<limit).last(where: { breathes(after: words[$0]) }) { return breath + 1 }
        if half + 1 < limit, let opening = (half + 1..<limit).last(where: { opensClause(words[$0]) }) { return opening }
        return limit
    }

    private static let breathMarks: Set<Character> = [",", ";", ":", "—", "–", "，", "、", "；", "：", "。", "！", "？"]

    private static func breathes(after word: String) -> Bool { word.last.map(breathMarks.contains) ?? false }

    /// Closing quotes and brackets, which a sentence's ending mark may sit inside.
    private static let closers = CharacterSet(charactersIn: "\"'”’»)] ")

    /// A word that ends a sentence: ".", "?", "!", "…" or the full-width "。！？",
    /// past closing quotes, but not a title, initial or dotted abbreviation.
    static func endsSentence(_ word: String) -> Bool {
        let bare = word.trimmingCharacters(in: closers)
        guard let last = bare.last, ".?!…。！？".contains(last) else { return false }
        return last != "." || !isAbbreviation(bare)
    }

    /// Titles and Latin shorthand that end in a full stop mid-sentence.
    private static let abbreviations: Set<String> = ["mr.", "mrs.", "ms.", "dr.", "prof.", "st.", "jr.", "sr.", "vs.", "mt.", "e.g.", "i.e."]

    /// "Dr.", "J." (an initial) or a dotted shorthand like "U.S." or "a.m."
    /// (two or more pieces of one or two letters); never "...", a word's own
    /// full stop, or a number ending a sentence ("3.14.").
    static func isAbbreviation(_ word: String) -> Bool {
        let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“‘«([")).lowercased()
        guard bare.hasSuffix(".") else { return false }
        if abbreviations.contains(bare) { return true }
        let body = bare.dropLast()
        if body.count == 1, body.first?.isLetter == true { return true }
        let pieces = body.split(separator: ".", omittingEmptySubsequences: false)
        return pieces.count >= 2 && pieces.allSatisfy { (1...2).contains($0.count) && $0.allSatisfy(\.isLetter) }
    }

    /// Words that open a clause, so a part can end just before one.
    private static let clauseOpeners: Set<String> = ["and", "but", "or", "nor", "so", "yet", "because", "since", "although",
                                                     "though", "while", "when", "where", "which", "who", "whom", "whose",
                                                     "that", "if", "unless", "until", "after", "before"]

    private static func opensClause(_ word: String) -> Bool { clauseOpeners.contains(word.lowercased()) }

    /// `next` said after `text` in the same call. Across a line break, text
    /// that ends without punctuation ("Dear team") gets a comma, so the break
    /// is still heard rather than run into the next line; otherwise a space.
    static func joined(_ text: String, _ next: String, acrossLine: Bool) -> String {
        guard acrossLine, let last = text.last, last.isLetter || last.isNumber else { return text + " " + next }
        return text + ", " + next
    }

    /// Characters, with Chinese, Japanese and Korean ones counted as 3.
    private static func spoken(_ word: String) -> Int {
        word.reduce(0) { total, character in
            guard let scalar = character.unicodeScalars.first?.value else { return total + 1 }
            let wide = (0x3040...0x30FF).contains(scalar) || (0x3400...0x9FFF).contains(scalar)
                || (0xAC00...0xD7AF).contains(scalar) || (0xF900...0xFAFF).contains(scalar) || (0x20000...0x2FFFF).contains(scalar)
            return total + (wide ? 3 : 1)
        }
    }

    /// A word longer than `maxLength` in pieces that each fit, cut after a
    /// breath mark in the second half of a piece when there is one.
    private static func cut(_ word: String, maxLength: Int) -> [String] {
        guard spoken(word) > maxLength else { return [word] }
        var pieces: [String] = []
        var rest = Substring(word)
        while !rest.isEmpty {
            var end = rest.startIndex, length = 0, breath: String.Index?
            while end < rest.endIndex {
                let weight = spoken(String(rest[end]))
                if length + weight > maxLength, end > rest.startIndex { break }
                length += weight
                end = rest.index(after: end)
                if length * 2 >= maxLength, breathMarks.contains(rest[rest.index(before: end)]) { breath = end }
            }
            if end < rest.endIndex, let breath { end = breath }
            pieces.append(String(rest[..<end]))
            rest = rest[end...]
        }
        return pieces
    }

    /// Lines grouped into paragraphs; blank lines separate paragraphs.
    private static func paragraphs(in text: String) -> [[String]] {
        var paragraphs: [[String]] = [[]]
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !paragraphs[paragraphs.count - 1].isEmpty { paragraphs.append([]) }
            } else {
                paragraphs[paragraphs.count - 1].append(trimmed)
            }
        }
        return paragraphs.filter { !$0.isEmpty }
    }

    /// The sentences of one line. One the system's splitter ended at a title or
    /// initial ("Dr. Smith", "J. Doe") runs on into the next, whichever way
    /// the splitter treats them.
    private static func sentences(in line: String) -> [String] {
        var sentences: [String] = []
        line.enumerateSubstrings(in: line.startIndex..., options: [.bySentences, .localized]) { sentence, _, _, _ in
            guard let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
            if let previous = sentences.last, let word = previous.split(whereSeparator: \.isWhitespace).last,
               isAbbreviation(String(word)) {
                sentences[sentences.count - 1] = previous + " " + sentence
            } else {
                sentences.append(sentence)
            }
        }
        return sentences
    }

    /// The pause a sentence's ending asks for, ignoring closing quotes and brackets.
    static func pause(after sentence: String) -> Double {
        let ending = sentence.trimmingCharacters(in: closers)
        if ending.hasSuffix("…") || ending.hasSuffix("...") { return trailingOffPause }
        if ending.hasSuffix("—") || ending.hasSuffix("–") || ending.hasSuffix("--") { return cutOffPause }
        return sentencePause
    }

    /// The pause after a sentence, by what it ends. Precedence, highest first:
    /// 1. the end of a paragraph: `paragraphPause`, the longest break, whatever the ending;
    /// 2. a cut-off ("—") anywhere else: `cutOffPause`, even at a line break,
    ///    since the next line interrupts it;
    /// 3. the end of a line: `lineBreakPause`, or `trailingOffPause` if "…" asks for longer;
    /// 4. inside a line: the ending's own pause (`pause(after:)`).
    static func pause(after sentence: String, endsLine: Bool, endsParagraph: Bool) -> Double {
        if endsParagraph { return paragraphPause }
        let own = pause(after: sentence)
        guard endsLine, own != cutOffPause else { return own }
        return max(own, lineBreakPause)
    }

    /// Trims the silence a generated piece starts and ends with, so the pause
    /// after it is the plan's and not whatever the model left, and fades the
    /// last few milliseconds so an ending never clicks. It streams: sound is
    /// passed on as soon as it arrives, and silence after it waits until more
    /// sound follows (a pause inside the piece, kept whole) or the piece ends
    /// (trimmed).
    struct Edges {
        /// About -50 dBFS over 10 ms: well under a soft consonant at speaking level.
        static let threshold: Float = 0.003
        static let lead = 0.02
        static let tail = 0.08
        /// The shortest fade-out, for a piece whose sound runs to its end.
        static let fade = 0.02

        private let rate: Int
        private var started = false
        private var held: [Float] = []

        init(rate: Int) { self.rate = rate }

        private var frame: Int { max(1, rate / 100) }
        private func samples(_ seconds: Double) -> Int { Int(seconds * Double(rate)) }

        private func sounding(_ start: Int, in buffer: [Float]) -> Bool {
            let end = min(buffer.count, start + frame)
            guard end > start else { return false }
            var power: Float = 0
            for i in start..<end { power += buffer[i] * buffer[i] }
            return (power / Float(end - start)).squareRoot() >= Self.threshold
        }

        /// Audio that can be played now; the rest waits for more or for `finish`.
        mutating func push(_ chunk: [Float]) -> [Float] {
            held += chunk
            if !started {
                guard let first = stride(from: 0, to: held.count, by: frame).first(where: { sounding($0, in: held) }) else {
                    let keep = samples(Self.lead)
                    if held.count > keep { held.removeFirst(held.count - keep) }
                    return []
                }
                held.removeFirst(max(0, first - samples(Self.lead)))
                started = true
                // Fade in over the quiet lead, so a piece never starts with a step.
                Self.fade(&held, from: 0, count: min(samples(Self.lead), first), rising: true)
            }
            // Whole frames only, so frames line up the same however audio arrives.
            guard let last = lastSound(), last + frame <= held.count else {
                guard let last = lastSound(), last > 0 else { return [] }
                let ready = Array(held[..<last])
                held.removeFirst(last)
                return ready
            }
            let ready = Array(held[..<(last + frame)])
            held.removeFirst(last + frame)
            return ready
        }

        /// Where the last sounding frame in `held` starts.
        private func lastSound() -> Int? {
            guard !held.isEmpty else { return nil }
            let lastFrame = (held.count - 1) / frame * frame
            return stride(from: lastFrame, through: 0, by: -frame).first { sounding($0, in: held) }
        }

        /// The rest of the piece, its silent ending trimmed and faded: across
        /// the whole quiet tail into the pause, or at least `fade` at the end.
        mutating func finish() -> [Float] {
            defer { held = [] }
            guard started, !held.isEmpty else { return [] }
            let soundEnd = lastSound().map { $0 + frame } ?? 0
            let end = min(held.count, soundEnd + samples(Self.tail))
            var out = Array(held[..<end])
            let fade = min(out.count, max(end - soundEnd, samples(Self.fade)))
            Self.fade(&out, from: out.count - fade, count: fade, rising: false)
            return out
        }

        /// A raised-cosine fade over `count` samples from `start`.
        private static func fade(_ samples: inout [Float], from start: Int, count: Int, rising: Bool) {
            guard count > 0 else { return }
            for i in 0..<count {
                let progress = Float(i + 1) / Float(count + 1)
                let gain = 0.5 - 0.5 * cos(Float.pi * progress)
                samples[start + i] *= rising ? gain : 1 - gain
            }
        }

        /// A whole piece at once.
        static func trimmed(_ samples: [Float], rate: Int) -> [Float] {
            var edges = Edges(rate: rate)
            return edges.push(samples) + edges.finish()
        }

    }
}
