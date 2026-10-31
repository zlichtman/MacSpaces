import AppKit
import Foundation
import Combine
import UniformTypeIdentifiers

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

    struct Session: Identifiable, Equatable, Sendable {
        enum State: String, Sendable { case working, needsYou, done }
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
        var prompt: String?
        var started: Date?
        var steps = 0
        /// Why it's waiting ("Claude needs your permission to use Bash").
        var note: String?
        /// A permission request MacSpaces can answer, while its hook is waiting.
        var request: Request?
        /// The agent's last reply, once a turn has finished.
        var reply: String?
        var name: String { agent == "codex" ? "Codex" : "Claude" }
        /// The app beside the agent's name, unless it only repeats it.
        var appLabel: String? { AgentHookConfig.appLabel(agent: name, app: appName) }
        var project: String { (folder as NSString).lastPathComponent }

        /// The closed notch's words for it.
        var headline: String {
            switch state {
            case .needsYou: return note.map { $0.localizedCaseInsensitiveContains("permission") ? "Needs permission" : "Needs you" } ?? "Needs you"
            case .done: return "Done"
            case .working: return action ?? "Thinking…"
            }
        }
    }

    /// One pending permission request: the hook process waiting for it, the tool and
    /// what it would do.
    struct Request: Equatable, Sendable {
        let hook: String
        let tool: String
        let title: String
        let detail: String?
    }

    enum Answer: String { case allow, deny, app }

    @Published private(set) var isEnabled: Bool
    /// Permission requests wait briefly for Allow or Deny in MacSpaces (on by default).
    @Published private(set) var answersEnabled: Bool
    /// The agent bubble also shows while agents work and ticks when one
    /// finishes, not only when one needs you (on by default).
    @Published private(set) var peekWhileWorking: Bool
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var error: String?
    /// The session the agent pop-out opened the Agents tab for, outlined there.
    @Published var spotlight: String?


    private let defaults: UserDefaults
    private let fileManager = FileManager.default
    private var timer: Timer?
    private var scanTask: Task<[Session], Never>?
    private var scanGeneration = 0
    private static let enabledKey = "agentActivity.enabled"
    private static let answersKey = "agentActivity.answers"
    private static let peekWhileWorkingKey = "agentActivity.peekWhileWorking"
    private var ticks = 0
    nonisolated static let marker = "MacSpaces/agent-activity/activity-hook.sh"
    static let events = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "SessionEnd"]
    /// Codex has no Notification event: it asks for approval with PermissionRequest.
    static let codexEvents = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]
    /// A finished session stays in Agents for half an hour, with its last reply; a
    /// silent "working" one is dropped after ten minutes.
    nonisolated private static let doneShowsFor: TimeInterval = 1800
    nonisolated private static let workingGoesStaleAfter: TimeInterval = 600

    private var home: URL { fileManager.homeDirectoryForCurrentUser }
    private var directory: URL { home.appendingPathComponent("Library/Application Support/MacSpaces/agent-activity", isDirectory: true) }
    private var statusDirectory: URL { directory.appendingPathComponent("sessions", isDirectory: true) }
    private var scriptURL: URL { directory.appendingPathComponent("activity-hook.sh") }
    private var aliveURL: URL { directory.appendingPathComponent("alive") }
    private var claudeSettingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    private var codexHooksURL: URL { home.appendingPathComponent(".codex/hooks.json") }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" && defaults.bool(forKey: Self.enabledKey)
        answersEnabled = defaults.object(forKey: Self.answersKey) as? Bool ?? true
        // Off unless chosen: before 3.30 the bubble showed only while an agent needed you,
        // and 3.30–3.34's default of on changed that for everyone who never set it.
        peekWhileWorking = defaults.object(forKey: Self.peekWhileWorkingKey) as? Bool ?? false
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
        waiting.note = "Needs permission"; waiting.prompt = "Run the test suite and fix what fails"
        waiting.request = Request(hook: "1", tool: "Bash", title: "Run a command", detail: "npm test -- --watch=false")
        waiting.started = now.addingTimeInterval(-95); waiting.steps = 6
        var codex = Session(id: "c", agent: "codex", state: .working, folder: "/Users/sample/Projects/Atlas", updated: now)
        codex.action = "Running npm test"; codex.prompt = "Add pagination to the search API"
        codex.started = now.addingTimeInterval(-1260); codex.steps = 41
        var finished = Session(id: "d", agent: "codex", state: .done, folder: "/Users/sample/Projects/Atlas", updated: now.addingTimeInterval(-240))
        finished.appBundleID = "com.openai.chat"; finished.appName = "ChatGPT"; finished.prompt = "Bump the API client to v3"
        finished.reply = "Updated the client to v3 and fixed the two call sites that changed. All 48 tests pass."
        finished.started = now.addingTimeInterval(-900); finished.steps = 17
        isEnabled = true
        sessions = [waiting, editing, codex, finished]
    }

    /// Website demos: these synthetic sessions, turned on.
    func preview(_ list: [Session]) {
        isEnabled = true
        sessions = list
    }

    /// Website demos: the agents' real app icons by agent ("claude", "codex"), fetched at run
    /// time (GitHub's runners have neither app) and never committed.
    static var previewAgentIcons: [String: NSImage] = [:]

    /// QA captures of the empty Agents tab: turned on with no sessions, or off.
    func previewEmpty(enabled: Bool) {
        isEnabled = enabled
        sessions = []
    }
