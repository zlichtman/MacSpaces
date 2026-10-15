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
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        if let screen {
            let top = screen.frame.maxY - max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - Self.size.width / 2, y: top - Self.size.height - 6))
        }
        panel.orderFrontRegardless()
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.window === self?.panel else { return event }
                let prompter = ScriptPrompter.shared
                switch Int(event.keyCode) {
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

/// The script wrapped to the panel's width, scrolled so the current line sits
/// on the reading line; words already read fade back.
struct PrompterView: View {
    @ObservedObject var prompter: ScriptPrompter
    @ObservedObject private var theme = ThemeStore.shared
    @State private var hovering = false

    var body: some View {
        let font = prompter.textSize.points
        let lines = Self.wrap(prompter.words, width: PrompterPanel.size.width - 48, size: font)
        let lineHeight = font * 1.32
        let current = Self.line(containing: prompter.position, in: lines)
        let within = Self.progress(within: current, at: prompter.position, in: lines)
        ZStack(alignment: .top) {
            VStack(alignment: .center, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line.text)
                        .font(.system(size: font, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.nookForeground.opacity(index < current ? 0.32 : index == current ? 1 : 0.7))
                        .frame(height: lineHeight)
                        .frame(maxWidth: .infinity)
                }
            }
            .offset(y: 26 - (CGFloat(current) + CGFloat(within) * 0.6) * lineHeight)
            .animation(prompter.mode == .voice ? .easeOut(duration: 0.35) : nil, value: prompter.position)
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
        .overlay(alignment: .bottom) { if hovering || !prompter.isRunning { controls } }
        .background(theme.notch.surface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 10))
        .onHover { hovering = $0 }
        .preferredColorScheme(theme.notch.colorScheme)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button { prompter.skip(-8) } label: { Image(systemName: "gobackward") }.help("Back a line (←)")
            Button { prompter.togglePause() } label: { Image(systemName: prompter.isRunning ? "pause.fill" : "play.fill") }
                .help("Pause or carry on (Space)")
            Button { prompter.skip(8) } label: { Image(systemName: "goforward") }.help("Forward a line (→)")
            if prompter.mode == .scroll || prompter.scrollingInstead {
                Button { prompter.changeSpeed(by: -10) } label: { Image(systemName: "tortoise.fill") }.help("Slower (↓)")
                Text("\(Int(prompter.speed)) wpm").font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
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

    struct Line { let text: String; let first: Int; let count: Int }

    /// Greedy wrap by measured width, so lines match what's drawn.
    static func wrap(_ words: [String], width: CGFloat, size: CGFloat) -> [Line] {
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        var lines: [Line] = []
        var current: [String] = [], first = 0, used: CGFloat = 0
        for (index, word) in words.enumerated() {
            let w = (word as NSString).size(withAttributes: [.font: font]).width
            if !current.isEmpty, used + space + w > width {
                lines.append(Line(text: current.joined(separator: " "), first: first, count: current.count))
                current = []; used = 0; first = index
            }
            used += (current.isEmpty ? 0 : space) + w
            current.append(word)
        }
        if !current.isEmpty { lines.append(Line(text: current.joined(separator: " "), first: first, count: current.count)) }
        return lines
    }

    static func line(containing position: Double, in lines: [Line]) -> Int {
        let word = Int(position)
        return lines.lastIndex { $0.first <= word } ?? 0
    }

    static func progress(within line: Int, at position: Double, in lines: [Line]) -> Double {
        guard lines.indices.contains(line), lines[line].count > 0 else { return 0 }
        return min(1, max(0, (position - Double(lines[line].first)) / Double(lines[line].count)))
    }
}
