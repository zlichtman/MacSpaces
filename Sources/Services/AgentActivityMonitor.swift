import AppKit
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
        /// The app it runs in (bundle identifier and terminal name, when known).
        var appBundleID = ""
        var appName: String?
        /// What it's doing now ("Editing Notch.swift"), what it was asked, since when, and how many steps.
        var action: String?
        /// The same in one word ("Editing"), for the closed notch.
        var verb: String?
        var prompt: String?
        var started: Date?
        var steps = 0
        /// Why it's waiting ("Claude needs your permission to use Bash").
        var note: String?
        var name: String { agent == "codex" ? "Codex" : "Claude" }
        var project: String { (folder as NSString).lastPathComponent }

        /// The closed notch's words for it.
        var headline: String {
            switch state {
            case .needsYou: return note.map { $0.localizedCaseInsensitiveContains("permission") ? "Needs permission" : "Needs you" } ?? "Needs you"
            case .done: return "Done"
            case .working: return action ?? "Thinking…"
            }
        }

        /// The closed notch's word: short and steady, so the notch never jitters.
        var shortHeadline: String {
            switch state {
            case .needsYou: return "Needs you"
            case .done: return "Done"
            case .working: return verb ?? "Thinking"
            }
        }
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
    /// Stable positions: progress updates must not shuffle the closed-notch indicators.
    var notchSessions: [Session] {
        sessions.sorted { $0.agent == $1.agent ? $0.id < $1.id : $0.agent < $1.agent }
    }
    struct NotchGroup: Identifiable {
        let id: String
        let sessions: [Session]
    }
    var notchGroups: [NotchGroup] {
        Dictionary(grouping: notchSessions, by: \.agent).keys.sorted().map { agent in
            NotchGroup(id: agent, sessions: notchSessions.filter { $0.agent == agent })
        }
    }

    var workingCount: Int { sessions.filter { $0.state == .working }.count }

    private let defaults: UserDefaults
    private let fileManager = FileManager.default
    private var timer: Timer?
    private static let enabledKey = "agentActivity.enabled"
    private static let marker = "MacSpaces/agent-activity/activity-hook.sh"
    static let events = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd"]
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
        if isEnabled {
            upgradeInstallation()
            start()
        }
    }

    /// Earlier versions installed a simpler hook; bring the script and the hook
    /// events up to date (only writing files that actually change).
    private func upgradeInstallation() {
        if (try? String(contentsOf: scriptURL, encoding: .utf8)) != Self.script {
            try? Self.script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        }
        try? updateHooks(at: claudeSettingsURL, install: true, agent: "claude", createIfMissing: false)
        try? updateHooks(at: codexHooksURL, install: true, agent: "codex", createIfMissing: false)
    }

#if DEBUG
    /// Synthetic sessions for QA captures (never the user's real ones).
    func preview() {
        let now = Date()
        var editing = Session(id: "a", agent: "claude", state: .working, folder: "/Users/sample/Projects/Lighthouse", updated: now)
        editing.appBundleID = "com.apple.Terminal"; editing.appName = "Terminal"
        editing.action = "Editing StatusView.swift"; editing.prompt = "Make the status bar show every running job"
        editing.started = now.addingTimeInterval(-372); editing.steps = 23
        var waiting = Session(id: "b", agent: "claude", state: .needsYou, folder: "/Users/sample/Projects/Garden", updated: now)
        waiting.appBundleID = "com.apple.dt.Xcode"; waiting.appName = "Xcode"
        waiting.note = "Claude needs your permission to use Bash"; waiting.prompt = "Run the test suite and fix what fails"
        waiting.started = now.addingTimeInterval(-95); waiting.steps = 6
        var codex = Session(id: "c", agent: "codex", state: .working, folder: "/Users/sample/Projects/Atlas", updated: now)
        codex.action = "Running npm test"; codex.prompt = "Add pagination to the search API"
        codex.started = now.addingTimeInterval(-1260); codex.steps = 41
        isEnabled = true
        sessions = [waiting, editing, codex]
    }
