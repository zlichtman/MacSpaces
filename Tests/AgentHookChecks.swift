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
        precondition(AgentHookConfig.state(forEvent: "Notification") == "needsYou" && AgentHookConfig.state(forEvent: "Stop") == "done")
        // Output is valid JSON with the nested group format both tools expect.
        let data = try! JSONSerialization.data(withJSONObject: fresh, options: [.sortedKeys])
        let group = ((try! JSONSerialization.jsonObject(with: data) as! [String: Any])["hooks"] as! [String: Any])["PostToolUse"] as! [[String: Any]]
        precondition((group[0]["hooks"] as! [[String: Any]])[0]["type"] as? String == "command")
        print("Agent hook checks passed: merge keeps user settings and hooks, no duplicates, clean removal, nested format")
    }
}
