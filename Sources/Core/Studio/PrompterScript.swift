import Foundation

/// A script as the teleprompter reads it. Plain words are spoken; a few marks shape the rest:
/// - `# Title` (one to six #) starts a section: its title shows on its own line, and Tab or the
///   number keys jump to it.
/// - `[like this]` is a stage note: shown dimmed, never spoken, so voice following skips it.
/// - `> Mention the launch date` is a point to cover in your own words: it's listed apart from
///   the text and ticks off once enough of its words have been said.
/// - A blank line starts a new paragraph on a new line.
/// `position` everywhere is an index into `words`, the words as drawn.
struct PrompterScript: Equatable {
    enum Kind: Equatable { case spoken, note, heading }

    struct Word: Equatable {
        let text: String
        let kind: Kind
        /// Starts a new line: the first of a paragraph or a heading, or the first after a heading.
        let breaksBefore: Bool
    }

    struct Section: Equatable {
        let title: String
        /// Its heading's first word.
        let firstWord: Int
    }

    struct Point: Equatable {
        let text: String
        /// The words that count when said: lowercased, without small common words.
        let keywords: [String]
    }

    let words: [Word]
    let sections: [Section]
    let points: [Point]
    /// Each spoken word's index in `words`, in order.
    let spokenIndex: [Int]
    /// The spoken words as compared with speech.
    let spoken: [String]

