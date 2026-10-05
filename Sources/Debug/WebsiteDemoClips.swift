#if DEBUG
import SwiftUI
import AppKit

/// Short website clips, one tool each, framed tightly on the open Nook:
/// Music Player (songs skipping, each on its theme), Themes (live themes, each with a song), Tray (a file dropped in), Terminal (a
/// command) and Timers (a countdown starting). No lyrics are shown. Frames render natively at 60 fps
/// in slow motion, as in the main demo. Content is synthetic apart from the
/// track names and covers (from MACSPACES_DEMO_COVERS); no lyrics are shown.
@MainActor
enum WebsiteDemoClips {
    static let stage = CGSize(width: 820, height: 470)

    final class Clock: ObservableObject {
        @Published var t: Double = 0
        @Published var wallpaper = ["#DDE6F3", "#A6BBD8", "#6C87AE", "#344B70"]
        @Published var drag: (from: CGPoint, to: CGPoint, start: Double, end: Double)?
    }

    struct Pairing { let family: ThemeFamily; let wallpaper: [String]; let cover: String
                     let title: String; let artist: String; let album: String; let duration: Double }
    static let pairings: [Pairing] = [
        Pairing(family: .kemosabe, wallpaper: ["#E7DCEB", "#B39CC6", "#7C629A", "#42325A"], cover: "kemosabe",
                title: "Maps - Live at the Royal Albert Hall", artist: "Yeah Yeah Yeahs",
                album: "Hidden in Pieces: Live at the Royal Albert Hall", duration: 393),
        Pairing(family: .everforest, wallpaper: ["#E4ECD6", "#AFC398", "#6F8C63", "#3E5439"], cover: "everforest",
                title: "Catacombs", artist: "Fog Lake", album: "Tragedy Reel", duration: 201),
        Pairing(family: .macspaces, wallpaper: ["#DDE6F3", "#A6BBD8", "#6C87AE", "#344B70"], cover: "midnight",
                title: "I Melt With You - Rerecorded", artist: "Modern English", album: "Pillow Lips", duration: 236),
    ]

