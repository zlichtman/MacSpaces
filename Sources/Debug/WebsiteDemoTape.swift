#if DEBUG
import SwiftUI
import AppKit

/// The site's Tape video (`tape`, in `WebsiteDemoClips`): a 14-inch MacBook Pro's screen at the
/// site card's shape (the tour's 1512×867-point stage, drawn whole into the clip's 820×470 window,
/// so 1640×940 pixels) made to read as a real desktop: the Lotus photo as the wallpaper, a menu
/// bar with the focused app's own menus and Tape's mark, the camera housing, and a Dock that
/// Tape's strip stops above. Five app windows are drawn here to look like the apps they stand
/// for (Safari on an article, Notes, Xcode, Music's Recently Added with the demo songs' albums,
/// and Calendar's week), each with its own toolbar, sidebar and real text; nothing is a real app
/// or anyone's data. They are laid out by Tape's own
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
    /// The Dock's band at the bottom: the visible frame ends above it, so Tape's strip does too.
    static let dock: CGFloat = 78
    static let geometry = ScreenGeometry(frame: CGRect(origin: .zero, size: screen),
                                         visibleFrame: CGRect(x: 0, y: menuBar, width: screen.width, height: screen.height - menuBar - dock))
    /// Tape's default gaps, with Centre always on.
    static let options = LayoutOptions(gap: 8, edgeGap: 8, centering: .always)
    /// Tape moves windows in 0.14 s; the video eases over a little longer so the move reads.
    static let move = 0.42
    /// The music player window's song (the hero reel plays its own).
    static var musicSong = "generationals"

    enum App: Int, CaseIterable {
        case notes, browser, code, music, calendar
        var id: WindowID { WindowID(UUID(uuidString: String(format: "7A9E0000-0000-4000-8000-%012d", rawValue + 1))!) }
        var name: String {
            switch self {
            case .notes: return "Notes"
            case .browser: return "Safari"
            case .code: return "Xcode"
            case .music: return "Music"
            case .calendar: return "Calendar"
            }
        }
        /// The app's own menus, as its menu bar shows them.
        var menus: [String] {
            switch self {
            case .notes: return ["File", "Edit", "Format", "View", "Window", "Help"]
            case .browser: return ["File", "Edit", "View", "History", "Bookmarks", "Window", "Help"]
            case .code: return ["File", "Edit", "View", "Find", "Navigate", "Editor", "Product", "Window", "Help"]
            case .music: return ["File", "Edit", "Song", "View", "Controls", "Account", "Window", "Help"]
            case .calendar: return ["File", "Edit", "View", "Window", "Help"]
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
        for (app, width) in [(App.notes, 1.0 / 3), (.browser, 0.5), (.code, 0.5), (.music, 0.5)] {
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
                Image("ThemeLotus").resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
                ForEach(now.windows) { window in
                    TapeDemoWindow(app: window.app, focused: window.focused)
                        .frame(width: window.frame.width, height: window.frame.height)
                        .opacity(window.opacity)
                        .scaleEffect(0.97 + 0.03 * window.opacity)
                        .position(x: window.frame.midX, y: window.frame.midY)
                }
                TapeDemoDock(running: Set(now.windows.filter { $0.opacity > 0.5 }.map(\.app)))
                    .position(x: size.width / 2, y: size.height - WebsiteDemoTape.dock / 2)
                DemoMenuBar(height: WebsiteDemoTape.menuBar, app: now.focused.name, tapeMark: true, menus: now.focused.menus)
                    .frame(width: size.width)
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                    .fill(.black).frame(width: WebsiteDemoProfile.notchSize.width, height: WebsiteDemoTape.menuBar)
                    .position(x: size.width / 2, y: WebsiteDemoTape.menuBar / 2)
                if keys, let hint = now.hint {
                    KeyLine(hint: hint)
                        .opacity(now.hintOpacity)
                        .position(x: size.width / 2, y: size.height - WebsiteDemoTape.dock - 40)
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

/// One drawn app window: the window's shape and shadow, traffic lights, and its app's toolbar and
/// content (also the hero reel's).
struct TapeDemoWindow: View {
    let app: WebsiteDemoTape.App
    let focused: Bool

    private var dark: Bool { app == .code }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(dark ? Color(red: 0.118, green: 0.118, blue: 0.137) : Color.white)
            .overlay(alignment: .topLeading) { lights.padding(.leading, 14).padding(.top, (TapeDemoChrome.toolbar - 12) / 2) }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(dark ? 0.6 : 0.2), lineWidth: 0.5))
            .shadow(color: .black.opacity(focused ? 0.4 : 0.22), radius: focused ? 22 : 10, y: focused ? 10 : 4)
    }

    private var lights: some View {
        HStack(spacing: 8) {
            ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) { colour in
                Circle().fill(focused ? colour : Color(white: dark ? 0.34 : 0.82)).frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
            }
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

/// What the drawn windows share: the toolbar's height and its symbols.
private enum TapeDemoChrome {
    static let toolbar: CGFloat = 52
    /// The room the traffic lights take at a toolbar's leading edge.
    static let lights: CGFloat = 66
    static let hairline = Color.black.opacity(0.1)
}

/// A toolbar button: a symbol in a square, as macOS draws them.
private struct Glyph: View {
    let name: String
    var size: CGFloat = 15
    init(_ name: String, size: CGFloat = 15) { self.name = name; self.size = size }
    var body: some View { Image(systemName: name).font(.system(size: size, weight: .regular)).frame(width: 30, height: 28) }
}

/// The Dock: plain app tiles (a symbol on a colour, no app's own artwork), a dot under each app
/// in the strip, a divider and the Trash.
private struct TapeDemoDock: View {
    let running: Set<WebsiteDemoTape.App>
    private struct Tile: Identifiable {
        let symbol: String, top: Color, bottom: Color
        var glyph = Color.white
        var app: WebsiteDemoTape.App? = nil
        var id: String { symbol }
    }
    private static let tiles: [Tile] = [
        Tile(symbol: "folder.fill", top: Color(red: 0.36, green: 0.72, blue: 1), bottom: Color(red: 0.1, green: 0.45, blue: 0.95)),
        Tile(symbol: "safari.fill", top: .white, bottom: Color(white: 0.9), glyph: Color(red: 0.1, green: 0.5, blue: 0.98), app: .browser),
        Tile(symbol: "envelope.fill", top: Color(red: 0.3, green: 0.7, blue: 1), bottom: Color(red: 0.08, green: 0.4, blue: 0.92)),
        Tile(symbol: "message.fill", top: Color(red: 0.4, green: 0.9, blue: 0.45), bottom: Color(red: 0.1, green: 0.72, blue: 0.25)),
        Tile(symbol: "calendar", top: .white, bottom: Color(white: 0.92), glyph: Color(red: 0.95, green: 0.2, blue: 0.2), app: .calendar),
        Tile(symbol: "note.text", top: Color(red: 1, green: 0.88, blue: 0.4), bottom: Color(red: 1, green: 0.76, blue: 0.12), glyph: Color(white: 0.25), app: .notes),
        Tile(symbol: "music.note", top: Color(red: 1, green: 0.36, blue: 0.45), bottom: Color(red: 0.95, green: 0.12, blue: 0.25), app: .music),
        Tile(symbol: "hammer.fill", top: Color(red: 0.25, green: 0.6, blue: 1), bottom: Color(red: 0.05, green: 0.3, blue: 0.8), app: .code),
        Tile(symbol: "gearshape.fill", top: Color(white: 0.72), bottom: Color(white: 0.45)),
    ]

    private func tile(_ tile: Tile) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [tile.top, tile.bottom], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: tile.symbol).font(.system(size: 26, weight: .medium)).foregroundStyle(tile.glyph))
                .frame(width: 50, height: 50)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 1.5)
            Circle().fill(Color.black.opacity(0.6)).frame(width: 4, height: 4)
                .opacity(tile.app.map(running.contains) == true ? 1 : 0)
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            ForEach(Self.tiles) { tile($0) }
            Rectangle().fill(Color.black.opacity(0.18)).frame(width: 1, height: 44).padding(.horizontal, 3).padding(.bottom, 7)
            tile(Tile(symbol: "trash", top: Color.white.opacity(0.75), bottom: Color.white.opacity(0.45), glyph: Color(white: 0.3)))
        }
        .padding(.horizontal, 9).padding(.top, 7).padding(.bottom, 3)
        .background(Color.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
    }
}

