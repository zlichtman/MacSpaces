import Foundation

/// Pure JSON editing for agent hook files (`~/.claude/settings.json`,
/// `~/.codex/hooks.json`): adds or removes MacSpaces' hook groups and leaves
/// every other key, event and hook exactly as it was.
enum AgentHookConfig {
    static let events = ["UserPromptSubmit", "PostToolUse"]

    static func merged(_ root: [String: Any], command: String, marker: String, install: Bool,
                       events: [String] = AgentHookConfig.events) -> [String: Any] {
        var root = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = (hooks[event] as? [[String: Any]] ?? []).filter { !isOurs($0, marker: marker) }
            if install {
                groups.append(["hooks": [["type": "command", "command": command, "timeout": 5]]])
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return root
    }

    static func isInstalled(_ root: [String: Any], marker: String, events: [String] = AgentHookConfig.events) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { isOurs($0, marker: marker) }
        }
    }

    /// What a hook event says about the session: working, waiting for the user, finished or gone.
    static func state(forEvent event: String) -> String? {
        switch event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": return "working"
        case "Notification": return "needsYou"
        case "Stop": return "done"
        case "SessionEnd": return "ended"
        default: return nil
        }
    }

    static func isOurs(_ group: [String: Any], marker: String) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
    }
}
