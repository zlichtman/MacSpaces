#if DEBUG
import SwiftUI
import AppKit

/// The site's Tape video (`tape`, in `WebsiteDemoClips`): a 14-inch MacBook Pro's screen at the
/// site card's shape (the tour's 1512×867-point stage, drawn whole into the clip's 820×470 window,
/// so 1640×940 pixels), the Night Blossom photo as the desktop, a plain menu bar with Tape's mark
/// and the camera housing. Five drawn app windows (a browser, a code editor, notes, a music
/// player with a demo song and a calendar; no real apps or data) are laid out by Tape's own
/// `Strip` and `StripLayout` with the focused column centred, and parked at the screen's edges as
/// Tape's `Animator` parks them. Every frame is a pure function of the clip's time, so it loops:
/// Next Column twice, a new window joins the strip, Next Width widens it, it closes and the strip
/// closes up, then a two-finger swipe scrolls back and a click focuses the first window again.
/// A small key line at the bottom says what was pressed (the app draws none).
@MainActor
enum WebsiteDemoTape {
    static let length = 9.6
    /// The poster's moment: the new window centred in the strip.
    static let posterAt = 3.6
    /// The screen, in points, with a menu bar as tall as the camera housing.
    static let screen = CGSize(width: 1512, height: 867)
    static let menuBar = WebsiteDemoProfile.notchSize.height
    static let geometry = ScreenGeometry(frame: CGRect(origin: .zero, size: screen),
                                         visibleFrame: CGRect(x: 0, y: menuBar, width: screen.width, height: screen.height - menuBar))
    /// Tape's default gaps, with Centre always on.
    static let options = LayoutOptions(gap: 8, edgeGap: 8, centering: .always)
    /// Tape moves windows in 0.14 s; the video eases over a little longer so the move reads.
    static let move = 0.42

    enum App: Int, CaseIterable {
        case notes, browser, code, music, calendar
        var id: WindowID { WindowID(UUID(uuidString: String(format: "7A9E0000-0000-4000-8000-%012d", rawValue + 1))!) }
        var name: String {
            switch self {
            case .notes: return "Notes"
            case .browser: return "Browser"
            case .code: return "Code"
            case .music: return "Music"
            case .calendar: return "Calendar"
            }
        }
        static func of(_ id: WindowID) -> App? { allCases.first { $0.id == id } }
    }

    /// What was pressed for a step, shown in the key line.
    struct Hint: Equatable { let keys: [String]; let label: String }

    struct Step {
        let at: Double
        let strip: Strip
        /// A swipe: the offset glides, nothing else changes.
        var swipe = false
        var hint: Hint?
        var duration: Double { swipe ? 1.5 : WebsiteDemoTape.move }
    }

    static let steps: [Step] = {
        var strip = Strip()
        for (app, width) in [(App.notes, 1.0 / 3), (.browser, 0.5), (.code, 0.5), (.music, 1.0 / 3)] {
            strip.columns.append(Column(window: app.id, width: .fraction(width)))
        }
        strip.focusedWindow = App.browser.id
        func centred(_ strip: Strip) -> Strip {
            var strip = strip
            strip.scrollOffset = StripLayout.revealedOffset(for: strip, screen: geometry, options: options)
            return strip
        }
        let start = centred(strip)
        var steps = [Step(at: 0, strip: start)]
        func step(_ at: Double, _ keys: [String], _ label: String, _ change: (inout Strip) -> Void) {
            var next = steps.last!.strip
            change(&next)
            steps.append(Step(at: at, strip: centred(next), hint: Hint(keys: keys, label: label)))
        }
        step(0.9, ["⌃", "⌥", "→"], "Next Column") { $0.perform(.focus(.right)) }
        step(1.9, ["⌃", "⌥", "→"], "Next Column") { $0.perform(.focus(.right)) }
        step(2.9, ["⌘", "N"], "A new window joins the strip") { $0.insert(App.calendar.id, foreground: true) }
        step(4.1, ["⌃", "⌥", "W"], "Next Width") { $0.perform(.nextWidth) }
        step(5.3, ["⌘", "W"], "The strip closes up") { $0.remove(App.calendar.id) }
        // Browse back with the trackpad: the strip glides, focus stays where it was.
        var browsed = steps.last!.strip
        browsed.scrollOffset = StripLayout.scrolledOffset(for: browsed, by: start.scrollOffset - browsed.scrollOffset,
                                                          screen: geometry, options: options)
        steps.append(Step(at: 6.3, strip: browsed, swipe: true, hint: Hint(keys: ["⌃", "⌥"], label: "Two-finger swipe")))
        // A click on the browser focuses it where it is, so the last frame is the first.
        var clicked = browsed
        clicked.select(App.browser.id)
        steps.append(Step(at: 8.3, strip: clicked, hint: Hint(keys: ["Click"], label: "Focus a window")))
        return steps
    }()

