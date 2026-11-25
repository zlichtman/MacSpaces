import AppKit
import SwiftUI

/// The prompter itself: a panel hanging just under the notch (the camera), in
/// the Nook's colours. It is excluded from screen sharing and recordings.
@MainActor
final class PrompterPanel {
    static let shared = PrompterPanel()
    private var panel: NSPanel?
    private var keyMonitor: Any?
    static let size = NSSize(width: 560, height: 170)

    func show() {
        let panel = self.panel ?? make()
        self.panel = panel
        // The display with the camera: its notch, or its island (which may hang below the menu bar).
        let screen = NSScreen.screens.first { NotchGeometry.detect(on: $0).isHardwareNotch } ?? NSScreen.main
        if let screen {
            let camera = NotchGeometry.detect(on: screen).cameraBottom
            let top = screen.frame.maxY - max(screen.safeAreaInsets.top, camera, NSStatusBar.system.thickness)
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - Self.size.width / 2, y: top - Self.size.height - 6))
        }
        panel.orderFrontRegardless()
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.window === self?.panel else { return event }
                let prompter = ScriptPrompter.shared
                // 1 to 9 jump to that section.
                if let number = Self.digitKeys.firstIndex(of: Int(event.keyCode)), event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                    prompter.jump(toSection: number)
                    return nil
                }
                switch Int(event.keyCode) {
                case 48:                                        // Tab, Shift-Tab
                    event.modifierFlags.contains(.shift) ? prompter.previousSection() : prompter.nextSection()
                case 115: prompter.restart()                    // Home
                case 49: prompter.togglePause()                 // Space
                case 53: prompter.close()                       // Escape
                case 123: prompter.skip(-8)                     // ←
                case 124: prompter.skip(8)                      // →
                case 126: prompter.changeSpeed(by: 10)          // ↑
                case 125: prompter.changeSpeed(by: -10)         // ↓
                default: return event
                }
                return nil
            }
        }
    }

    /// The key codes of 1 to 9 on the number row.
    private static let digitKeys = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    func hide() {
        panel?.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
    }

    private func make() -> NSPanel {
        let panel = PrompterWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Only you see it: not in screen sharing, screenshots or recordings.
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: PrompterView(prompter: .shared))
        return panel
    }
}

private final class PrompterWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The script wrapped to the panel's width, scrolled so the current line sits on the reading
/// line; words already read fade back. Headings show small, in capitals and the accent; stage
/// notes dimmed and in italics.
struct PrompterView: View {
    @ObservedObject var prompter: ScriptPrompter
    @ObservedObject private var theme = ThemeStore.shared
    @State private var hovering = false

