import Accelerate
import Foundation

/// Bounded signal/transcript heuristics for reference selection. These scores
/// estimate reference fitness, not speaker identity or perceptual likeness.
/// Weak references remain usable; callers compare candidates rather than
/// treating a score as an admission threshold.
enum ReferenceFitness {
    static func qualityScore(samples: [Float], transcript: String, sampleRate: Int = 24_000) -> Double {
        guard sampleRate > 0, !samples.isEmpty, samples.allSatisfy({ $0.isFinite }) else { return 0 }
        let seconds = Double(samples.count) / Double(sampleRate)
        let frameSize = max(1, sampleRate / 50)
        var levels: [Double] = []
        for start in stride(from: 0, to: samples.count, by: frameSize) {
            let end = min(samples.count, start + frameSize)
            var power = 0.0
            for index in start..<end { power += Double(samples[index]) * Double(samples[index]) }
            levels.append((power / Double(end - start)).squareRoot())
        }
        let peak = levels.max() ?? 0
        guard peak > 0.000_01 else { return 0 }
        let activeFloor = max(0.000_1, peak * 0.1)
        let coverage = Double(levels.filter { $0 >= activeFloor }.count) / Double(max(1, levels.count))
        let clipped = Double(samples.filter { abs($0) >= 0.98 }.count) / Double(samples.count)
        let words = transcript.split(whereSeparator: \.isWhitespace).count
        let rate = Double(words) / max(seconds, 0.01)
        let rateFitness: Double
        if words == 0 { rateFitness = 0 }
        else if rate < 0.7 { rateFitness = max(0, rate / 0.7) }
        else if rate <= 4.5 { rateFitness = 1 }
        else { rateFitness = max(0, 1 - (rate - 4.5) / 4.5) }
        let durationFitness = min(1, seconds / 12)
        let clippingFitness = max(0, 1 - clipped * 20)
        let score = (0.30 * durationFitness + 0.35 * coverage + 0.20 * rateFitness + 0.15 * clippingFitness)
        return min(1, max(0, score * clippingFitness))
    }

    static func sourceDynamics(_ samples: [Float], sampleRate: Int = 24_000) -> (loudness: Double, liveliness: Double) {
        guard sampleRate > 0, !samples.isEmpty, samples.allSatisfy({ $0.isFinite }) else { return (-100, 0) }
        let frame = max(1, sampleRate / 20)
        var levels: [Double] = []
        for start in stride(from: 0, to: samples.count, by: frame) {
            let end = min(samples.count, start + frame)
            let power = samples[start..<end].reduce(0.0) { $0 + Double($1) * Double($1) }
            levels.append((power / Double(max(1, end - start))).squareRoot())
        }
        let threshold = max(0.000_1, (levels.max() ?? 0) * 0.1)
        let active = levels.filter { $0 >= threshold }.map { 20 * log10($0) }
        guard !active.isEmpty else { return (-100, 0) }
        let mean = active.reduce(0, +) / Double(active.count)
        let spread = (active.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(active.count)).squareRoot()
        return (mean, spread)
    }

    /// Stretches of a clip that sound like speech but sit outside every word
    /// the recogniser placed: words it missed, a
    /// mumble, or the start of a word the clip's edge cut into. The model reads
    /// a reference's text over its sound, so text that leaves speech out makes
    /// it misplace words and lose the voice.
    ///
    /// Speech here is a 20 ms frame within 30 dB of the clip's loud frames, at
    /// least 10 dB over its quiet ones, and periodic like a voice (80–400 Hz),
    /// which leaves out breaths, clicks and noise. Each word is allowed 0.12 s
    /// before it and 0.3 s after (the recogniser ends a phrase's last word
    /// early, before its tail fades), so a short word missed between two
    /// others can hide; missed phrases, mumbles and cut-in words can't.
    /// Stretches under 0.1 s are ignored. A clip with no clear speech above
    /// its floor returns nothing.
    static func unheardSpeech(_ samples: [Float], sampleRate: Int = 24_000,
                              words: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        guard sampleRate >= 8_000, samples.count >= sampleRate / 10, samples.allSatisfy({ $0.isFinite }) else { return [] }
        // Voicing is judged at 8 kHz, where 80–400 Hz is a lag of 20–100 samples.
        let factor = sampleRate / 8_000
        let rate = Double(sampleRate) / Double(factor)
        let low: [Float] = stride(from: 0, to: samples.count - factor + 1, by: factor).map { start in
            var sum: Float = 0
            for index in start..<start + factor { sum += samples[index] }
            return sum / Float(factor)
        }
        let hop = Int(rate * 0.02), window = Int(rate * 0.04)
        let minLag = Int(rate / 400), maxLag = Int(rate / 80)
        let frames = (low.count - window - maxLag) / hop
        guard frames > 0 else { return [] }
        var levels = [Double](repeating: -120, count: frames)
        var periodic = [Bool](repeating: false, count: frames)
        low.withUnsafeBufferPointer { signal in
            guard let base = signal.baseAddress else { return }
            for frame in 0..<frames {
                let start = base + frame * hop
                var energy: Float = 0
                vDSP_svesq(start, 1, &energy, vDSP_Length(window))
                levels[frame] = 10 * log10(max(Double(energy) / Double(window), 1e-12))
                guard energy > 0 else { continue }
                var best: Float = 0
                for lag in minLag...maxLag {
                    var product: Float = 0, shifted: Float = 0
                    vDSP_dotpr(start, 1, start + lag, 1, &product, vDSP_Length(window))
                    vDSP_svesq(start + lag, 1, &shifted, vDSP_Length(window))
                    if shifted > 0 { best = max(best, product / (energy * shifted).squareRoot()) }
                }
                periodic[frame] = best >= 0.5
            }
        }
        let sorted = levels.sorted()
        let quiet = sorted[frames / 10], loud = sorted[min(frames - 1, frames * 95 / 100)]
        guard loud - quiet >= 10 else { return [] }
        let threshold = max(quiet + 10, loud - 30)
        var stretches: [ClosedRange<Double>] = []
        var runStart: Double?
        for frame in 0...frames {
            let time = Double(frame * hop) / rate + 0.02
            let speech = frame < frames && periodic[frame] && levels[frame] >= threshold
                && !words.contains { time >= $0.lowerBound - 0.12 && time <= $0.upperBound + 0.3 }
            if speech { runStart = runStart ?? Double(frame * hop) / rate }
            else if let start = runStart {
                let end = Double(frame * hop) / rate + 0.04
                if end - start >= 0.1 { stretches.append(start...end) }
                runStart = nil
            }
        }
        return stretches
    }
}
