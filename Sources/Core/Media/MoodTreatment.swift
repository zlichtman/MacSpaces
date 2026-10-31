import Foundation

/// The motion Mood sets behind a line's poster, chosen from how the line feels
/// (on-device sentiment, -1…1, re-centred by `calibrated`) and how fast it's sung
/// (words per second over its sung span). Pure, so `check-lyrics` covers the
/// choice and the word timing.
enum MoodTreatment: String, CaseIterable, Sendable {
    /// Soft motes rising slowly: calm, plain lines at an easy pace.
    case drift
    /// Rings spreading from behind the headline on the beat: fast, plain lines.
    case pulse
    /// A warm glow swelling and breathing: warm lines at an easy pace.
    case bloom
    /// Fine streaks falling at two depths: sad lines.
    case rain
    /// Bands of light passing behind the headline as the line starts: short, emphatic lines.
    case sweep
    /// Slow ribbons of colour flowing across: plain lines at a medium pace.
    case aurora
    /// Sparks rising quickly from below: warm, fast lines.
    case embers
    /// Banks of fog drifting slowly: sad, slow lines.
    case haze

    /// The pace untimed lyrics count as (they have no sung span).
    static let mediumPace = 2.2
    /// Below this many words a second a line is slow.
    static let slowPace = 1.6
    /// At or above this many words a second a line is fast.
    static let fastPace = 3.2

    /// Words a second over the line's sung span; nil for untimed lyrics and rests.
    static func wordsPerSecond(words: Int, span: ClosedRange<TimeInterval>?) -> Double? {
        guard let span, words > 0 else { return nil }
        return Double(words) / max(0.5, span.upperBound - span.lowerBound)
    }

    /// Short lines with feeling sweep. Otherwise feeling picks a family and pace a
    /// member: sad lines are haze when slow, rain otherwise; warm lines bloom, or
    /// throw embers when fast; plain lines drift when slow, flow as aurora at a
    /// medium pace (untimed lyrics too) and pulse when fast.
    static func choose(sentiment: Double, wordsPerSecond: Double?, wordCount: Int) -> MoodTreatment {
        let pace = wordsPerSecond ?? mediumPace
        if wordCount > 0, wordCount <= 2 || (wordCount <= 3 && abs(sentiment) >= 0.4) { return .sweep }
        if sentiment <= -0.3 { return pace < slowPace ? .haze : .rain }
        if sentiment >= 0.3 { return pace >= fastPace ? .embers : .bloom }
        if pace >= fastPace { return .pulse }
        return pace < slowPace ? .drift : .aurora
    }

    /// How much faster than its resting pace a treatment moves (0.75…1.35): the
    /// motion follows the singing without ever hurrying.
    static func tempo(wordsPerSecond: Double?) -> Double {
        let pace = wordsPerSecond ?? mediumPace
        return min(1.35, max(0.75, 0.75 + (pace - 1.2) * 0.2))
    }

    /// How hard a line lands when it starts (0.6…1): fast lines hit harder.
    static func hitStrength(wordsPerSecond: Double?) -> Double {
        let pace = wordsPerSecond ?? mediumPace
        return min(1, max(0.6, 0.6 + (pace - 1.5) * 0.16))
    }

    // MARK: Words

    /// Words in a line, as Mood counts them for pace and emphasis.
    static func wordCount(_ line: String) -> Int {
        words(line).count
    }

    /// The line's words in order, punctuation-only tokens dropped.
    static func words(_ line: String) -> [String] {
        line.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }.map(String.init)
    }

    /// A rough syllable count (vowel groups, a silent final e dropped), at least 1:
    /// how long a word takes to sing, relative to its neighbours.
    static func syllables(_ word: String) -> Int {
        let letters = Array(word.lowercased().filter(\.isLetter))
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var groups = 0, previous = false
        for letter in letters {
            let vowel = vowels.contains(letter)
            if vowel, !previous { groups += 1 }
            previous = vowel
        }
        if letters.count > 2, letters.last == "e", !vowels.contains(letters[letters.count - 2]), groups > 1 { groups -= 1 }
        return max(1, groups)
    }

    /// When each word starts, in seconds from the first, spread over `sung` seconds
    /// by syllables: a long word takes longer than "a" before the next one starts.
    static func wordOnsets(_ words: [String], sung: TimeInterval) -> [TimeInterval] {
        guard !words.isEmpty else { return [] }
        let weights = words.map { Double(syllables($0)) }
        let total = weights.reduce(0, +)
        var start = 0.0
        return weights.map { weight in
            defer { start += weight }
            return max(0, sung) * start / total
        }
    }

    /// Lines are sung for about this much of their span; the rest is a held note or a breath.
    static let sungShare = 0.85

    /// Seconds from now until each word of the line is sung, from its sung span in
    /// song time and the song's time now; nil when the timing isn't known (untimed
    /// lyrics). Words already past come out negative.
    static func wordDelays(words: [String], span: ClosedRange<TimeInterval>?, songTime: TimeInterval?) -> [TimeInterval]? {
        guard let span, let songTime, !words.isEmpty else { return nil }
        let sung = sungShare * max(0.5, span.upperBound - span.lowerBound)
        return wordOnsets(words, sung: sung).map { span.lowerBound + $0 - songTime }
    }

    // MARK: Feeling

    /// Apple's sentiment model (`NLTagger`, `.sentimentScore`) reads plain lyric lines
    /// as mildly negative (-0.6 for "Here comes the sun", about the same as "I'm crying
    /// in the rain"), so its score is re-centred there, and a few unmistakably sad words
    /// tip a line toward Rain. A missing score counts as that neutral middle.
    static func calibrated(raw: Double?, line: String) -> Double {
        let centred = min(1, max(-1, ((raw ?? neutralScore) - neutralScore) / 1.5))
        let words = line.lowercased().filter { $0 != "'" && $0 != "’" }
            .split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.contains(where: sadWords.contains) ? max(-1, centred - 0.4) : centred
    }

    /// Where the model puts a plain, neutral lyric line.
    static let neutralScore = -0.5

    static let sadWords: Set<String> = [
        "cry", "cried", "cries", "crying", "tears", "weep", "weeping", "lonely", "alone", "goodbye", "broken",
        "heartbreak", "heartbroken", "hurt", "hurts", "hurting", "pain", "miss", "missing", "sorry", "lost", "lose",
        "losing", "die", "dying", "dead", "gone", "sad", "sorrow", "grief", "empty", "regret", "bleed", "bleeding", "hate",
    ]
}
