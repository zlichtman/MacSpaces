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
        start()
        view.send(txt: trimmed + "\r")
        remember(trimmed)
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

    private static var loginShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    // MARK: LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in self?.title = title }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    /// The shell exited (for example after `exit`); the next command starts a new one.
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in self?.isRunning = false }
    }
}