    /// Where each window is at `t`, front to back last, and how present it is (joining or closing).
    struct Placed: Identifiable {
        let app: App
        let frame: CGRect
        let opacity: Double
        let focused: Bool
        var id: Int { app.rawValue }
    }

    static func placed(at time: Double) -> (windows: [Placed], hint: Hint?, hintOpacity: Double, focused: App) {
        let t = min(max(time, 0), length)
        let index = steps.lastIndex { $0.at <= t } ?? 0
        let step = steps[index]
        let previous = index > 0 ? steps[index - 1] : step
        let progress = index > 0 ? min(1, (t - step.at) / step.duration) : 1
        let target = StripLayout.frames(for: step.strip, screen: geometry, options: options)
        var frames: [WindowID: CGRect] = [:]
        if step.swipe {
            // A trackpad glide: eased in and out, the layout read at each offset.
            let eased = progress * progress * (3 - 2 * progress)
            var strip = step.strip
            strip.scrollOffset = previous.strip.scrollOffset + (step.strip.scrollOffset - previous.strip.scrollOffset) * eased
            frames = StripLayout.frames(for: strip, screen: geometry, options: options)
        } else {
            // As Tape's Animator: from where each window is (parked) to its new place.
            let before = StripLayout.frames(for: previous.strip, screen: geometry, options: options)
            for (id, rect) in target {
                let origin = before[id].map { StripLayout.parked($0, on: geometry) } ?? rect
                frames[id] = FrameMotion.interpolate(from: origin, to: rect, progress: progress)
            }
        }
        let focusedID = step.strip.focusedWindow
        var windows: [Placed] = []
        for column in step.strip.columns {
            for id in column.windows {
                guard let app = App.of(id), let rect = frames[id] else { continue }
                let joining = previous.strip.columns.contains { $0.windows.contains(id) } == false && index > 0
                windows.append(Placed(app: app, frame: StripLayout.parked(rect, on: geometry),
                                      opacity: joining ? min(1, progress * 1.6) : 1, focused: id == focusedID))
            }
        }
        // A window that closed fades where it was.
        for column in previous.strip.columns {
            for id in column.windows where !step.strip.columns.contains(where: { $0.windows.contains(id) }) {
                guard let app = App.of(id), let rect = StripLayout.frames(for: previous.strip, screen: geometry, options: options)[id] else { continue }
                windows.insert(Placed(app: app, frame: StripLayout.parked(rect, on: geometry), opacity: max(0, 1 - progress * 2), focused: false), at: 0)
            }
        }
        // The focused window is in front; parked ones sit behind the strip.
        windows.sort { a, b in
            func rank(_ p: Placed) -> Int { p.focused ? 2 : (p.frame.minX < 0 || p.frame.maxX > screen.width ? 0 : 1) }
            return rank(a) < rank(b)
        }
        let since = t - step.at
        let hintOpacity = index == 0 ? 0 : since < 0.12 ? since / 0.12 : since > 0.95 ? max(0, 1 - (since - 0.95) / 0.25) : 1
        return (windows, step.hint, hintOpacity, App.of(focusedID ?? App.browser.id) ?? .browser)
    }

    /// The whole stage: desktop, windows, menu bar, camera and the key line.
    struct Stage: View {
        @ObservedObject var clock: WebsiteDemoClips.Clock
        /// The Tape video's time at the clip's start (the hero reel shows a stretch of it).
        var from: Double = 0
        /// The key line; the hero reel has its own captions instead.
        var keys = true
        static let scale = WebsiteDemoClips.stage.width / WebsiteDemoTape.screen.width

