import Foundation

/// Finds where a speaker is in a script from the last few words heard. Pure, so
/// it's checked on its own (Scripts/check-prompter.sh). It only moves forward
/// (or a couple of words back), so a repeated phrase never yanks the script
/// back to an earlier paragraph.
enum ScriptAligner {
    /// Lowercased words without punctuation, as both the script and speech are compared.
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .map { $0.replacingOccurrences(of: "'", with: "") }
            .filter { !$0.isEmpty }
    }

    /// The index of the word after the best match for the end of `heard`,
    /// searching from a little before `from` to `lookahead` words after it.
    static func position(script: [String], heard: [String], from: Int, lookahead: Int = 60) -> Int? {
        let tail = Array(heard.suffix(5))
        guard !tail.isEmpty, !script.isEmpty else { return nil }
        let lower = max(0, from - 2), upper = min(script.count - 1, from + lookahead)
        guard lower <= upper else { return nil }
        var best: (index: Int, score: Int)?
        for end in lower...upper {
            var score = 0
            // Compare the heard words, last first, with the script ending at `end`.
            for (offset, word) in tail.reversed().enumerated() {
                let index = end - offset
                guard index >= 0 else { break }
                if similar(script[index], word) { score += 1 }
            }
            // A single word needs to be distinctive to count; nearer matches win ties.
            if score > (best?.score ?? 0) { best = (end, score) }
        }
        guard let best else { return nil }
        let needed = tail.count >= 3 ? 2 : 1
        guard best.score >= needed else { return nil }
        if best.score == 1, tail.last.map({ $0.count < 4 }) ?? true { return nil }
        return best.index + 1
    }

    /// Equal, or close enough for speech recognition's spelling (one edit in a longer word).
    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 4, b.count >= 4, abs(a.count - b.count) <= 1 else { return false }
        return editDistance(a, b) <= 1
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
