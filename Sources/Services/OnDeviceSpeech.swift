import Foundation

/// The teleprompter's promise that audio stays on this Mac: voice following runs
/// only with on-device recognition. When the recognizer can't do that (its
/// language has no on-device model, or it's unavailable), voice mode is refused
/// before any microphone or speech request and the prompter scrolls instead.
enum OnDeviceSpeech {
    enum Decision: Equatable {
        case listen
        case refuse(String)
    }

    static func decide(hasRecognizer: Bool, isAvailable: Bool, supportsOnDevice: Bool) -> Decision {
        guard hasRecognizer, supportsOnDevice else {
            return .refuse("Following your voice needs on-device speech recognition for your language, which this Mac doesn't have. Scrolling instead; nothing was sent anywhere.")
        }
        guard isAvailable else { return .refuse("Speech recognition isn't available right now. Scrolling instead.") }
        return .listen
    }
}
