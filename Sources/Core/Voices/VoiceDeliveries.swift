import Foundation

/// Siren's deliveries: the same voice copied from a different clip of them. The engines continue
/// a clip's pace and mood, so a slower, quieter clip reads Slow and Soft and a quicker, livelier
/// one Upbeat. Natural is the voice's clip itself.
enum VoiceDelivery: String, Codable, CaseIterable, Identifiable, Sendable {
    case natural, soft, upbeat

    var id: String { rawValue }
    var title: String {
        switch self {
        case .natural: "Natural"
        case .soft: "Slow and Soft"
        case .upbeat: "Upbeat"
        }
    }

    /// A clip of a delivery other than Natural, kept beside the voice's clip as <delivery>.wav.
    struct Clip: Codable, Equatable, Sendable {
        let delivery: VoiceDelivery
        /// Where it is while the person waits to be named (Voices/Sorting); empty once saved.
        var file: String
        /// Exactly what it says.
        let transcript: String
        let seconds: Double
        /// What sorting measured of it, for choosing between a voice's clips.
        var evidence: VoiceSamples.Evidence? = nil
    }

    /// One of a person's clips, as sorting measured it.
    struct Candidate: Equatable, Sendable {
        /// How good a clip it is to copy (higher is better).
        let score: Double
        let words: Int
        let seconds: Double
        let loudness: Double
        let liveliness: Double

        var wordsPerSecond: Double { seconds > 0 ? Double(words) / seconds : 0 }
    }

    /// Candidates within this of the best score are good enough to read a delivery from.
    static let strongMargin = 0.12

    /// Which candidates read each delivery (Siren's choice): Natural is the best; with three or
    /// more strong candidates, Slow and Soft is the slowest and quietest of them and Upbeat the
    /// quickest and liveliest, each by how it compares with the others. A delivery that would be
    /// the Natural clip again is left out. Nothing for an empty list.
    static func pick(_ candidates: [Candidate]) -> [VoiceDelivery: Int] {
        guard let best = candidates.indices.max(by: { candidates[$0].score < candidates[$1].score }) else { return [:] }
        var picks: [VoiceDelivery: Int] = [.natural: best]
        let strong = candidates.indices.filter { candidates[$0].score >= candidates[best].score - strongMargin }
        guard strong.count >= 3 else { return picks }
        let pace = zScores(strong.map { candidates[$0].wordsPerSecond })
        let loud = zScores(strong.map { candidates[$0].loudness })
        let lively = zScores(strong.map { candidates[$0].liveliness })
        let soft = strong.indices.min { pace[$0] + loud[$0] < pace[$1] + loud[$1] }!
        let upbeat = strong.indices.max { pace[$0] + lively[$0] < pace[$1] + lively[$1] }!
        if strong[soft] != best { picks[.soft] = strong[soft] }
        if strong[upbeat] != best, strong[upbeat] != strong[soft] { picks[.upbeat] = strong[upbeat] }
        return picks
    }

    static func zScores(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [] }
        let mean = values.reduce(0, +) / Double(values.count)
        let spread = (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)).squareRoot()
        return values.map { spread > 0 ? ($0 - mean) / spread : 0 }
    }
}