#endif

    /// Answers a session's pending permission request: Allow or Deny goes back to the
    /// agent through its waiting hook; `.app` hands it to the agent's own prompt.
    func answer(_ session: Session, _ answer: Answer) {
        guard let request = session.request else { return }
        let file = statusDirectory.appendingPathComponent(session.id).appendingPathExtension("answer")
        try? Data("\(request.hook) \(answer.rawValue)".utf8).write(to: file, options: .atomic)
        if answer == .app { reveal(session) }
        // Show the answer at once; the next scan confirms it.
        sessions = sessions.map { item in
            guard item.id == session.id else { return item }
            var next = item
            next.request = nil
            return next
        }
        Haptics.tap()
    }

    func setAnswersEnabled(_ enabled: Bool) {
        answersEnabled = enabled
        defaults.set(enabled, forKey: Self.answersKey)
        heartbeat()
    }

    func setPeekWhileWorking(_ enabled: Bool) {
        peekWhileWorking = enabled
        defaults.set(enabled, forKey: Self.peekWhileWorkingKey)
    }

    /// While this is fresh, a waiting hook gives MacSpaces time to answer.
    private func heartbeat() {
        if answersEnabled && isEnabled {
            if !fileManager.fileExists(atPath: aliveURL.path) { fileManager.createFile(atPath: aliveURL.path, contents: nil) }
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: aliveURL.path)
        } else {
            try? fileManager.removeItem(at: aliveURL)
        }
    }

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

    /// The agent's own app icon (Claude's app for Claude Code; for Codex the Codex app, or
    /// ChatGPT, which ships it), so the bubble shows which agent it is; else the app it
    /// runs in; else Terminal's, where agents run. Never nil, so nothing stands in for it.
    static func agentIcon(for session: Session?) -> NSImage {
#if DEBUG
        if let agent = session?.agent, let icon = previewAgentIcons[agent] { return icon }
#endif
        let brands: [String]
        switch session?.agent {
        case "codex": brands = ["com.openai.codex", "com.openai.chat"]
        case "claude": brands = ["com.anthropic.claudefordesktop"]
        default: brands = []
        }
        for brand in brands {
            if let cached = icons[brand] { if let cached { return cached } else { continue } }
            let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: brand).map { NSWorkspace.shared.icon(forFile: $0.path) }
            icons[brand] = icon
            if let icon { return icon }
        }
        if let session, let icon = icon(for: session) { return icon }
        return appIcon("com.apple.Terminal") ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private static func appIcon(_ bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[bundleID] = icon
        return icon
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
                try? fileManager.removeItem(at: aliveURL)
                stop()
            }
            isEnabled = enabled
            defaults.set(enabled, forKey: Self.enabledKey)
            heartbeat()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func start() {
        guard timer == nil else { return }
        let poll = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
        scanGeneration += 1
        heartbeat()
        refresh()
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        scanGeneration += 1
        scanTask?.cancel()
        sessions = []
    }

    /// One bounded worker; an old scan cannot repopulate disabled/restarted monitoring.
    private func refresh() {
        ticks += 1
        if ticks % 5 == 0 { heartbeat() }
        guard timer != nil, scanTask == nil else { return }
        let generation = scanGeneration
        let directory = statusDirectory
        let task = Task.detached(priority: .utility) { Self.readSessions(at: directory) }
        scanTask = task
        Task { @MainActor [weak self] in
            let found = await task.value
            guard let self else { return }
            self.scanTask = nil
            guard self.timer != nil, self.scanGeneration == generation, !task.isCancelled else { return }
            self.publish(found)
        }
    }

    nonisolated static func readSessions(at statusDirectory: URL) -> [Session] {
        let fileManager = FileManager.default
        let now = Date()
        let files = (try? fileManager.contentsOfDirectory(at: statusDirectory, includingPropertiesForKeys: nil)) ?? []
        var found: [Session] = []
        for file in files where file.pathExtension == "json" {
            guard !Task.isCancelled else { return [] }
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
                    for suffix in ["json", "prompt", "tool", "count", "note", "ask", "answer", "reply"] { try? fileManager.removeItem(at: base.appendingPathExtension(suffix)) }
                }
                continue
            }
            var session = Session(id: base.lastPathComponent, agent: object["agent"] as? String ?? "claude",
                                  state: state, folder: object["cwd"] as? String ?? "", updated: updated)
            session.appBundleID = AgentHookConfig.hostApp(object["app"] as? String ?? "")
            session.appName = AgentHookConfig.appName(bundleID: session.appBundleID, term: object["term"] as? String ?? "")
            func read(_ suffix: String) -> String? {
                (try? Data(contentsOf: base.appendingPathExtension(suffix))).map { String(decoding: $0, as: UTF8.self) }
            }
            if let payload = read("prompt") {
                session.prompt = AgentHookConfig.userPrompt(AgentHookConfig.field("prompt", in: payload))
                session.started = (try? fileManager.attributesOfItem(atPath: base.appendingPathExtension("prompt").path))?[.modificationDate] as? Date
            }
            if let payload = read("tool"), let tool = AgentHookConfig.field("tool_name", in: payload) {
                session.action = AgentHookConfig.describe(tool: tool, payload: payload)
            }
            session.steps = ((try? fileManager.attributesOfItem(atPath: base.appendingPathExtension("count").path))?[.size] as? Int) ?? 0
            if state == .needsYou, let payload = read("note") { session.note = AgentHookConfig.field("message", in: payload) }
            // A hook still waiting for Allow or Deny: its process id, then the request.
            if state == .needsYou, let ask = read("ask"), let newline = ask.firstIndex(of: "\n") {
                let payload = String(ask[ask.index(after: newline)...])
                let tool = AgentHookConfig.field("tool_name", in: payload) ?? ""
                let (title, detail) = AgentHookConfig.request(tool: tool, payload: payload)
                session.request = Request(hook: String(ask[..<newline]), tool: tool, title: title, detail: detail)
            }
            if state == .done, let payload = read("reply") {
                session.reply = AgentHookConfig.field("last_assistant_message", in: payload)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            found.append(session)
        }
        found.sort { $0.updated > $1.updated }
        return found
    }

    private func publish(_ found: [Session]) {
        // `AgentPopout` follows these: a session that needs you pulses beside the notch.
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
        let before = root
        // Ours come out of every event first, so an event an agent no longer gets is dropped.
        root = AgentHookConfig.merged(root, command: command, marker: Self.marker, install: false,
                                      events: Array(Set(Self.events + Self.codexEvents)))
        if install {
            root = AgentHookConfig.merged(root, command: command, marker: Self.marker, install: true,
                                          events: agent == "codex" ? Self.codexEvents : Self.events, timeouts: Self.hookTimeouts)
        }
        // Already up to date: leave the file alone.
        if (before as NSDictionary).isEqual(to: root) { return }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        // Codex runs a changed hook only after it's reviewed again.
        if agent == "codex" { CodexHookReview.shared.check(force: true) }
    }

    /// Records each session's state for the notch. It prints nothing, except the
    /// answer to a permission request given in MacSpaces: while MacSpaces is running
    /// (it touches `alive` every few seconds) and answering is on, a PermissionRequest
    /// waits up to `answerWait` seconds for Allow, Deny or "answer in the app", then
    /// stays silent so the agent's own prompt decides.
    static let script = #"""
    #!/bin/sh
    # Installed by MacSpaces (Settings → Activities → Coding agents that need you).
    # Records what this session is doing for the notch, and passes on Allow or Deny
    # when you answer a permission request in MacSpaces. Prints nothing otherwise.
    dir="$HOME/Library/Application Support/MacSpaces/agent-activity/sessions"
    [ -d "$dir" ] || exit 0
    input=$(cat)
    agent="${1:-claude}"
    event=$(printf '%s' "$input" | sed -n 's/.*"hook_event_name" *: *"\([A-Za-z]*\)".*/\1/p' | head -n 1)
    session=$(printf '%s' "$input" | sed -n 's/.*"session_id" *: *"\([A-Za-z0-9_.-]*\)".*/\1/p' | head -n 1)
    cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd" *: *"\([^"]*\)".*/\1/p' | head -n 1)
    case "$event" in
      UserPromptSubmit|PreToolUse|PostToolUse) state=working ;;
      Notification|PermissionRequest) state=needsYou ;;
      Stop) state=done ;;
      SessionEnd) state=ended ;;
      *) exit 0 ;;
    esac
    base="$dir/${agent}-${session:-unknown}"
    # The first few KB of what it was asked (not text an app injected, which starts
    # with "<"), the tool it's using, why it's waiting and its last reply, read by
    # MacSpaces for the notch; a byte per step counts steps.
    case "$event" in
      UserPromptSubmit)
        if ! printf '%s' "$input" | grep -q '"prompt" *: *"<'; then
          printf '%s' "$input" | head -c 4000 > "$base.prompt"; : > "$base.count"; rm -f "$base.reply"
        fi ;;
      PreToolUse) printf '%s' "$input" | head -c 4000 > "$base.tool"; printf . >> "$base.count" ;;
      Notification) printf '%s' "$input" | head -c 2000 > "$base.note" ;;
      PermissionRequest)
        printf '{"message":"Needs permission"}' > "$base.note"
        { printf '%s\n' "$$"; printf '%s' "$input" | head -c 6000; } > "$base.ask.tmp" && mv "$base.ask.tmp" "$base.ask" ;;
      Stop) printf '%s' "$input" | head -c 6000 > "$base.reply"; rm -f "$base.ask" ;;
    esac
    app=$(printf '%s' "${__CFBundleIdentifier:-}" | tr -cd 'A-Za-z0-9._-')
    term=$(printf '%s' "${TERM_PROGRAM:-}" | tr -cd 'A-Za-z0-9._-')
    file="$base.json"
    status() {
      printf '{"agent":"%s","state":"%s","cwd":"%s","time":%s,"app":"%s","term":"%s"}\n' "$agent" "$1" "$cwd" "$(date +%s)" "$app" "$term" > "$file.tmp" && mv "$file.tmp" "$file"
    }
    status "$state"
    [ "$event" = PermissionRequest ] || exit 0
    # Wait for an answer only while MacSpaces is running and answering is on.
    alive() { seen=$(stat -f %m "$dir/../alive" 2>/dev/null || echo 0); [ $(( $(date +%s) - seen )) -le 15 ]; }
    decision=""
    if alive; then
      i=0
      while [ $i -lt ANSWER_STEPS ]; do
        case "$(cat "$base.answer" 2>/dev/null)" in
          "$$ allow") decision=allow; break ;;
          "$$ deny") decision=deny; break ;;
          "$$ app") break ;;
        esac
        i=$((i + 1))
        [ $((i % 20)) -eq 0 ] && ! alive && break
        sleep 0.25
      done
    fi
    [ "$(head -n 1 "$base.ask" 2>/dev/null)" = "$$" ] && rm -f "$base.ask"
    rm -f "$base.answer"
    [ -n "$decision" ] || exit 0
    rm -f "$base.note"
    status working
    if [ "$decision" = allow ]; then
      printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n'
    else
      printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied in MacSpaces."}}}\n'
    fi
    exit 0
    """#.replacingOccurrences(of: "ANSWER_STEPS", with: String(Int(answerWait * 4)))

    /// How long a permission request waits for an answer in MacSpaces before the
    /// agent's own prompt takes over; the hook's timeout leaves room beyond it.
    static let answerWait: TimeInterval = 45
    static let hookTimeouts = ["PermissionRequest": Int(answerWait) + 15]

    private struct ActivityError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
