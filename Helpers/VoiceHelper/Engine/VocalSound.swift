import Foundation

/// A sound someone makes that isn't a word but is part of how they sound: a
/// laugh, a sigh, a breath. Kept with a recording's timeline for the coverage
/// map (`VoiceCoverage`); samples are still cut around them. Foundation only,
/// so the model-free checks can compile it.
struct VocalSound: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case laugh, sigh, breath

        var title: String {
            switch self {
            case .laugh: "Laughs"
            case .sigh: "Sighs"
            case .breath: "Breaths"
            }
        }

        /// The sound classifier's labels for it.
        var labels: [String] {
            switch self {
            case .laugh: ["laughter", "giggling", "belly_laugh"]
            case .sigh: ["sigh"]
            case .breath: ["breathing", "gasp"]
            }
        }
    }

    var kind: Kind
    var start: Double
    var end: Double

    /// How many of `sounds` are one person's: within `margin` seconds of
    /// their talk (`ranges`), and no nearer anyone else's (`others`).
    static func counts(_ sounds: [VocalSound], near ranges: [ClosedRange<Double>], others: [[ClosedRange<Double>]],
                       margin: Double = 1) -> [Kind: Int] {
        func gap(_ sound: VocalSound, _ talk: [ClosedRange<Double>]) -> Double {
            talk.map { max(0, $0.lowerBound - sound.end, sound.start - $0.upperBound) }.min() ?? .infinity
        }
        var counts: [Kind: Int] = [:]
        for sound in sounds {
            let mine = gap(sound, ranges)
            guard mine <= margin, others.allSatisfy({ gap(sound, $0) >= mine }) else { continue }
            counts[sound.kind, default: 0] += 1
        }
        return counts
    }
}