/// Safari on an article: the unified toolbar with its address field, then a real page (a site
/// header, a headline, a byline, a photo with its caption and body text).
private struct TapeDemoBrowser: View {
    private static let teal = Color(red: 0.1, green: 0.42, blue: 0.5)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(TapeDemoChrome.hairline).frame(height: 1)
            page
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: TapeDemoChrome.lights, height: 1)
            Glyph("sidebar.left")
            Glyph("chevron.left", size: 14)
            Glyph("chevron.right", size: 14).opacity(0.35)
            Spacer(minLength: 10)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 9))
                Text("trailnotes.example").font(.system(size: 13))
            }
            .foregroundStyle(Color.black.opacity(0.78))
            .frame(maxWidth: 360).frame(height: 30)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .trailing) {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.black.opacity(0.45)).padding(.trailing, 9)
            }
            Spacer(minLength: 10)
            Glyph("square.and.arrow.up")
            Glyph("plus")
            Glyph("square.on.square")
        }
        .foregroundStyle(Color.black.opacity(0.6))
        .padding(.horizontal, 8).frame(height: TapeDemoChrome.toolbar)
        .background(Color(white: 0.965))
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 22) {
                Text("Trail Notes").font(.system(size: 19, weight: .heavy, design: .serif))
                Spacer()
                ForEach(["Routes", "Gear", "Journal", "About"], id: \.self) { Text($0).font(.system(size: 13, weight: .medium)) }
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 36).frame(height: 52)
            Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
            article.padding(.horizontal, 36).padding(.top, 24)
        }
        .foregroundStyle(Color.black.opacity(0.86))
    }

    private var article: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ROUTES  ·  6 MIN READ").font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(Self.teal)
            Text("Five lakes for a long weekend").font(.system(size: 34, weight: .bold, design: .serif)).lineLimit(2).padding(.top, 8)
            Text("Cold water, quiet trails and a cabin at the end of each day. A loop you can drive in three days.")
                .font(.system(size: 17)).foregroundStyle(Color.black.opacity(0.6)).lineLimit(3).padding(.top, 8)
            HStack(spacing: 8) {
                Circle().fill(Self.teal).frame(width: 24, height: 24)
                    .overlay(Text("ML").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                Text("Maya Lindqvist").fontWeight(.semibold)
                Text("November 3, 2026").foregroundStyle(Color.black.opacity(0.5))
            }
            .font(.system(size: 12.5)).padding(.top, 14)
            Image("ThemeGlacier").resizable().scaledToFill()
                .frame(maxWidth: .infinity).frame(height: 236).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 18)
            Text("Glacier Lake from the north shore, an hour after sunrise.")
                .font(.system(size: 11.5)).foregroundStyle(Color.black.opacity(0.5)).padding(.top, 7)
            Text("The road north leaves the valley just after the last gas station, and for the next ninety miles the lakes come one after another. None of them is far from the car, which is the point: you can swim before breakfast, hike until lunch and still be at the next cabin by dark.")
                .padding(.top, 16)
            Text("Start at Glacier Lake while the water is still glass. The trail along the north shore is flat for two miles, then climbs through larch to a bench with the whole basin below it.")
                .padding(.top, 12)
        }
        .font(.system(size: 15, design: .serif)).lineSpacing(4)
    }
}

