import AudioCommon
import CoreML
import CosyVoiceTTS
import Foundation
@preconcurrency import MLX

/// CosyVoice 3 (0.5B, Apache-2.0, FunAudioLLM), the second engine. Like
/// Qwen3-TTS it copies a voice from one clip and the clip's exact words; it
/// also follows a style ("calm", "whispering", "speak slowly"). The Swift port
/// is vendored from soniqo/speech-swift in Packages/SirenCosyVoice, because
/// that package's MLX version can't be resolved alongside mlx-audio-swift's.
///
/// Weights: the bf16 bundle (2.25 GB; its 8-bit LLM adds noise when cloning)
/// plus the CAM++ speaker encoder (15 MB), in the `ModelStore` with the other
/// models. `VoiceEngine` makes one call at a time, which is what makes
/// sharing this across tasks safe.
final class CosyVoiceSpeaker: SpeechBackend, @unchecked Sendable {
    static let repo = VoiceModel.expressive.parts[0]
    static let speakerRepo = VoiceModel.expressive.parts[1]
    /// Everything the bundle needs; the bundle's own loader skips downloading
    /// once any weight is present, and leaves out the speech tokenizer.
    static let modelFiles = ["llm.safetensors", "flow.safetensors", "hifigan.safetensors", "speech_tokenizer.safetensors",
                             "flow_noise.bin", "vocab.json", "merges.txt", "tokenizer_config.json", "config.json"]
    /// The model drifts from the voice past about 12 s of speech, so longer
    /// pieces are made in parts of at most this many words (and
    /// `SpeechPlan.bounded`'s length, for text without spaces).
    static let maximumWords = 25
    /// CosyVoice's own "no style" instruction, which keeps the closest copy.
    static let noStyle = "You are a helpful assistant."

    let sampleRate: Int
    private let model: CosyVoiceTTSModel
    /// The speech tokenizer (484 MB) is only needed to read a new reference,
    /// so it's loaded for that and let go again, keeping it out of speaking's peak.
    private let tokenizerFile: URL
    private let speaker: CamPlusPlusSpeaker
    /// The conditioning taken from a reference (its speech codes, mel and
    /// speaker embedding), kept for the few clips most recently used.
    private var profiles: [(key: String, profile: CosyVoiceVoiceProfile)] = []
    private let lock = NSLock()
    /// The task running the model for the current piece.
    private var producer: Task<Void, Never>?

    private init(model: CosyVoiceTTSModel, tokenizerFile: URL, speaker: CamPlusPlusSpeaker) {
        self.model = model
        self.tokenizerFile = tokenizerFile
        self.speaker = speaker
        sampleRate = model.config.sampleRate
    }

    /// Downloads whatever is missing (resuming a download that stopped
    /// part-way), then loads. A complete cache loads without the network.
    /// `progress` gets each stage as it starts (downloading, weights,
    /// warm-up), from 0 to 1.
    static func load(store: VoiceModelStore, progress: (@Sendable (Double, String) -> Void)? = nil) async throws -> CosyVoiceSpeaker {
        let modelFolder = store.folder(for: repo)
        progress?(0, "Checking the model files")
        // Loading never downloads: only Download in Settings does.
        guard model(isWholeIn: store) else { throw VoiceEngine.Failure.notDownloaded }
        let model = try await CosyVoiceTTSModel.fromPretrained(modelId: repo, cacheDir: modelFolder) { fraction, stage in
            progress?(0.05 + 0.85 * fraction, stage)
        }
        progress?(0.9, "Loading the speaker encoder")
        let speaker = try await loadSpeakerEncoder(store: store)
        progress?(1, "Ready")
        return CosyVoiceSpeaker(model: model, tokenizerFile: modelFolder.appendingPathComponent("speech_tokenizer.safetensors"),
                                speaker: speaker)
    }

    /// Both parts, the bundle first; `progress` goes from 0 to 1 by size.
    static func download(into store: VoiceModelStore, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await ensureWhole(repo, in: store.folder(for: repo), files: modelFiles) { progress?(0.99 * $0) }
        try await ensureWhole(speakerRepo, in: store.folder(for: speakerRepo), files: ["CamPlusPlus.mlmodelc/**"]) {
            progress?(0.99 + 0.01 * $0)
        }
    }

