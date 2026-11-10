import Foundation
import HuggingFace
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioTTS
import SirenQwen

/// The one loaded voice engine (Siren's `VoiceEngine`; Studio's takes pass a seed and a style). MLX
/// models aren't safe to share, so every generation goes through this actor, one at a time.
actor VoiceEngine {
    enum Failure: LocalizedError {
        case notDownloaded, emptyText, noSound
        var errorDescription: String? {
            switch self {
            case .notDownloaded: "This voice model isn't downloaded. Download it in Settings, Tsukumo, Voice."
            case .emptyText: "There's nothing to say."
            case .noSound: "A sentence came out silent on every try, so nothing was kept. Try again."
            }
        }
    }

    private var backend: SpeechBackend?
    private(set) var loaded: VoiceModel?

    var sampleRate: Int { backend?.sampleRate ?? 24_000 }

    /// Calmer sampling than the model's default (temperature 0.9): the voice and pacing drift
    /// less from line to line, with a little life left in (Siren's setting).
    static let parameters = GenerateParameters(maxTokens: 4096, temperature: 0.7, topP: 0.9, repetitionPenalty: 1.05)

    /// Seconds of speech the engine turns into sound at a time, for playing and for Best Quality's
    /// attempts (seven of Qwen's 12.5 Hz frames). The decoder's working memory grows with the frames
    /// it decodes at once; 2-frame chunks measured only 50-100 MB lower and changed the takes.
    static let chunkSeconds = 0.6

    /// Loads `model` from its download, never from the network.
    func load(_ model: VoiceModel, store: VoiceModelStore) async throws {
        if loaded == model, backend != nil { return }
        backend = nil
        loaded = nil
        Memory.clearCache()
        guard store.state(of: model).isDownloaded else { throw Failure.notDownloaded }
        // MLX keeps freed buffers for reuse; a small cap keeps speaking near the weights (a step
        // of speech needs far less, and the engine clears the cache every 50 steps anyway).
        Memory.cacheLimit = 128 * 1_024 * 1_024
        switch model.runtime {
        case .qwen:
            let speech = try await SirenQwen.Qwen3TTSModel.fromPretrained(model.repo, cache: HubCache(cacheDirectory: store.hub))
            backend = MLXAudioBackend(model: speech, parameters: Self.parameters)
        case .cosyVoice:
            backend = try await CosyVoiceSpeaker.load(store: store)
        case .sorting, .musicRemoval:
            throw Failure.notDownloaded
        }
        loaded = model
    }

    /// The whole text in the clip's voice, as mono samples at `sampleRate`: each piece of the
    /// `SpeechPlan` (a passage of a few sentences on Qwen, a sentence on CosyVoice) is made from
    /// the same clip, its silent edges trimmed, with the plan's pause after it. `seed` seeds
    /// MLX's sampler first (Studio's takes); `style` reaches only an engine that follows one.
    /// With a `judge` and more than one of `attempts` (Best Quality), each piece is made up to
    /// that many times instead, each attempt seeded from `seed` (`TakeChoice.seed`), and the best
    /// by `TakeChoice` is kept; making more stops once one is good enough. `progress` hears how
    /// far through the pieces it is.
    func render(_ text: String, reference: URL, transcript: String, seed: UInt64? = nil,
                style: String? = nil, judge: TakeJudge? = nil, attempts: Int = 1,
                progress: (@Sendable (Double) -> Void)? = nil) async throws -> [Float] {
        guard let backend, let loaded else { throw Failure.notDownloaded }
        let plan = SpeechPlan(text, passage: loaded.runtime == .qwen ? SpeechPlan.passageLength : 0).units
        guard !plan.isEmpty else { throw Failure.emptyText }
        if let judge, attempts > 1 {
            return try await bestOf(plan, attempts: attempts, judge: judge, backend: backend, reference: reference,
                                    transcript: transcript, seed: seed, style: style, progress: progress)
        }
        if let seed { MLXRandom.seed(seed) }
        let rate = backend.sampleRate
        let (_, clip) = try loadAudioArray(from: reference, sampleRate: rate)
        let samples = clip.asArray(Float.self)
        var out: [Float] = []
        for (index, unit) in plan.enumerated() {
            try Task.checkCancellation()
            progress?(Double(index) / Double(plan.count))
            if index > 0 { out += [Float](repeating: 0, count: Int(plan[index - 1].pause * Double(rate))) }
            var edges = SpeechPlan.Edges(rate: rate)
            var heard = false
            do {
                for try await chunk in backend.generate(unit.text, reference: samples, key: reference.path, transcript: transcript,
                                                        style: style, interval: Self.chunkSeconds) {
                    let ready = edges.push(chunk)
                    if !ready.isEmpty { heard = true; out += ready }
                    try Task.checkCancellation()
                }
            } catch {
                backend.cancel()
                await backend.finished()
                throw error
            }
            let ending = edges.finish()
            if !ending.isEmpty { heard = true; out += ending }
            MemoryTrace.mark("piece \(index + 1)")
            // A silent piece: say so (Try Again), rather than leave it out of the reading.
            guard heard else { throw Failure.noSound }
        }
        return out
    }

    /// Best Quality: each piece made up to `attempts` times and the best kept (`TakeChoice`).
    /// Only one piece's attempts are held at a time.
    private func bestOf(_ plan: [SpeechPlan.Unit], attempts: Int, judge: TakeJudge, backend: SpeechBackend,
                        reference: URL, transcript: String, seed: UInt64?, style: String?,
                        progress: (@Sendable (Double) -> Void)?) async throws -> [Float] {
        let rate = backend.sampleRate
        let (_, clip) = try loadAudioArray(from: reference, sampleRate: rate)
        let samples = clip.asArray(Float.self)
        // Before any speech: measuring the clip from its file clears MLX's buffer cache.
        await judge.prepare(reference: reference)
        MemoryTrace.mark("judge ready")
        var out: [Float] = []
        for (index, unit) in plan.enumerated() {
            try Task.checkCancellation()
            if index > 0 { out += [Float](repeating: 0, count: Int(plan[index - 1].pause * Double(rate))) }
            // Only attempts with sound are kept to choose from: a silent one can't win over speech.
            var takes: [[Float]] = []
            var scores: [TakeChoice.Score] = []
            var made = 0
            repeat {
                progress?((Double(index) + Double(made) / Double(attempts)) / Double(plan.count))
                if let seed { MLXRandom.seed(TakeChoice.seed(seed, piece: index, attempt: made)) }
                made += 1
                let take: [Float]
                do {
                    take = try await attempt(unit.text, backend: backend, reference: samples, key: reference.path,
                                             transcript: transcript, style: style)
                } catch let failure where !takes.isEmpty && !(failure is CancellationError) && !Task.isCancelled {
                    // A later attempt failed: the best one already made still stands.
                    break
                }
                // The piece has let go of the model before its attempt is measured.
                await backend.finished()
                try Task.checkCancellation()
                MemoryTrace.mark("piece \(index + 1) attempt \(made) made")
                guard !take.isEmpty else { continue }
                scores.append(await judge.score(take, rate: rate, text: unit.text))
                MemoryTrace.mark("piece \(index + 1) attempt \(made) scored")
                takes.append(take)
            } while made < attempts && !scores.contains(where: \.isGoodEnough)
            // Every attempt came out silent: say so (Try Again), rather than leave the piece out.
            guard let best = TakeChoice.best(scores) else { throw Failure.noSound }
            out += takes[best]
        }
        return out
    }

    /// One attempt at a piece, whole, its silent edges trimmed.
    private func attempt(_ text: String, backend: SpeechBackend, reference: [Float], key: String,
                         transcript: String, style: String?) async throws -> [Float] {
        var edges = SpeechPlan.Edges(rate: backend.sampleRate)
        var made: [Float] = []
        do {
            // The same chunks as speaking (4 s chunks took the helper past 6 GB).
            for try await chunk in backend.generate(text, reference: reference, key: key, transcript: transcript,
                                                    style: style, interval: Self.chunkSeconds) {
                made += edges.push(chunk)
                try Task.checkCancellation()
            }
        } catch {
            backend.cancel()
            await backend.finished()
            throw error
        }
        return made + edges.finish()
    }

    func unload() async {
        backend?.cancel()
        await backend?.finished()
        backend = nil
        loaded = nil
        Memory.clearCache()
    }
}

