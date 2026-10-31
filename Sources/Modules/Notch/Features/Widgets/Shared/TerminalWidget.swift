import SwiftUI
import AppKit
import SwiftTerm

/// Quick commands without opening a terminal app: type, press Return, and the
/// output streams above while the command keeps running after the Nook closes.
/// Serves both the Home widget and the Terminal page; they share one shell.
/// The command line is the terminal's last line, a prompt under the output rather than
/// a separate bar. Swipe up on it (or press ↑) for earlier commands, down for later
/// ones. Click the output to answer a prompt such as a password.
struct TerminalWidget: View {
    @ObservedObject var shell: QuickShell
    /// The full Terminal page: larger type and more room.
    var isPage = false
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @State private var command = ""
    /// Position while browsing history; nil is the line being typed.
    @State private var historyIndex: Int?
    @State private var draft = ""
    @FocusState private var focused: Bool
    private var fontSize: CGFloat { isPage ? 12 : 10.5 }

    var body: some View {
        // No rule between output and prompt: the command line reads as the terminal's
        // last line, in the output's type, inside the same box.
        VStack(spacing: 0) {
            ShellOutputView(shell: shell, fontSize: fontSize)
                .padding(.leading, 4).padding(.top, 3)
            commandBar
        }
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: isPage ? 12 : 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: isPage ? 12 : 8, style: .continuous))
        // On the page the box meets the page's own insets, like every other tab.
        .padding(isPage ? 0 : 8)
        .nookAfterOpening(perform: shell.start)
        .onChange(of: theme.notch.accent) { _ in shell.applyTheme() }
        .onChange(of: command) { value in onEditingChanged(!value.isEmpty) }
        .onDisappear { onEditingChanged(false) }
    }

    private var commandBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: fontSize - 2.5, weight: .bold))
                .foregroundStyle(theme.notch.accent)
            TextField("Type a command", text: $command)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize, design: .monospaced))
                .focused($focused)
                .onSubmit(submit)
                .textFieldKeys(up: { step(older: true) }, down: { step(older: false) })
                .accessibilityLabel("Command")
                .accessibilityHint("Return runs it. Up and down arrows go through earlier commands.")
            menu
        }
        .padding(.leading, 6).padding(.trailing, isPage ? 8 : 6)
        .frame(height: isPage ? 28 : 22)
        .contentShape(Rectangle())
        .background { HistorySwipe { older in step(older: older) } }
        .help("Swipe up for earlier commands")
    }

    private var menu: some View {
        Menu {
            Button("Interrupt (⌃C)", action: shell.interrupt).disabled(!shell.isRunning)
            Button("Clear Screen", action: shell.clearScreen).disabled(!shell.isRunning)
            Divider()
            Button("Clear History", action: shell.clearHistory).disabled(shell.history.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Terminal options")
    }

    private func submit() {
        shell.run(command)
        command = ""
        historyIndex = nil
        focused = true
    }

    /// Moves through history; past the newest entry returns to what was being typed.
    private func step(older: Bool) {
        let history = shell.history
        guard !history.isEmpty else { return }
        if historyIndex == nil {
            guard older else { return }
            draft = command
            historyIndex = history.count - 1
        } else if let index = historyIndex {
            let next = index + (older ? -1 : 1)
            if next < 0 { return }
            if next >= history.count {
                historyIndex = nil
                command = draft
                return
            }
            historyIndex = next
        }
        if let index = historyIndex { command = history[index] }
    }
}

/// Hosts the shell's terminal view. One view serves every Nook, so the most
/// recently shown host takes it; hosts never pull it back on later updates, so
/// two visible hosts (another display, or Home and the page) can't fight over it.
private struct ShellOutputView: NSViewRepresentable {
    let shell: QuickShell
    let fontSize: CGFloat

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {}

    private func attach(to container: NSView) {
        let view = shell.view
        if view.font.pointSize != fontSize {
            view.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        // Moving between the Home tile and the page changes size (and type), so redraw the buffer.
        container.layoutSubtreeIfNeeded()
        view.needsDisplay = true
    }
}

/// Turns vertical trackpad swipes over the command bar into history steps:
/// fingers up for older commands, down for newer, whatever the scroll direction setting.
private struct HistorySwipe: NSViewRepresentable {
    let step: (_ older: Bool) -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.step = step
        return view
    }

    func updateNSView(_ view: SwipeView, context: Context) { view.step = step }

    final class SwipeView: NSView {
        var step: (Bool) -> Void = { _ in }
        private var monitor: Any?
        private var travel: CGFloat = 0
        private static let threshold: CGFloat = 22

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            // The text field sits on top, so watch scrolls over this area instead of receiving them.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                self.handle(event)
                return nil
            }
        }

        private func handle(_ event: NSEvent) {
            if event.phase == .began { travel = 0 }
            guard event.momentumPhase == [] else { return }
            let fingersUp = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            travel += event.hasPreciseScrollingDeltas ? fingersUp : fingersUp * Self.threshold
            while abs(travel) >= Self.threshold {
                step(travel > 0)
                travel -= travel > 0 ? Self.threshold : -Self.threshold
            }
            if event.phase == .ended || event.phase == .cancelled { travel = 0 }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
