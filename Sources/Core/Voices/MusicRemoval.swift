import Foundation

/// When sorting takes music out from under someone talking (Siren's music removal), and how its
/// pieces are joined. Foundation only, so the checks run it without a model; the voice helper's
/// `SourceProcessor.clean` runs SAM-Audio on what this lets through.
enum MusicRemoval {
    /// A stretch goes to SAM-Audio when its quietest moments (the gaps between words) are within
    /// this many dB of its speech (Siren's gate). With music 10 dB under the talk they measure
    /// -14 to -17 dB; in a clean recording, -60 dB or lower.
    static let gateDB: Float = -30
    /// After separation, a stretch keeps its original sound unless SAM-Audio put at least this
    /// share of its energy into the residual (the part that isn't speech).
    static let residualDB: Float = -18
    /// The deepest the music mask cuts any time-frequency cell.
    static let maskFloorDB: Float = -40
    /// Longer stretches are separated in overlapping pieces of this many seconds.
    static let pieceSeconds = 24.0

    /// How far the quietest moments (5th percentile of 20 ms frames: the gaps between words) sit
    /// below the speech (90th percentile), in dB; -120 for a stretch under 10 frames.
    static func gapLevelDB(_ samples: [Float], rate: Int) -> Float {
        let frame = max(1, rate / 50)
        var levels: [Float] = []
        var i = 0
        while i + frame <= samples.count {
            var sum: Float = 0
            for j in i..<(i + frame) { sum += samples[j] * samples[j] }
            levels.append(20 * log10(max((sum / Float(frame)).squareRoot(), 1e-6)))
            i += frame
        }
        guard levels.count >= 10 else { return -120 }
        levels.sort()
        return levels[Int(Double(levels.count - 1) * 0.05)] - levels[Int(Double(levels.count - 1) * 0.9)]
    }

    /// Whether a stretch with this `gapLevelDB` is worth separating.
    static func needsSeparation(gapDB: Float) -> Bool { gapDB > gateDB }

    /// Residual energy as a share of speech plus residual, in dB; -100 for silence.
    static func residualShareDB(speechEnergy t: Float, residualEnergy r: Float, samples: Int) -> Float {
        guard t + r > Float(samples) * 1e-9 else { return -100 }
        return 10 * log10(max(r / (t + r), 1e-10))
    }

    /// Whether SAM-Audio found music after all; if not, the original sound is kept.
    static func foundMusic(residualShareDB share: Float) -> Bool { share > residualDB }

    /// Runs `transform` over overlapping pieces of `samples` and joins the results: each piece
    /// sees `context` extra samples either side (zeros past the ends), and neighbours meet with a
    /// short linear crossfade of `fade` samples. A transform that returns its input gives the
    /// input back.
    static func overlapped(_ samples: [Float], step: Int, context: Int, fade: Int,
                           transform: ([Float]) async throws -> [Float]) async throws -> [Float] {
        precondition(step > 0)
        let n = samples.count, half = min(fade / 2, context)
        var output: [Float] = []
        output.reserveCapacity(n)
        var tail: [Float] = []
        var start = 0
        while start < n {
            let end = min(start + step, n)
            let lo = start - context, hi = end + context
            var piece = [Float](repeating: 0, count: hi - lo)
            let from = max(0, lo), to = min(n, hi)
            piece.replaceSubrange((from - lo)..<(to - lo), with: samples[from..<to])
            let result = fitted(try await transform(piece), piece.count)
            let ownLo = max(0, start - half), ownHi = min(n, end + half)
            var own = Array(result[(ownLo - lo)..<(ownHi - lo)])
            let blend = min(tail.count, own.count)
            for i in 0..<blend {
                let w = Float(i + 1) / Float(blend + 1)
                own[i] = own[i] * w + tail[i] * (1 - w)
            }
            if end < n {
                let keep = min(own.count, ownHi - (end - half))
                tail = Array(own.suffix(keep))
                own.removeLast(keep)
            } else {
                tail = []
            }
            output += own
            start = end
        }
        return output
    }

    /// `samples` cut or padded with zeros to `count`.
    static func fitted(_ samples: [Float], _ count: Int) -> [Float] {
        if samples.count == count { return samples }
        if samples.count > count { return Array(samples.prefix(count)) }
        return samples + [Float](repeating: 0, count: count - samples.count)
    }
}
