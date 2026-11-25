import AVFoundation
import Foundation

/// Measures Best Quality's attempts (`TakeChoice` decides): likeness is the WeSpeaker fingerprint
/// of an attempt against the reference clip's (the model that sorts recordings, 26 MB, loaded
/// beside the voice model only for this request), words are checked by the on-device transcriber
/// when it can run (macOS 26), and length against the clip's pace.
actor TakeJudge {
    private let processor: SourceProcessor
    private let wordsPerSecond: Double?
    private var voice: [Float]?

    /// `transcript` is exactly what the `reference` clip says; with its length it gives the voice's pace.
    init(store: VoiceModelStore, reference: URL? = nil, transcript: String = "") {
        processor = SourceProcessor(store: store)
        var seconds = 0.0
        if let reference, let file = try? AVAudioFile(forReading: reference), file.processingFormat.sampleRate > 0 {
            seconds = Double(file.length) / file.processingFormat.sampleRate
        }
        wordsPerSecond = TakeChoice.wordsPerSecond(transcript: transcript, seconds: seconds)
    }

    /// The reference clip's fingerprint. Called before any speech is made: reading a file clears
    /// MLX's buffer cache, which mustn't happen while a generation may still be using the GPU.
    func prepare(reference: URL) async {
        voice = try? await processor.fingerprint(of: reference)
    }

    /// One attempt (mono samples at `rate`) of `text`. An empty attempt scores below any other.
    func score(_ samples: [Float], rate: Int, text: String) async -> TakeChoice.Score {
        let paceKnown = wordsPerSecond != nil
        guard !samples.isEmpty else { return .init(likeness: 0, wordError: 1, lengthRatio: nil, paceKnown: paceKnown) }
        let seconds = Double(samples.count) / Double(max(1, rate))
        let lengthRatio = TakeChoice.lengthRatio(seconds: seconds, text: text, wordsPerSecond: wordsPerSecond)
        // The fingerprint model and the transcriber take the voice models' 24 kHz.
        guard rate == ReferenceBuilder.sampleRate else { return .init(likeness: nil, wordError: nil, lengthRatio: lengthRatio, paceKnown: paceKnown) }
        var likeness: Double?
        if let voice, let take = await processor.fingerprint(of: samples) {
            likeness = Double(SourceProcessor.similarity(voice, take))
        }
        let heard = await ReferenceBuilder.transcript(of: samples)
        return .init(likeness: likeness, wordError: heard.map { TakeChoice.wordErrorRate(said: $0, meant: text) },
                     lengthRatio: lengthRatio, paceKnown: paceKnown)
    }

    /// Fingerprint likeness of each file to `reference`, for the side-by-side harness; nil where
    /// one couldn't be measured.
    func likeness(of files: [URL], to reference: URL) async throws -> [Double?] {
        guard let voice = try await processor.fingerprint(of: reference) else { return files.map { _ in nil } }
        return try await likeness(of: files, to: voice)
    }

    /// Fingerprint likeness of each file to a person's fingerprint (a voice's clips from earlier
    /// versions, measured once); nil where one couldn't be measured.
    func likeness(of files: [URL], to voice: [Float]) async throws -> [Double?] {
        var scores: [Double?] = []
        for file in files {
            try Task.checkCancellation()
            let print = try? await processor.fingerprint(of: file)
            scores.append(print.map { Double(SourceProcessor.similarity(voice, $0)) })
        }
        return scores
    }
}