    var body: some View {
        let font = prompter.textSize.points
        let lines = prompter.lines
        let lineHeight = font * 1.32
        let current = PrompterLayout.line(containing: prompter.position, in: lines)
        let within = PrompterLayout.progress(within: current, at: prompter.position, in: lines)
        ZStack(alignment: .top) {
            VStack(alignment: .center, spacing: 0) {
                ForEach(Array(prompter.lineRuns.enumerated()), id: \.offset) { index, runs in
                    text(runs, size: font)
                        .opacity(index < current ? 0.32 : index == current ? 1 : 0.7)
                        .frame(height: lineHeight)
                        .frame(maxWidth: .infinity)
                }
            }
            .offset(y: 26 - (CGFloat(current) + CGFloat(within) * 0.6) * lineHeight)
            .animation(prompter.mode == .voice && !theme.reduceMotion ? .easeOut(duration: 0.35) : nil, value: prompter.position)
            .padding(.horizontal, 24)

            if let value = prompter.countdownValue {
                Text("\(value)")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.notch.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.notch.surface.opacity(0.9))
            }
        }
        .frame(width: PrompterPanel.size.width, height: PrompterPanel.size.height, alignment: .top)
        .clipped()
        .overlay(alignment: .top) { if !prompter.script.points.isEmpty || prompter.target != nil { topBar } }
        .overlay(alignment: .bottom) { if hovering || !prompter.isRunning { controls } }
        .background(theme.notch.surface.opacity(prompter.opacity))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 10))
        .onHover { hovering = $0 }
        .preferredColorScheme(theme.notch.colorScheme)
    }

    /// One line from its runs (made once per wrap, in the fonts `ScriptPrompter.wrapLines`
    /// measured): a plain line is a single piece of text.
    private func text(_ runs: [PrompterLayout.Segment], size: CGFloat) -> Text {
        let design: Font.Design = prompter.typeface == .serif ? .serif : prompter.typeface == .mono ? .monospaced : .rounded
        if runs.first?.kind == .heading {
            return Text(runs.map(\.text).joined(separator: " ")).font(.system(size: size * ScriptPrompter.headingScale, weight: .bold, design: design))
                .foregroundColor(theme.notch.accent)
        }
        var result = Text("")
        for (index, run) in runs.enumerated() {
            var piece = Text(run.text)
            if run.kind == .note { piece = piece.italic().foregroundColor(theme.nookForeground.opacity(0.45)) }
            else { piece = piece.foregroundColor(theme.nookForeground) }
            result = index == 0 ? piece : result + Text(" ") + piece
        }
        return result.font(.system(size: size, weight: .semibold, design: design))
    }

    /// Along the top, only for a script with points or a target: the points to cover, each ticked
    /// once said (or clicked), and the reading time against the target.
    private var topBar: some View {
        let points = prompter.script.points
        return HStack(spacing: 6) {
            ForEach(Array(points.enumerated().prefix(4)), id: \.offset) { index, point in
                let done = prompter.covered.contains(index)
                Button { prompter.togglePoint(index) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(done ? theme.notch.accent : theme.nookForeground.opacity(0.6))
                        Text(point.text).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            .foregroundStyle(theme.nookForeground.opacity(done ? 0.4 : 0.85))
                            .strikethrough(done)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Fewer points get more room each.
                .frame(maxWidth: 440 / CGFloat(min(points.count, 4)) - 6, alignment: .leading)
                .help(done ? "Covered" : "To cover: \(point.text)")
            }
            if points.count > 4 {
                Text("+\(points.count - 4)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .help(points.dropFirst(4).map(\.text).joined(separator: "\n"))
            }
            Spacer(minLength: 0)
            if let target = prompter.target { clock(target: target) }
        }
        .padding(.horizontal, 14).frame(height: 20)
        .background(theme.notch.surface.opacity(prompter.opacity))
    }

    /// The reading time over the target: orange from 80% of it, red past it.
    private func clock(target: TimeInterval) -> some View {
        TimelineView(.periodic(from: .now, by: prompter.isRunning ? 1 : 3600)) { context in
            let elapsed = prompter.elapsed(at: context.date)
            let state = PrompterTiming.state(elapsed: elapsed, target: target)
            Text("\(PrompterTiming.clock(elapsed)) / \(PrompterTiming.clock(target))")
                .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                .foregroundStyle(state == .over ? Color.red : state == .near ? Color.orange : theme.nookForeground.opacity(0.6))
                .accessibilityLabel(state == .over ? "Over the target length" : state == .near ? "Close to the target length" : "Reading time")
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if !prompter.script.sections.isEmpty { sectionsMenu }
            Button { prompter.restart() } label: { Image(systemName: "backward.end.fill") }.help("From the top (Home)")
            Button { prompter.skip(-8) } label: { Image(systemName: "gobackward") }.help("Back a line (←)")
            Button { prompter.togglePause() } label: { Image(systemName: prompter.isRunning ? "pause.fill" : "play.fill") }
                .help("Pause or carry on (Space)")
            Button { prompter.skip(8) } label: { Image(systemName: "goforward") }.help("Forward a line (→)")
            if prompter.mode == .scroll || prompter.scrollingInstead {
                Button { prompter.changeSpeed(by: -10) } label: { Image(systemName: "tortoise.fill") }.help("Slower (↓)")
                Text("\(Int(prompter.runSpeed)) wpm").font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
                Button { prompter.changeSpeed(by: 10) } label: { Image(systemName: "hare.fill") }.help("Faster (↑)")
                if prompter.scrollingInstead {
                    Image(systemName: "mic.slash").foregroundStyle(.orange).help(prompter.voiceProblem ?? "")
                }
            } else {
                Image(systemName: prompter.listening ? "waveform" : "mic.slash")
                    .foregroundStyle(prompter.listening ? theme.notch.accent : .secondary)
                if let problem = prompter.voiceProblem {
                    Text(problem).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(1)
                }
            }
            Button { prompter.close() } label: { Image(systemName: "xmark") }.help("Close (Esc)")
        }
        .buttonStyle(WidgetChipStyle(height: 24))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 8)
    }

    /// The script's sections, the one you're in ticked: Tab, Shift-Tab and 1 to 9 do the same.
    private var sectionsMenu: some View {
        let here = prompter.script.section(containing: Int(prompter.position))
        return NookMenu {
            ForEach(Array(prompter.script.sections.enumerated()), id: \.offset) { index, section in
                NookMenuRow(index < 9 ? "\(index + 1)  \(section.title)" : section.title, selected: index == here) {
                    prompter.jump(toSection: index)
                }
            }
        } label: { Image(systemName: "list.bullet") }
        .help("Sections (Tab, Shift-Tab, 1 to 9)")
    }
}