/// Xcode: its toolbar (run, stop, the scheme and the build's result), the project navigator, a
/// tab and a jump bar over the source.
private struct TapeDemoCode: View {
    private typealias Token = (String, Color)
    private static let keyword = Color(red: 0.99, green: 0.37, blue: 0.64), type = Color(red: 0.37, green: 0.85, blue: 1)
    private static let plain = Color.white.opacity(0.85), comment = Color(red: 0.42, green: 0.47, blue: 0.53), number = Color(red: 0.82, green: 0.75, blue: 0.41)
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
    /// The navigator's rows: indent, symbol, name.
    private static let files: [(Int, String, String)] = [
        (0, "app.fill", "Tape"), (1, "folder.fill", "Sources"), (2, "swift", "StripView.swift"), (2, "swift", "ColumnView.swift"),
        (2, "swift", "Layout.swift"), (2, "swift", "Gestures.swift"), (2, "swift", "Animator.swift"), (1, "folder.fill", "Tests"),
        (1, "folder.fill", "Resources"), (1, "swift", "Package.swift"),
    ]
    private static let orange = Color(red: 1, green: 0.48, blue: 0.25), blue = Color(red: 0.25, green: 0.6, blue: 1)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1)
            HStack(spacing: 0) {
                navigator
                Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1)
                editor
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: TapeDemoChrome.lights, height: 1)
            Glyph("sidebar.left")
            Spacer().frame(width: 70)
            Glyph("play.fill", size: 14)
            Glyph("stop.fill", size: 13).opacity(0.4)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(Self.blue).frame(width: 14, height: 14)
                Text("Tape").fontWeight(.medium)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).opacity(0.5)
                Image(systemName: "laptopcomputer").font(.system(size: 11))
                Text("My Mac")
                Spacer(minLength: 12)
                Text("Build Succeeded").foregroundStyle(Color.white.opacity(0.85))
                Text("|  Today at 9:38 AM").foregroundStyle(Color.white.opacity(0.45))
            }
            .font(.system(size: 12)).lineLimit(1)
            .padding(.horizontal, 10).frame(height: 28)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, 8)
            Glyph("plus")
            Glyph("sidebar.right")
        }
        .foregroundStyle(Color.white.opacity(0.75))
        .padding(.horizontal, 8).frame(height: TapeDemoChrome.toolbar)
        .background(Color(red: 0.2, green: 0.2, blue: 0.22))
    }

    private var navigator: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "folder.fill").foregroundStyle(Self.blue)
                ForEach(["magnifyingglass", "exclamationmark.triangle", "checkmark.diamond", "ladybug", "tag"], id: \.self) { Image(systemName: $0) }
            }
            .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.45))
            .padding(.horizontal, 12).frame(height: 30)
            Rectangle().fill(Color.black.opacity(0.4)).frame(height: 1)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(Self.files.enumerated()), id: \.offset) { _, file in
                    HStack(spacing: 6) {
                        Image(systemName: file.1 == "swift" ? "swift" : file.1).font(.system(size: 11))
                            .foregroundStyle(file.1 == "swift" ? Self.orange : Self.blue).frame(width: 16)
                        Text(file.2).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(file.0) * 14 + 6).frame(height: 22)
                    .background(file.2 == "StripView.swift" ? Self.blue.opacity(0.55) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(8)
            Spacer(minLength: 0)
        }
        .frame(width: 208).frame(maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "swift").font(.system(size: 11)).foregroundStyle(Self.orange)
                Text("StripView.swift").font(.system(size: 12))
            }
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 12).frame(height: 28)
            .background(Color(red: 0.118, green: 0.118, blue: 0.137))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.16, green: 0.16, blue: 0.18))
            HStack(spacing: 5) {
                ForEach(Array(["Tape", "Sources", "StripView.swift", "No Selection"].enumerated()), id: \.offset) { index, part in
                    if index > 0 { Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).opacity(0.5) }
                    Text(part)
                }
            }
            .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
            .padding(.horizontal, 12).frame(height: 24)
            Rectangle().fill(Color.black.opacity(0.4)).frame(height: 1)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(Self.lines.enumerated()), id: \.offset) { number, tokens in
                    HStack(spacing: 14) {
                        Text("\(number + 1)").foregroundStyle(Color.white.opacity(0.28)).frame(width: 22, alignment: .trailing)
                        tokens.reduce(Text("")) { $0 + Text($1.0).foregroundColor($1.1) }
                    }
                    .lineLimit(1)
                }
            }
            .font(.system(size: 12.5, design: .monospaced))
            .padding(.vertical, 12).padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Notes: the list of notes with the open one in yellow, and the note itself (a checklist, a
/// heading and real text) under Notes' toolbar.
private struct TapeDemoNotes: View {
    private static let yellow = Color(red: 1, green: 0.84, blue: 0.3)
    private static let check = Color(red: 0.95, green: 0.67, blue: 0.1)
    private static let sections: [(String, [(String, String, String)])] = [
        ("Pinned", [("Weekend", "9:12 AM", "Drive up Friday after lunch")]),
        ("Today", [("Groceries", "8:40 AM", "Oat milk, lemons, coffee")]),
        ("Previous 7 Days", [("Gift ideas", "Thursday", "Film camera strap"), ("Book list", "Tuesday", "Three to start with"),
                             ("Trip budget", "Monday", "Cabin, gas, park pass")]),
    ]

    var body: some View {
        HStack(spacing: 0) {
            list
            Rectangle().fill(TapeDemoChrome.hairline).frame(width: 1)
            note
        }
        .foregroundStyle(Color.black.opacity(0.86))
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) { Spacer(); Glyph("list.bullet"); Glyph("trash") }
                .foregroundStyle(Color.black.opacity(0.55))
                .padding(.trailing, 6).frame(height: TapeDemoChrome.toolbar)
            ForEach(Array(Self.sections.enumerated()), id: \.offset) { _, section in
                Text(section.0).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.black.opacity(0.45))
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
                ForEach(Array(section.1.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        (Text(row.1).foregroundColor(Color.black.opacity(0.8)) + Text("  " + row.2).foregroundColor(Color.black.opacity(0.5)))
                            .font(.system(size: 11.5)).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                    .background(row.0 == "Weekend" ? Self.yellow : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(.horizontal, 8)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 198).frame(maxHeight: .infinity, alignment: .top)
        .background(Color(white: 0.955))
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Glyph("square.and.pencil")
                Spacer(minLength: 2)
                Glyph("textformat"); Glyph("checklist"); Glyph("tablecells"); Glyph("photo.on.rectangle")
                Spacer(minLength: 2)
                Glyph("square.and.arrow.up"); Glyph("magnifyingglass")
            }
            .foregroundStyle(Color.black.opacity(0.55))
            .padding(.horizontal, 6).frame(height: TapeDemoChrome.toolbar)
            Text("November 8, 2026 at 9:12 AM").font(.system(size: 11)).foregroundStyle(Color.black.opacity(0.4))
                .frame(maxWidth: .infinity).padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 9) {
                Text("Weekend").font(.system(size: 24, weight: .bold)).padding(.bottom, 2)
                ForEach(Array(["Drive up Friday after lunch", "Swim at the second lake", "Cabin keys from the office", "Pack the night before", "Charge the camera"].enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: index < 2 ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(index < 2 ? Self.check : Color.black.opacity(0.3))
                        Text(item).foregroundStyle(Color.black.opacity(index < 2 ? 0.4 : 0.85)).lineLimit(2)
                    }
                }
                Text("Cabin").font(.system(size: 17, weight: .bold)).padding(.top, 8)
                Text("The one past the boat launch, green door. Keys are at the office until six; after that they leave them in the lockbox by the woodpile.")
                Text("Bring").font(.system(size: 17, weight: .bold)).padding(.top, 8)
                ForEach(["Swimsuits and the big towels", "Headlamps", "Film camera, two rolls"], id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); Text(item) }
                }
            }
            .font(.system(size: 14)).lineSpacing(3)
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Music: the sidebar (Search, Home, New, Radio, the Library and playlists), the playback bar with
/// the playing song, and Recently Added with the demo songs' albums.
private struct TapeDemoMusic: View {
    private static let red = Color(red: 0.98, green: 0.16, blue: 0.27)
    private static let keys = ["generationals", "phantogram", "suki-waterhouse", "fog-lake", "modern-english"]
    private static var covers: [String: NSImage] = [:]
    private static func cover(_ track: WebsiteDemoProfile.Track?) -> NSImage? {
        guard let track else { return nil }
        if let cover = covers[track.cover] { return cover }
        let cover = NSImage(contentsOfFile: track.cover)
        covers[track.cover] = cover
        return cover
    }
    private static var playing: WebsiteDemoProfile.Track? { WebsiteDemoProfile.track(WebsiteDemoTape.musicSong) }
    private static let library: [(String, [(String, String)])] = [
        ("", [("house.fill", "Home"), ("square.grid.2x2.fill", "New"), ("dot.radiowaves.left.and.right", "Radio")]),
        ("Library", [("clock.fill", "Recently Added"), ("music.mic", "Artists"), ("square.stack.fill", "Albums"), ("music.note", "Songs")]),
        ("Playlists", [("square.grid.3x3.fill", "All Playlists"), ("music.note.list", "Euphoric"), ("music.note.list", "Road Trip"), ("music.note.list", "Late Night")]),
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(TapeDemoChrome.hairline).frame(width: 1)
            VStack(spacing: 0) {
                playback
                Rectangle().fill(TapeDemoChrome.hairline).frame(height: 1)
                recent
            }
        }
        .foregroundStyle(Color.black.opacity(0.86))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: TapeDemoChrome.toolbar)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12))
                Text("Search").font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(Color.black.opacity(0.45))
            .padding(.horizontal, 8).frame(height: 28)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(.horizontal, 10).padding(.bottom, 8)
            ForEach(Array(Self.library.enumerated()), id: \.offset) { _, section in
                if !section.0.isEmpty {
                    Text(section.0).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.black.opacity(0.4))
                        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 4)
                }
                ForEach(Array(section.1.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        Image(systemName: row.0).font(.system(size: 13)).foregroundStyle(Self.red).frame(width: 20)
                        Text(row.1).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).frame(height: 28)
                    .background(row.1 == "Recently Added" ? Color.black.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.horizontal, 10)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 196).frame(maxHeight: .infinity, alignment: .top)
        .background(Color(white: 0.95))
    }

    private var playback: some View {
        HStack(spacing: 4) {
            Glyph("shuffle", size: 12).opacity(0.5)
            Glyph("backward.fill", size: 14)
            Glyph("pause.fill", size: 19)
            Glyph("forward.fill", size: 14)
            Glyph("repeat", size: 12).opacity(0.5)
            HStack(spacing: 9) {
                artwork(Self.playing).frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(spacing: 1) {
                    Text(Self.playing?.title ?? "Put a Light On").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text([Self.playing?.artist ?? "Generationals", Self.playing?.album ?? "Heza"].joined(separator: " — "))
                        .font(.system(size: 11)).foregroundStyle(Color.black.opacity(0.5)).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 5).frame(height: 40)
            .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Rectangle().fill(Color.black.opacity(0.45)).frame(width: 84, height: 2).padding(.leading, 46)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, 8)
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 12)).opacity(0.5)
            Capsule().fill(Color.black.opacity(0.15)).frame(width: 60, height: 4)
                .overlay(alignment: .leading) { Capsule().fill(Color.black.opacity(0.5)).frame(width: 40, height: 4) }
            Glyph("quote.bubble", size: 13).opacity(0.6)
            Glyph("list.bullet", size: 13).opacity(0.6)
        }
        .foregroundStyle(Color.black.opacity(0.75))
        .padding(.horizontal, 10).frame(height: TapeDemoChrome.toolbar)
    }

    @ViewBuilder private func artwork(_ track: WebsiteDemoProfile.Track?) -> some View {
        if let cover = Self.cover(track) { Image(nsImage: cover).resizable().scaledToFill() }
        else { LinearGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.6), Color(red: 0.35, green: 0.2, blue: 0.45)], startPoint: .top, endPoint: .bottom) }
    }

    private func album(_ key: String) -> some View {
        let track = WebsiteDemoProfile.track(key)
        return VStack(alignment: .leading, spacing: 3) {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay(artwork(track))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                .padding(.bottom, 4)
            Text(track?.album ?? "Album").font(.system(size: 12.5, weight: .medium)).lineLimit(1)
            Text(track?.artist ?? "Artist").font(.system(size: 12)).foregroundStyle(Color.black.opacity(0.5)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Recently Added").font(.system(size: 26, weight: .bold))
            HStack(alignment: .top, spacing: 20) { ForEach(Self.keys.prefix(3), id: \.self) { album($0) } }
            HStack(alignment: .top, spacing: 20) {
                ForEach(Self.keys.dropFirst(3), id: \.self) { album($0) }
                Color.clear.frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26).padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Calendar: its toolbar (Day, Week, Month, Year), the month's name, and the week with an all-day
/// event, today's number in red and the red line at the time the menu bar shows.
private struct TapeDemoCalendar: View {
    private struct Event { let day: Int; let start: Double; let hours: Double; let title: String; let colour: Color }
    private static let events = [
        Event(day: 1, start: 9.5, hours: 0.5, title: "Standup", colour: .blue),
        Event(day: 1, start: 13, hours: 1.5, title: "Design review", colour: .purple),
        Event(day: 2, start: 10, hours: 1, title: "Dentist", colour: .orange),
        Event(day: 2, start: 12, hours: 1, title: "Lunch with Sam", colour: .green),
        Event(day: 3, start: 9.5, hours: 0.5, title: "Standup", colour: .blue),
        Event(day: 3, start: 15, hours: 2, title: "Focus time", colour: .pink),
        Event(day: 4, start: 11, hours: 1, title: "Planning", colour: .purple),
        Event(day: 4, start: 17, hours: 1.5, title: "Climbing", colour: .green),
        Event(day: 5, start: 9.5, hours: 0.5, title: "Standup", colour: .blue),
        Event(day: 5, start: 13, hours: 3, title: "Drive north", colour: .orange),
    ]
    private static let days = ["Sun 8", "Mon 9", "Tue 10", "Wed 11", "Thu 12", "Fri 13", "Sat 14"]
    private static let first = 8.0, last = 19.0, now = 9.0 + 41.0 / 60
    private static let red = Color(red: 1, green: 0.23, blue: 0.19)
    private static let gutter: CGFloat = 52, header: CGFloat = 30, allDay: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Rectangle().fill(TapeDemoChrome.hairline).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("November").font(.system(size: 26, weight: .bold))
                Text("2026").font(.system(size: 26, weight: .light))
                Spacer()
                HStack(spacing: 0) {
                    Glyph("chevron.left", size: 12)
                    Text("Today").font(.system(size: 12.5, weight: .medium)).padding(.horizontal, 10).frame(height: 24)
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Glyph("chevron.right", size: 12)
                }
                .foregroundStyle(Color.black.opacity(0.65))
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 6)
            week
        }
        .foregroundStyle(Color.black.opacity(0.86))
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: TapeDemoChrome.lights, height: 1)
            Glyph("calendar")
            Glyph("plus")
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                ForEach(["Day", "Week", "Month", "Year"], id: \.self) { mode in
                    Text(mode).font(.system(size: 12.5, weight: .medium)).padding(.horizontal, 12).frame(height: 24)
                        .background(mode == "Week" ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(mode == "Week" ? 0.12 : 0), radius: 1, y: 0.5)
                }
            }
            .padding(2).background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 12))
                Text("Search").font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.black.opacity(0.4))
            .padding(.horizontal, 8).frame(width: 150, height: 28)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .foregroundStyle(Color.black.opacity(0.6))
        .padding(.horizontal, 8).frame(height: TapeDemoChrome.toolbar)
        .background(Color(white: 0.965))
    }

    private func hourLabel(_ hour: Double) -> String {
        hour == 12 ? "Noon" : "\(Int(hour) > 12 ? Int(hour) - 12 : Int(hour)) \(hour > 12 ? "PM" : "AM")"
    }

    private var week: some View {
        GeometryReader { proxy in
            let top = Self.header + Self.allDay
            let hourHeight = (proxy.size.height - top - 8) / CGFloat(Self.last - Self.first)
            let column = (proxy.size.width - Self.gutter) / 7
            let y = { (hour: Double) in top + CGFloat(hour - Self.first) * hourHeight }
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.days.enumerated()), id: \.offset) { index, day in
                    let parts = day.split(separator: " ")
                    HStack(spacing: 5) {
                        Text(String(parts[0])).foregroundStyle(Color.black.opacity(0.5))
                        Text(String(parts[1])).fontWeight(.semibold).foregroundStyle(index == 0 ? Color.white : Color.black.opacity(0.8))
                            .frame(minWidth: 22, minHeight: 22).background(index == 0 ? Self.red : .clear, in: Circle())
                    }
                    .font(.system(size: 12.5))
                    .position(x: Self.gutter + column * (CGFloat(index) + 0.5), y: Self.header / 2)
                    Rectangle().fill(Color.black.opacity(0.07)).frame(width: 1, height: proxy.size.height - Self.header)
                        .position(x: Self.gutter + column * CGFloat(index), y: Self.header + (proxy.size.height - Self.header) / 2)
                }
                Text("all-day").font(.system(size: 10)).foregroundStyle(Color.black.opacity(0.45))
                    .position(x: Self.gutter / 2, y: Self.header + Self.allDay / 2)
                Text("Lake weekend").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.green.opacity(0.95))
                    .padding(.horizontal, 7).frame(width: column * 2 - 6, height: Self.allDay - 6, alignment: .leading)
                    .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .position(x: Self.gutter + column * 6, y: Self.header + Self.allDay / 2)
                Rectangle().fill(Color.black.opacity(0.12)).frame(width: proxy.size.width, height: 1).position(x: proxy.size.width / 2, y: top)
                ForEach(Array(stride(from: Self.first + 1, to: Self.last, by: 1)), id: \.self) { hour in
                    Text(hourLabel(hour)).font(.system(size: 10)).foregroundStyle(Color.black.opacity(0.45))
                        .frame(width: Self.gutter - 8, alignment: .trailing)
                        .position(x: (Self.gutter - 8) / 2, y: y(hour))
                        .opacity(abs(hour - Self.now) < 0.5 ? 0 : 1)
                    Rectangle().fill(Color.black.opacity(0.07)).frame(width: proxy.size.width - Self.gutter, height: 1)
                        .position(x: Self.gutter + (proxy.size.width - Self.gutter) / 2, y: y(hour))
                }
                ForEach(Array(Self.events.enumerated()), id: \.offset) { _, event in
                    let height = CGFloat(event.hours) * hourHeight - 3
                    Text(event.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(event.colour.opacity(0.95))
                        .padding(.horizontal, 7).padding(.top, 4)
                        .frame(width: column - 6, height: height, alignment: .topLeading)
                        .background(event.colour.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(alignment: .leading) { Rectangle().fill(event.colour).frame(width: 3) }
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .position(x: Self.gutter + column * (CGFloat(event.day) + 0.5), y: y(event.start) + height / 2 + 1)
                }
                // The time the menu bar shows, on today's column.
                Text("9:41 AM").font(.system(size: 10, weight: .semibold)).foregroundStyle(Self.red)
                    .frame(width: Self.gutter - 8, alignment: .trailing).position(x: (Self.gutter - 8) / 2, y: y(Self.now))
                Rectangle().fill(Self.red).frame(width: column, height: 1.5).position(x: Self.gutter + column / 2, y: y(Self.now))
                Circle().fill(Self.red).frame(width: 8, height: 8).position(x: Self.gutter, y: y(Self.now))
            }
        }
        .clipped()
    }
}
#endif