    init(_ text: String) {
        var words: [Word] = [], sections: [Section] = [], points: [Point] = []
        var breakNext = true, inNote = false
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // A note left open ends with its paragraph.
            if line.isEmpty { breakNext = true; inNote = false; continue }
            if let point = Self.point(in: line) {
                points.append(Point(text: point, keywords: Self.keywords(point)))
                continue
            }
            if let title = Self.heading(in: line) {
                inNote = false
                sections.append(Section(title: title, firstWord: words.count))
                for (index, part) in title.split(whereSeparator: \.isWhitespace).enumerated() {
                    words.append(Word(text: String(part), kind: .heading, breaksBefore: index == 0))
                }
                breakNext = true
                continue
            }
            for part in line.split(whereSeparator: \.isWhitespace) {
                let token = String(part)
                // A note opens at a word starting "[" and closes at the word with "]".
                if token.hasPrefix("[") { inNote = true }
                words.append(Word(text: token, kind: inNote ? .note : .spoken, breaksBefore: breakNext))
                if inNote, token.contains("]") { inNote = false }
                breakNext = false
            }
        }
        self.words = words
        self.sections = sections
        self.points = points
        var index: [Int] = [], spoken: [String] = []
        for (at, word) in words.enumerated() where word.kind == .spoken {
            let normal = Self.normalised(word.text)
            guard !normal.isEmpty else { continue }
            index.append(at)
            spoken.append(normal)
        }
        spokenIndex = index
        self.spoken = spoken
    }

    /// `# Title` to `###### Title`, the title without its marks; nil for anything else.
    static func heading(in line: String) -> String? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    /// `> Point` (Markdown's quote): the point; nil for anything else.
    static func point(in line: String) -> String? {
        guard line.hasPrefix(">") else { return nil }
        let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// Lowercased letters and digits, apostrophes dropped, as speech is compared.
    static func normalised(_ word: String) -> String {
        String(word.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    private static let common: Set<String> = ["the", "and", "for", "are", "but", "not", "you", "your", "our", "with", "that",
        "this", "from", "have", "has", "had", "was", "were", "will", "its", "about", "into", "than", "then", "them", "they",
        "their", "what", "when", "how", "why", "who", "can", "all", "any", "out", "just", "also", "very", "more", "some"]

    static func keywords(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isWhitespace).map { normalised(String($0)) }
            .filter { $0.count >= 3 && !common.contains($0) && seen.insert($0).inserted }
    }

    /// Said in your own words: at least six in ten of its keywords heard (at least one, and two
    /// when it has three or more), a word counting when its first five letters match.
    static func covered(_ point: Point, heard: Set<String>) -> Bool {
        guard !point.keywords.isEmpty else { return false }
        let stems = Set(heard.map { String($0.prefix(5)) })
        let found = point.keywords.filter { stems.contains(String($0.prefix(5))) }.count
        let needed = max(point.keywords.count >= 3 ? 2 : 1, Int((Double(point.keywords.count) * 0.6).rounded(.up)))
        return found >= needed
    }

    // MARK: - Positions

    /// Where the prompter rests once `count` spoken words have been heard: just after the last
    /// of them, so a stage note or heading that comes next is still ahead, not skipped.
    func word(afterSpoken count: Int) -> Int {
        guard count > 0, !spokenIndex.isEmpty else { return 0 }
        return spokenIndex[min(count, spokenIndex.count) - 1] + 1
    }

    /// The first spoken word at or after drawn word `word`.
    func spoken(atOrAfter word: Int) -> Int {
        spokenIndex.firstIndex { $0 >= word } ?? spokenIndex.count
    }

    /// The section a drawn word is in: the last heading at or before it.
    func section(containing word: Int) -> Int? {
        sections.lastIndex { $0.firstWord <= word }
    }

    /// Where Tab goes: the next section's heading, or nil at the last.
    func nextSection(after position: Double) -> Int? {
        sections.firstIndex { Double($0.firstWord) > position + 0.5 }
    }

    /// Where Shift-Tab goes: the start of this section if you're into it, else the one before.
    func previousSection(before position: Double) -> Int? {
        sections.lastIndex { Double($0.firstWord) < position - 0.5 }
    }

    /// Scrolling: notes and headings pass this many times faster than spoken words.
    static let quickPass = 4.0

    /// Spoken words passed by `position`, for the take's pace.
    func spokenPassed(by position: Double) -> Int { spoken(atOrAfter: Int(position.rounded(.down))) }
}

/// The script's words in lines that fit the prompter: greedy, by measured width, a heading always
/// on a line of its own and each paragraph starting a new line.
enum PrompterLayout {
    struct Line: Equatable {
        let first: Int
        let count: Int
        let isHeading: Bool
    }

    static func wrap(_ words: [PrompterScript.Word], width: Double, space: Double, measure: (Int) -> Double) -> [Line] {
        var lines: [Line] = []
        var first = 0, count = 0, used = 0.0, heading = false
        func close() {
            if count > 0 { lines.append(Line(first: first, count: count, isHeading: heading)) }
            count = 0; used = 0
        }
        for (index, word) in words.enumerated() {
            let w = measure(index)
            let isHeading = word.kind == .heading
            if count > 0, word.breaksBefore || isHeading != heading || used + space + w > width { close() }
            if count == 0 { first = index; heading = isHeading }
            used += (count == 0 ? 0 : space) + w
            count += 1
        }
        close()
        return lines
    }

    /// A run of a line's words drawn the same way.
    struct Segment: Equatable {
        let text: String
        let kind: PrompterScript.Kind
    }

    /// Each line as runs of one kind, its words joined (`shown` gives a word as drawn), so a line
    /// of plain words is a single run: made once per wrap, never per frame.
    static func segments(_ lines: [Line], words: [PrompterScript.Word], shown: (PrompterScript.Word) -> String) -> [[Segment]] {
        lines.map { line in
            var runs: [Segment] = []
            for index in line.first..<line.first + line.count {
                let word = words[index], text = shown(word)
                if let last = runs.last, last.kind == word.kind {
                    runs[runs.count - 1] = Segment(text: last.text + " " + text, kind: word.kind)
                } else {
                    runs.append(Segment(text: text, kind: word.kind))
                }
            }
            return runs
        }
    }

    static func line(containing position: Double, in lines: [Line]) -> Int {
        let word = Int(position)
        return lines.lastIndex { $0.first <= word } ?? 0
    }

    static func progress(within line: Int, at position: Double, in lines: [Line]) -> Double {
        guard lines.indices.contains(line), lines[line].count > 0 else { return 0 }
        return min(1, max(0, (position - Double(lines[line].first)) / Double(lines[line].count)))
    }
}

/// How long a take has run against the script's target length, if it has one.
enum PrompterTiming: Equatable {
    case fine, near, over

    /// Near from 80% of the target, over past it; always fine without a target.
    static func state(elapsed: TimeInterval, target: TimeInterval?) -> PrompterTiming {
        guard let target, target > 0 else { return .fine }
        if elapsed > target { return .over }
        return elapsed >= target * 0.8 ? .near : .fine
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// What a take was like, shown in Studio once the prompter closes.
struct PrompterTakeSummary: Equatable {
    var duration: TimeInterval
    var spokenWords: Int
    /// The longest gap between words heard, in voice mode only.
    var longestPause: TimeInterval?
    var points: Int
    var missed: [String]
    var target: TimeInterval?

    /// Words a minute; nil for a take under five seconds.
    var pace: Int? {
        guard duration >= 5, spokenWords > 0 else { return nil }
        return Int((Double(spokenWords) / (duration / 60)).rounded())
    }

    /// The longest gap between words heard, from the take's start; the quiet after the last word
    /// (finishing, closing) doesn't count.
    static func longestPause(_ heard: [TimeInterval], start: TimeInterval) -> TimeInterval? {
        guard !heard.isEmpty else { return nil }
        var previous = start, longest = 0.0
        for time in heard.sorted() { longest = max(longest, time - previous); previous = time }
        return longest
    }
}

/// A script as saved in scripts.json. Fields added after 4.33 are optional, so every library saved
/// before them still opens: a missing one means the default.
struct SavedScript: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var edited = Date()
    /// How long it should take, in seconds; nil is no target.
    var target: TimeInterval?
    /// Where the prompter last stopped in it, in drawn words, to carry on from.
    var lastPosition: Double?
    /// Its own scroll speed in words a minute; nil uses the prompter's.
    var speed: Double?
}

/// Text brought in from elsewhere, made into a script.
enum ScriptImport {
    /// A PDF's text has a line break at the end of every printed line. Lines of one paragraph are
    /// joined (a word split with a hyphen at a line's end rejoined when the next line carries on in
    /// lower case); a blank line, or a line that is a mark of its own (# or >), still starts anew.
    static func paragraphs(fromPrinted text: String) -> String {
        var paragraphs: [String] = [], current = ""
        func close() { if !current.isEmpty { paragraphs.append(current); current = "" } }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { close(); continue }
            if PrompterScript.heading(in: line) != nil || PrompterScript.point(in: line) != nil {
                close(); paragraphs.append(line); continue
            }
            if current.isEmpty { current = line; continue }
            if current.hasSuffix("-"), current.dropLast().last?.isLetter == true, line.first?.isLowercase == true {
                current = String(current.dropLast()) + line
            } else {
                current += " " + line
            }
        }
        close()
        return paragraphs.joined(separator: "\n\n")
    }
}
