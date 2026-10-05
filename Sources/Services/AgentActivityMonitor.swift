import Foundation
import Combine

/// What coding agents (Claude Code and Codex) are doing, for the closed notch:
/// working, waiting for you, or just finished.
///
/// When enabled, MacSpaces installs one hook command in `~/.claude/settings.json`
/// and `~/.codex/hooks.json` (alongside any of the user's own hooks, which are
/// kept). The hook writes a tiny status file per session (agent, state, folder,
/// time) and prints nothing, so agents never see it. Turning it off removes only
/// MacSpaces' entries and the status files.
@MainActor
final class AgentActivityMonitor: ObservableObject {
    static let shared = AgentActivityMonitor()

    struct Session: Identifiable, Equatable {
        enum State: String { case working, needsYou, done }
        let id: String
        let agent: String
        let state: State
        let folder: String
        let updated: Date
        var name: String { agent == "codex" ? "Codex" : "Claude" }
        var project: String { (folder as NSString).lastPathComponent }
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var error: String?

    /// The one to show: anyone waiting for you, then anyone working, then a recent finish.
    var headline: Session? {
        sessions.first { $0.state == .needsYou }
            ?? sessions.first { $0.state == .working }
            ?? sessions.first { $0.state == .done }
    }
    var workingCount: Int { sessions.filter { $0.state == .working }.count }

    private let defaults: UserDefaults
    private let fileManager = FileManager.default
    private var timer: Timer?
    private static let enabledKey = "agentActivity.enabled"
    private static let marker = "MacSpaces/agent-activity/activity-hook.sh"
    static let events = ["UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]
    /// A finished session shows for a few seconds; a silent "working" one is dropped after ten minutes.
    private static let doneShowsFor: TimeInterval = 8
    private static let workingGoesStaleAfter: TimeInterval = 600

    private var home: URL { fileManager.homeDirectoryForCurrentUser }
    private var directory: URL { home.appendingPathComponent("Library/Application Support/MacSpaces/agent-activity", isDirectory: true) }
    private var statusDirectory: URL { directory.appendingPathComponent("sessions", isDirectory: true) }
    private var scriptURL: URL { directory.appendingPathComponent("activity-hook.sh") }
    private var claudeSettingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    private var codexHooksURL: URL { home.appendingPathComponent(".codex/hooks.json") }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" && defaults.bool(forKey: Self.enabledKey)
        if isEnabled { start() }
    }

    func setEnabled(_ enabled: Bool) {
        // Isolated QA/demo builds never touch the user's agent configuration.
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        error = nil
        do {
            if enabled {
                try fileManager.createDirectory(at: statusDirectory, withIntermediateDirectories: true)
                try Self.script.write(to: scriptURL, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
                try updateHooks(at: claudeSettingsURL, install: true, agent: "claude", createIfMissing: true)
                try updateHooks(at: codexHooksURL, install: true, agent: "codex",
                                createIfMissing: fileManager.fileExists(atPath: codexHooksURL.deletingLastPathComponent().path))
                start()
            } else {
                try updateHooks(at: claudeSettingsURL, install: false, agent: "claude", createIfMissing: false)
                try updateHooks(at: codexHooksURL, install: false, agent: "codex", createIfMissing: false)
                try? fileManager.removeItem(at: statusDirectory)
                stop()
            }
            isEnabled = enabled
            defaults.set(enabled, forKey: Self.enabledKey)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        sessions = []
    }

    /// Reads the status files (a few bytes each) and drops stale ones.
    private func refresh() {
        let now = Date()
        let files = (try? fileManager.contentsOfDirectory(at: statusDirectory, includingPropertiesForKeys: nil)) ?? []
        var found: [Session] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = object["state"] as? String else { continue }
            let updated = Date(timeIntervalSince1970: (object["time"] as? Double) ?? 0)
            let age = now.timeIntervalSince(updated)
            guard let state = Session.State(rawValue: raw),
                  !(state == .done && age > Self.doneShowsFor),
                  !(state == .working && age > Self.workingGoesStaleAfter) else {
                if raw == "ended" || age > 3600 { try? fileManager.removeItem(at: file) }
                continue
            }
            found.append(Session(id: file.deletingPathExtension().lastPathComponent, agent: object["agent"] as? String ?? "claude",
                                 state: state, folder: object["cwd"] as? String ?? "", updated: updated))
        }
        found.sort { $0.updated > $1.updated }
        if found != sessions { sessions = found }
    }

    private func updateHooks(at url: URL, install: Bool, agent: String, createIfMissing: Bool) throws {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ActivityError("\(url.lastPathComponent) isn't a JSON object, so MacSpaces left it unchanged.")
            }
            root = parsed
            let backup = url.appendingPathExtension("macspaces-backup")
            if install, !fileManager.fileExists(atPath: backup.path) { try? data.write(to: backup) }
        } else if !install || !createIfMissing {
            return
        }
        let command = "/bin/sh \"\(scriptURL.path)\" \(agent)"
        root = AgentHookConfig.merged(root, command: command, marker: Self.marker, install: install, events: Self.events)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    /// Prints nothing (hook output would reach the agent); records the session's state.
    static let script = #"""
    #!/bin/sh
    # Installed by MacSpaces (Settings → Activities → Coding agents).
    # Records what this session is doing for the notch. Prints nothing.
    dir="$HOME/Library/Application Support/MacSpaces/agent-activity/sessions"
    [ -d "$dir" ] || exit 0
    input=$(cat)
    agent="${1:-claude}"
    event=$(printf '%s' "$input" | sed -n 's/.*"hook_event_name" *: *"\([A-Za-z]*\)".*/\1/p' | head -n 1)
    session=$(printf '%s' "$input" | sed -n 's/.*"session_id" *: *"\([A-Za-z0-9_.-]*\)".*/\1/p' | head -n 1)
    cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd" *: *"\([^"]*\)".*/\1/p' | head -n 1)
    case "$event" in
      UserPromptSubmit|PreToolUse|PostToolUse) state=working ;;
      Notification) state=needsYou ;;
      Stop) state=done ;;
      SessionEnd) state=ended ;;
      *) exit 0 ;;
    esac
    file="$dir/${agent}-${session:-unknown}.json"
    printf '{"agent":"%s","state":"%s","cwd":"%s","time":%s}\n' "$agent" "$state" "$cwd" "$(date +%s)" > "$file.tmp" && mv "$file.tmp" "$file"
    exit 0
    """#

    private struct ActivityError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