    static func run(output: URL) {
        let settings = NookSettings.shared
        let services = AppServices.shared
        let theme = ThemeStore.shared
        let covers = ProcessInfo.processInfo.environment["MACSPACES_DEMO_COVERS"] ?? "/private/tmp/macspaces-covers"
        settings.showTeleprompterBar = false
        settings.showTimerLiveActivity = false
        settings.showPowerLiveActivity = false
        settings.dockApps = [.music, .calendar, .terminal, .timers, .weather, .tray]
        services.calendar.setAppPreview()
        services.systemStats.setPreview()
        services.teleprompter.setPreview(current: "", upcoming: "", source: .lyrics)
        theme.animatesEffects = true
        theme.appearanceMode = .dark

        func play(_ pairing: Pairing) {
            theme.selectFamily(pairing.family)
            var info = NowPlayingInfo()
            info.title = pairing.title; info.artist = pairing.artist; info.album = pairing.album
            info.sourceName = "Music"; info.isPlaying = true; info.elapsed = 74; info.duration = pairing.duration
            info.capabilities = [.playPause, .previous, .next, .seek]
            info.artwork = NSImage(contentsOfFile: "\(covers)/\(pairing.cover).jpg")
            services.nowPlaying.setPreviewInfo(info)
        }
        func home(_ widgets: [(NookWidgetKind, NookWidgetSize)]) {
            let profile = NookProfile(id: UUID(), name: "Home", widgets: widgets.map(\.0))
            settings.profiles = [profile]; settings.activeProfileID = profile.id
            for (kind, size) in widgets { settings.setSize(size, for: kind) }
        }

        let files = output.appendingPathComponent("clip-files", isDirectory: true)
        try? FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let itinerary = files.appendingPathComponent("Trip itinerary.md")
        try? "# Trip itinerary\nFriday: drive up, dinner by the lake.\n".write(to: itinerary, atomically: true, encoding: .utf8)

        // MACSPACES_DEMO_CLIPS limits which clips render (comma-separated), e.g. "music".
        // Music Player: the song skips forward, each with its matching theme and wallpaper.
        home([(.media, .large), (.clock, .small), (.timer, .small)])
        clip("player", length: 6.0, output: output, tab: .nook, setup: { clock, _, _ in
            play(pairings[2]); clock.wallpaper = pairings[2].wallpaper
        }, beats: [
            (2.0, { clock, _, _ in play(pairings[0]); clock.wallpaper = pairings[0].wallpaper }),
            (4.0, { clock, _, _ in play(pairings[1]); clock.wallpaper = pairings[1].wallpaper }),
        ])


        // Themes: the live themes on the full Home hub, each with a song that suits it.
        let looks: [Pairing] = [
            Pairing(family: .rainbow, wallpaper: ["#3B3550", "#2C2740", "#1F1B30", "#141220"], cover: "strfkr",
                    title: "Dear Stranger", artist: "STRFKR", album: "Future Past Life", duration: 272),
            Pairing(family: .synthwave, wallpaper: ["#F4DCEF", "#D99DCC", "#9C5198", "#3D1F4D"], cover: "classactress",
                    title: "Careful What You Say", artist: "Class Actress", album: "Journal of Ardency", duration: 312),
            Pairing(family: .lava, wallpaper: ["#F6DCD2", "#E59A82", "#B64A32", "#521A12"], cover: "orville",
                    title: "Dead of Night", artist: "Orville Peck", album: "Pony", duration: 239),
            Pairing(family: .monsoon, wallpaper: ["#E3EEF3", "#A9C8D6", "#5F8FA6", "#22404F"], cover: "jbrekkie",
                    title: "Everybody Wants to Love You", artist: "Japanese Breakfast", album: "Psychopomp", duration: 133),
        ]
        home([(.media, .large), (.timer, .small), (.clock, .small), (.weather, .small), (.systemStats, .small)])
        WebsiteDemo234.previewWeather()
        clip("themes", length: 8.8, output: output, tab: .nook, setup: { clock, _, _ in
            play(looks[0]); clock.wallpaper = looks[0].wallpaper
        }, beats: (1..<looks.count).map { index in
            (Double(index) * 2.2, { clock, _, _ in play(looks[index]); clock.wallpaper = looks[index].wallpaper })
        })
        home([(.media, .large), (.clock, .small), (.timer, .small)])

        // Tray: a file dragged in from the desktop lands in the Tray.
        play(pairings[2])
        clip("tray", length: 4.2, output: output, tab: .tray, setup: { clock, _, _ in
            clock.wallpaper = pairings[2].wallpaper
            clock.drag = (CGPoint(x: stage.width * 0.86, y: stage.height * 0.9), CGPoint(x: stage.width / 2, y: 170), 0.5, 2.0)
        }, beats: [
            (2.1, { clock, _, shelf in clock.drag = nil; shelf.setPreviewItems([itinerary], selectedIndex: 0) }),
        ])

        // Terminal: a quick command. A plain prompt (no user or Mac name) is set first.
        theme.selectFamily(.everforest)
        let shell = services.quickShell
        if only?.contains("terminal") ?? true { shell.start() }
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        shell.view.send(txt: "PS1='%1~ %% '; clear\r")
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        // The command is typed out and its output shown on the terminal itself
        // (scripted, so nothing on this Mac is upgraded).
        let command = Array("brew upgrade")
        let upgrade = [
            "\u{1B}[34;1m==>\u{1B}[0m \u{1B}[1mUpgrading 3 outdated packages:\u{1B}[0m",
            "node 24.9.0 -> 24.10.0", "ffmpeg 8.0 -> 8.0.1", "gh 2.81.0 -> 2.82.1",
            "\u{1B}[34;1m==>\u{1B}[0m \u{1B}[1mPouring node--24.10.0.arm64_tahoe.bottle.tar.gz\u{1B}[0m",
            "🍺  /opt/homebrew/Cellar/node/24.10.0: 2,451 files, 78.9MB",
            "\u{1B}[34;1m==>\u{1B}[0m \u{1B}[1mPouring ffmpeg--8.0.1.arm64_tahoe.bottle.tar.gz\u{1B}[0m",
            "🍺  /opt/homebrew/Cellar/ffmpeg/8.0.1: 285 files, 52.1MB",
            "\u{1B}[34;1m==>\u{1B}[0m \u{1B}[1mPouring gh--2.82.1.arm64_tahoe.bottle.tar.gz\u{1B}[0m",
            "🍺  /opt/homebrew/Cellar/gh/2.82.1: 215 files, 34.6MB",
        ]
        var beats: [Beat] = command.enumerated().map { index, character in
            (0.6 + Double(index) * 0.07, { _, _, _ in shell.view.feed(text: String(character)) })
        }
        beats.append((1.6, { _, _, _ in shell.view.feed(text: "\r\n") }))
        for (index, line) in upgrade.enumerated() {
            beats.append((2.0 + Double(index) * 0.32, { _, _, _ in shell.view.feed(text: line + "\r\n") }))
        }
        beats.append((2.0 + Double(upgrade.count) * 0.32 + 0.2, { _, _, _ in shell.view.feed(text: "~ % ") }))
        clip("terminal", length: 6.4, output: output, tab: .terminal, setup: { clock, _, _ in
            clock.wallpaper = pairings[1].wallpaper
        }, beats: beats)
        shell.stop()

        // Timers: a five-minute countdown starts.
        theme.selectFamily(.kemosabe)
        clip("timers", length: 3.6, output: output, tab: .timers, setup: { clock, _, _ in
            clock.wallpaper = pairings[0].wallpaper
        }, beats: [
            (0.8, { _, model, _ in model.timerService.start(minutes: 5) }),
        ])
        services.timerService.cancel()
        print("Clips rendered in \(output.path)")
    }

