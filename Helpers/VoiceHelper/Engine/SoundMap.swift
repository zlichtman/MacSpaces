import AVFoundation
import Foundation
import SoundAnalysis

/// What a recording sounds like every half second: talk, singing, music, talk
/// over music, or quiet. Apple's built-in sound classifier does the listening
/// (on this Mac, nothing to download, about 20 s for 75 minutes).
///
/// Songs are told apart from a host talking over a song's intro by how the
/// voice sounds: clear speech with no singing is talk, any other voice under
/// music is the song's vocals.
struct SoundMap: Sendable {
    enum Kind: UInt8, Sendable {
        case quiet, talk, singing, music, talkOverMusic
    }

    /// Seconds between entries.
    static let step = 0.5
    /// One per `step`, starting at 0.
    let kinds: [Kind]
    /// One per `step`: whether a sound that isn't words is heard (`noiseLabels`).
    var noises: [Bool] = []
    /// One per `step`: the laugh, sigh or breath heard, if any.
    var vocal: [VocalSound.Kind?] = []

    /// Sounds people make that aren't words. The engines copy everything in a
    /// sample, so a cough in one comes back in what Siren says.
    static let noiseLabels = ["cough", "sneeze", "laughter", "giggling", "belly_laugh", "breathing",
                              "gasp", "sigh", "hiccup", "burp", "chewing"]
    /// Any of them at least this sure marks the step.
    static let noiseLevel: Float = 0.4

    /// Where those sounds are, joined across half-second gaps.
    func noiseStretches() -> [SpeechSegment] {
        var runs: [SpeechSegment] = []
        for (index, noisy) in noises.enumerated() where noisy {
            let run = SpeechSegment(start: Double(index) * Self.step, end: Double(index + 1) * Self.step)
            if let last = runs.last, run.start - last.end <= Self.step { runs[runs.count - 1] = SpeechSegment(start: last.start, end: run.end) }
            else { runs.append(run) }
        }
        return runs
    }

    /// Laughs, sighs and breaths, each kind joined across half-second gaps.
    func vocalSounds() -> [VocalSound] {
        var sounds: [VocalSound] = []
        for (index, kind) in vocal.enumerated() {
            guard let kind else { continue }
            let start = Double(index) * Self.step
            if let last = sounds.lastIndex(where: { $0.kind == kind }), start - sounds[last].end <= Self.step {
                sounds[last].end = start + Self.step
            } else {
                sounds.append(VocalSound(kind: kind, start: start, end: start + Self.step))
            }
        }
        return sounds
    }

    /// Music at least this sure counts as music playing.
    static let musicLevel: Float = 0.5
    /// Speech at least this sure, with singing under `talkSingingLimit`, is someone talking.
    static let talkLevel: Float = 0.7
    static let talkSingingLimit: Float = 0.25
    /// Under music, any voice at least this sure is the song's vocals.
    static let vocalLevel: Float = 0.15
    /// Without music, speech this sure is talk.
    static let speechLevel: Float = 0.3

    static func kind(speech: Float, singing: Float, music: Float) -> Kind {
        if music >= musicLevel {
            if speech >= talkLevel && singing < talkSingingLimit { return .talkOverMusic }
            return max(speech, singing) >= vocalLevel ? .singing : .music
        }
        if singing >= 0.5 && singing > speech { return .singing }
        return speech >= speechLevel ? .talk : .quiet
    }

    func kind(at seconds: Double) -> Kind {
        guard !kinds.isEmpty else { return .quiet }
        return kinds[min(kinds.count - 1, max(0, Int(seconds / Self.step)))]
    }

    /// Share of `range` spent as one of `kinds`.
    func share(of wanted: Set<Kind>, from start: Double, to end: Double) -> Double {
        let lo = max(0, Int(start / Self.step)), hi = min(kinds.count, Int((end / Self.step).rounded(.up)))
        guard hi > lo else { return 0 }
        return Double(kinds[lo..<hi].filter(wanted.contains).count) / Double(hi - lo)
    }

    /// Runs of `wanted`, joined across gaps up to `bridging` seconds, at least `minimum` long.
    func stretches(of wanted: Set<Kind>, bridging: Double = 0, minimum: Double = 0) -> [SpeechSegment] {
        var runs: [SpeechSegment] = []
        var i = 0
        while i < kinds.count {
            guard wanted.contains(kinds[i]) else { i += 1; continue }
            var end = i + 1
            while end < kinds.count, wanted.contains(kinds[end]) { end += 1 }
            let run = SpeechSegment(start: Double(i) * Self.step, end: Double(end) * Self.step)
            if let last = runs.last, run.start - last.end <= bridging {
                runs[runs.count - 1] = SpeechSegment(start: last.start, end: run.end)
            } else {
                runs.append(run)
            }
            i = end
        }
        return runs.filter { $0.duration >= minimum }
    }

