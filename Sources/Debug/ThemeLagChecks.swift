#if DEBUG
import AppKit
import SwiftUI

/// The `theme-lag` scope (report only): what Settings → Appearance costs, in a fresh process.
/// First each drawer opened as a click opens it, on the Appearance page as it first shows in
/// a Settings-sized window: the time to its first frame, the longest main-thread pass and the
/// passes over a frame while it settles, and for the scenes how many photos the first frame
/// had (five rounds, medians). Then scrolling at 60 frames a second (`ScrollDriver`): through the Terminal
/// list and back, and the page with the scenes drawer open down and back, each with the
/// main-thread time per frame (median, 95th percentile, longest), frames over 16.7 ms, frames
/// dropped (timer ticks that came late) and the distance covered. Then the page with every
/// drawer open twice (first layout, when every scene card has its photo, CPU), each drawer
/// alone, and the Terminal drawer's first layout five times, as a median.
/// `theme-lag-legacy` runs the same in a fresh process with 3.39's views
/// (`NookThemePicker.legacyViews`), so one dispatch compares before and after.
/// Writes `theme-lag.txt` (or `theme-lag-legacy.txt`) and two stills.
@MainActor enum ThemeLagChecks {
    private static var report: [String] = []
    private static var name = "theme-lag"
    /// Settings' own window size.
    private static let settingsSize = NSSize(width: 980, height: 680)

    private static func note(_ line: String) {
        print(name + " " + line)
        report.append(line)
    }

    /// Every photo a theme card in a drawer shows.
    private static var assets: [String] { ThemeCollection.live.cardPhotos }

    private static func photosReady() -> Int {
        assets.filter { MotifThumbnails.shared.images[$0] != nil }.count
    }

    static func measure(to directory: URL, legacy: Bool = false) {
        name = legacy ? "theme-lag-legacy" : "theme-lag"
        NookThemePicker.legacyViews = legacy
        ThemeMotifView.legacyStillMask = legacy
        note(legacy ? "3.39's views: the SwiftUI Terminal grid of buttons, scene cards that each observe the theme store, with a still mask, no photo warm-up"
                    : "today's views: the AppKit Terminal table, scene cards observing nothing with no still mask, photos warmed while Appearance shows")
        note("photo cards: \(assets.count)")
        ThemeStore.shared.selectFamily(.everforest)
        SettingsNavigationModel.shared.selection = .appearance
        // As SettingsWindowController.show does before the page appears.
        if !legacy { GhosttyLibrary.shared.load() }

        drawerOpens()
        scrolling()
        allOpen(directory)
        eachDrawerAlone()
        terminalMedian()

        NookThemePicker.initiallyOpen = []
        NookThemePicker.legacyViews = false
        ThemeMotifView.legacyStillMask = false
        try? report.joined(separator: "\n").write(to: directory.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    // MARK: Windows

    private static func window(_ size: NSSize, open: Set<ThemeCollection>) -> (NSWindow, NSHostingView<SettingsView>) {
        NookThemePicker.initiallyOpen = open
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 20, y: 20), size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: SettingsView())
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
        return (window, host)
    }

    private static func close(_ window: NSWindow) {
        window.orderOut(nil)
        window.contentView = nil
    }

    private static func draw(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        CATransaction.flush()
    }

