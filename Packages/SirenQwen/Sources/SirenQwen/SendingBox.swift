// Apple silicon only: MLX voices never run on Intel, where this builds empty (Float16 and Metal).
#if arch(arm64)
import Foundation

/// Transfers a value into a generation task without copying its tensor storage.
///
/// The sending initializer disconnects the value from the caller. The lock and
/// single-use take ensure that only one consumer can acquire it, even if the box
/// is captured by a Sendable closure. This does not make the value itself Sendable.
final class SendingBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    init(_ value: consuming sending Value) {
        self.value = consume value
    }

    func take() -> sending Value {
        lock.lock()
        defer { lock.unlock() }
        guard let value else {
            preconditionFailure("Generation input already transferred")
        }
        self.value = nil
        return value
    }
}
#endif
