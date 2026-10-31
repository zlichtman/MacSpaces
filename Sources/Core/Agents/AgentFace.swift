import Foundation

/// The agent bubble's state: an agent needs you, works, or just finished. Pure, so the
/// checks can pin it. (The bubble shows the agent's app icon; the poses below drew the
/// earlier Peek face and are kept only for the checks until they're retired.)
enum AgentFace {
    enum Mood: Equatable {
        /// An agent is working: it glances toward the camera and back, and blinks.
        case working
        /// One needs you: round eyes, raised brows, a little "o" and a hop each breath.
        case needsYou
        /// One just finished: it smiles for `cheerDuration`, then tucks away.
        case cheering
    }

    /// How long it smiles after a session finishes.
    static let cheerDuration: TimeInterval = 4

    /// Frames per second while shown: enough for a glance and a blink while working,
    /// smoother for the hop. Nothing animates under Reduce Motion.
    static func frameRate(_ mood: Mood) -> Double { mood == .needsYou ? 24 : 12 }

    /// The mood for what the agents are doing, or nil when there's nothing to show.
    /// Waiting beats a smile, and a smile beats working. `whileWorking` is Settings →
    /// Activities → Show the bubble while agents work; without it only a waiting agent shows.
    static func mood(waiting: Int, working: Int, cheering: Bool, whileWorking: Bool) -> Mood? {
        if waiting > 0 { return .needsYou }
        guard whileWorking else { return nil }
        if cheering { return .cheering }
        return working > 0 ? .working : nil
    }

    /// Where the face is at one moment, in the bubble's 32-point design space.
    struct Pose: Equatable {
        /// Sideways look, negative toward the camera (the bubble sits right of it).
        var glance: Double = 0
        /// How open the eyes are, 1 open to 0 shut.
        var openness: Double = 1
        /// How far the face has hopped up.
        var hop: Double = 0
        /// How far the brows have lifted above their rest.
        var brow: Double = 0
    }

    /// The pose at `time` seconds; Reduce Motion uses `Pose()` for every mood.
    static func pose(_ mood: Mood, at time: Double) -> Pose {
        switch mood {
        case .working:
            return Pose(glance: glance(at: time), openness: openness(at: time))
        case .needsYou:
            // The hop lands on the ring's breath (`AgentPopoutLayout.pulse`, 1.6 s).
            let lift = hop(at: time)
            return Pose(hop: lift, brow: lift * 0.6)
        case .cheering:
            return Pose(hop: hop(at: time) * 0.5)
        }
    }

    /// A 5 s look around: ahead, toward the camera, a little the other way, ahead.
    static func glance(at time: Double) -> Double {
        let phase = time.truncatingRemainder(dividingBy: 5)
        func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
        switch phase {
        case ..<1.5: return 0
        case ..<1.9: return -1.8 * ease((phase - 1.5) / 0.4)
        case ..<3.1: return -1.8
        case ..<3.5: return -1.8 + 3.0 * ease((phase - 3.1) / 0.4)
        case ..<4.5: return 1.2
        default: return 1.2 * (1 - ease((phase - 4.5) / 0.5))
        }
    }

    /// A blink every 3.6 s, 0.18 s long.
    static func openness(at time: Double) -> Double {
        let phase = time.truncatingRemainder(dividingBy: 3.6)
        guard phase > 3.42 else { return 1 }
        let x = (phase - 3.42) / 0.18
        return max(0.1, abs(1 - 2 * x))
    }

    /// Two small bounces late in each 1.6 s breath, then still.
    static func hop(at time: Double) -> Double {
        let phase = time.truncatingRemainder(dividingBy: 1.6) / 1.6
        switch phase {
        case 0.6..<0.8: return 1.4 * sin((phase - 0.6) / 0.2 * .pi)
        case 0.8..<0.92: return 0.7 * sin((phase - 0.8) / 0.12 * .pi)
        default: return 0
        }
    }

    /// The bubble's words: what's waiting, what finished or what's working.
    static func summary(mood: Mood, waiting: [(name: String, project: String)], working: [(name: String, project: String)]) -> String {
        switch mood {
        case .needsYou:
            return AgentPopoutLayout.summary(waiting: waiting)
        case .cheering:
            return "An agent finished"
        case .working:
            guard let first = working.first else { return "" }
            return working.count == 1 ? "\(first.name) is working in \(first.project)" : "\(working.count) agents are working"
        }
    }
}
