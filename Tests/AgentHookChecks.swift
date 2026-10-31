import Foundation

@main
enum AgentHookChecks {
    static func main() {
        let marker = "MacSpaces/agent-power/agent-hook.sh"
        let command = "/bin/sh \"/Users/x/Library/Application Support/\(marker)\""
        // A settings file with the user's own hooks and unrelated keys.
        let original: [String: Any] = [
            "model": "opus", "permissions": ["allow": ["Bash(ls)"]],
            "hooks": ["PostToolUse": [["matcher": "Edit", "hooks": [["type": "command", "command": "prettier --write"]]]],
                      "Stop": [["hooks": [["type": "command", "command": "say done"]]]]]
        ]
        let installed = AgentHookConfig.merged(original, command: command, marker: marker, install: true)
        precondition(AgentHookConfig.isInstalled(installed, marker: marker))
        let hooks = installed["hooks"] as! [String: Any]
        precondition((hooks["PostToolUse"] as! [[String: Any]]).count == 2, "user's PostToolUse hook kept")
        precondition((hooks["Stop"] as! [[String: Any]]).count == 1, "unrelated events kept")
        precondition(installed["model"] as? String == "opus" && installed["permissions"] != nil, "other settings kept")
        // Installing twice doesn't duplicate.
        let twice = AgentHookConfig.merged(installed, command: command, marker: marker, install: true)
        precondition(((twice["hooks"] as! [String: Any])["UserPromptSubmit"] as! [[String: Any]]).count == 1)
        // Removing restores the original exactly.
        let removed = AgentHookConfig.merged(twice, command: command, marker: marker, install: false)
        precondition(NSDictionary(dictionary: removed).isEqual(to: original), "removal restores the user's file")
        precondition(!AgentHookConfig.isInstalled(removed, marker: marker))
        // An empty file gains only the hooks, and loses them again cleanly.
        let fresh = AgentHookConfig.merged([:], command: command, marker: marker, install: true)
        precondition(Set(fresh.keys) == ["hooks"])
        precondition(AgentHookConfig.merged(fresh, command: command, marker: marker, install: false).isEmpty)
        // A second MacSpaces hook set (agent activity) with its own events and marker
        // coexists with the battery hook and comes out cleanly.
        let activityEvents = ["UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]
        let both = AgentHookConfig.merged(installed, command: "/bin/sh activity.sh", marker: "activity.sh", install: true, events: activityEvents)
        precondition(AgentHookConfig.isInstalled(both, marker: marker) && AgentHookConfig.isInstalled(both, marker: "activity.sh", events: activityEvents))
        precondition(((both["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]).count == 2, "the user's Stop hook is kept")
        let back = AgentHookConfig.merged(both, command: "/bin/sh activity.sh", marker: "activity.sh", install: false, events: activityEvents)
        precondition(NSDictionary(dictionary: back).isEqual(to: installed), "removing activity hooks leaves the battery hook")
        // Payloads (possibly cut short) describe what the agent is doing.
        let edit = #"{"session_id":"a","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/Users/x/MacSpaces/Sources/Notch.swift","old_string":"a \"quoted\" bit"#
        precondition(AgentHookConfig.field("tool_name", in: edit) == "Edit")
        precondition(AgentHookConfig.describe(tool: "Edit", payload: edit) == "Editing Notch.swift")
        let bash = #"{"tool_name":"Bash","tool_input":{"command":"make release && say done","description":"Build the release"}}"#
        precondition(AgentHookConfig.describe(tool: "Bash", payload: bash) == "Build the release")
        let bare = #"{"tool_name":"Bash","tool_input":{"command":"make"}}"#
        precondition(AgentHookConfig.describe(tool: "Bash", payload: bare) == "Running make")
        precondition(AgentHookConfig.describe(tool: "mcp__github__create_issue", payload: "{}") == "Using create issue")
        precondition(AgentHookConfig.describe(tool: "mcp__ccd_session__mark_chapter", payload: "{}") == "Using mark chapter")
        // Permission requests: what the Allow button would allow.
        let ask = #"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm test -- --watch=false","description":"Run tests"}}"#
        precondition(AgentHookConfig.request(tool: "Bash", payload: ask) == ("Run a command", "npm test -- --watch=false"))
        precondition(AgentHookConfig.request(tool: "shell", payload: #"{"tool_input":{"command":["bash","-lc","make test"]}}"#).detail == "make test")
        precondition(AgentHookConfig.request(tool: "Write", payload: #"{"tool_input":{"file_path":"/a/b/Notes.md"}}"#).title == "Edit Notes.md")
        precondition(AgentHookConfig.request(tool: "mcp__github__create_issue", payload: "{}").title == "Use create issue")
        // Injected text never stands in for what the user asked.
        precondition(AgentHookConfig.userPrompt("<system-reminder>\nhi") == nil)
        precondition(AgentHookConfig.userPrompt("  Fix the timer\nthen ship") == "Fix the timer")
        precondition(AgentHookConfig.appLabel(agent: "Claude", app: "Claude") == nil && AgentHookConfig.appLabel(agent: "Codex", app: "ChatGPT") == "ChatGPT")
        // Codex in ChatGPT reports its bundled helper; the notch shows and opens ChatGPT.
        precondition(AgentHookConfig.hostApp("com.openai.codex.cli") == "com.openai.codex")
        precondition(AgentHookConfig.appName(bundleID: AgentHookConfig.hostApp("com.openai.codex.cli"), term: "") == "ChatGPT")
        precondition(AgentHookConfig.hostApp("com.apple.Terminal") == "com.apple.Terminal")
        // A longer timeout for the event that waits for an answer.
        let timed = AgentHookConfig.merged([:], command: command, marker: marker, install: true, events: ["Stop", "PermissionRequest"],
                                           timeouts: ["PermissionRequest": 75])
        let groups = (timed["hooks"] as! [String: Any])
        precondition(((groups["PermissionRequest"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]["timeout"] as? Int == 75)
        precondition(((groups["Stop"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]["timeout"] as? Int == 5)
        let prompt = #"{"prompt":"Fix the \"timer\" lane\nand ship it"}"#
        precondition(AgentHookConfig.field("prompt", in: prompt) == "Fix the \"timer\" lane\nand ship it", "escapes decode")
        popout()
        peek()
        print("Agent hook checks passed: payload fields and action descriptions; merge keeps user settings and hooks, no duplicates, clean removal, nested format; the agent pop-out's visibility, place, pulse and wording; Peek's moods, poses and words")
    }

    /// The bubble beside the notch: only while an agent waits, never over the open Nook,
    /// a locked screen or a Hide-in app, and always on screen.
    static func popout() {
        let waiting = AgentPopoutLayout.Context(waiting: 1)
        precondition(AgentPopoutLayout.isVisible(waiting))
        precondition(!AgentPopoutLayout.isVisible(.init(waiting: 0)), "Nothing waiting, nothing shown")
        for blocked in [AgentPopoutLayout.Context(waiting: 1, enabled: false), .init(waiting: 1, locked: true),
                        .init(waiting: 1, hiddenForApp: true), .init(waiting: 2, nookOpen: true)] {
            precondition(!AgentPopoutLayout.isVisible(blocked), "Off, locked, hidden or under an open Nook: not shown")
        }
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = CGRect(x: 600, y: 950, width: 312, height: 32)
        let bubble = AgentPopoutLayout.frame(besideNotch: notch, on: screen)
        let side = 32 - AgentPopoutLayout.gap
        precondition(bubble == CGRect(x: 912 + AgentPopoutLayout.gap, y: 950, width: side, height: side),
                     "A circle the gap short of the notch's height, just right of it, the gap below the top")
        precondition(!bubble.intersects(notch), "It never covers the notch")
        let edge = AgentPopoutLayout.frame(besideNotch: CGRect(x: 1480, y: 950, width: 30, height: 32), on: screen)
        precondition(screen.contains(edge), "It stays on its screen")
        let start = AgentPopoutLayout.startFrame(besideNotch: notch)
        precondition(start.maxX == notch.maxX && notch.contains(start), "It slides out from under the notch")
        precondition(abs(AgentPopoutLayout.pulse(at: 0)) < 0.0001 && abs(AgentPopoutLayout.pulse(at: 0.8) - 1) < 0.0001,
                     "A slow breath: rest, then full at 0.8 s")
        precondition(AgentPopoutLayout.summary(waiting: [("Claude", "Garden")]) == "Claude in Garden needs you")
        precondition(AgentPopoutLayout.summary(waiting: [("Claude", "Garden"), ("Codex", "Atlas")]) == "2 agents need you")
        precondition(AgentPopoutLayout.summary(waiting: []).isEmpty)
    }

    /// Peek: a waiting agent always shows it; working and finishing show it only with
    /// Show Peek while agents work; its motion stays small and in step with the ring.
    static func peek() {
        precondition(AgentFace.mood(waiting: 1, working: 3, cheering: true, whileWorking: true) == .needsYou, "Waiting wins")
        precondition(AgentFace.mood(waiting: 1, working: 0, cheering: false, whileWorking: false) == .needsYou)
        precondition(AgentFace.mood(waiting: 0, working: 2, cheering: true, whileWorking: true) == .cheering, "A smile beats working")
        precondition(AgentFace.mood(waiting: 0, working: 2, cheering: false, whileWorking: true) == .working)
        precondition(AgentFace.mood(waiting: 0, working: 0, cheering: false, whileWorking: true) == nil, "Nothing running, nothing shown")
        precondition(AgentFace.mood(waiting: 0, working: 2, cheering: true, whileWorking: false) == nil, "Off: only a waiting agent shows")
        let working = AgentPopoutLayout.Context(working: 1, whileWorking: true)
        precondition(AgentPopoutLayout.isVisible(working) && AgentPopoutLayout.mood(working) == .working)
        precondition(!AgentPopoutLayout.isVisible(.init(working: 1)), "Working alone needs the setting")
        precondition(!AgentPopoutLayout.isVisible(.init(working: 1, whileWorking: true, nookOpen: true)), "Never under an open Nook")
        precondition(!AgentPopoutLayout.isVisible(.init(cheering: true, whileWorking: true, locked: true)), "Never on a locked screen")
        // Motion: a glance toward the camera and back, a short blink, a hop on the breath.
        var glances: [Double] = [], open: [Double] = [], hops: [Double] = []
        for step in 0..<400 {
            let time = Double(step) * 0.025
            let pose = AgentFace.pose(.working, at: time)
            glances.append(pose.glance); open.append(pose.openness)
            precondition(pose.hop == 0 && pose.brow == 0, "Working doesn't hop")
            hops.append(AgentFace.pose(.needsYou, at: time).hop)
        }
        precondition(glances.min()! <= -1.7 && glances.max()! >= 1.1 && glances.allSatisfy { abs($0) <= 1.8 }, "It looks both ways, a little")
        precondition(AgentFace.glance(at: 0) == 0 && AgentFace.glance(at: 5) == 0, "Each look starts ahead")
        precondition(open.filter { $0 < 1 }.count < open.count / 10 && open.min()! >= 0.1, "Blinks are brief and never vanish")
        precondition(hops.max()! <= 1.4 && hops.min()! >= 0, "A small hop, never down")
        precondition(AgentFace.hop(at: 0) == 0 && AgentFace.hop(at: 0.8) == 0, "Still at rest and at the ring's fullest")
        precondition(AgentFace.hop(at: 1.6 * 0.7) > 1.3, "The hop lands late in the breath")
        precondition(AgentFace.pose(.needsYou, at: 1.12).brow > 0, "Brows lift with the hop")
        precondition(AgentFace.frameRate(.working) == 12 && AgentFace.frameRate(.needsYou) == 24, "Quiet while working")
        precondition(AgentFace.summary(mood: .working, waiting: [], working: [("Claude", "Garden")]) == "Claude is working in Garden")
        precondition(AgentFace.summary(mood: .working, waiting: [], working: [("Claude", "Garden"), ("Codex", "Atlas")]) == "2 agents are working")
        precondition(AgentFace.summary(mood: .needsYou, waiting: [("Codex", "Atlas")], working: []) == "Codex in Atlas needs you")
    }
}
