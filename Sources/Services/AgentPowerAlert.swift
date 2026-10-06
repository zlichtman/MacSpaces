import Foundation
import Combine

/// Tells running coding agents (Claude Code and Codex) to save their work when
/// this Mac is on battery at 20% or below.
///
/// When enabled, MacSpaces installs one hook command in `~/.claude/settings.json`
/// and `~/.codex/hooks.json` for the UserPromptSubmit and PostToolUse events.
/// The hook is silent unless a flag file exists; MacSpaces writes that file only
/// while the battery is low and not on power. Each session is told once per
/// level (20%, 10%, 5%). Turning the alert off removes only MacSpaces' entries.
@MainActor
final class AgentPowerAlert: ObservableObject {
    static let shared = AgentPowerAlert()
    static let threshold = 20

    @Published private(set) var isEnabled: Bool
    @Published private(set) var claudeInstalled = false
    @Published private(set) var codexInstalled = false
    /// The level the current alert was raised at, while one is active.
    @Published private(set) var alertLevel: Int?
    @Published private(set) var error: String?

    private let defaults: UserDefaults
    private let fileManager = FileManager.default
    private var observer: AnyCancellable?
    private static let enabledKey = "agentPowerAlert.enabled"
    private static let marker = "MacSpaces/agent-power/agent-hook.sh"

    private var directory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacSpaces/agent-power", isDirectory: true)
    }
    private var scriptURL: URL { directory.appendingPathComponent("agent-hook.sh") }
    private var flagURL: URL { directory.appendingPathComponent("low-battery.json") }
    private var sentURL: URL { directory.appendingPathComponent("sent") }
    private var claudeSettingsURL: URL { fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }
    private var codexHooksURL: URL { fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json") }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" && defaults.bool(forKey: Self.enabledKey)
        refreshInstallState()
    }

    /// Starts following the battery. Called once at launch.
    func observe(_ monitor: PowerSourceMonitor) {
        observer = monitor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak monitor] _ in
                // objectWillChange fires before the new values land.
                DispatchQueue.main.async {
                    guard let self, let monitor else { return }
                    self.evaluate(level: monitor.batteryLevel, hasBattery: monitor.hasBattery && monitor.hasReading,
                                  onBattery: !monitor.isOnExternalPower)
                }
            }
        evaluate(level: monitor.batteryLevel, hasBattery: monitor.hasBattery && monitor.hasReading,
                 onBattery: !monitor.isOnExternalPower)
    }

    func setEnabled(_ enabled: Bool) {
        // Isolated QA/demo builds never touch the user's agent configuration.
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        error = nil
        do {
            if enabled {
                try installScript()
                try updateHooks(at: claudeSettingsURL, install: true, createIfMissing: true)
                try updateHooks(at: codexHooksURL, install: true,
                                createIfMissing: fileManager.fileExists(atPath: codexHooksURL.deletingLastPathComponent().path))
            } else {
                try updateHooks(at: claudeSettingsURL, install: false, createIfMissing: false)
                try updateHooks(at: codexHooksURL, install: false, createIfMissing: false)
                try? fileManager.removeItem(at: flagURL)
                try? fileManager.removeItem(at: sentURL)
                alertLevel = nil
            }
            isEnabled = enabled
            defaults.set(enabled, forKey: Self.enabledKey)
        } catch {
            self.error = error.localizedDescription
        }
        refreshInstallState()
        AppServices.shared.reconcileDemand(app: AppSettings.shared, nook: NookSettings.shared)
    }

    // MARK: - Battery

    private func evaluate(level: Int, hasBattery: Bool, onBattery: Bool) {
        guard isEnabled, hasBattery, onBattery, level <= Self.threshold else {
            if alertLevel != nil || fileManager.fileExists(atPath: flagURL.path) {
                try? fileManager.removeItem(at: flagURL)
                try? fileManager.removeItem(at: sentURL)
                alertLevel = nil
            }
            return
        }
        let bucket = level <= 5 ? 5 : level <= 10 ? 10 : 20
        let body = "{\"percent\":\(level),\"bucket\":\(bucket),\"since\":\(Int(Date().timeIntervalSince1970))}\n"
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? body.write(to: flagURL, atomically: true, encoding: .utf8)
        alertLevel = level
    }

    // MARK: - Hook installation

    private func installScript() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    private var hookCommand: String { "/bin/sh \"\(scriptURL.path)\"" }

    /// Adds or removes MacSpaces' hook groups, leaving every other setting as it was.
    private func updateHooks(at url: URL, install: Bool, createIfMissing: Bool) throws {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AlertError("\(url.lastPathComponent) isn't a JSON object, so MacSpaces left it unchanged.")
            }
            root = parsed
            // One backup of the user's original file, before MacSpaces first edits it.
            let backup = url.appendingPathExtension("macspaces-backup")
            if install, !fileManager.fileExists(atPath: backup.path) { try? data.write(to: backup) }
        } else if !install || !createIfMissing {
            return
        }
        root = AgentHookConfig.merged(root, command: hookCommand, marker: Self.marker, install: install)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    private func refreshInstallState() {
        func installed(_ url: URL) -> Bool {
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return AgentHookConfig.isInstalled(root, marker: Self.marker)
        }
        claudeInstalled = installed(claudeSettingsURL)
        codexInstalled = installed(codexHooksURL)
    }

    /// Silent (no output) unless the low-battery flag exists; then tells each
    /// session once per level through the hook's additionalContext.
    static let script = #"""
    #!/bin/sh
    # Installed by MacSpaces (Settings → Widgets → System → Low-battery agent alert).
    # Prints nothing unless this Mac is on battery at 20% or below.
    dir="$HOME/Library/Application Support/MacSpaces/agent-power"
    flag="$dir/low-battery.json"
    [ -f "$flag" ] || exit 0
    input=$(cat)
    event=$(printf '%s' "$input" | sed -n 's/.*"hook_event_name" *: *"\([A-Za-z]*\)".*/\1/p')
    session=$(printf '%s' "$input" | sed -n 's/.*"session_id" *: *"\([A-Za-z0-9_.-]*\)".*/\1/p')
    percent=$(sed -n 's/.*"percent" *: *\([0-9]*\).*/\1/p' "$flag")
    bucket=$(sed -n 's/.*"bucket" *: *\([0-9]*\).*/\1/p' "$flag")
    [ -n "$event" ] || event="PostToolUse"
    key="${session:-unknown}-${bucket:-20}"
    grep -qx "$key" "$dir/sent" 2>/dev/null && exit 0
    echo "$key" >> "$dir/sent"
    msg="MacSpaces: this Mac is on battery at ${percent}% and may shut down soon. Save and commit your work now, keep changes small, and do not start long-running tasks (large builds, full test suites, big refactors or downloads) until the user plugs in. Briefly tell the user you noticed the low battery."
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$msg"
    """#

    private struct AlertError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
