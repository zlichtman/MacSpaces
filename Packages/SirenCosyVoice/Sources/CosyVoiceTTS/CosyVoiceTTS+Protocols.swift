// Apple silicon only: MLX voices never run on Intel, where this builds empty (Float16 and Metal).
#if arch(arm64)
import AudioCommon

// MARK: - SpeechGenerationModel

extension CosyVoiceTTSModel: SpeechGenerationModel {
    public var sampleRate: Int { config.sampleRate }

    public func generate(text: String, language: String?) async throws -> [Float] {
        synthesize(text: text, language: language ?? "english")
    }

    public func generateStream(text: String, language: String?) -> AsyncThrowingStream<AudioChunk, Error> {
        synthesizeStream(text: text, language: language ?? "english")
    }
}
#endif