        var body: some View {
            let now = WebsiteDemoTape.placed(at: clock.t + from)
            let size = WebsiteDemoTape.screen
            ZStack(alignment: .topLeading) {
                Image("ThemeNightBlossom").resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
                    .overlay(Color.black.opacity(0.12))
                ForEach(now.windows) { window in
                    TapeDemoWindow(app: window.app, focused: window.focused)
                        .frame(width: window.frame.width, height: window.frame.height)
                        .opacity(window.opacity)
                        .scaleEffect(0.97 + 0.03 * window.opacity)
                        .position(x: window.frame.midX, y: window.frame.midY)
                }
                DemoMenuBar(height: WebsiteDemoTape.menuBar, app: now.focused.name, tapeMark: true)
                    .frame(width: size.width)
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                    .fill(.black).frame(width: WebsiteDemoProfile.notchSize.width, height: WebsiteDemoTape.menuBar)
                    .position(x: size.width / 2, y: WebsiteDemoTape.menuBar / 2)
                if keys, let hint = now.hint {
                    KeyLine(hint: hint)
                        .opacity(now.hintOpacity)
                        .position(x: size.width / 2, y: size.height - 46)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .scaleEffect(Self.scale, anchor: .topLeading)
            .frame(width: WebsiteDemoClips.stage.width, height: WebsiteDemoClips.stage.height, alignment: .topLeading)
            .environment(\.colorScheme, .light)
        }
    }

    /// Keycaps and a few words, like a keystroke overlay in a screen recording.
    private struct KeyLine: View {
        let hint: Hint
        var body: some View {
            HStack(spacing: 6) {
                ForEach(Array(hint.keys.enumerated()), id: \.offset) { _, key in
                    Text(key).font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(minWidth: 30, minHeight: 30).padding(.horizontal, key.count > 1 ? 8 : 0)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                Text(hint.label).font(.system(size: 16, weight: .medium)).padding(.leading, 6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color.black.opacity(0.55), in: Capsule())
        }
    }
}

/// One drawn app window: a title bar with traffic lights, and its app's content.
private struct TapeDemoWindow: View {
    let app: WebsiteDemoTape.App
    let focused: Bool

    private var dark: Bool { app == .code || app == .music }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
        }
        .background(dark ? Color(white: 0.12) : Color(white: 0.985))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(dark ? 0.6 : 0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(focused ? 0.42 : 0.24), radius: focused ? 22 : 10, y: focused ? 10 : 4)
    }

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) { colour in
                    Circle().fill(focused ? colour : Color(white: dark ? 0.32 : 0.82)).frame(width: 12, height: 12)
                }
                Spacer()
            }
            Text(title).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(dark ? Color.white.opacity(focused ? 0.85 : 0.45) : Color.black.opacity(focused ? 0.8 : 0.4))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(dark ? Color(white: 0.16) : Color(white: 0.94))
    }

    private var title: String {
        switch app {
        case .notes: return "Weekend"
        case .browser: return "Five lakes for a long weekend"
        case .code: return "StripView.swift"
        case .music: return "Music"
        case .calendar: return "Calendar"
        }
    }

    @ViewBuilder private var content: some View {
        switch app {
        case .notes: TapeDemoNotes()
        case .browser: TapeDemoBrowser()
        case .code: TapeDemoCode()
        case .music: TapeDemoMusic()
        case .calendar: TapeDemoCalendar()
        }
    }
}

/// A grey bar standing in for a line of body text.
private struct TextLine: View {
    let width: CGFloat
    var tint = Color.black.opacity(0.1)
    var body: some View { RoundedRectangle(cornerRadius: 3).fill(tint).frame(maxWidth: width, minHeight: 9, maxHeight: 9) }
}

private struct TapeDemoBrowser: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left"); Image(systemName: "chevron.right").opacity(0.35)
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 10))
                    Text("trailnotes.example/five-lakes").lineLimit(1)
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).frame(height: 26)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                Image(systemName: "square.and.arrow.up")
            }
            .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.black.opacity(0.55))
            .padding(.horizontal, 14).padding(.vertical, 8)
            Image("ThemeGlacier").resizable().scaledToFill()
                .frame(maxWidth: .infinity).frame(height: 300).clipped()
            VStack(alignment: .leading, spacing: 12) {
                Text("TRAIL NOTES").font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(Color(red: 0.16, green: 0.45, blue: 0.62))
                Text("Five lakes for a long weekend").font(.system(size: 28, weight: .bold, design: .serif)).foregroundStyle(.black.opacity(0.85))
                    .lineLimit(2)
                Text("Cold water, quiet trails and a cabin at the end of each day. A loop you can drive in three days.")
                    .font(.system(size: 15)).foregroundStyle(.black.opacity(0.6)).lineLimit(3)
                ForEach([1.0, 0.94, 0.98, 0.7, 0.96, 0.88, 0.5] as [CGFloat], id: \.self) { TextLine(width: 640 * $0) }
            }
            .padding(24)
        }
    }
}

