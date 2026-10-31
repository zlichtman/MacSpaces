import CoreGraphics

/// Whether and where the agent pop-out shows: a round bubble the closed notch's height,
/// just right of the notch (its lanes included), with the agent's app icon while a coding
/// agent needs you, and also while one works or just finished when Settings →
/// Activities → Show the bubble while agents work is on. It stays at the top of the screen and
/// never covers windows, the open Nook, a locked screen or a Hide-in app.
enum AgentPopoutLayout {
    /// Space between the camera and a bubble, and between bubbles: tight, like the
    /// bubbles' flush top edge.
    static let gap: CGFloat = 2

    struct Context: Equatable {
        /// Sessions that need you, and sessions working.
        var waiting = 0
        var working = 0
        /// A session finished in the last `AgentFace.cheerDuration`.
        var cheering = false
        /// Show the bubble while agents work (not only when one needs you).
        var whileWorking = false
        /// Settings → Activities → Coding agents that need you.
        var enabled = true
        var locked = false
        var hiddenForApp = false
        /// The Nook it sits beside is open (the Agents tab is a click away there).
        var nookOpen = false
    }

    static func isVisible(_ context: Context) -> Bool {
        context.enabled && !context.locked && !context.hiddenForApp && !context.nookOpen && mood(context) != nil
    }

    /// The face's mood for this moment, or nil when nothing should show.
    static func mood(_ context: Context) -> AgentFace.Mood? {
        AgentFace.mood(waiting: context.waiting, working: context.working, cheering: context.cheering,
                       whileWorking: context.whileWorking)
    }

    /// The bubble beside a closed notch, in screen coordinates (origin bottom-left),
    /// kept on the notch's screen.
    static func frame(besideNotch notch: CGRect, on screen: CGRect) -> CGRect {
        let side = bubbleSide(forHeight: notch.height)
        let x = min(notch.maxX + gap, screen.maxX - side - 2)
        return CGRect(x: x, y: notch.maxY - gap - side, width: side, height: side)
    }

    /// A bubble beside a closed notch `height` tall: `gap` short of it, so it sits `gap`
    /// below the top edge just as it sits `gap` from the camera, its bottom level with the notch's.
    static func bubbleSide(forHeight height: CGFloat) -> CGFloat { max(0, height - gap) }

    /// The room a row of `bubbles` takes beside the camera, each followed by `gap` on
    /// its camera side: the clear look's activity bubbles, in the agent bubble's size
    /// and spacing, so the agent bubble (placed beside the closed frame) ends the row.
    static func laneWidth(bubbles: Int, side: CGFloat) -> CGFloat {
        CGFloat(max(0, bubbles)) * (side + gap)
    }

    /// Where it slides out from: tucked under the notch's right edge.
    static func startFrame(besideNotch notch: CGRect) -> CGRect {
        let side = bubbleSide(forHeight: notch.height)
        return CGRect(x: notch.maxX - side, y: notch.maxY - gap - side, width: side, height: side)
    }

    /// The pulse, 0…1, over a slow breath (1.6 s), so it reads as waiting, not alarm.
    static func pulse(at time: Double) -> Double {
        (1 - cos(time * 2 * .pi / 1.6)) / 2
    }

    /// "Claude in Garden needs you", "3 agents need you".
    static func summary(waiting: [(name: String, project: String)]) -> String {
        guard let first = waiting.first else { return "" }
        return waiting.count == 1 ? "\(first.name) in \(first.project) needs you" : "\(waiting.count) agents need you"
    }
}
