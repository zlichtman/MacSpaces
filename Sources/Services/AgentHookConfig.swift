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

    /// A string field from a hook payload, which may be cut short (the hook keeps
    /// only its first few kilobytes), so this reads it without parsing the whole.
    static func field(_ name: String, in payload: String) -> String? {
        let pattern = "\"" + NSRegularExpression.escapedPattern(for: name) + #""\s*:\s*"((?:[^"\\]|\\.)*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: payload, range: NSRange(payload.startIndex..., in: payload)),
              let range = Range(match.range(at: 1), in: payload) else { return nil }
        let raw = String(payload[range])
        let decoded = (try? JSONSerialization.jsonObject(with: Data("\"\(raw)\"".utf8), options: .fragmentsAllowed)) as? String
        return decoded ?? raw
    }

    /// What a tool call is doing, in a few words: "Editing Notch.swift", "Running make".
    static func describe(tool: String, payload: String) -> String {
        func file(_ key: String) -> String? { field(key, in: payload).map { ($0 as NSString).lastPathComponent } }
        func short(_ text: String, _ limit: Int = 40) -> String {
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
        }
        switch tool {
        case "Edit", "MultiEdit", "NotebookEdit", "apply_patch":
            return file("file_path").map { "Editing \($0)" } ?? file("notebook_path").map { "Editing \($0)" } ?? "Editing files"
        case "Write": return file("file_path").map { "Writing \($0)" } ?? "Writing a file"
        case "Read": return file("file_path").map { "Reading \($0)" } ?? "Reading"
        case "Bash", "shell", "exec_command", "local_shell":
            if let description = field("description", in: payload), !description.isEmpty { return short(description) }
            return field("command", in: payload).map { "Running " + short($0, 32) } ?? "Running a command"
        case "Grep": return field("pattern", in: payload).map { "Searching “\(short($0, 24))”" } ?? "Searching"
        case "Glob", "LS": return field("pattern", in: payload).map { "Finding \(short($0, 28))" } ?? "Looking through files"
        case "WebFetch": return field("url", in: payload).flatMap { URL(string: $0)?.host }.map { "Reading \($0)" } ?? "Reading the web"
        case "WebSearch": return field("query", in: payload).map { "Searching “\(short($0, 24))”" } ?? "Searching the web"
        case "Task", "Agent": return field("description", in: payload).map { "Delegating: " + short($0, 30) } ?? "Delegating"
        case "TodoWrite", "update_plan": return "Planning"
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
                return parts.count >= 2 ? "Using \(parts[1])" : "Using a tool"
            }
            return "Using \(tool)"
        }
    }

    /// The app a session runs in, from the hook's environment: the bundle
    /// identifier macOS passes down, or a terminal's TERM_PROGRAM.
    static func appName(bundleID: String, term: String) -> String? {
        let known = ["com.apple.Terminal": "Terminal", "com.googlecode.iterm2": "iTerm", "com.microsoft.VSCode": "VS Code",
                     "com.todesktop.230313mzl4w4u92": "Cursor", "dev.warp.Warp-Stable": "Warp", "com.mitchellh.ghostty": "Ghostty",
                     "dev.zed.Zed": "Zed", "com.anthropic.claudefordesktop": "Claude", "com.openai.codex": "Codex",
                     "com.apple.dt.Xcode": "Xcode", "co.zeit.hyper": "Hyper", "net.kovidgoyal.kitty": "kitty", "org.alacritty": "Alacritty"]
        if let name = known[bundleID] { return name }
        let terms = ["Apple_Terminal": "Terminal", "iTerm.app": "iTerm", "vscode": "VS Code", "WarpTerminal": "Warp",
                     "ghostty": "Ghostty", "Hyper": "Hyper", "tmux": "tmux", "zed": "Zed"]
        return terms[term]
    }

    static func isOurs(_ group: [String: Any], marker: String) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
    }
}