    /// The CAM++ speaker encoder from a complete cache. It runs once per
    /// reference, so the CPU is plenty; compiling it for the Neural Engine
    /// took about 97 s on every launch.
    static func loadSpeakerEncoder(store: VoiceModelStore, computeUnits: MLComputeUnits = .cpuOnly) async throws -> CamPlusPlusSpeaker {
        let folder = store.folder(for: speakerRepo)
        return try await CamPlusPlusSpeaker.fromPretrained(modelId: speakerRepo, cacheDir: folder, computeUnits: computeUnits)
    }

    static func model(isWholeIn store: VoiceModelStore) -> Bool {
        store.isWhole(repo) && store.isWhole(speakerRepo)
    }

    private static func ensureWhole(_ repo: String, in folder: URL, files: [String],
                                    progress: ((Double) -> Void)? = nil) async throws {
        guard !VoiceModelStore.isComplete(folder) else { progress?(1); return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await HuggingFaceDownloader.downloadWeights(modelId: repo, to: folder, additionalFiles: files, progressHandler: progress)
        try Task.checkCancellation()
        try VoiceModelStore.markComplete(folder)
    }

    /// One piece of speech, as a stream like Qwen3's (it arrives whole). The
    /// model runs off the engine actor, so Stop is heard while it runs; the
    /// stream ends only once the model call has returned. `reference` is at
    /// `sampleRate`.
    func generate(_ text: String, reference: [Float], key: String, transcript: String,
                  style: String?, interval: Double) -> AsyncThrowingStream<[Float], Error> {
        let rate = sampleRate
        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let samples = try self.speak(text, reference: reference, rate: rate, key: key,
                                                 transcript: transcript, styleInstruction: style)
                    continuation.yield(samples)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            lock.withLock { producer = task }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Stops the piece being made: the model ends at its next token or step.
    func cancel() {
        lock.withLock { producer }?.cancel()
    }

    /// Returns once the piece being made has left the model, so the next job
    /// can't start while it still runs.
    func finished() async {
        await lock.withLock { producer }?.value
    }

    /// With no style, the reference's words lead the text, the closest copy
    /// of the voice. A style switches to CosyVoice's instruction layout: the
    /// voice still comes from the reference's sound, the delivery from the style.
    /// Each bounded part is one model call: CosyVoice's own long-form path
    /// would split it again at every sentence and leave about 0.7 s of
    /// silence between them, twice the plan's pause.
    private func speak(_ text: String, reference: [Float], rate: Int, key: String, transcript: String,
                       styleInstruction: String?) throws -> [Float] {
        try Task.checkCancellation()
        let profile = try profile(reference: reference, rate: rate, key: key, transcript: transcript)
        defer { Memory.clearCache() }
        let style = styleInstruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var joined: [Float] = []
        for (index, part) in SpeechPlan.bounded(text, maxWords: Self.maximumWords).enumerated() {
            try Task.checkCancellation()
            let samples = model.synthesize(text: part, instruction: style.isEmpty ? Self.noStyle : style,
                                           speakerEmbedding: profile.speakerEmbedding, promptToken: profile.promptToken,
                                           promptFeat: profile.promptFeat, promptText: profile.promptText)
            Memory.clearCache()
            try Task.checkCancellation()
            if index > 0 { joined += [Float](repeating: 0, count: Int(SpeechPlan.continuationPause * Double(sampleRate))) }
            // The model's own pauses inside a part are kept (about 0.55–0.65 s
            // between sentences), like Qwen3's: they carry its cadence.
            joined += SpeechPlan.Edges.trimmed(samples, rate: sampleRate)
        }
        return joined
    }

    private func profile(reference: [Float], rate: Int, key: String, transcript: String) throws -> CosyVoiceVoiceProfile {
        let key = key + "\n" + transcript
        if let index = profiles.firstIndex(where: { $0.key == key }) {
            let found = profiles.remove(at: index)
            profiles.append(found)
            return found.profile
        }
        let profile = try autoreleasepool {
            let tokenizer = try SpeechTokenizerModel.fromSafetensors(at: tokenizerFile)
            return try model.extractVoiceProfile(audio: reference, sampleRate: rate, speechTokenizer: tokenizer,
                                                 camppSpeaker: speaker, referenceTranscript: transcript)
        }
        Memory.clearCache()
        profiles.append((key, profile))
        if profiles.count > 4 { profiles.removeFirst() }
        return profile
    }
}
