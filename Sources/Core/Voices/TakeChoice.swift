import Foundation

/// Studio's Best Quality (Siren's `TakeJudge`): each piece of a reading is made up to `attempts`
/// times and the one most like the voice is kept. The engines sample every attempt afresh, so some
/// come out less like the voice, skip or repeat words, or run on. Each attempt is scored on likeness
/// (its speaker fingerprint against the reference clip's, the same WeSpeaker cosine that sorts and
/// joins voices), on saying the words (on-device transcription against the text, when it can run),
/// and on a length near the clip's pace. Making more stops once one is good enough. Pure, so
/// `Scripts/check-voices.sh` checks it; the helper measures and renders.
enum TakeChoice {
    /// Attempts per piece with Best Quality; Fast makes one.
    static let attempts = 3
    /// An attempt this close to the words and this alike is kept without making more.
    static let goodWordError = 0.1
    static let goodLikeness = 0.75
    /// Lengths inside this share of what the clip's pace predicts aren't penalised.
    static let fairLength: ClosedRange<Double> = 0.6...1.6

    struct Score: Equatable, Sendable {
        /// Cosine similarity to the reference clip's fingerprint; nil if it couldn't be measured.
        let likeness: Double?
        /// Share of the text's words missed, swapped or added; nil if transcription couldn't run.
        let wordError: Double?
        /// The attempt's length over the length the clip's pace predicts; nil without a pace.
        let lengthRatio: Double?
        /// Whether the clip's pace was known, so the length could be checked. With no pace (a very
        /// short clip) there's nothing to check it against, which isn't a failed check.
        var paceKnown: Bool = true

        /// A cosine similarity, a word error rate (0 or more) and a length ratio (above 0), or nil
        /// where it isn't one: nonsense counts as unmeasured.
        var measuredLikeness: Double? { likeness.flatMap { $0.isFinite && (-1...1).contains($0) ? $0 : nil } }
        var measuredWordError: Double? { wordError.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } }
        var measuredLength: Double? { lengthRatio.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }

        /// Higher is better: likeness (0.5 when unmeasured), less 1.5 for every word in error (at
        /// most all of them, `unmeasuredWordError` when unheard), less how far the length strays
        /// outside `fairLength`. A failed measurement costs an attempt little, but gains it nothing.
        var total: Double {
            var total = measuredLikeness ?? 0.5
            total -= 1.5 * min(1, measuredWordError ?? TakeChoice.unmeasuredWordError)
            if let lengthRatio = measuredLength {
                total -= max(0, lengthRatio - TakeChoice.fairLength.upperBound) + max(0, TakeChoice.fairLength.lowerBound - lengthRatio)
            }
            return total
        }

        /// Good enough to stop making more attempts of this piece: likeness and words were both
        /// measured and both pass, and the length too when the pace is known. A check that
        /// couldn't run never counts as a pass.
        var isGoodEnough: Bool {
            guard let likeness = measuredLikeness, let wordError = measuredWordError else { return false }
            guard likeness >= TakeChoice.goodLikeness, wordError <= TakeChoice.goodWordError else { return false }
            guard paceKnown else { return true }
            return measuredLength.map { TakeChoice.fairLength.contains($0) } ?? false
        }
    }

    /// What unheard words cost in `Score.total`: as if past the good line (`goodWordError`), so an
    /// attempt whose words couldn't be checked never outscores one that said them all just because
    /// nobody heard it.
    static let unmeasuredWordError = 0.25

    /// Whether `take` replaces `best` so far: one good enough to stop always beats one that isn't,
    /// whatever their totals, so stopping on a good attempt also keeps a good attempt. Otherwise
    /// the higher total wins; of equals, or against a total that isn't a number, the earlier stays.
    static func replaces(_ take: Score, best: Score?) -> Bool {
        guard let best else { return true }
        if take.isGoodEnough != best.isGoodEnough { return take.isGoodEnough }
        guard take.total.isFinite else { return false }
        return !best.total.isFinite || take.total > best.total
    }

    /// The best of `scores` by `replaces` (the first of equals); nil for none.
    static func best(_ scores: [Score]) -> Int? {
        var best: Int?
        for index in scores.indices where replaces(scores[index], best: best.map { scores[$0] }) { best = index }
        return best
    }

    /// Whether to make another attempt after `made`: fewer than `limit` made and none good enough.
    static func wantsAnother(_ made: [Score], limit: Int = attempts) -> Bool {
        made.count < limit && !made.contains(where: \.isGoodEnough)
    }

    /// The seed of an attempt: the take's own seed for the first attempt of the first piece, and a
    /// different one, fixed by the take's seed, for every other, so the same seed makes the same
    /// Best Quality take again.
    static func seed(_ seed: UInt64, piece: Int, attempt: Int) -> UInt64 {
        guard piece > 0 || attempt > 0 else { return seed }
        // SplitMix64 of the seed and the attempt's place.
        var z = seed &+ UInt64(piece * attempts + attempt) &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// The voice's pace in the clip, words per second; nil for a clip too short to tell.
    static func wordsPerSecond(transcript: String, seconds: Double) -> Double? {
        let count = words(transcript).count
        return seconds > 1 && count > 2 ? Double(count) / seconds : nil
    }

    /// An attempt's length over what `wordsPerSecond` predicts for `text`; nil without either.
    static func lengthRatio(seconds: Double, text: String, wordsPerSecond: Double?) -> Double? {
        let count = words(text).count
        guard let wordsPerSecond, wordsPerSecond > 0, count > 0 else { return nil }
        return seconds / (Double(count) / wordsPerSecond)
    }

    /// Word error rate: edits (missed, swapped, added words) over the words meant.
    static func wordErrorRate(said: String, meant: String) -> Double {
        let a = words(meant), b = words(said)
        guard !a.isEmpty else { return b.isEmpty ? 0 : 1 }
        guard !b.isEmpty else { return 1 }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return Double(row[b.count]) / Double(a.count)
    }

    /// Lowercased words without punctuation, numbers spelled out ("2" and "two" are the same word
    /// to a listener).
    static func words(_ text: String) -> [String] {
        let speller = NumberFormatter()
        speller.numberStyle = .spellOut
        speller.locale = Locale(identifier: "en_US")
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
            .flatMap { word -> [String] in
                guard let number = Int(word), let spelled = speller.string(from: NSNumber(value: number)) else { return [word] }
                return spelled.components(separatedBy: CharacterSet(charactersIn: " -")).filter { !$0.isEmpty }
            }
    }
}