private struct TapeDemoCode: View {
    private typealias Token = (String, Color)
    private static let keyword = Color(red: 0.99, green: 0.37, blue: 0.64), type = Color(red: 0.37, green: 0.82, blue: 0.86)
    private static let plain = Color.white.opacity(0.82), comment = Color(red: 0.45, green: 0.52, blue: 0.48), number = Color(red: 0.85, green: 0.79, blue: 0.49)
    private static let lines: [[Token]] = [
        [("import", keyword), (" SwiftUI", plain)],
        [],
        [("/// Columns side by side, the focused one centred.", comment)],
        [("struct", keyword), (" StripView", type), (": ", plain), ("View", type), (" {", plain)],
        [("    let", keyword), (" columns: [", plain), ("Column", type), ("]", plain)],
        [("    var", keyword), (" focused = ", plain), ("0", number)],
        [("    var", keyword), (" gap: ", plain), ("CGFloat", type), (" = ", plain), ("8", number)],
        [],
        [("    var", keyword), (" body: ", plain), ("some", keyword), (" View", type), (" {", plain)],
        [("        HStack", type), ("(spacing: gap) {", plain)],
        [("            ForEach", type), ("(columns) { column ", plain), ("in", keyword)],
        [("                ColumnView", type), ("(column: column)", plain)],
        [("                    .frame(width: column.width)", plain)],
        [("            }", plain)],
        [("        }", plain)],
        [("        .offset(x: -scrollOffset)", plain)],
        [("        .animation(.", plain), ("snappy", type), (", value: focused)", plain)],
        [("    }", plain)],
        [],
        [("    // Keep the focused column in the middle.", comment)],
        [("    private var", keyword), (" scrollOffset: ", plain), ("CGFloat", type), (" {", plain)],
        [("        columns.prefix(focused).reduce(", plain), ("0", number), (") { $0 + $1.width + gap }", plain)],
        [("    }", plain)],
        [("}", plain)],
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Text("SOURCES").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                ForEach(["StripView.swift", "ColumnView.swift", "Layout.swift", "Gestures.swift", "Tests"], id: \.self) { name in
                    Label(name, systemImage: name == "Tests" ? "folder" : "swift")
                        .font(.system(size: 12)).lineLimit(1)
                        .foregroundStyle(name == "StripView.swift" ? .white : .white.opacity(0.55))
                }
                Spacer()
            }
            .padding(14).frame(width: 170, alignment: .leading).frame(maxHeight: .infinity, alignment: .top)
            .background(Color(white: 0.09))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(Self.lines.enumerated()), id: \.offset) { number, tokens in
                    HStack(spacing: 14) {
                        Text("\(number + 1)").foregroundStyle(.white.opacity(0.25)).frame(width: 22, alignment: .trailing)
                        tokens.reduce(Text("")) { $0 + Text($1.0).foregroundColor($1.1) }
                    }
                    .lineLimit(1)
                }
            }
            .font(.system(size: 12.5, design: .monospaced))
            .padding(.vertical, 14).padding(.horizontal, 10)
        }
    }
}

private struct TapeDemoNotes: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(["Weekend", "Groceries", "Gift ideas", "Book list"].enumerated()), id: \.offset) { index, title in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Text(["Pack the night before", "Oat milk, lemons", "Film camera strap", "Three to start"][index])
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(index == 0 ? Color(red: 1, green: 0.83, blue: 0.3).opacity(0.45) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                Spacer()
            }
            .padding(10).frame(width: 170).frame(maxHeight: .infinity, alignment: .top)
            .background(Color(white: 0.955))
            VStack(alignment: .leading, spacing: 12) {
                Text("Weekend").font(.system(size: 22, weight: .bold))
                ForEach(Array(["Drive up Friday after lunch", "Swim at the second lake", "Cabin keys from the office", "Pack the night before"].enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 8) {
                        Image(systemName: index < 2 ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(index < 2 ? Color(red: 0.95, green: 0.67, blue: 0.1) : Color.black.opacity(0.3))
                        Text(item).strikethrough(index < 2).foregroundStyle(.black.opacity(index < 2 ? 0.4 : 0.8)).lineLimit(1)
                    }
                    .font(.system(size: 14))
                }
                ForEach([0.9, 0.75, 0.82] as [CGFloat], id: \.self) { TextLine(width: 280 * $0) }
            }
            .padding(20)
            .foregroundStyle(.black.opacity(0.85))
        }
    }
}

private struct TapeDemoMusic: View {
    private static let track = WebsiteDemoProfile.track("generationals")
    private static let cover = track.flatMap { NSImage(contentsOfFile: $0.cover) }

