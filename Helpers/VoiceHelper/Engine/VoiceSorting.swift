import Accelerate

/// The second look at who's who in one recording, after the pieces are grouped
/// by voice. Grouping at one threshold makes two kinds of mistake: one person
/// split in two (their voice changed: on the phone, laughing, music under
/// them), and a piece of someone else left inside a person (an 8 s piece that
/// hides a change of speaker, or a voice Sortformer reused). This fixes both
/// with arithmetic on fingerprints already taken, so it costs no model time.
enum VoiceSorting {
    /// A fingerprinted piece of talk: its unit vector, length and Sortformer voice.
    struct Piece: Sendable {
        var vector: [Float]
        var seconds: Double
        var slot: Int
    }

    /// A piece this unlike its own person (cosine to their average)...
    static let outlierSimilarity: Float = 0.5
    /// ...moves to someone it's at least this like, by at least `moveMargin`.
    static let moveSimilarity: Float = 0.6
    static let moveMargin: Float = 0.15
    /// Two people this alike (cosine of their averages) are one person split
    /// in two, if they hardly ever talk at the same time.
    static let joinSimilarity: Float = 0.70
    /// Seconds two people may overlap and still be joined: Sortformer marks a
    /// few frames as two voices at once around any change of speaker. Someone
    /// can't talk over themself, so more than this means two people.
    static let joinOverlapSeconds = 0.5

    /// `groups` (one per piece, as `SourceProcessor.cluster` returns them) after
    /// moving out pieces that sound like someone else and joining people split
    /// in two. `overlap(a, b)` is how long Sortformer voices `a` and `b` talked
    /// at the same time. Returns a group per piece, 0 for the most talk.
    static func refine(_ pieces: [Piece], groups: [Int], overlap: (Int, Int) -> Double) -> [Int] {
        guard pieces.count == groups.count, !pieces.isEmpty else { return groups }
        var group = groups

        // Pieces that sound like someone else move to them. One pass, against
        // the averages before any move, so the order of pieces doesn't matter.
        let before = centroids(pieces, group)
        for (index, piece) in pieces.enumerated() {
            guard let own = before[group[index]] else { continue }
            let mine = cosine(piece.vector, own)
            guard mine < outlierSimilarity else { continue }
            var best: (key: Int, score: Float)?
            for key in before.keys.sorted() where key != group[index] {
                let score = cosine(piece.vector, before[key]!)
                if best.map({ score > $0.score }) ?? true { best = (key, score) }
            }
            if let best, best.score >= moveSimilarity, best.score - mine >= moveMargin { group[index] = best.key }
        }

        // People who sound alike and never talk over each other are one person.
        // The closest pair joins first; averages are recomputed after each join.
        while true {
            let averages = centroids(pieces, group)
            var slots: [Int: Set<Int>] = [:]
            for (index, piece) in pieces.enumerated() { slots[group[index], default: []].insert(piece.slot) }
            let keys = averages.keys.sorted()
            var best: (a: Int, b: Int, score: Float)?
            for (i, a) in keys.enumerated() {
                for b in keys[(i + 1)...] {
                    let score = cosine(averages[a]!, averages[b]!)
                    guard score >= joinSimilarity, best.map({ score > $0.score }) ?? true else { continue }
                    var together = 0.0
                    for s in slots[a] ?? [] { for t in slots[b] ?? [] where s != t { together += overlap(s, t) } }
                    if together <= joinOverlapSeconds { best = (a, b, score) }
                }
            }
            guard let best else { break }
            for index in group.indices where group[index] == best.b { group[index] = best.a }
        }

        // Most talk first, as before.
        var talk: [Int: Double] = [:]
        for (index, piece) in pieces.enumerated() { talk[group[index], default: 0] += piece.seconds }
        let order = talk.keys.sorted { talk[$0]! == talk[$1]! ? $0 < $1 : talk[$0]! > talk[$1]! }
        let renumber = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return group.map { renumber[$0]! }
    }

    /// Each group's length-weighted average of unit vectors, scaled to unit length.
    static func centroids(_ pieces: [Piece], _ group: [Int]) -> [Int: [Float]] {
        var sums: [Int: [Float]] = [:]
        for (index, piece) in pieces.enumerated() where !piece.vector.isEmpty {
            let weighted = vDSP.multiply(Float(max(piece.seconds, 1e-3)), unit(piece.vector))
            sums[group[index]] = sums[group[index]].map { $0.count == weighted.count ? vDSP.add($0, weighted) : $0 } ?? weighted
        }
        return sums.mapValues(unit)
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let norms = sqrt(vDSP.sumOfSquares(a) * vDSP.sumOfSquares(b))
        return norms > 0 ? vDSP.dot(a, b) / norms : 0
    }

    private static func unit(_ v: [Float]) -> [Float] {
        let norm = sqrt(vDSP.sumOfSquares(v))
        return norm > 0 ? vDSP.divide(v, norm) : v
    }
}