extension VoiceModelStore {
    /// Downloads whatever the model is missing from Hugging Face, resuming a download that
    /// stopped part-way, then records it whole. A whole download returns at once without the
    /// network. Cancelling stops it; what was fetched stays for the next try.
    func download(_ model: VoiceModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard !state(of: model).isDownloaded || lacksExtras(model) else { progress(1); return }
        let cache = HubCache(cacheDirectory: hub)
        switch model.runtime {
        case .qwen, .sorting, .musicRemoval:
            let parts = model.allParts
            let share = 1 / Double(parts.count)
            for (index, part) in parts.enumerated() where !isWhole(part) {
                guard let repo = Repo.ID(rawValue: part) else { throw CocoaError(.fileReadInvalidFileName) }
                let base = Double(index) * share
                // The same files `fromPretrained` asks for, so loading finds them whole. DeepFilterNet
                // keeps its versions in folders, which mlx-audio's check for a top-level .safetensors
                // rejects, so it's fetched by its README (Siren's way).
                _ = try await ModelUtils.resolveOrDownloadModel(
                    client: HubClient(cache: cache), cache: cache, repoID: repo,
                    requiredExtension: part == VoiceModel.enhancerRepo ? "md" : "safetensors",
                    additionalMatchingPatterns: ["*.model"],
                    progressHandler: { progress(min(0.99, base + share * $0.fractionCompleted)) })
                try Task.checkCancellation()
                try Self.markComplete(folder(for: part))
                // The Hub keeps its own copy (blobs and snapshot) beside the folder models load
                // from; once that folder is whole the copy only doubles the size shown and,
                // where the files couldn't be cloned, the space taken.
                for hubCopy in folders(for: part).dropFirst() { try? FileManager.default.removeItem(at: hubCopy) }
            }
        case .cosyVoice:
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try await CosyVoiceSpeaker.download(into: self, progress: progress)
        }
        try Task.checkCancellation()
        try markWhole(model)
        progress(1)
    }
}