    var body: some View {
        VStack(spacing: 18) {
            Group {
                if let cover = Self.cover { Image(nsImage: cover).resizable().scaledToFill() }
                else { LinearGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.6), Color(red: 0.35, green: 0.2, blue: 0.45)], startPoint: .top, endPoint: .bottom) }
            }
            .frame(width: 260, height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
            VStack(spacing: 4) {
                Text(Self.track?.title ?? "Put a Light On").font(.system(size: 19, weight: .bold)).lineLimit(1)
                Text(Self.track?.artist ?? "Generationals").font(.system(size: 15)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            VStack(spacing: 5) {
                GeometryReader { proxy in
                    Capsule().fill(.white.opacity(0.18))
                        .overlay(alignment: .leading) { Capsule().fill(.white.opacity(0.85)).frame(width: proxy.size.width * 0.34) }
                }
                .frame(height: 4)
                HStack { Text("1:14"); Spacer(); Text("-2:31") }.font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: 300)
            HStack(spacing: 40) {
                Image(systemName: "backward.fill"); Image(systemName: "pause.fill").font(.system(size: 30)); Image(systemName: "forward.fill")
            }
            .font(.system(size: 22))
        }
        .foregroundStyle(.white)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LinearGradient(colors: [Color(red: 0.36, green: 0.22, blue: 0.3), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
    }
}

private struct TapeDemoCalendar: View {
    private struct Event { let day: Int; let start: Double; let hours: Double; let title: String; let colour: Color }
    private static let events = [
        Event(day: 0, start: 9.5, hours: 0.5, title: "Standup", colour: .blue),
        Event(day: 0, start: 13, hours: 1.5, title: "Design review", colour: .purple),
        Event(day: 1, start: 10, hours: 1, title: "Dentist", colour: .orange),
        Event(day: 1, start: 12, hours: 1, title: "Lunch", colour: .green),
        Event(day: 2, start: 9.5, hours: 0.5, title: "Standup", colour: .blue),
        Event(day: 2, start: 15, hours: 2, title: "Focus time", colour: .pink),
        Event(day: 3, start: 11, hours: 1, title: "Planning", colour: .purple),
        Event(day: 3, start: 18, hours: 1.5, title: "Climbing", colour: .green),
        Event(day: 4, start: 9.5, hours: 0.5, title: "Standup", colour: .blue),
        Event(day: 4, start: 19, hours: 2, title: "Dinner at 7", colour: .orange),
    ]
    private static let first = 9.0, last = 21.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("November").font(.system(size: 24, weight: .bold))
                Text("2026").font(.system(size: 24, weight: .regular)).foregroundStyle(Color.red.opacity(0.85))
                Spacer()
                HStack(spacing: 2) {
                    ForEach(["Day", "Week", "Month"], id: \.self) { mode in
                        Text(mode).font(.system(size: 12, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 4)
                            .background(mode == "Week" ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(2).background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
            GeometryReader { proxy in
                let hourHeight = (proxy.size.height - 30) / CGFloat(Self.last - Self.first)
                let column = (proxy.size.width - 44) / 5
                ZStack(alignment: .topLeading) {
                    ForEach(Array(["Mon 9", "Tue 10", "Wed 11", "Thu 12", "Fri 13"].enumerated()), id: \.offset) { index, day in
                        Text(day).font(.system(size: 12, weight: .semibold)).foregroundStyle(index == 0 ? Color.red : Color.black.opacity(0.6))
                            .position(x: 44 + column * (CGFloat(index) + 0.5), y: 10)
                    }
                    ForEach(Array(stride(from: Self.first, to: Self.last, by: 2)), id: \.self) { hour in
                        Text("\(Int(hour) > 12 ? Int(hour) - 12 : Int(hour)) \(hour >= 12 ? "PM" : "AM")").font(.system(size: 10)).foregroundStyle(.secondary)
                            .position(x: 18, y: 30 + CGFloat(hour - Self.first) * hourHeight)
                        Rectangle().fill(Color.black.opacity(0.07)).frame(width: proxy.size.width - 44, height: 1)
                            .position(x: 44 + (proxy.size.width - 44) / 2, y: 30 + CGFloat(hour - Self.first) * hourHeight)
                    }
                    ForEach(Array(Self.events.enumerated()), id: \.offset) { _, event in
                        let height = CGFloat(event.hours) * hourHeight - 3
                        Text(event.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                            .foregroundStyle(event.colour.opacity(0.95))
                            .padding(.horizontal, 6).padding(.top, 4)
                            .frame(width: column - 6, height: height, alignment: .topLeading)
                            .background(event.colour.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(alignment: .leading) { Rectangle().fill(event.colour).frame(width: 3) }
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .position(x: 44 + column * (CGFloat(event.day) + 0.5), y: 30 + CGFloat(event.start - Self.first) * hourHeight + height / 2)
                    }
                }
            }
        }
        .padding(18)
        .foregroundStyle(.black.opacity(0.85))
    }
}
#endif
