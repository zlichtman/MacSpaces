import SwiftUI
import AppKit
import EventKit
import ApplicationServices

struct CryptoWidget: View {
    @ObservedObject var service: CryptoService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if service.quotes.isEmpty {
                ProgressView(service.errorText ?? "Loading prices…")
                    .controlSize(.small)
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(service.quotes) { quote in
                    HStack(spacing: 7) {
                        Text(quote.symbol)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 27, alignment: .leading)
                        Text(quote.price, format: .currency(code: "USD").precision(.fractionLength(quote.price < 100 ? 2 : 0)))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Spacer(minLength: 0)
                        Text(quote.change24Hours / 100, format: .percent.precision(.fractionLength(1)))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(quote.change24Hours >= 0 ? .green : .red)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .onAppear { service.startIfNeeded() }
    }
}

struct ClaudeWidget: View {
    @State private var prompt = ""
    @State private var composing = false

    var body: some View {
        Button {
            composing.toggle()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(ThemeStore.shared.accent)
                Text("Ask Claude")
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $composing, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Ask Claude", systemImage: "sparkles")
                    .font(.headline)
                TextEditor(text: $prompt)
                    .font(.system(size: 12))
                    .frame(width: 300, height: 100)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                HStack {
                    Text("The prompt is copied for a private handoff.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Claude", action: openClaude)
                        .buttonStyle(.borderedProminent)
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(14)
        }
    }

    private func openClaude() {
        let value = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.open(appURL)
        } else if let webURL = URL(string: "https://claude.ai/new") {
            NSWorkspace.shared.open(webURL)
        }
        composing = false
    }
}

struct ZoomMeetingsWidget: View {
    @ObservedObject var service: CalendarService

    var body: some View {
        Group {
            if service.eventsAccessDenied {
                Label("Calendar access needed", systemImage: "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let meeting = nextMeeting {
                HStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(ThemeStore.shared.accent)
                        .frame(width: 36, height: 36)
                        .background(ThemeStore.shared.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.event.title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Text(meeting.event.startDate, format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Join") { NSWorkspace.shared.open(meeting.url) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.horizontal, 10)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "video")
                    Text("No upcoming meeting links")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { service.startEventsIfNeeded() }
    }

    private var nextMeeting: (event: CalendarEventItem, url: URL)? {
        for event in service.todayEvents where event.endDate > Date() {
            if let url = event.url, isMeetingURL(url) { return (event, url) }
            let text = [event.location, event.notes].compactMap { $0 }.joined(separator: " ")
            if let match = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let url = match.url,
               isMeetingURL(url) {
                return (event, url)
            }
        }
        return nil
    }

    private func isMeetingURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("zoom.") || host.contains("meet.google.") ||
            host.contains("teams.microsoft.") || host.contains("webex.")
    }
}

struct WindowManagerWidget: View {
    var body: some View {
        HStack(spacing: 7) {
            windowButton("rectangle.lefthalf.inset.filled", "Left Half", .left)
            windowButton("rectangle.inset.filled", "Center", .center)
            windowButton("rectangle.righthalf.inset.filled", "Right Half", .right)
            windowButton("rectangle.fill", "Fill", .fill)
        }
        .padding(.horizontal, 9)
    }

    private func windowButton(_ symbol: String, _ help: String, _ action: WindowAction) -> some View {
        Button {
            Task { @MainActor in
                WindowManager.perform(action)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private enum WindowAction {
    case left, center, right, fill
}

@MainActor
private enum WindowManager {
    static func perform(_ action: WindowAction) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options),
              let application = NSWorkspace.shared.frontmostApplication else { return }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else { return }

        let window = unsafeBitCast(focusedValue, to: AXUIElement.self)
        guard let primary = DisplayTargeting.primaryScreen else { return }
        let screen = screen(containing: window, flippedAgainst: primary) ?? primary
        let visible = screen.visibleFrame
        let target: CGRect

        switch action {
        case .left:
            target = CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .right:
            target = CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .center:
            target = CGRect(
                x: visible.midX - visible.width * 0.35,
                y: visible.midY - visible.height * 0.35,
                width: visible.width * 0.70,
                height: visible.height * 0.70
            )
        case .fill:
            target = visible
        }

        // Accessibility positions are top-left origin anchored to the primary
        // display, so the flip has to use that display's height. Using the
        // target screen's height threw windows off-screen on any multi-monitor
        // layout where the screens are not bottom-aligned with the primary.
        var position = CGPoint(x: target.minX, y: primary.frame.maxY - target.maxY)
        var size = target.size
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    /// Resolves the display a window currently lives on, so a snap acts on that
    /// screen rather than wherever the keyboard focus happens to be.
    private static func screen(
        containing window: AXUIElement,
        flippedAgainst primary: NSScreen
    ) -> NSScreen? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        var origin = CGPoint.zero
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetValue(axValue, .cgPoint, &origin) else { return nil }

        // Nudge below the title bar so a window flush with the top of a screen
        // still resolves to that screen rather than falling outside its frame.
        let cocoaPoint = CGPoint(x: origin.x, y: primary.frame.maxY - origin.y - 1)
        return NSScreen.screens.first { $0.frame.contains(cocoaPoint) }
    }
}

struct WallpaperWidget: View {
    @State private var isApplying = false

    var body: some View {
        VStack(spacing: 6) {
            Button(action: shuffle) {
                Image(systemName: isApplying ? "hourglass" : "photo.on.rectangle.angled")
                    .font(.system(size: 20))
                    .foregroundStyle(ThemeStore.shared.accent)
            }
            .buttonStyle(.plain)
            .disabled(isApplying)
            Text("Shuffle")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            Button("Open Wallpaper Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func shuffle() {
        isApplying = true
        Task.detached {
            let directory = URL(fileURLWithPath: "/System/Library/Desktop Pictures", isDirectory: true)
            let keys: [URLResourceKey] = [.isRegularFileKey]
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ))?.filter { ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) } ?? []
            let selection = files.randomElement()
            await MainActor.run {
                if let selection {
                    for screen in NSScreen.screens {
                        try? NSWorkspace.shared.setDesktopImageURL(selection, for: screen, options: [:])
                    }
                }
                isApplying = false
            }
        }
    }
}

struct SpacerWidget: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .help("Flexible visual spacer")
    }
}

struct SeparatorWidget: View {
    let isVerticalDock: Bool

    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.18))
            .frame(
                width: isVerticalDock ? nil : 1,
                height: isVerticalDock ? 1 : nil
            )
            .padding(isVerticalDock ? .horizontal : .vertical, 7)
    }
}
