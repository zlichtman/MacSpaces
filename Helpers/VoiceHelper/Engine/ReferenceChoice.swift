import Foundation

/// Whether a reference clip keeps its cleaned sound or the recording as it
/// was. Cleanup (music removed where there is music, light noise reduction
/// everywhere) usually helps, but it can take some of the person away with
/// what it removes. The original is kept only when it is clearly more like
/// the person and no noisier than cleanup would have allowed. Before any of
/// that, a long recording's stretches are narrowed to the cleanest few (`spread`).
enum ReferenceChoice {
    /// Likeness (cosine to the person's fingerprint) the original must gain.
    static let likenessMargin = 0.05
    /// Speech this far above the background is clean, whatever cleanup did.
    static let cleanBackgroundDB = 25.0
    /// Otherwise the original may sit at most this much closer to its background.
    /// Synthetic checks with steady hiss showed the person's fingerprint, taken
    /// from the same noisy recording, rating the noisy original higher; at 6 dB
    /// a 3 dB noisier original was kept although it was less like the person.
    static let backgroundAllowanceDB = 2.0

    /// How far the background (10th percentile of 20 ms frame levels, the
    /// gaps between words) sits under the speech (90th percentile), in dB.
    /// Larger is cleaner; 0 for silence or a clip too short to tell.
    static func backgroundGapDB(_ samples: [Float], rate: Int) -> Double {
        VoiceSamples.backgroundGapDB(samples, rate: rate)
    }

    static func keepsOriginal(cleanLikeness: Double, originalLikeness: Double,
                              cleanGapDB: Double, originalGapDB: Double) -> Bool {
        originalLikeness >= cleanLikeness + likenessMargin
            && (originalGapDB >= cleanBackgroundDB || originalGapDB >= cleanGapDB - backgroundAllowanceDB)
    }

    /// `count` of the `windows` (in recording order), spread across the
    /// recording so one long stretch doesn't crowd out the rest: the windows
    /// are split into `count` runs in order and each run gives one. With
    /// `gapDB` (the `backgroundGapDB` of the recording as it is), that's the
    /// run's cleanest, or the longest within `backgroundAllowanceDB` of it,
    /// since a longer stretch leaves the clip more to choose from; of equals,
    /// the earliest. A score that isn't a finite gap above 0 (silence, too
    /// short to tell, unreadable) doesn't count, and a run with none gives its
    /// first, as without `gapDB`. An error from `gapDB` (cancelling) stops it.
    ///
    /// The gap is a cheap hint at what's worth cleaning, not a measure of the
    /// voice: intermittent music, clicks or sparse speech can score well, so
    /// the purity check, transcription and the ranking after cleanup still decide.
    static func spread(_ windows: [(start: Double, end: Double)], count: Int,
                       gapDB: ((Double, Double) throws -> Double)? = nil) throws -> [(start: Double, end: Double)] {
        guard count > 0 else { return [] }
        guard windows.count > count else { return windows }
        return try (0..<count).map { index in
            let run = windows[(index * windows.count / count)..<((index + 1) * windows.count / count)]
            let first = run[run.startIndex]
            guard let gapDB else { return first }
            let scored = try run.map { (window: $0, gap: try gapDB($0.start, $0.end)) }.filter { $0.gap.isFinite && $0.gap > 0 }
            guard let clearest = scored.map(\.gap).max() else { return first }
            let near = scored.filter { $0.gap >= clearest - backgroundAllowanceDB }
            return near.max { $0.window.end - $0.window.start < $1.window.end - $1.window.start }?.window ?? first
        }
    }
}
