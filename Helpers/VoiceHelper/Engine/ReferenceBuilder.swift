import AVFoundation
import Foundation
import MLXAudioCore
import Speech

/// Turns a recording into the one clip the model copies: mono 24 kHz, up to
/// 20 s of clear speech cut on word boundaries, plus exactly what was said.
/// Transcription runs on this Mac: Apple's SpeechAnalyzer (macOS 26, no
/// permission needed), then the older recogniser if that can't run.
/// Short or rough speech is still used: a weak clip beats no voice, and the
/// person is told what would make it better.
///
/// Known limit: both transcribers are set to US English (en-US). Speech in
/// another language gets no words or wrong ones, so its clips come out weak
/// or not at all. References are English-only until the language is
/// detected or chosen.
enum ReferenceBuilder {
    static let sampleRate = 24_000
    static let maximumSeconds = 20.0
    /// The model can copy a voice from a few seconds; below this there's nothing to hear.
    static let minimumSeconds = 1.0
    /// Only the opening of a long file is searched; a voice memo needs no more.
    static let searchSeconds = 90.0

    enum Failure: LocalizedError {
        case unreadable, tooShort, noSpeech, recognitionDenied, recognitionUnavailable, transcriptNeedsReview
        var errorDescription: String? {
            switch self {
            case .unreadable: "That file couldn't be opened. Try a voice memo, or an audio file like .m4a, .mp3 or .wav."
            case .tooShort: "This recording is too short to hear a voice in. Record a few seconds of talking."
            case .noSpeech: "No words could be heard. Use a recording of someone talking, without music."
            case .recognitionDenied: "MacSpaces needs Speech Recognition to write down what each person says. Turn it on in System Settings, Privacy & Security, Speech Recognition."
            case .recognitionUnavailable: "On-device speech recognition isn't available. Turn on Dictation in System Settings, Keyboard, then try again."
            case .transcriptNeedsReview: "The words in this clip couldn't be confirmed."
            }
        }
    }

    struct Result: Sendable {
        let file: URL
        let transcript: String
        let seconds: Double
        /// Cheap reference fitness, not a measurement of speaker likeness.
        let qualityScore: Double
        /// Dynamics before normalization, used to choose a delivery.
        let sourceLoudness: Double
        let sourceLiveliness: Double
        /// Seconds of the source the clip was cut from, first word to last.
        var excerpt: ClosedRange<Double>? = nil
        /// Seconds of speech left in the clip that its words don't cover
        /// (`ReferenceFitness.unheardSpeech`); 0 when the text fits the sound.
        var unheardSeconds = 0.0
        /// Longest quiet between two kept words, in seconds. The engines copy a
        /// reference's pauses, so a long one comes back as an odd gap.
        var longestPause = 0.0
    }

