import Foundation

/// The engine's own copy of the voice sample, which `MLXAudioBackend` hands to
/// mlx-audio-swift. Qwen3-TTS encodes a sample once and remembers the result
/// by the copy's identity, without keeping the copy itself. So:
/// - the same sample has to arrive as the same copy, or it's encoded again for
///   every sentence, which is the pause between sentences;
/// - a freed copy's identity can go to the next copy made, which would then be
///   read as the old voice. A new copy is made while the older ones are still
///   alive, and they stay alive until audio from the new one has started,
///   which means the engine has moved on from them.
final class HeldReference<Copy: AnyObject>: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var current: Copy?
    private var retired: [Copy] = []

    /// The copy for `samples`; `make` runs only when they've changed.
    func copy(of samples: [Float], make: ([Float]) -> Copy) -> Copy {
        lock.withLock {
            if let current, samples == self.samples { return current }
            let made = make(samples)
            if let current { retired.append(current) }
            self.samples = samples
            current = made
            return made
        }
    }

    /// Audio from `copy` has started, so the engine no longer remembers an older one.
    func started(_ copy: Copy) {
        lock.withLock {
            if current === copy { retired.removeAll() }
        }
    }

    /// Older copies still kept alive.
    var retiredCount: Int { lock.withLock { retired.count } }
}
