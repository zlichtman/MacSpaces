import AppKit
import SwiftTerm

/// One login shell for the Terminal widget, started the first time it's needed
/// and kept running while the widget is on Home, so a command keeps going after
/// the Nook closes. Commands are typed into the shell like keystrokes; the
/// terminal view renders its output, prompts and progress bars.
@MainActor
final class QuickShell: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    /// Past commands, newest last. Kept on this Mac only, like a shell history file.
    @Published private(set) var history: [String]
    @Published private(set) var isRunning = false
    @Published private(set) var title = ""

    private(set) lazy var view: LocalProcessTerminalView = makeView()
    private let defaults: UserDefaults
    private static let historyKey = "terminal.history"
    private static let historyLimit = 100

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        history = defaults.stringArray(forKey: Self.historyKey) ?? []
        super.init()
    }

#if DEBUG
    /// QA captures: a synthetic history (never saved).
    func setPreviewHistory(_ commands: [String]) { history = commands }
#endif

    /// Starts the shell if it isn't running yet.
    func start() {
        guard !isRunning else { return }
        let shell = Self.loginShell
        let name = "-" + (shell as NSString).lastPathComponent
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        view.startProcess(executable: shell, args: [],
                          environment: Terminal.getEnvironmentVariables(termName: "xterm-256color"),
                          execName: name, currentDirectory: home)
        isRunning = true
    }

    /// Types the command into the shell and presses Return.
    func run(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Read before typing: text for a running program, a password above all, is never saved.
        let isCommand = !isRunning || shellIsReadingCommand
        start()
        view.send(txt: trimmed + "\r")
        if isCommand, !ClipboardSecrets.looksSecret(trimmed) { remember(trimmed) }
    }

    private var shellIsReadingCommand: Bool {
        guard let process = view.process else { return false }
        var modes = termios()
        guard process.childfd >= 0, tcgetattr(process.childfd, &modes) == 0 else { return false }
        return Self.isCommandInput(foreground: tcgetpgrp(process.childfd), shell: process.shellPid, localModes: modes.c_lflag)
    }

    /// The shell is at its prompt: it holds the terminal and isn't reading hidden input.
    /// Echo alone can't tell, because zsh and bash turn it off at their own prompt. A
    /// program in front (sudo, ssh, npm login) has its own process group; a shell's
    /// `read -s` has echo off with line input still on.
    static func isCommandInput(foreground: pid_t, shell: pid_t, localModes: tcflag_t) -> Bool {
        guard foreground == shell else { return false }
        return localModes & tcflag_t(ECHO) != 0 || localModes & tcflag_t(ICANON) == 0
    }

    /// Sends Control-C to whatever is running.
    func interrupt() {
        guard isRunning else { return }
        view.send([0x03])
    }

    func clearScreen() {
        guard isRunning else { return }
        view.send([0x0c])
    }

    func clearHistory() {
        history = []
        defaults.removeObject(forKey: Self.historyKey)
    }

    /// Ends the shell, for when the widget leaves Home.
    func stop() {
        guard isRunning else { return }
        view.terminate()
        isRunning = false
    }

    private func remember(_ command: String) {
        history.removeAll { $0 == command }
        history.append(command)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        defaults.set(history, forKey: Self.historyKey)
    }

    private func makeView() -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        view.processDelegate = self
        view.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        view.optionAsMetaKey = true
        applyTheme(to: view)
        return view
    }

    func applyTheme(to view: LocalProcessTerminalView? = nil) {
        let target = view ?? self.view
        let theme = ThemeStore.shared
        // Clear, so the output sits on the tile's own surface.
        target.nativeBackgroundColor = .clear
        target.nativeForegroundColor = NSColor(theme.nookForeground)
        target.caretColor = NSColor(theme.notch.accent)
        target.selectedTextBackgroundColor = NSColor(theme.notch.accent).withAlphaComponent(0.35)
    }

    static var loginShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    // MARK: LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Agents and spinners retitle the window many times a second; only a new title redraws.
        Task { @MainActor [weak self] in if self?.title != title { self?.title = title } }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    /// The shell exited (for example after `exit`); the next command starts a new one.
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in self?.isRunning = false }
    }
}