    /// `script` identifies a guided take; it is never substituted for words
    /// the recogniser could not confirm. `confirmedTranscript` must describe
    /// exactly the first 20 seconds (or the whole take, if shorter), which
    /// the person has listened to and explicitly confirmed.
    static func build(from source: URL, script: String? = nil,
                      confirmedTranscript: String? = nil) async throws -> Result {
        try Task.checkCancellation()
        let samples = try decode(source, seconds: confirmedTranscript == nil ? searchSeconds : maximumSeconds)
        guard Double(samples.count) / Double(sampleRate) >= minimumSeconds else { throw Failure.tooShort }
        if let confirmedTranscript {
            let text = confirmedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw Failure.transcriptNeedsReview }
            var result = try write(samples, transcript: text)
            result.excerpt = 0...result.seconds
            return result
        }
        let search = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: search) }
        try AudioUtils.writeWavFile(samples: samples, sampleRate: sampleRate, fileURL: search)

        let heard: Heard
        do {
            heard = try await recognize(search)
            guard !heard.words.isEmpty else { throw Failure.noSpeech }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if script != nil { throw Failure.transcriptNeedsReview }
            throw error
        }
        try Task.checkCancellation()
        let duration = Double(samples.count) / Double(sampleRate)
        let textLength = (heard.text as NSString).length
        let words = heard.words.filter {
            $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start &&
            $0.end <= duration && $0.range.location >= 0 && $0.range.length > 0 &&
            $0.range.location <= textLength && $0.range.length <= textLength - $0.range.location
        }
        guard let first = words.first else {
            throw script == nil ? Failure.noSpeech : Failure.transcriptNeedsReview
        }

        // From just before the first word to the last word that ends inside
        // the window, stopping short of any word that isn't in the text.
        let start = max(0, first.start - 0.15)
        let kept = words.filter { $0.start >= first.start && $0.end <= start + maximumSeconds }
        guard !kept.isEmpty else { throw Failure.noSpeech }
        var choice = cut(kept, all: words, from: start, limit: duration)
        // The text must match the sound: speech the words leave out (a missed
        // phrase, someone talking over) or words the recogniser made up for a
        // mumble make the model misplace words. Keep the longest stretch of
        // words clear of both, if it's long enough to carry the voice;
        // otherwise keep the clip and say so in its score.
        let unheard = (ReferenceFitness.unheardSpeech(slice(samples, choice.bounds), sampleRate: sampleRate,
                                                      words: choice.words.map { ($0.start - choice.bounds.lowerBound)...($0.end - choice.bounds.lowerBound) })
            .map { ($0.lowerBound + choice.bounds.lowerBound)...($0.upperBound + choice.bounds.lowerBound) }
            + doubtful(choice.words, in: heard.text)).sorted { $0.lowerBound < $1.lowerBound }
        var unheardSeconds = unheard.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
        if !unheard.isEmpty, let run = longestRun(choice.words, around: unheard), let head = run.first, let tail = run.last,
           tail.end - head.start >= min(4, 0.5 * (choice.bounds.upperBound - choice.bounds.lowerBound)) {
            // Start after the speech left out and the word before the run; end before what follows.
            let before = max(unheard.last { $0.upperBound <= head.start }?.upperBound ?? 0,
                             words.last { $0.range.location < head.range.location }?.end ?? 0)
            let after = unheard.first { $0.lowerBound >= tail.end }?.lowerBound ?? duration
            choice = cut(run, all: words, from: min(head.start, max(before + 0.05, head.start - 0.15)), limit: min(duration, after - 0.03))
            unheardSeconds = 0
        }
        let window = slice(samples, choice.bounds)
        guard !window.isEmpty, let head = choice.words.first, let tail = choice.words.last,
              NSMaxRange(tail.range) >= head.range.location else { throw Failure.noSpeech }
        // The punctuated text for exactly the kept words.
        let span = NSRange(location: head.range.location, length: NSMaxRange(tail.range) - head.range.location)
        let transcript = (heard.text as NSString).substring(with: span)
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.noSpeech }
        var result = try write(window, transcript: transcript, unheardSeconds: unheardSeconds)
        result.excerpt = choice.bounds
        result.longestPause = zip(choice.words, choice.words.dropFirst()).map { max(0, $1.start - $0.end) }.max() ?? 0
        return result
    }

    /// `words` (in order) from `start`, ending 0.25 s after the last one (and
    /// by `limit`) but before the next word in `all` begins, so no part of a
    /// word outside the text is kept.
    private static func cut(_ words: [Word], all: [Word], from start: Double,
                            limit: Double) -> (words: [Word], bounds: ClosedRange<Double>) {
        let last = words[words.count - 1]
        var end = min(limit, start + maximumSeconds, last.end + 0.25)
        if let next = all.first(where: { $0.range.location > last.range.location }) {
            end = min(end, max(last.end, next.start - 0.03))
        }
        return (words, start...max(start, end))
    }

    /// Where the recogniser was guessing: two or more words in any three under
    /// 0.4 confidence. Made-up words over a mumble look like this (0.20–0.32
    /// on reversed speech), while a clear voice dips below 0.4 only now and
    /// then, one word at a time. Numbers it writes as digits score low even
    /// when right ("19" at 0.31), so they don't count.
    private static func doubtful(_ words: [Word], in text: String) -> [ClosedRange<Double>] {
        let text = text as NSString
        let unsure = words.map { word in
            (word.confidence ?? 1) < 0.4 && !text.substring(with: word.range).contains(where: \.isNumber)
        }
        var marked = Set<Int>()
        for start in words.indices {
            let found = (start..<min(words.count, start + 3)).filter { unsure[$0] }
            if found.count >= 2 { marked.formUnion(found) }
        }
        return marked.sorted().map { words[$0].start...words[$0].end }
    }

    /// The longest run of consecutive `words` with no unheard speech between
    /// them; a word inside a doubtful stretch is left out and ends the run.
    private static func longestRun(_ words: [Word], around unheard: [ClosedRange<Double>]) -> [Word]? {
        var runs: [[Word]] = [[]]
        for word in words {
            let middle = (word.start + word.end) / 2
            if unheard.contains(where: { $0.contains(middle) }) {
                runs.append([])
                continue
            }
            if let previous = runs[runs.count - 1].last,
               unheard.contains(where: { $0.lowerBound < word.start && $0.upperBound > previous.end }) {
                runs.append([])
            }
            runs[runs.count - 1].append(word)
        }
        func length(_ run: [Word]) -> Double { (run.last?.end ?? 0) - (run.first?.start ?? 0) }
        return runs.filter { !$0.isEmpty }.max { length($0) < length($1) }
    }

    private static func slice(_ samples: [Float], _ bounds: ClosedRange<Double>) -> [Float] {
        let lower = min(samples.count, max(0, Int(bounds.lowerBound * Double(sampleRate))))
        let upper = min(samples.count, max(lower, Int(bounds.upperBound * Double(sampleRate))))
        return Array(samples[lower..<upper])
    }

    /// A clip from 24 kHz mono `samples` whose words are already known (the
    /// same stretch as another clip), prepared exactly as `build` prepares
    /// one, without transcribing again.
    /// `build(from:)` on one stretch of a longer recording, `start` to `end`
    /// seconds; `excerpt` is given in the recording's own seconds.
    static func build(from source: URL, start: Double, end: Double) async throws -> Result {
        let slice = AVAudioFile.readSlice(source, from: start, to: end)
        guard !slice.samples.isEmpty, slice.rate.isFinite, slice.rate > 0 else { throw Failure.unreadable }
        let stretch = FileManager.default.temporaryDirectory.appendingPathComponent("macspaces-stretch-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: stretch) }
        try AudioUtils.writeWavFile(samples: slice.samples, sampleRate: Int(slice.rate.rounded()), fileURL: stretch)
        var result = try await build(from: stretch)
        result.excerpt = result.excerpt.map { ($0.lowerBound + start)...($0.upperBound + start) }
        return result
    }

    /// Siren's short bursts (`VoiceBursts`): clips of one person, already built, joined in the
    /// order given with `VoiceBursts.pause` of quiet between them into one clip that says all of
    /// their words. The pieces' files are left for the caller to remove.
    static func joined(_ pieces: [Result]) throws -> Result {
        try Task.checkCancellation()
        let gap = [Float](repeating: 0, count: Int(VoiceBursts.pause * Double(sampleRate)))
        var samples: [Float] = []
        for piece in pieces {
            if !samples.isEmpty { samples += gap }
            samples += try decode(piece.file, seconds: maximumSeconds)
        }
        guard Double(samples.count) / Double(sampleRate) >= minimumSeconds else { throw Failure.tooShort }
        let transcript = pieces.map { $0.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " ")
        let unheard = pieces.reduce(0) { $0 + $1.unheardSeconds }
        let file = temporaryWAV()
        do {
            try AudioUtils.writeWavFile(samples: normalized(samples), sampleRate: sampleRate, fileURL: file)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        let span = pieces.first?.excerpt.flatMap { first in pieces.last?.excerpt.map { first.lowerBound...max(first.lowerBound, $0.upperBound) } }
        return Result(file: file, transcript: transcript, seconds: Double(samples.count) / Double(sampleRate),
                      qualityScore: qualityScore(samples: samples, transcript: transcript) * (1 - min(0.5, unheard)),
                      sourceLoudness: VoiceBursts.weighted(pieces.map { ($0.sourceLoudness, $0.seconds) }),
                      sourceLiveliness: VoiceBursts.weighted(pieces.map { ($0.sourceLiveliness, $0.seconds) }),
                      excerpt: span, unheardSeconds: unheard,
                      longestPause: max(VoiceBursts.pause, pieces.map(\.longestPause).max() ?? 0))
    }

    static func reference(from samples: [Float], transcript: String) throws -> Result {
        guard Double(samples.count) / Double(sampleRate) >= minimumSeconds else { throw Failure.tooShort }
        var result = try write(samples, transcript: transcript)
        result.excerpt = 0...result.seconds
        return result
    }

    /// The exact excerpt used with `confirmedTranscript`. The caller owns
    /// the returned temporary file and removes it after review or dismissal.
    static func reviewExcerpt(from source: URL) throws -> URL {
        try Task.checkCancellation()
        let samples = try decode(source, seconds: maximumSeconds)
        guard !samples.isEmpty else { throw Failure.tooShort }
        let file = temporaryWAV()
        do {
            try AudioUtils.writeWavFile(samples: normalized(samples), sampleRate: sampleRate, fileURL: file)
            return file
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    // MARK: - Steps

    /// `unheardSeconds` of speech the text leaves out lowers the score (by
    /// half at 0.5 s or more), so a clip whose words fit is chosen first.
    private static func write(_ samples: [Float], transcript: String, unheardSeconds: Double = 0) throws -> Result {
        try Task.checkCancellation()
        let file = temporaryWAV()
        let dynamics = sourceDynamics(samples)
        do {
            try AudioUtils.writeWavFile(samples: normalized(samples), sampleRate: sampleRate, fileURL: file)
            return Result(file: file, transcript: transcript, seconds: Double(samples.count) / Double(sampleRate),
                          qualityScore: qualityScore(samples: samples, transcript: transcript) * (1 - min(0.5, unheardSeconds)),
                          sourceLoudness: dynamics.loudness, sourceLiveliness: dynamics.liveliness,
                          unheardSeconds: unheardSeconds)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    /// What the newer on-device transcriber hears in 24 kHz `samples`; nil if it
    /// can't run. Never asks for a permission, so it's safe mid-speech.
    static func transcript(of samples: [Float]) async -> String? {
        guard #available(macOS 26.0, *) else { return nil }
        let file = temporaryWAV()
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try AudioUtils.writeWavFile(samples: samples, sampleRate: sampleRate, fileURL: file)
            return try await analyze(file).text
        } catch {
            return nil
        }
    }

    private static func temporaryWAV() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("macspaces-voice-\(UUID().uuidString).wav")
    }

    /// Any file AVFoundation reads, folded to mono at 24 kHz. The shared
    /// reader bounds every request to the remaining frames and drains EOF.
    static func decode(_ url: URL, seconds: Double) throws -> [Float] {
        var samples: [Float] = []
        try AudioFileReader.streamMono(url, sampleRate: Double(sampleRate), maximumSeconds: seconds) { samples += $0 }
        return samples
    }

    /// Even loudness (about -20 dBFS) without clipping, so quiet memos clone as well as loud ones.
    static func normalized(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let peak = samples.reduce(0) { max($0, abs($1)) }
        let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        guard peak > 0, rms > 0 else { return samples }
        let gain = min(0.1 / rms, 0.95 / peak)
        return samples.map { $0 * gain }
    }

    /// Cheap, deterministic reference fitness. A low score never rejects a take.
    static func qualityScore(samples: [Float], transcript: String, sampleRate: Int = ReferenceBuilder.sampleRate) -> Double {
        ReferenceFitness.qualityScore(samples: samples, transcript: transcript, sampleRate: sampleRate)
    }

    private static func sourceDynamics(_ samples: [Float]) -> (loudness: Double, liveliness: Double) {
        ReferenceFitness.sourceDynamics(samples, sampleRate: sampleRate)
    }

    // MARK: - Recognition

    struct Word: Sendable {
        let range: NSRange
        let start: Double
        let end: Double
        /// The recogniser's confidence, 0–1, when it gives one.
        var confidence: Double? = nil
    }

    struct Heard: Sendable {
        let text: String
        let words: [Word]
    }

    /// The helper never asks: MacSpaces asks for Speech Recognition when recordings are
    /// dropped in (before macOS 26, whose transcriber needs no permission).
    static func authorize() async -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// The newer on-device transcriber first (it needs no permission), then
    /// the older one; whichever hears words wins.
    private static func recognize(_ url: URL) async throws -> Heard {
        try Task.checkCancellation()
        if #available(macOS 26.0, *) {
            do {
                let heard = try await analyze(url)
                if !heard.words.isEmpty { return heard }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The older on-device recogniser may still be available.
            }
        }
        try Task.checkCancellation()
        return try await recognizeWithRecognizer(url)
    }

    @available(macOS 26.0, *)
    private static func analyze(_ url: URL) async throws -> Heard {
        let transcriber = SpeechTranscriber(locale: Locale(identifier: "en-US"), transcriptionOptions: [],
                                            reportingOptions: [], attributeOptions: [.audioTimeRange, .transcriptionConfidence])
        // The language model downloads once, through the system.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let file = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collected = Task { () -> [SpeechTranscriber.Result] in
            var results: [SpeechTranscriber.Result] = []
            for try await result in transcriber.results { results.append(result) }
            return results
        }
        defer { collected.cancel() }
        do {
            try await withTaskCancellationHandler {
                if let end = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: end)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                try Task.checkCancellation()
            } onCancel: {
                Task { await analyzer.cancelAndFinishNow() }
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            throw error
        }
        var text = ""
        var words: [Word] = []
        for result in try await collected.value {
            if !text.isEmpty, !text.hasSuffix(" ") { text += " " }
            for run in result.text.runs {
                let piece = String(result.text[run.range].characters)
                let location = (text as NSString).length
                text += piece
                guard let time = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self],
                      !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                // Leading spaces belong to the text, not the word.
                let leading = piece.prefix { $0.isWhitespace }.utf16.count
                let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                words.append(Word(range: NSRange(location: location + leading, length: trimmed.utf16.count),
                                  start: time.start.seconds, end: time.end.seconds,
                                  confidence: run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self]))
            }
        }
        return Heard(text: text, words: words)
    }

    private static func recognizeWithRecognizer(_ url: URL) async throws -> Heard {
        try Task.checkCancellation()
        guard await authorize() else { throw Failure.recognitionDenied }
        try Task.checkCancellation()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else { throw Failure.recognitionUnavailable }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        let operation = RecognitionOperation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard operation.begin(continuation) else { return }
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        let best = result.bestTranscription
                        let words = best.segments.map {
                            Word(range: $0.substringRange, start: $0.timestamp, end: $0.timestamp + $0.duration,
                                 confidence: Double($0.confidence))
                        }
                        operation.finish(.success(Heard(text: best.formattedString, words: words)))
                    } else if error != nil {
                        operation.finish(.failure(Failure.noSpeech))
                    }
                }
                operation.attach(task)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    /// Recognition callbacks and cancellation may arrive on different queues.
    /// Complete the continuation once, including cancellation before startup.
    private final class RecognitionOperation: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Heard, Error>?
        private var task: SFSpeechRecognitionTask?
        private var cancelled = false
        private var finished = false

        func begin(_ continuation: CheckedContinuation<Heard, Error>) -> Bool {
            lock.lock()
            if cancelled {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return false
            }
            self.continuation = continuation
            lock.unlock()
            return true
        }

        func attach(_ task: SFSpeechRecognitionTask) {
            lock.lock()
            let shouldCancel = finished || cancelled
            if !shouldCancel { self.task = task }
            lock.unlock()
            if shouldCancel { task.cancel() }
        }

        func finish(_ result: Swift.Result<Heard, Error>) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            let continuation = self.continuation
            self.continuation = nil
            task = nil
            lock.unlock()
            continuation?.resume(with: result)
        }

        func cancel() {
            lock.lock()
            cancelled = true
            finished = true
            let task = self.task
            let continuation = self.continuation
            self.task = nil
            self.continuation = nil
            lock.unlock()
            task?.cancel()
            continuation?.resume(throwing: CancellationError())
        }

    }
}
