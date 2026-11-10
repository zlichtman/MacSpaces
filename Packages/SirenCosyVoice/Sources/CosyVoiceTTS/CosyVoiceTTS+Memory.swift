// Apple silicon only: MLX voices never run on Intel, where this builds empty (Float16 and Metal).
#if arch(arm64)
import AudioCommon

extension CosyVoiceTTSModel: ModelMemoryManageable {
    public var isLoaded: Bool { _isLoaded }

    public func unload() {
        guard _isLoaded else { return }
        llm.clearParameters()
        flow.clearParameters()
        hifigan.clearParameters()
        mlxCacheLimitLease?.release()
        mlxCacheLimitLease = nil
        _isLoaded = false
    }

    public var memoryFootprint: Int {
        guard _isLoaded else { return 0 }
        return llm.parameterMemoryBytes()
            + flow.parameterMemoryBytes()
            + hifigan.parameterMemoryBytes()
    }
}
#endif
