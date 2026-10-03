import SwiftUI
import AppKit
import SwiftTerm

/// Quick commands without opening a terminal app: type, press Return, and the
/// output streams below while the command keeps running after the Nook closes.
/// Swipe up on the command bar (or press ↑) for earlier commands, down for later
/// ones. Click the output to answer a prompt such as a password.
struct TerminalWidget: View {
    @ObservedObject var shell: QuickShell
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @State private var command = ""
    /// Position while browsing history; nil is the line being typed.
    @State private var historyIndex: Int?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            ShellOutputView(shell: shell)
                .padding(.leading, 4).padding(.vertical, 3)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            commandBar
        }
        .padding(8)
        .onAppear(perform: shell.start)
        .onChange(of: theme.notch.accent) { _, _ in shell.applyTheme() }
        .onChange(of: command) { _, value in onEditingChanged(!value.isEmpty) }
        .onDisappear { onEditingChanged(false) }
    }

    private var commandBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.notch.accent)
            TextField("Command", text: $command)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .focused($focused)
                .onSubmit(submit)
                .onKeyPress(.upArrow) { step(older: true); return .handled }
                .onKeyPress(.downArrow) { step(older: false); return .handled }
                .accessibilityLabel("Command")
                .accessibilityHint("Return runs it. Up and down arrows go through earlier commands.")
            menu
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Color.primary.opacity(0.08), in: Capsule())
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

/// Hosts the shell's terminal view. One view serves every Nook, so it moves to
/// whichever Home is showing it.
private struct ShellOutputView: NSViewRepresentable {
    let shell: QuickShell

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if shell.view.superview !== container { attach(to: container) }
    }

    private func attach(to container: NSView) {
        let view = shell.view
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
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
