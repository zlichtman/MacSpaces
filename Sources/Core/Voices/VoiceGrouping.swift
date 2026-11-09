import Foundation

/// Sorts the people found in several recordings into one list: the same person heard in two
/// recordings becomes one entry. Pure, so `Scripts/check-voices.sh` checks it on made-up
/// fingerprints. The thresholds are Siren's (`BatchMatch`, `BatchGroupingPolicy`).
enum VoiceGrouping {
    /// One person found in one recording.
    struct Member: Equatable, Sendable {
        let recording: Int
        let person: Int
        let seconds: Double
        /// WeSpeaker fingerprint (256 floats); nil if it couldn't be worked out.
        let fingerprint: [Float]?
    }

    /// Two recordings' people are one when every pair of their fingerprints is at least this
    /// alike (cosine, complete link).
    static let sameAcrossRecordings = 0.75
    /// A found person is offered a tagged voice's name when this alike.
    static let knownVoice = 0.80

    /// Groups of indices into `members`, most heard first. Two people of one recording are
    /// never joined (the recording already told them apart), uncertain matches stay apart, and
    /// someone with no fingerprint stays on their own.
    static func groups(_ members: [Member]) -> [[Int]] {
        var groups: [[Int]] = []
        // Most heard first, so each group starts from its clearest fingerprint.
        for index in members.indices.sorted(by: { members[$0].seconds > members[$1].seconds }) {
            let member = members[index]
            guard let print = member.fingerprint, isUsable(print) else { groups.append([index]); continue }
            var best: (group: Int, score: Double)?
            for (g, group) in groups.enumerated() {
                guard !group.contains(where: { members[$0].recording == member.recording }) else { continue }
                let scores = group.map { other in members[other].fingerprint.map { similarity(print, $0) } ?? -1 }
                guard let worst = scores.min(), worst >= sameAcrossRecordings else { continue }
                if best.map({ worst > $0.score }) ?? true { best = (g, worst) }
            }
            if let best { groups[best.group].append(index) } else { groups.append([index]) }
        }
        func heard(_ group: [Int]) -> Double { group.reduce(0) { $0 + members[$1].seconds } }
        return groups.map { $0.sorted() }.sorted { heard($0) > heard($1) }
    }

    /// The tagged voice a fingerprint sounds like, if any clearly does.
    static func match(_ fingerprint: [Float]?, among known: [(id: String, fingerprint: [Float])]) -> String? {
        guard let fingerprint, isUsable(fingerprint) else { return nil }
        let scored = known.filter { isUsable($0.fingerprint) }.map { ($0.id, similarity(fingerprint, $0.fingerprint)) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= knownVoice else { return nil }
        return best.0
    }

    /// Several fingerprints of one person, weighted by how long each was heard.
    static func average(_ prints: [([Float], Double)]) -> [Float]? {
        let usable = prints.filter { isUsable($0.0) && $0.1 > 0 }
        guard let first = usable.first?.0 else { return nil }
        var sum = [Double](repeating: 0, count: first.count)
        for (print, weight) in usable where print.count == first.count {
            let norm = (print.reduce(0) { $0 + Double($1) * Double($1) }).squareRoot()
            for i in print.indices { sum[i] += Double(print[i]) / norm * weight }
        }
        let norm = (sum.reduce(0) { $0 + $1 * $1 }).squareRoot()
        return norm > 0 ? sum.map { Float($0 / norm) } : nil
    }

    static func similarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices {
            dot += Double(a[i]) * Double(b[i]); na += Double(a[i]) * Double(a[i]); nb += Double(b[i]) * Double(b[i])
        }
        return na > 0 && nb > 0 ? dot / (na * nb).squareRoot() : 0
    }

    static func isUsable(_ print: [Float]) -> Bool {
        !print.isEmpty && print.allSatisfy(\.isFinite) && print.contains { $0 != 0 }
    }
}
