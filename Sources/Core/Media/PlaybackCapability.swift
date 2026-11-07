import Foundation

enum PlaybackCapability: String, Hashable, Sendable {
    case playPause, previous, next, seek
}
enum PlaybackSource: String, CaseIterable, Identifiable {
    case automatic, system, music, spotify, browser
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .system: return "System player"
        case .music: return "Apple Music"
        case .spotify: return "Spotify"
        case .browser: return "Browser"
        }
    }
}
enum PlaybackCommandError: Error, LocalizedError {
    case unavailable, rejected, changedSource
    var errorDescription: String? {
        switch self {
        case .unavailable: return "This player does not support that control."
        case .rejected: return "The player did not accept the command. Check its Automation access."
        case .changedSource: return "The track or player changed. Try the control again."
        }
    }
}

enum PlaybackValidation {
    static func seek(_ value: Double, duration: Double) -> Double? {
        guard value.isFinite, duration.isFinite, duration > 0 else { return nil }
        return min(max(value, 0), duration)
    }

    /// A number AppleScript joined onto text, which uses the Mac's decimal separator
    /// ("213,457" with a German region). Unreadable text counts as 0.
    static func scriptSeconds(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}