    /// Songs: long stretches of music that have vocals in them.
    func songs(minimum: Double = 20, vocals: Double = 4) -> [SpeechSegment] {
        stretches(of: [.music, .singing, .talkOverMusic], bridging: 2, minimum: minimum).filter {
            share(of: [.singing], from: $0.start, to: $0.end) * $0.duration >= vocals
        }
    }

    /// Classifies `url` (any file AVFoundation reads).
    static func analyze(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> SoundMap {
        let analyzer = try SNAudioFileAnalyzer(url: url)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 2 * step, preferredTimescale: 48_000)
        request.overlapFactor = 0.5
        let seconds = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        let observer = Observer(total: seconds, progress: progress)
        try analyzer.add(request, withObserver: observer)
        let finished = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                analyzer.analyze { continuation.resume(returning: $0) }
            }
        } onCancel: {
            analyzer.cancelAnalysis()
        }
        try Task.checkCancellation()
        if !finished, let error = observer.failure { throw error }
        let count = Int((seconds / step).rounded(.up))
        var map = SoundMap(kinds: observer.kinds(count: count))
        map.noises = observer.noises(count: count)
        map.vocal = observer.vocal(count: count)
        return map
    }

    private final class Observer: NSObject, SNResultsObserving, @unchecked Sendable {
        private let lock = NSLock()
        private var scores: [(time: Double, kind: Kind)] = []
        private var noisy: [Double] = []
        private var vocal: [(time: Double, kind: VocalSound.Kind)] = []
        private(set) var failure: Error?
        private let total: Double
        private let progress: @Sendable (Double) -> Void

        init(total: Double, progress: @escaping @Sendable (Double) -> Void) {
            self.total = total
            self.progress = progress
        }

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let result = result as? SNClassificationResult else { return }
            func confidence(_ id: String) -> Float { Float(result.classification(forIdentifier: id)?.confidence ?? 0) }
            let singing = max(confidence("singing"), confidence("choir_singing"), confidence("rapping"), confidence("humming"))
            let kind = SoundMap.kind(speech: confidence("speech"), singing: singing, music: confidence("music"))
            let middle = result.timeRange.start.seconds + result.timeRange.duration.seconds / 2
            let noise = SoundMap.noiseLabels.map(confidence).max() ?? 0
            let sound = VocalSound.Kind.allCases.map { ($0, $0.labels.map(confidence).max() ?? 0) }.max { $0.1 < $1.1 }
            lock.withLock {
                scores.append((middle, kind))
                if noise >= SoundMap.noiseLevel { noisy.append(middle) }
                if let sound, sound.1 >= SoundMap.noiseLevel { vocal.append((middle, sound.0)) }
            }
            if total > 0 { progress(min(1, middle / total)) }
        }

        func request(_ request: SNRequest, didFailWithError error: Error) {
            lock.withLock { failure = error }
        }

        /// One flag per step: set when a window centred within the step heard a noise.
        func noises(count: Int) -> [Bool] {
            var out = [Bool](repeating: false, count: count)
            for time in lock.withLock({ noisy }) {
                let index = Int(time / SoundMap.step)
                if index >= 0 && index < count { out[index] = true }
            }
            return out
        }

        /// One laugh, sigh or breath per step, from a window centred within it.
        func vocal(count: Int) -> [VocalSound.Kind?] {
            var out = [VocalSound.Kind?](repeating: nil, count: count)
            for (time, kind) in lock.withLock({ vocal }) {
                let index = Int(time / SoundMap.step)
                if index >= 0 && index < count { out[index] = kind }
            }
            return out
        }

        /// One kind per step: the window centred nearest to it.
        func kinds(count: Int) -> [Kind] {
            let sorted = lock.withLock { scores.sorted { $0.time < $1.time } }
            guard !sorted.isEmpty else { return [Kind](repeating: .talk, count: count) }
            var out: [Kind] = []
            out.reserveCapacity(count)
            var j = 0
            for i in 0..<count {
                let t = (Double(i) + 0.5) * SoundMap.step
                while j + 1 < sorted.count, abs(sorted[j + 1].time - t) <= abs(sorted[j].time - t) { j += 1 }
                out.append(sorted[j].kind)
            }
            return out
        }
    }
}
