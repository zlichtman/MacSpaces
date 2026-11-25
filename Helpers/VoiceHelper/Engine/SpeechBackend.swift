import Foundation
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioTTS

/// What `VoiceEngine` drives to make one piece of speech. Every engine that
/// mlx-audio-swift loads shares `MLXAudioBackend`; CosyVoice keeps its own.
/// `VoiceEngine` makes one call at a time, which is what makes sharing a
/// backend across tasks safe.
protocol SpeechBackend: AnyObject, Sendable {
    var sampleRate: Int { get }
    /// One piece in the reference's voice, as chunks of mono samples at
    /// `sampleRate`. `reference` is at `sampleRate` too; `key` names it for
    /// any per-clip cache; `transcript` is exactly what it says. `style`
    /// matters only to an engine that follows one.
    func generate(_ text: String, reference: [Float], key: String, transcript: String,
                  style: String?, interval: Double) -> AsyncThrowingStream<[Float], Error>
    /// Stops the piece being made.
    func cancel()
    /// Returns once the piece being made has let go of the model.
    func finished() async
}

/// Any model `TTS.loadModel` returns. Its generation runs in the library's
/// own task, which `VoiceEngine` drains after Stop, so `cancel` and
/// `finished` have nothing more to do.
final class MLXAudioBackend: SpeechBackend, @unchecked Sendable {
    private let model: SpeechGenerationModel
    private let parameters: GenerateParameters
    /// One copy of the sample across sentences and takes (see `HeldReference`).
    private let held = HeldReference<MLXArray>()

    init(model: SpeechGenerationModel, parameters: GenerateParameters) {
        self.model = model
        self.parameters = parameters
    }

    var sampleRate: Int { model.sampleRate }

    func generate(_ text: String, reference: [Float], key: String, transcript: String,
                  style: String?, interval: Double) -> AsyncThrowingStream<[Float], Error> {
        let copy = held.copy(of: reference) { MLXArray($0) }
        let source = Source(model.generateSamplesStream(text: text, voice: nil, refAudio: copy, refText: transcript,
                                                        language: nil, generationParameters: parameters,
                                                        streamingInterval: interval).makeAsyncIterator())
        let held = held
        // Pulled by the caller's own task, so Stop and draining work as before.
        return AsyncThrowingStream {
            guard let chunk = try await source.iterator.next() else { return nil }
            if !source.started {
                source.started = true
                held.started(copy)
            }
            return chunk
        }
    }

    private final class Source: @unchecked Sendable {
        var iterator: AsyncThrowingStream<[Float], Error>.AsyncIterator
        var started = false
        init(_ iterator: AsyncThrowingStream<[Float], Error>.AsyncIterator) { self.iterator = iterator }
    }

    func cancel() {}
    func finished() async {}
}
