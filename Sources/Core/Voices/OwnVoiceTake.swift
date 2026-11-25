import Foundation

/// Record My Voice, in Studio's Voices (Siren's guided take): the passage to read aloud, how a take
/// is judged once the helper has made its clip, and the level meter's and clock's arithmetic.
/// Pure, so `Scripts/check-voices.sh` checks it.
enum OwnVoiceTake {
    /// Siren's Natural passage, about 18 s read aloud: a clip copies at most 20 s
    /// (`VoiceSamples.referenceSeconds`), so a longer one would only be cut.
    static let passage = "Hi, it's me. I'm recording this so MacSpaces can learn how I sound. I like slow mornings, strong coffee, and long walks when the weather turns cold. Honestly, the best part of any day is a good conversation. So, how's yours going? Tell me everything."

    /// What the voice made from a take is called until it's renamed.
    static let name = "My voice"

    /// A take stops on its own after this long; the passage takes about 18 s.
    static let maximumSeconds = 60.0

    /// Why a take can't make a voice, in one line, when it fails Siren's sample checks
    /// (`VoiceSamples.passesChecks`): too little clear speech, or too much background.
    enum Problem: Equatable, Sendable {
        case tooShort(seconds: Double)
        case tooNoisy

        var message: String {
            switch self {
            case .tooShort(let seconds):
                "Only \(Int(seconds.rounded())) seconds of clear speech were heard. Read the whole passage, then Use This."
            case .tooNoisy:
                "There's too much background noise. Somewhere quieter, a hand's width from the mic, works best."
            }
        }
    }

    /// The problem with a take's clip, or nil when it can make a voice: at least
    /// `VoiceSamples.cleanSeconds` of speech, and speech at least `VoiceSamples.cleanBackgroundDB`
    /// above its background when that could be measured.
    static func problem(seconds: Double, evidence: VoiceSamples.Evidence?) -> Problem? {
        guard seconds.isFinite, seconds >= VoiceSamples.cleanSeconds else { return .tooShort(seconds: seconds.isFinite ? max(0, seconds) : 0) }
        if let gap = evidence?.backgroundDB, !(gap.isFinite && gap >= VoiceSamples.cleanBackgroundDB) { return .tooNoisy }
        return nil
    }

    /// The meter's level, 0 to 1, from a microphone's average power in dBFS (-50 dB and under is 0),
    /// eased from `previous` so it doesn't flicker (Siren's `Recorder`).
    static func level(power: Float, previous: Float) -> Float {
        let target = power.isFinite ? max(0, min(1, (power + 50) / 50)) : 0
        return previous * 0.6 + target * 0.4
    }

    /// How many of `count` meter segments `level` lights.
    static func lit(_ level: Float, of count: Int) -> Int {
        guard level.isFinite, count > 0 else { return 0 }
        return max(0, min(count, Int((level * Float(count)).rounded())))
    }

    /// Elapsed time as m:ss.
    static func clock(_ seconds: Double) -> String {
        let whole = seconds.isFinite ? max(0, Int(seconds)) : 0
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
