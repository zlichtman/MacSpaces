import CoreGraphics
import Foundation

/// One sideways two-finger swipe on the closed notch: at most one song change per gesture.
struct SongSwipe {
    enum Action: Equatable {
        case next, previous
        /// The hand coming back after a swipe, brushing the trackpad: it changes nothing.
        case returnStroke
    }

    static let threshold: CGFloat = 40
    /// Sideways travel that counts as a stroke of the hand, even too short to change the song.
    static let stroke: CGFloat = 8
    /// A mouse's sideways wheel has no gesture phases, so a pause this long ends its "gesture".
    static let restGap: TimeInterval = 0.35
    /// Going the other way this soon after a stroke ends is the hand returning. Real swipes the
    /// other way come at least 0.7 s apart, so this stays well under that.
    static let returnGuard: TimeInterval = 0.3

    private var travelled: CGFloat = 0
    private var fired = false
    private var lastEvent: TimeInterval?
    private var startedAt: TimeInterval?
    private var peak: CGFloat = 0
    private var returning = false
    private var lastAction: Action?
    private var lastActionAt: TimeInterval = 0

    /// Adds a scroll event, giving the action once this gesture has travelled far enough.
    /// `scrollingDeltaX` follows the Mac's scroll direction, and so does the swipe: negative is
    /// next, which is fingers left with natural scrolling and fingers right without it.
    /// Mostly vertical events count for nothing, and neither does momentum: the inertia
    /// after the fingers lift isn't a second swipe.
    mutating func add(deltaX: CGFloat, deltaY: CGFloat, momentum: Bool, at time: TimeInterval) -> Action? {
        guard !momentum else { return nil }
        if let lastEvent, time - lastEvent > Self.restGap { end() }
        lastEvent = time
        guard !fired, abs(deltaX) > abs(deltaY) else { return nil }
        if startedAt == nil { startedAt = time }
        travelled += deltaX
        peak = max(peak, abs(travelled))
        guard abs(travelled) >= Self.threshold else { return nil }
        fired = true
        let action: Action = travelled < 0 ? .next : .previous
        if let lastAction, lastAction != action, time - lastActionAt < Self.returnGuard { returning = true; return .returnStroke }
        return action
    }

    /// How far the gesture under way has gone, for the log.
    var travel: CGFloat { travelled }
    /// How long the gesture under way took to travel that far, for the log.
    var duration: TimeInterval {
        guard let startedAt, let lastEvent else { return 0 }
        return lastEvent - startedAt
    }

    mutating func end() {
        // The stroke just finished, short or not, is what a return stroke would be coming back from.
        if !returning, peak >= Self.stroke, let lastEvent {
            lastAction = travelled < 0 ? .next : .previous
            lastActionAt = lastEvent
        }
        peak = 0
        startedAt = nil
        returning = false
        travelled = 0
        fired = false
        lastEvent = nil
    }
}

/// The symbol for an audio output: its name first (headphones report other transports,
/// and a Mac's own headphone jack is built in), then how it's connected.
enum AudioOutputSymbol {
    enum Transport { case builtIn, bluetooth, display, airPlay, other }

    static func symbol(name: String, transport: Transport) -> String {
        let name = name.lowercased()
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("headphone") || name.contains("beats") || name.contains("buds") { return "headphones" }
        switch transport {
        case .display: return "display"
        case .airPlay: return "airplayaudio"
        case .builtIn, .bluetooth, .other: return "speaker.wave.2"
        }
    }
}
