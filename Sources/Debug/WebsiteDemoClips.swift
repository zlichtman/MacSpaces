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
        // Site (2.78): a bare desktop (wallpaper and camera only) to frame outside recordings.
        if only?.contains("wallpaper-lava") == true {
            let host = NSHostingView(rootView: ZStack(alignment: .top) {
                DemoWallpaper(colors: ["#F6DCD2", "#E59A82", "#B64A32", "#521A12"].map { Color(themeHex: $0) ?? .gray })
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(.black).frame(width: 185, height: 32)
            }.frame(width: stage.width, height: stage.height))
            host.frame = NSRect(origin: .zero, size: stage)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("wallpaper-lava.png"))
            }
        }

        // Site (2.78): one Home per theme, each with its own layout and song, and a
        // running countdown. Short loops so the theme's effect moves.
        let siteLooks: [(String, Pairing, [(NookWidgetKind, NookWidgetSize)])] = [
            ("theme-everforest", Pairing(family: .everforest, wallpaper: ["#E4ECD6", "#AFC398", "#6F8C63", "#3E5439"], cover: "almostfantasy",
                                         title: "Almost Fantasy", artist: "Fog Lake", album: "Almost Fantasy", duration: 132),
             [(.media, .large), (.timer, .small), (.weather, .small), (.clock, .small), (.todos, .small)]),
            ("theme-rainbow", Pairing(family: .rainbow, wallpaper: ["#3B3550", "#2C2740", "#1F1B30", "#141220"], cover: "currents",
                                      title: "The Less I Know the Better", artist: "Tame Impala", album: "Currents", duration: 216),
             [(.media, .large), (.clock, .small), (.systemStats, .small), (.timer, .small)]),
            ("theme-synthwave", Pairing(family: .synthwave, wallpaper: ["#F4DCEF", "#D99DCC", "#9C5198", "#3D1F4D"], cover: "strfkr",
                                        title: "Dear Stranger", artist: "STRFKR", album: "Future Past Life", duration: 271),
             [(.media, .medium), (.calendar, .medium), (.timer, .small), (.weather, .small)]),
            ("theme-monsoon", Pairing(family: .monsoon, wallpaper: ["#E3EEF3", "#A9C8D6", "#5F8FA6", "#22404F"], cover: "midnight",
                                      title: "I Melt With You - Rerecorded", artist: "Modern English", album: "Pillow Lips", duration: 236),
             [(.media, .large), (.weather, .medium), (.timer, .small)]),
        ]
        WebsiteDemo234.previewWeather()
        services.timerService.setPreview(remaining: 18 * 60 + 19, total: 25 * 60)
        for (name, look, widgets) in siteLooks {
            home(widgets)
            clip(name, length: 4.0, output: output, tab: .nook, setup: { clock, _, _ in
                play(look); clock.wallpaper = look.wallpaper
                services.timerService.setPreview(remaining: 18 * 60 + 19, total: 25 * 60)
            }, beats: [])
        }

        // Site (2.78): each tool page in its own theme, as stills (the last frame of a short clip).
        services.messages.setInboxPreview([
            .init(id: "iMessage;-;+15550100", groupName: "", handle: "Sam Rivera", lastText: "Running 10 minutes late, save me a seat?", lastFromMe: false, lastDate: Date().addingTimeInterval(-120)),
            .init(id: "iMessage;+;chat1", groupName: "Climbing crew", handle: "", lastText: "Saturday at 9?", lastFromMe: true, lastDate: Date().addingTimeInterval(-3600)),
            .init(id: "iMessage;-;+15550101", groupName: "", handle: "Jo Park", lastText: "Sent the photos", lastFromMe: false, lastDate: Date().addingTimeInterval(-90_000)),
            .init(id: "iMessage;-;+15550102", groupName: "", handle: "Alex Kim", lastText: "Loved the playlist", lastFromMe: false, lastDate: Date().addingTimeInterval(-180_000)),
        ], thread: [
            .init(id: 1, fromMe: false, text: "Are we still on for dinner?", date: Date().addingTimeInterval(-900), sender: "Sam Rivera"),
            .init(id: 2, fromMe: true, text: "Yes! 7:30 at the usual place", date: Date().addingTimeInterval(-800), sender: "", reactions: ["❤️"]),
            .init(id: 3, fromMe: false, text: "Running 10 minutes late, save me a seat?", date: Date().addingTimeInterval(-120), sender: "Sam Rivera", reactions: ["👍"]),
            .init(id: 4, fromMe: true, text: "No rush, I'll order the dumplings", date: Date().addingTimeInterval(-60), sender: ""),
        ])
        CodingStats.shared.preview()
        AgentActivityMonitor.shared.preview()
        for text in ["Weekend plans\nCoffee, a long walk by the lake, and a new playlist for the drive.",
                     "Launch checklist\nNotarize, tag, update the tap, refresh the site.",
                     "Gift ideas\nFilm camera strap, a good notebook, concert tickets."] {
            if let id = services.notes.create() { services.notes.save(id, text: text) }
        }
        AppServices.shared.extraTimers[0].setPreview(remaining: 4 * 60 + 12, total: 5 * 60)
        AppServices.shared.extraTimers[1].setPreview(remaining: 52 * 60 + 3, total: 60 * 60)
        services.shortcuts.setPreview(["Start my workday", "Log water", "Text Sam I'm on my way", "Resize for web",
                                       "Morning playlist", "Focus for an hour", "Add to grocery list", "Make a GIF",
                                       "Turn on the lights", "Translate clipboard", "Meeting notes", "Good night"])
        let trayFolder = files.appendingPathComponent("Tray", isDirectory: true)
        try? FileManager.default.createDirectory(at: trayFolder, withIntermediateDirectories: true)
        var trayFiles: [URL] = []
        for (name, text) in [("Launch plan.md", "# Launch plan\n\n" + (1...14).map { "- Step \($0): notarize, tag, update the tap" }.joined(separator: "\n")),
                             ("Budget.csv", "Item,Cost\n" + (1...14).map { "Line \($0),\($0 * 120)" }.joined(separator: "\n")),
                             ("Interview notes.txt", (1...16).map { "Question \($0): what would make the first week easier?" }.joined(separator: "\n\n"))] {
            let url = trayFolder.appendingPathComponent(name)
            try? text.write(to: url, atomically: true, encoding: .utf8)
            trayFiles.append(url)
        }
        let coverDraft = trayFolder.appendingPathComponent("Cover draft.png")
        if let cover = NSImage(contentsOfFile: "\(covers)/everforest.jpg"), let tiff = cover.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: coverDraft); trayFiles.insert(coverDraft, at: 0)
        }
        let pages: [(String, ThemeFamily, [String], NotchTab, String?)] = [
            ("page-home", .everforest, ["#E4ECD6", "#AFC398", "#6F8C63", "#3E5439"], .nook, nil),
            ("page-calendar", .kemosabe, ["#E7DCEB", "#B39CC6", "#7C629A", "#42325A"], .calendar, nil),
            ("page-timers", .lava, ["#F6DCD2", "#E59A82", "#B64A32", "#521A12"], .timers, nil),
            ("page-notes", .citrine, ["#F3E9CF", "#D9C08A", "#A8843F", "#4E3B17"], .notes, nil),
            ("page-prompter", .catppuccin, ["#E6E1F2", "#B9AEDB", "#7D6FB0", "#3B335C"], .prompter, nil),
            ("page-coding", .monsoon, ["#E3EEF3", "#A9C8D6", "#5F8FA6", "#22404F"], .terminal, "agents"),
            ("page-usage", .synthwave, ["#F4DCEF", "#D99DCC", "#9C5198", "#3D1F4D"], .terminal, "usage"),
            ("page-messages", .macspaces, ["#DDE6F3", "#A6BBD8", "#6C87AE", "#344B70"], .messages, nil),
            ("page-shortcuts", .tokyoNight, ["#DCE0F2", "#A3AEDB", "#5F6DAA", "#232A4D"], .shortcuts, nil),
            ("page-tray", .everforest, ["#E4ECD6", "#AFC398", "#6F8C63", "#3E5439"], .tray, nil),
            ("page-music", .lava, ["#F6DCD2", "#E59A82", "#B64A32", "#521A12"], .music, nil),
        ]
        home([(.media, .large), (.timer, .small), (.weather, .small), (.clock, .small), (.todos, .small)])
        for (name, family, wallpaper, tab, terminalTab) in pages {
            if let terminalTab { UserDefaults.standard.set(terminalTab, forKey: "terminal.tab") }
            clip(name, length: tab == .tray ? 2.5 : 0.5, output: output, tab: tab, setup: { clock, _, shelf in
                play(siteLooks[0].1); theme.selectFamily(family); clock.wallpaper = wallpaper
                services.timerService.setPreview(remaining: 18 * 60 + 19, total: 25 * 60)
                if tab == .tray { shelf.setPreviewItems(trayFiles, selectedIndex: 0) }
            }, beats: [])
        }

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
