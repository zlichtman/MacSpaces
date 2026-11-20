// Apple silicon only: MLX voices never run on Intel, where this builds empty (Float16 and Metal).
#if arch(arm64)
import os

/// Centralized loggers for audio model subsystems.
public enum AudioLog {
    /// Logger for model weight loading and initialization.
    public static let modelLoading = Logger(subsystem: "com.qwen3speech", category: "ModelLoading")
    /// Logger for inference and generation.
    public static let inference = Logger(subsystem: "com.qwen3speech", category: "Inference")
    /// Logger for HuggingFace downloads and caching.
    public static let download = Logger(subsystem: "com.qwen3speech", category: "Download")
    /// Logger for voice pipeline events.
    public static let pipeline = Logger(subsystem: "com.qwen3speech", category: "Pipeline")
}
#endif
