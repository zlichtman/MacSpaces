import Foundation

/// What a timer does as it finishes, chosen on its card. Stored per timer.
enum TimerWhenDone: String, CaseIterable, Identifiable {
    case nothing, pauseMusic, startBreak

    var id: String { rawValue }
    var title: String {
        switch self {
        case .nothing: return "Nothing"
        case .pauseMusic: return "Pause music"
        case .startBreak: return "Start a 5 min break"
        }
    }
}

/// A finished timer's done state beside the notch.
enum TimerDone {
    /// `TimerWhenDone.startBreak`'s length.
    static let breakSeconds: TimeInterval = 5 * 60
    /// How long a finished timer's alert pulses, three times.
    static let pulseCount = 3
    static let pulseLength: TimeInterval = 1.1
    static var pulseDuration: TimeInterval { Double(pulseCount) * pulseLength }

    /// How far through a pulse, 0…1, at `elapsed` seconds after finishing; nil once they're over.
    static func pulseProgress(elapsed: TimeInterval) -> Double? {
        guard elapsed >= 0, elapsed < pulseDuration else { return nil }
        return elapsed.truncatingRemainder(dividingBy: pulseLength) / pulseLength
    }

    /// How long the tick stays when nothing else clears it.
    static let duration: TimeInterval = 10 * 60
    static let laneLabelLimit = 14

    /// The timer's name for the solid lane: one short piece of text, never a wider notch.
    static func laneLabel(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Timer" }
        return trimmed.count > laneLabelLimit ? String(trimmed.prefix(laneLabelLimit - 1)) + "…" : trimmed
    }

    /// Only ever pauses: a song that's already stopped must not start.
    static func shouldPauseMusic(_ action: TimerWhenDone, isPlaying: Bool) -> Bool {
        action == .pauseMusic && isPlaying
    }
}

/// Timer bubbles beside the camera: at most `maxBubbles`, with the rest counted in one more.
enum TimerRow {
    static let maxBubbles = 4

    /// `done` finished timers (after the one that shows as a pill) come first and always show,
    /// then as many running ones as fit.
    static func split(running: Int, done: Int) -> (shown: Int, more: Int) {
        let room = max(0, maxBubbles - done)
        let shown = min(running, room)
        return (shown, running - shown)
    }
}