    private static func settle(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        let own: [NSScrollView] = (view as? NSScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap(scrollViews(in:))
    }

    /// The Terminal list's own scroll view: ours by its identifier, 3.39's by its 404 pt frame.
    private static func terminalScroll(in host: NSView) -> NSScrollView? {
        let all = scrollViews(in: host)
        return all.first { $0.identifier == TerminalThemeGrid.scrollIdentifier }
            ?? all.first { abs($0.frame.height - 404) < 1.5 }
    }

    /// The Settings page's scroll view: the largest that isn't the Terminal list.
    private static func pageScroll(in host: NSView) -> NSScrollView? {
        let terminal = terminalScroll(in: host)
        return scrollViews(in: host).filter { $0 !== terminal && $0.frame.width > 400 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private static func contentHeight(_ host: NSView) -> CGFloat {
        pageScroll(in: host)?.documentView?.frame.height ?? 0
    }

    // MARK: Opening each drawer

    /// Each drawer opened as a click would, on the page as it first shows, then closed; five
    /// rounds through the three, as medians (the first round is a fresh process's first open).
    private static func drawerOpens() {
        let (window, host) = window(settingsSize, open: [])
        draw(host)
        // Appearance as people see it before they click: the library and (today) the photos
        // load in the background meanwhile.
        settle(0.8)
        note(String(format: "before opening a drawer: library %@, %d of %d photos decoded",
                    GhosttyLibrary.shared.themes.isEmpty ? "not loaded" : "loaded", photosReady(), assets.count))
        var opens: [ThemeCollection: [Double]] = [:]
        var longest: [ThemeCollection: Double] = [:]
        var slowFrames: [ThemeCollection: Int] = [:]
        for round in 0..<5 {
            for collection in ThemeCollection.allCases {
                let baseline = contentHeight(host)
                let recorder = MainThreadPasses()
                recorder.start()
                let start = CFAbsoluteTimeGetCurrent()
                NotificationCenter.default.post(name: NookThemePicker.qaToggle, object: collection)
                var shownAt = 2000.0
                while CFAbsoluteTimeGetCurrent() - start < 2 {
                    draw(host)
                    if contentHeight(host) > baseline + 40 { shownAt = (CFAbsoluteTimeGetCurrent() - start) * 1000; break }
                    RunLoop.main.run(until: Date().addingTimeInterval(0.001))
                }
                let photosAtFirstFrame = photosReady()
                settle(0.5)
                let passes = recorder.stop()
                opens[collection, default: []].append(shownAt)
                longest[collection] = max(longest[collection] ?? 0, passes.max() ?? 0)
                slowFrames[collection, default: 0] += passes.filter { $0 > 16.7 }.count
                if round == 0 {
                    var line = String(format: "first open of %@: first frame after %.0f ms", collection.title, shownAt)
                    if collection == .live { line += String(format: ", %d of %d photos in it", photosAtFirstFrame, assets.count) }
                    note(line)
                }
                NotificationCenter.default.post(name: NookThemePicker.qaToggle, object: collection)
                draw(host)
                settle(0.3)
            }
        }
        for collection in ThemeCollection.allCases {
            let times = opens[collection] ?? []
            note(String(format: "open %@: first frame median %.0f ms (%@); afterwards the longest main-thread pass %.0f ms, %d passes over a frame in all",
                        collection.title, times.sorted()[times.count / 2], times.map { String(format: "%.0f", $0) }.joined(separator: ", "),
                        longest[collection] ?? 0, slowFrames[collection] ?? 0))
        }
        close(window)
    }

    // MARK: Scrolling

    private static func scrolling() {
        // The Terminal list, with the page scrolled so all of it is on screen.
        do {
            let (window, host) = window(settingsSize, open: [.terminal])
            draw(host)
            settle(0.8)
            if let page = pageScroll(in: host), let list = terminalScroll(in: host) {
                let frame = list.convert(list.bounds, to: page.documentView)
                page.contentView.scroll(to: NSPoint(x: 0, y: max(0, frame.minY - 120)))
                page.reflectScrolledClipView(page.contentView)
                draw(host)
                settle(0.3)
                note(String(format: "Terminal list scroll: %.0f pt of rows in a %.0f pt frame", list.documentView?.frame.height ?? 0, list.frame.height))
                note("Terminal list scroll down, 30 pt a frame: " + ScrollDriver(list, host: host, step: 30, frames: 180).run())
                note("Terminal list scroll back up, 60 pt a frame: " + ScrollDriver(list, host: host, step: -60, frames: 90).run())
            } else {
                note("Terminal list scroll: no scroll view found")
            }
            close(window)
        }
        // The page with the scenes drawer open, once every card has its photo.
        do {
            let (window, host) = window(settingsSize, open: [.live])
            draw(host)
            let start = CFAbsoluteTimeGetCurrent()
            while photosReady() < assets.count, CFAbsoluteTimeGetCurrent() - start < 3 { settle(0.02) }
            settle(0.3)
            if let page = pageScroll(in: host) {
                note(String(format: "MacSpaces drawer page scroll: page %.0f pt tall", page.documentView?.frame.height ?? 0))
                note("MacSpaces drawer page scroll down, 20 pt a frame: " + ScrollDriver(page, host: host, step: 20, frames: 90).run())
                note("MacSpaces drawer page scroll back up, 20 pt a frame: " + ScrollDriver(page, host: host, step: -20, frames: 90).run())
            } else {
                note("MacSpaces drawer page scroll: no scroll view found")
            }
            close(window)
        }
    }

    // MARK: First layouts

    private static func allOpen(_ directory: URL) {
        for visit in ["all open", "all open again"] {
            let recorder = MainThreadPasses()
            let cpuStart = FeatureQAHarness.cpuSeconds()
            let start = CFAbsoluteTimeGetCurrent()
            recorder.start()
            let (window, host) = window(NSSize(width: 1100, height: 1400), open: Set(ThemeCollection.allCases))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            let firstLayout = (CFAbsoluteTimeGetCurrent() - start) * 1000
            var readyAt: Double?
            var shot = false
            while CFAbsoluteTimeGetCurrent() - start < 6 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                if !shot, elapsed > 0.3 {
                    shot = true
                    snapshot(host, to: directory.appendingPathComponent("\(name)-\(visit == "all open" ? "first" : "again")-300ms.png"))
                }
                if readyAt == nil, photosReady() == assets.count { readyAt = elapsed * 1000 }
                if readyAt != nil, elapsed > 2 { break }
            }
            let passes = recorder.stop()
            let cpu = (FeatureQAHarness.cpuSeconds() - cpuStart) * 1000
            let slow = passes.filter { $0 > 16.7 }
            note(String(format: "%@: first layout %.0f ms; every photo card ready after %@; longest main-thread pass %.0f ms; %d passes over a frame (%.0f ms in all); CPU %.0f ms",
                        visit, firstLayout, readyAt.map { String(format: "%.0f ms", $0) } ?? "more than 6 s",
                        passes.max() ?? 0, slow.count, slow.reduce(0, +), cpu))
            close(window)
        }
    }

    /// As people open it: the page with every drawer closed, then each drawer on its own.
    private static func eachDrawerAlone() {
        for (label, open) in [("drawers closed", Set<ThemeCollection>())] + ThemeCollection.allCases.map({ ("\($0.title) alone", Set([$0])) }) {
            let start = CFAbsoluteTimeGetCurrent()
            let (window, host) = window(NSSize(width: 1100, height: 1400), open: open)
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            note(String(format: "%@: first layout %.0f ms", label, (CFAbsoluteTimeGetCurrent() - start) * 1000))
            settle(0.5)
            close(window)
        }
    }

    /// The Terminal drawer's first layout five times after a discarded warm-up, as a median.
    private static func terminalMedian() {
        var timings: [Double] = []
        for _ in 0..<6 {
            let start = CFAbsoluteTimeGetCurrent()
            let (window, host) = window(NSSize(width: 1100, height: 1400), open: [.terminal])
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            timings.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            settle(0.3)
            close(window)
        }
        let kept = Array(timings.dropFirst())
        note(String(format: "Terminal alone: median first layout %.0f ms (%@)", kept.sorted()[kept.count / 2],
                    kept.map { String(format: "%.0f", $0) }.joined(separator: ", ")))
    }

    private static func snapshot(_ host: NSView, to url: URL) {
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Scrolls a scroll view by `step` points a frame, `frames` times, on a 60-a-second timer,
/// moving its clip view as a scroll does, and makes each frame: the scroll, then the
/// window's layout, display and Core Animation commit, all timed as that frame's main-thread
/// work. A tick that comes late counts the frames it missed as dropped. (A synthetic
/// scroll-wheel event sent straight to the view moved nothing, so it isn't used.)
@MainActor final class ScrollDriver: NSObject {
    private let scroll: NSScrollView
    private let host: NSView
    private let step: CGFloat
    private let frames: Int
    private var ticks: [Double] = []
    private var work: [Double] = []
    private static let frame = 1000.0 / 60

    init(_ scroll: NSScrollView, host: NSView, step: CGFloat, frames: Int) {
        self.scroll = scroll
        self.host = host
        self.step = step
        self.frames = frames
    }

    func run() -> String {
        let clip = scroll.contentView
        let startY = clip.bounds.origin.y
        let cpuStart = FeatureQAHarness.cpuSeconds()
        let timer = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        let deadline = CFAbsoluteTimeGetCurrent() + Double(frames) / 60 * 4 + 1
        // One run of the run loop for the whole scroll, so every tick lands inside it.
        while work.count < frames, CFAbsoluteTimeGetCurrent() < deadline {
            _ = CFRunLoopRunInMode(.defaultMode, 0.25, false)
        }
        timer.invalidate()
        let cpu = (FeatureQAHarness.cpuSeconds() - cpuStart) * 1000
        let distance = clip.bounds.origin.y - startY
        guard ticks.count > 1 else { return "no frames ran" }
        var dropped = 0
        for i in 1..<ticks.count {
            dropped += max(0, Int(((ticks[i] - ticks[i - 1]) * 1000 / Self.frame).rounded()) - 1)
        }
        let sorted = work.sorted()
        func percentile(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))] }
        let seconds = ticks.last! - ticks.first!
        return String(format: "%d frames in %.2f s (%.0f a second); main thread per frame median %.1f ms, 95th %.1f ms, longest %.1f ms; %d frames over 16.7 ms; %d frames dropped; moved %.0f pt; CPU %.0f ms",
                      work.count, seconds, Double(work.count - 1) / max(seconds, 0.001), percentile(0.5), percentile(0.95),
                      sorted.last ?? 0, work.filter { $0 > Self.frame }.count, dropped, distance, cpu)
    }

    @objc private func tick() {
        guard work.count < frames else { CFRunLoopStop(CFRunLoopGetMain()); return }
        let start = CFAbsoluteTimeGetCurrent()
        ticks.append(start)
        let clip = scroll.contentView
        var origin = clip.bounds.origin
        origin.y += step
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        scroll.reflectScrolledClipView(clip)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        CATransaction.flush()
        work.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

/// 3.39's scene card, for `theme-lag-legacy`: each card observed the theme store.
struct LegacyLiveThemeCard: View {
    let family: ThemeFamily
    @ObservedObject private var theme = ThemeStore.shared
    var body: some View {
        LiveThemeCard(family: family, selected: theme.family == family, accent: theme.settings.accent)
    }
}

/// 3.39's Terminal list, for `theme-lag-legacy`: a lazy SwiftUI grid of buttons, three to a
/// line, each a pill (one capsule and six circles) and the name.
struct LegacyTerminalPills: View {
    let items: [TerminalThemeItem]
    @ObservedObject private var library = GhosttyLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        let family = theme.family, ghosttyName = theme.ghosttyName, tint = theme.settings.accent
        LazyVGrid(columns: Self.columns, spacing: 2) {
            ForEach(items) { item in
                switch item {
                case .own(let own):
                    LegacyTerminalThemeRow(item: item, selected: family == own, pill: library.pill(own), tint: tint)
                case .ghostty(let ghostty):
                    LegacyTerminalThemeRow(item: item, selected: family == .ghostty && ghosttyName == ghostty.name,
                                           pill: ghostty.pill, tint: tint)
                }
            }
        }
    }
}

struct LegacyTerminalThemeRow: View {
    let item: TerminalThemeItem
    let selected: Bool
    let pill: TerminalPillColours
    let tint: Color
    private static let highlight = RoundedRectangle(cornerRadius: 6, style: .continuous)

    var body: some View {
        Button {
            switch item {
            case .own(let family): ThemeStore.shared.selectFamily(family)
            case .ghostty(let ghostty): ThemeStore.shared.selectGhostty(ghostty)
            }
        } label: {
            HStack(spacing: 8) {
                LegacyTerminalPill(colours: pill)
                Text(item.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                }
            }
            .padding(.horizontal, 6).frame(height: 26)
            .background { if selected { Self.highlight.fill(tint.opacity(0.14)) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LegacyTerminalPill: View {
    let colours: TerminalPillColours
    private static let edge = Color.primary.opacity(0.16)

    var body: some View {
        if colours.isLight {
            dotRow.background(Color(cgColor: colours.background), in: Capsule().inset(by: 0.5)).background(Self.edge, in: Capsule())
        } else {
            dotRow.background(Color(cgColor: colours.background), in: Capsule())
        }
    }

    private var dotRow: some View {
        let dots = colours.dots.map { Color(cgColor: $0) }
        return HStack(spacing: 3) {
            Circle().fill(dots[0]).frame(width: 7, height: 7)
            Circle().fill(dots[1]).frame(width: 6, height: 6)
            Circle().fill(dots[2]).frame(width: 6, height: 6)
            Circle().fill(dots[3]).frame(width: 6, height: 6)
            Circle().fill(dots[4]).frame(width: 6, height: 6)
            Circle().fill(dots[5]).frame(width: 6, height: 6)
        }
        .frame(width: 60, height: 16)
    }
}

/// 3.37's Terminal card, kept only so `theme-lag` and `themes-redesign` can compare it with
/// today's pills: the background as a rounded tile with the accent as one bar and red, green
/// and yellow as three dots, the name below, five to a row.
struct SwatchTerminalCard: View {
    let item: TerminalThemeItem
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var library = GhosttyLibrary.shared
    private static let tile = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        let selected: Bool
        let background: String, accent: String
        let ansi: [String]?
        switch item {
        case .own(let family):
            selected = theme.family == family
            let palette = family.palette(.dark)
            background = palette.background; accent = palette.accent
            ansi = GhosttyThemes.originals[family].flatMap { library.theme(named: $0)?.ansi }
        case .ghostty(let ghostty):
            selected = theme.family == .ghostty && theme.ghosttyName == ghostty.name
            background = ghostty.background; accent = ghostty.accent
            ansi = ghostty.ansi
        }
        return Button {} label: {
            VStack(alignment: .leading, spacing: 6) {
                Self.tile.fill(Color(themeHex: background) ?? .black)
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 4) {
                            Capsule().fill(Color(themeHex: accent) ?? .white).frame(width: 24, height: 6)
                            Spacer(minLength: 0)
                            if let ansi {
                                ForEach(1..<4, id: \.self) { i in
                                    Circle().fill(Color(themeHex: ansi[i]) ?? .clear).frame(width: 6, height: 6)
                                }
                            }
                        }
                        .padding(.horizontal, 10).padding(.bottom, 10)
                    }
                    .frame(height: 56)
                    .overlay(Self.tile.strokeBorder(
                        selected ? theme.settings.accent : Color.primary.opacity(0.10), lineWidth: selected ? 2 : 1))
                HStack(spacing: 4) {
                    Text(item.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.settings.accent) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