#endif

    /// Sessions whose "needs you" card is showing.
    private var waitingCards: Set<String> = []

    /// Brings the app a session runs in to the front.
    func reveal(_ session: Session) {
        guard !session.appBundleID.isEmpty,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: session.appBundleID).first else { return }
        app.activate()
    }

    /// The icon of the app a session runs in (looked up once per app).
    static func icon(for session: Session) -> NSImage? {
        guard !session.appBundleID.isEmpty else { return nil }
        if let cached = icons[session.appBundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: session.appBundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[session.appBundleID] = icon
        return icon
    }
    private static var icons: [String: NSImage?] = [:]

    /// The closed notch's line: the headline session, plus how many others are busy.
    var notchLabel: String? {
        guard let headline else { return nil }
        let others = sessions.filter { $0.id != headline.id && $0.state != .done }.count
        return others > 0 ? "\(headline.shortHeadline)  +\(others)" : headline.shortHeadline
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
            let base = file.deletingPathExtension()
            guard let state = Session.State(rawValue: raw),
                  !(state == .done && age > Self.doneShowsFor),
                  !(state == .working && age > Self.workingGoesStaleAfter) else {
                if raw == "ended" || age > 3600 {
                    for suffix in ["json", "prompt", "tool", "count", "note"] { try? fileManager.removeItem(at: base.appendingPathExtension(suffix)) }
                }
                continue
            }
            var session = Session(id: base.lastPathComponent, agent: object["agent"] as? String ?? "claude",
                                  state: state, folder: object["cwd"] as? String ?? "", updated: updated)
            session.appBundleID = object["app"] as? String ?? ""
            session.appName = AgentHookConfig.appName(bundleID: session.appBundleID, term: object["term"] as? String ?? "")
            func read(_ suffix: String) -> String? {
                (try? Data(contentsOf: base.appendingPathExtension(suffix))).map { String(decoding: $0, as: UTF8.self) }
            }
            if let payload = read("prompt") {
                session.prompt = AgentHookConfig.field("prompt", in: payload)?
                    .split(whereSeparator: \.isNewline).first.map(String.init)
                session.started = (try? fileManager.attributesOfItem(atPath: base.appendingPathExtension("prompt").path))?[.modificationDate] as? Date
            }
            if let payload = read("tool"), let tool = AgentHookConfig.field("tool_name", in: payload) {
                session.action = AgentHookConfig.describe(tool: tool, payload: payload)
                session.verb = AgentHookConfig.verb(tool: tool)
            }
            session.steps = ((try? fileManager.attributesOfItem(atPath: base.appendingPathExtension("count").path))?[.size] as? Int) ?? 0
            if state == .needsYou, let payload = read("note") { session.note = AgentHookConfig.field("message", in: payload) }
            found.append(session)
        }
        found.sort { $0.updated > $1.updated }
        if found != sessions { sessions = found }
        // An agent waiting for you comes down from the notch with a way back to
        // its app; the card leaves once it's working again.
        for session in found where session.state == .needsYou && !waitingCards.contains(session.id) {
            waitingCards.insert(session.id)
            NotchBanners.shared.post(.init(source: .agent(sessionID: session.id, appBundleID: session.appBundleID),
                                           title: "\(session.name) · \(session.project)",
                                           detail: session.note ?? "Needs your attention", persistent: true))
        }
        for id in waitingCards where !found.contains(where: { $0.id == id && $0.state == .needsYou }) {
            waitingCards.remove(id)
            NotchBanners.shared.withdraw(agentSession: id)
        }
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
        let before = root
        root = AgentHookConfig.merged(root, command: command, marker: Self.marker, install: install, events: Self.events)
        // Already up to date: leave the file alone.
        if install, AgentHookConfig.isInstalled(before, marker: Self.marker, events: Self.events) { return }
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
    base="$dir/${agent}-${session:-unknown}"
    # The first few KB of what it was asked, the tool it's using and why it's
    # waiting, read by MacSpaces for the notch; a byte per step counts steps.
    case "$event" in
      UserPromptSubmit) printf '%s' "$input" | head -c 4000 > "$base.prompt"; : > "$base.count" ;;
      PreToolUse) printf '%s' "$input" | head -c 4000 > "$base.tool"; printf . >> "$base.count" ;;
      Notification) printf '%s' "$input" | head -c 2000 > "$base.note" ;;
    esac
    app=$(printf '%s' "${__CFBundleIdentifier:-}" | tr -cd 'A-Za-z0-9._-')
    term=$(printf '%s' "${TERM_PROGRAM:-}" | tr -cd 'A-Za-z0-9._-')
    file="$base.json"
    printf '{"agent":"%s","state":"%s","cwd":"%s","time":%s,"app":"%s","term":"%s"}\n' "$agent" "$state" "$cwd" "$(date +%s)" "$app" "$term" > "$file.tmp" && mv "$file.tmp" "$file"
    exit 0
    """#

    private struct ActivityError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