    private typealias Beat = (Double, (Clock, NotchViewModel, ShelfStore) -> Void)

    /// Renders one clip with the Nook already open on `tab`.
    private static var only: Set<String>? {
        ProcessInfo.processInfo.environment["MACSPACES_DEMO_CLIPS"].map { Set($0.split(separator: ",").map(String.init)) }
    }

    private static func clip(_ name: String, length: Double, output: URL, tab: NotchTab,
                             setup: (Clock, NotchViewModel, ShelfStore) -> Void, beats: [Beat]) {
        guard only?.contains(name) ?? true else { return }
        let services = AppServices.shared
        let frames = output.appendingPathComponent("clip-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: frames)
        try! FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let shelf = ShelfStore(basketID: UUID())
        let model = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true),
            availableWidth: 1512, settings: NookSettings.shared, shelf: shelf, nowPlaying: services.nowPlaying,
            powerMonitor: services.powerMonitor, timerService: services.timerService, bluetoothMonitor: services.bluetooth,
            systemActivityMonitor: services.systemActivity, teleprompter: services.teleprompter)
        model.selectedTab = tab
        model.state = .expanded
        let clock = Clock()
        setup(clock, model, shelf)
        let host = NSHostingView(rootView: ClipStage(model: model, clock: clock).environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: stage)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        // Let the open Nook settle before the first frame.
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))

        let fps = WebsiteDemo234.fps, scale = WebsiteDemo234.timeScale
        let writer = DispatchQueue(label: "clip-frame-writer")
        let group = DispatchGroup()
        Design.demoTimeScale = scale
        defer { Design.demoTimeScale = 1 }
        var next = 0
        let start = Date()
        for n in 0..<Int(length * fps) {
            let t = Double(n) / fps
            clock.t = t
            while next < beats.count, t >= beats[next].0 { beats[next].1(clock, model, shelf); next += 1 }
            RunLoop.main.run(until: start.addingTimeInterval(t * scale))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let url = frames.appendingPathComponent(String(format: "f%05d.png", n))
            group.enter()
            writer.async { try? bitmap.representation(using: .png, properties: [:])?.write(to: url); group.leave() }
        }
        group.wait()
        window.contentView = nil
    }
}

/// The open Nook on a themed desktop, with an optional file being dragged in.
private struct ClipStage: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var clock: WebsiteDemoClips.Clock

    var body: some View {
        let size = WebsiteDemoClips.stage
        ZStack(alignment: .top) {
            DemoWallpaper(colors: clock.wallpaper.map { Color(themeHex: $0) ?? .gray })
                .animation(.easeInOut(duration: 0.6 * WebsiteDemo234.timeScale), value: clock.wallpaper)
            NotchContainerView(viewModel: model)
                .frame(width: size.width, height: size.height, alignment: .top)
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                .fill(.black).frame(width: 185, height: 32)
            if let drag = clock.drag, clock.t >= drag.start - 0.1 {
                let raw = min(max((clock.t - drag.start) / (drag.end - drag.start), 0), 1)
                let eased = raw < 0.5 ? 4 * raw * raw * raw : 1 - pow(-2 * raw + 2, 3) / 2
                DraggedFile()
                    .position(x: drag.from.x + (drag.to.x - drag.from.x) * eased,
                              y: drag.from.y + (drag.to.y - drag.from.y) * eased)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
#endif
