#if DEBUG
import SwiftUI
import AppKit

/// Short website clips, one tool each, framed tightly on the open Nook:
/// Music Player (songs skipping, each on its theme), Themes (live themes, each with a song), Tray (a file dropped in), Terminal (a
/// command) and Timers (a countdown starting). Website Poster captures use only verified short excerpts. Frames render natively at a configured sampling rate
/// in slow motion, as in the main demo. Every clip starts from `WebsiteDemoProfile`; content is
/// synthetic apart from the real songs and covers (`MACSPACES_DEMO_TRACKS`, fetched at run time).
@MainActor
enum WebsiteDemoClips {
    static let stage = CGSize(width: 820, height: 470)
    private static var localWindow: NSWindow?


    final class Clock: ObservableObject {
        @Published var t: Double = 0
        @Published var wallpaperAsset: String?
        /// The desktop: this theme's own scene (`SceneWallpaper`), over the asset and colours.
        @Published var wallpaperFamily: ThemeFamily?
        @Published var wallpaper = ["#DDE6F3", "#A6BBD8", "#6C87AE", "#344B70"]
        @Published var drag: (from: CGPoint, to: CGPoint, start: Double, end: Double)?
    }

    /// A theme with a real song (a key of `MACSPACES_DEMO_TRACKS`), for the clips that move
    /// between songs or themes.
    struct Pairing { let family: ThemeFamily; let song: String }
    static let pairings: [Pairing] = [
        Pairing(family: .synthwave, song: "home"),
        Pairing(family: .everforest, song: "everforest"),
        Pairing(family: .nightBlossom, song: "generationals"),
    ]

    static func run(output: URL) async {
        let local = ProcessInfo.processInfo.environment["MACSPACES_DEMO_LOCAL"] == "1"
        defer {
            if local { localWindow?.orderOut(nil); localWindow?.contentView = nil; localWindow = nil }
        }
        let services = AppServices.shared
        let theme = ThemeStore.shared
        // Everything starts from the shared demo profile (WebsiteDemoProfile): the owner's Home at
        // the widgets' own sizes, the Clear look, the site dock, a running timer, Keep Awake on and
        // a real song. Each clip then sets only its theme and page.
        WebsiteDemoProfile.apply()
        defer { WebsiteDemoProfile.finish() }
        // The agents' own icons on the Agents tab, as on a Mac with Claude and ChatGPT installed.
        let icons = ProcessInfo.processInfo.environment["MACSPACES_DEMO_AGENT_ICONS"] ?? "/private/tmp/macspaces-agent-icons"
        for agent in ["claude", "codex"] {
            if let icon = WebsiteDemoAgents.macIcon("\(icons)/\(agent).png") { AgentActivityMonitor.previewAgentIcons[agent] = icon }
        }
        defer { AgentActivityMonitor.previewAgentIcons = [:] }
        MeetingControls.shared.setPreview(muted: true, cameraOff: false)
        DictationModel.shared.text = "Here’s the updated plan. I’ll share the design after reviewing our meeting notes."

        func play(_ pairing: Pairing) {
            theme.selectFamily(pairing.family)
            play(pairing.song)
        }
        func play(_ name: String) {
            WebsiteDemoProfile.play(WebsiteDemoProfile.track(name) ?? WebsiteDemoProfile.homeTrack)
        }
        let sequence = WebsiteDemoProfile.musicSequence
        let tracks: [String: WebsiteDemoProfile.Track] = Dictionary(uniqueKeysWithValues:
            (sequence.songs.map(\.key) + ["home", "everforest"]).map { key in
                guard let track = WebsiteDemoProfile.track(key) else { fatalError("Missing demo track: \(key)") }
                return (key, track)
            })

        let files = output.appendingPathComponent("clip-files", isDirectory: true)
        try? FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let itinerary = files.appendingPathComponent("Trip itinerary.md")
        try? "# Trip itinerary\nFriday: drive up, dinner by the lake.\n".write(to: itinerary, atomically: true, encoding: .utf8)

        // Website-only reels keep the native stage and dock constant.
        func scene(_ family: ThemeFamily, _ clock: Clock) {
            theme.selectFamily(family)
            theme.reduceMotionPreference = false
            theme.lyricStyle = .classic
            clock.wallpaperFamily = family
            services.teleprompter.setPreview(current: "", upcoming: "", source: .lyrics, playing: true)
        }
        func lyric(_ text: String) {
            withAnimation(Design.spring()) { services.teleprompter.setPreview(current: text, upcoming: "", source: .lyrics, playing: true) }
        }
        // The original reel's songs, themes and excerpts. One approved manifest drives CI and local capture.
        let showcase = sequence.songs.map { (song: $0.key, family: ThemeFamily(rawValue: $0.theme)!) }
        let segment = sequence.segmentSeconds
        var showcaseBeats: [Beat] = [
            (1.2, { _, model, _ in withAnimation(Design.spring()) { model.selectedTab = .music } }),
        ]
        func sing(_ key: String) {
            guard let track = tracks[key], let line = track.lyrics?.first else { return }
            WebsiteDemoProfile.prepareSticker(for: line)
            if let at = track.lyricAt { StickerCapture.shared.spans[line] = max(1.5, (track.lyricEnd ?? at + 3) - at) }
            lyric(line)
        }
        for (index, item) in showcase.enumerated() {
            let start = Double(index) * segment
            if index > 0 {
                showcaseBeats.append((start - 0.35, { _, _, _ in lyric("") }))
                showcaseBeats.append((start, { clock, _, _ in
                    withAnimation(.easeInOut(duration: 0.35 * WebsiteDemo234.timeScale)) { scene(item.family, clock); play(item.song) }
                    theme.lyricStyle = .stickers
                }))
            }
            showcaseBeats.append((start + (index == 0 ? 1.65 : 0.4), { _, _, _ in sing(item.song) }))
        }
        showcaseBeats.sort { $0.0 < $1.0 }
        if only?.contains("music-showcase") ?? true {
            for item in showcase { if let line = tracks[item.song]?.lyrics?.first { WebsiteDemoProfile.prepareSticker(for: line) } }
        }
        await clip("music-showcase", length: Double(showcase.count) * segment, output: output, tab: .nook, setup: { clock, _, _ in
            scene(showcase[0].family, clock); play(showcase[0].song); theme.lyricStyle = .stickers
            StickerCapture.shared.pinnedTime = 0
        }, beats: showcaseBeats)
        StickerCapture.shared.pinnedTime = nil
        // A settled still for every original song, captured independently of the transition timing.
        for (index, item) in showcase.enumerated() {
            let name = String(format: "music-%02d-%@", index + 1, item.song)
            await clip(name, length: 3, output: output, tab: .music, setup: { clock, _, _ in
                scene(item.family, clock); play(item.song); theme.lyricStyle = .stickers
                sing(item.song)
            }, beats: [])
        }
        // The README's first image (owner, 3.2): the Music page in Blossom with a Stickers lyric,
        // over a soft evening desktop; the README uses a settled frame.
        await clip("readme-hero", length: 3, output: output, tab: .music, setup: { clock, _, _ in
            theme.selectFamily(.blossom); theme.reduceMotionPreference = false; theme.lyricStyle = .stickers
            clock.wallpaperAsset = nil; clock.wallpaper = ["#8E9BD3", "#A9A3D2", "#D9AFC0", "#EDB9A0"]
            play("generationals")
            services.teleprompter.setPreview(current: tracks["generationals"]?.lyrics?.first ?? "", upcoming: "", source: .lyrics, playing: true)
        }, beats: [])
        if only?.contains("converter-reel") == true { converterReel(output: output) }

        // MACSPACES_DEMO_CLIPS limits which clips render (comma-separated), e.g. "music".
        // Music Player: the song skips forward, each with its matching theme and wallpaper.
        await clip("player", length: 6.0, output: output, tab: .nook, setup: { clock, _, _ in
            scene(pairings[2].family, clock); play(pairings[2])
        }, beats: [
            (2.0, { clock, _, _ in scene(pairings[0].family, clock); play(pairings[0]) }),
            (4.0, { clock, _, _ in scene(pairings[1].family, clock); play(pairings[1]) }),
        ])


        // Themes: the live themes on Home, with the profile's song.
        let looks: [ThemeFamily] = [.rainbow, .synthwave, .lava, .monsoon]
        await clip("themes", length: 8.8, output: output, tab: .nook, setup: { clock, _, _ in
            scene(looks[0], clock); play("home")
        }, beats: (1..<looks.count).map { index in
            (Double(index) * 2.2, { clock, _, _ in scene(looks[index], clock) })
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

        // One Home per theme, with the profile's song and running countdown. Short loops so the
        // theme's effect moves.
        for family in [ThemeFamily.blossom, .lotus, .aurora, .prism, .synthwave] {
            await clip("theme-\(family.rawValue)", length: 4.0, output: output, tab: .nook, setup: { clock, _, _ in
                scene(family, clock); play("home")
                theme.reduceMotionPreference = family == .aurora || family == .prism
            }, beats: [])
        }

        // Site (2.78): each tool page in its own theme, as stills (the last frame of a short clip).
        CodingStats.shared.preview()
        AgentActivityMonitor.shared.preview()
        for text in ["Weekend plans\nCoffee, a long walk by the lake, and a new playlist for the drive.",
                     "Launch checklist\nNotarize, tag, update the tap, refresh the site.",
                     "Gift ideas\nFilm camera strap, a good notebook, concert tickets."] {
            if let id = services.notes.create() { services.notes.save(id, text: text) }
        }
        // Timers: three running, each its own colour and length, the second paused.
        AppServices.shared.extraTimers[0].setPreview(remaining: 4 * 60 + 12, total: 5 * 60, paused: true)
        AppServices.shared.extraTimers[1].setPreview(remaining: 52 * 60 + 3, total: 60 * 60)
        services.shortcuts.setPreview(["Start my workday", "Log water", "Running late", "Resize for web",
                                       "Morning playlist", "Focus for an hour", "Add to groceries", "Make a GIF",
                                       "Turn on the lights", "Translate text", "Meeting notes", "Good night"])
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
        // A made-up poster (a dusk gradient, a sun and hills), never album art.
        let posterDraft = trayFolder.appendingPathComponent("Poster draft.png")
        let poster = NSImage(size: NSSize(width: 1200, height: 800), flipped: false) { rect in
            NSGradient(colors: [NSColor(srgbRed: 0.99, green: 0.72, blue: 0.62, alpha: 1), NSColor(srgbRed: 0.86, green: 0.46, blue: 0.6, alpha: 1),
                                NSColor(srgbRed: 0.33, green: 0.2, blue: 0.42, alpha: 1)])?.draw(in: rect, angle: -90)
            NSColor(srgbRed: 1, green: 0.9, blue: 0.7, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 760, y: 380, width: 170, height: 170)).fill()
            for (i, shade) in [0.42, 0.3, 0.2].enumerated() {
                NSColor(srgbRed: shade, green: shade * 0.62, blue: shade * 0.9, alpha: 1).setFill()
                let hill = NSBezierPath(); hill.move(to: .zero)
                for x in stride(from: 0, through: 1200, by: 30) {
                    hill.line(to: NSPoint(x: CGFloat(x), y: 250 - CGFloat(i) * 70 + 50 * sin(CGFloat(x) / 170 + CGFloat(i) * 1.9)))
                }
                hill.line(to: NSPoint(x: 1200, y: 0)); hill.close(); hill.fill()
            }
            return true
        }
        if let tiff = poster.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: posterDraft); trayFiles.insert(posterDraft, at: 0)
        }
        // Every page on an offered theme, over that theme's own scene (owner).
        let pages: [(String, ThemeFamily, NotchTab, String?)] = [
            ("page-meetings", .lotus, .meetings, nil),
            ("page-dictation", .lavender, .dictation, nil),
            ("page-clock", .moonrise, .clock, nil),
            ("page-system", .alpine, .system, nil),
            ("page-life", .dune, .calendar, nil),
            ("page-weather", .rainCanopy, .weather, nil),
            // Home (owner): the profile's Home in Snow with I Melt With You.
            ("page-home", WebsiteDemoProfile.homeTheme, .nook, nil),
            ("page-calendar", .autumn, .calendar, nil),
            ("page-timers", .obsidianCoast, .timers, nil),
            ("page-notes", .fern, .notes, nil),
            ("page-prompter", .aurora, .prompter, nil),
            ("page-coding", .thunderstorm, .terminal, "agents"),
            ("page-usage", .lava, .terminal, "usage"),
            ("page-shortcuts", .synthwave, .shortcuts, nil),
            // Blossom, like the clipboard and File Converter captures beside it.
            ("page-tray", .blossom, .tray, nil),
            // Music: Put a Light On in Blossom, its real line in Scenes, so the star plays.
            ("page-music", .blossom, .music, nil),
        ]
        // Agents: the synthetic sessions with prompts short enough to show whole.
        var sessions = AgentActivityMonitor.shared.sessions
        for index in sessions.indices {
            if sessions[index].prompt == "Make the status bar show every running job" { sessions[index].prompt = "Show every running job" }
            if sessions[index].reply != nil { sessions[index].reply = "Updated the client to v3. All 48 tests pass."; sessions[index].prompt = nil }
        }
        AgentActivityMonitor.shared.preview(sessions)
        UserDefaults.standard.set(3, forKey: "timers.count")
        defer { UserDefaults.standard.removeObject(forKey: "timers.count") }
        if only?.contains("page-music") ?? true, let line = tracks["generationals"]?.lyrics?.first {
            WebsiteDemoProfile.prepareSticker(for: line)
        }
        for (name, family, tab, terminalTab) in pages {
            if let terminalTab { UserDefaults.standard.set(terminalTab, forKey: "terminal.tab") }
            await clip(name, length: tab == .music ? 3.5 : (tab == .tray ? 2.5 : 0.5), output: output, tab: tab, setup: { clock, _, shelf in
                scene(family, clock)
                play("home")
                services.timerService.setPreview(remaining: WebsiteDemoProfile.timerRemaining, total: WebsiteDemoProfile.timerTotal)
                if name == "page-music", let track = tracks["generationals"], let line = track.lyrics?.first {
                    play("generationals")
                    theme.lyricStyle = .stickers
                    StickerCapture.shared.pinnedTime = 0
                    if let at = track.lyricAt { StickerCapture.shared.spans[line] = max(1.5, (track.lyricEnd ?? at + 3) - at) }
                    services.teleprompter.setPreview(current: line, upcoming: "", source: .lyrics, playing: true)
                }
                if tab == .tray { shelf.setPreviewItems(trayFiles, selectedIndex: 0) }
                // Calendar shows the month; Life shows a synthetic birthday's life in weeks.
                UserDefaults.standard.set(name == "page-life", forKey: "calendar.showsLife")
                if name == "page-life" {
                    WidgetOptions.shared.birthday = Calendar.current.date(from: DateComponents(year: 1998, month: 4, day: 18, hour: 12))
                    WidgetOptions.shared.lifespan = 80
                }
            }, beats: [])
            StickerCapture.shared.pinnedTime = nil
        }

        // Wisp, with Claude behind it (the tag): a reminder, then a tea timer, each reply holding
        // up its prop. Stills: the greeting, and the finished conversation.
        let wisp = WispModel.shared
        wisp.previewEngine = WispEngine(name: "Claude", detail: "", isModel: true, symbol: "key.horizontal")
        let ask = WispMessage(role: .user, text: "Remind me to call Sam tomorrow at 10")
        let added = WispMessage(role: .wisp, text: "Added “call Sam” for tomorrow at 10:00.")
        let tea = WispMessage(role: .user, text: "Tea timer, 4 minutes")
        let brewing = WispMessage(role: .wisp, text: "Tea's on. I'll ping you in 4 minutes.")
        await clip("page-wisp-hello", length: 0.5, output: output, tab: .wisp, setup: { clock, _, _ in
            scene(.starlight, clock)
            wisp.setPreview([], mood: .idle)
        }, beats: [])
        await clip("page-wisp", length: 0.5, output: output, tab: .wisp, setup: { clock, _, _ in
            scene(.nightBlossom, clock)
            wisp.setPreview([ask, added, tea, brewing], mood: .happy)
            wisp.show(.mug, for: 60)
        }, beats: [])
        await clip("wisp", length: 8, output: output, tab: .wisp, setup: { clock, _, _ in
            scene(.nightBlossom, clock)
            wisp.setPreview([], mood: .idle)
            wisp.show(.note, for: 0)   // Clears the still's mug before the first frame.
        }, beats: [
            (1.0, { _, _, _ in wisp.setPreview([ask], mood: .thinking) }),
            (2.0, { _, _, _ in wisp.setPreview([ask, added], mood: .happy); wisp.show(.bell, for: 2.4) }),
            (4.6, { _, _, _ in wisp.setPreview([ask, added, tea], mood: .thinking) }),
            (5.5, { _, _, _ in wisp.setPreview([ask, added, tea, brewing], mood: .celebrating); wisp.show(.mug, for: 3) }),
        ])
        wisp.setPreview([], mood: .idle)
        wisp.previewEngine = nil

        // Music's views from the dock's middle group: Stats (Spotify's top songs for three
        // ranges, the owner's songs and their covers), Backups, and Connect before sign-in.
        if only.map({ !$0.filter { $0.hasPrefix("page-music-views") }.isEmpty }) ?? false {
            let spotify = SpotifyLibrary.shared
            func song(_ key: String) -> SpotifyLibrary.Song? {
                tracks[key].map { SpotifyLibrary.Song(title: $0.title, artists: $0.artist, album: $0.album,
                                                      image: URL(fileURLWithPath: $0.cover), link: nil) }
            }
            let keys = ["generationals", "phantogram", "suki-waterhouse", "fog-lake", "modern-english"]
            let orders = [[0, 1, 2, 3, 4], [1, 0, 3, 2, 4], [0, 3, 4, 1, 2]]
            var top = SpotifyLibrary.Top(fetched: Date())
            for (range, order) in zip(SpotifyLibrary.Range.allCases, orders) {
                top.songs[range.rawValue] = order.compactMap { song(keys[$0]) }
                top.artists[range.rawValue] = order.compactMap { tracks[keys[$0]].map { SpotifyLibrary.Artist(name: $0.artist, image: URL(fileURLWithPath: $0.cover)) } }
            }
            let now = Date()
            let backups = [0, 7, 14, 21].map { days in
                SpotifyLibrary.Backup(date: now.addingTimeInterval(-Double(days) * 86_400 - 3600), likedSongs: 1_284 - days,
                                      playlists: 37, playlistSongs: 2_906 - days * 3, followed: 12, folder: "\(days)")
            }
            let views: [(String, MusicView, Bool)] = [("page-music-views-stats", .stats, true), ("page-music-views-backups", .backups, true),
                                                     ("page-music-views-playing", .playing, true), ("page-music-views-connect", .stats, false)]
            for (name, view, connected) in views where only?.contains(name) ?? false {
                spotify.setPreview(account: connected ? "zach" : nil, top: connected ? top : nil, backups: connected ? backups : [])
                UserDefaults.standard.set(view.rawValue, forKey: MusicView.defaultsKey)
                await clip(name, length: 3, output: output, tab: .music, setup: { clock, _, _ in
                    scene(.blossom, clock)
                    play("generationals")
                }, beats: [])
            }
            UserDefaults.standard.removeObject(forKey: MusicView.defaultsKey)
        }

        // ASCII album art on the Music page (braille vinyl) in Midnight and Everforest, and the
        // Album art card in Settings, as stills for review.
        for (name, family) in [("page-music-ascii-midnight", ThemeFamily.midnight), ("page-music-ascii-everforest", .everforest)]
            where only?.contains(name) ?? false {
            let options = WidgetOptions.shared
            options.asciiCover = true; options.asciiStyle = .braille; options.asciiScene = .vinyl; options.asciiDetail = .medium
            UserDefaults.standard.set(MusicView.playing.rawValue, forKey: MusicView.defaultsKey)
            await clip(name, length: 3, output: output, tab: .music, setup: { clock, _, _ in
                scene(family, clock)
                play("generationals")
                AsciiCoverCache.shared.prepareNow(services.nowPlaying.info.artwork)
            }, beats: [])
            options.asciiCover = false
        }
        // The site's ASCII demo: Midnight, Put a Light On, a style and scene every two seconds;
        // `page-ascii` is its still (braille vinyl).
        if only?.contains("ascii") ?? false {
            let options = WidgetOptions.shared
            options.asciiCover = true; options.asciiStyle = .braille; options.asciiScene = .vinyl; options.asciiDetail = .medium
            UserDefaults.standard.set(MusicView.playing.rawValue, forKey: MusicView.defaultsKey)
            let steps: [(AsciiStyle, AsciiScene)] = [(.classic, .pulse), (.blocks, .horizon), (.contour, .spiral), (.braille, .cover)]
            await clip("ascii", length: 10, output: output, tab: .music, setup: { clock, _, _ in
                scene(.midnight, clock)
                play("generationals")
                AsciiCoverCache.shared.prepareNow(services.nowPlaying.info.artwork)
            }, beats: steps.enumerated().map { index, step in
                (2.0 * Double(index + 1), { _, _, _ in options.asciiStyle = step.0; options.asciiScene = step.1 })
            })
            options.asciiCover = false
        }
        if only?.contains("page-ascii") ?? false {
            let options = WidgetOptions.shared
            options.asciiCover = true; options.asciiStyle = .braille; options.asciiScene = .vinyl; options.asciiDetail = .medium
            UserDefaults.standard.set(MusicView.playing.rawValue, forKey: MusicView.defaultsKey)
            await clip("page-ascii", length: 3, output: output, tab: .music, setup: { clock, _, _ in
                scene(.midnight, clock)
                play("generationals")
                AsciiCoverCache.shared.prepareNow(services.nowPlaying.info.artwork)
            }, beats: [])
            options.asciiCover = false
        }
        for (name, family) in [("settings-ascii-midnight", ThemeFamily.midnight), ("settings-ascii-everforest", .everforest)]
            where only?.contains(name) ?? false {
            theme.selectFamily(family)
            play("generationals")
            AsciiCoverCache.shared.prepareNow(services.nowPlaying.info.artwork)
            WidgetOptions.shared.asciiCover = true
            let host = NSHostingView(rootView: AsciiArtPicker().padding(20).frame(width: 700).background(Color(nsColor: .windowBackgroundColor)))
            host.frame = NSRect(x: 0, y: 0, width: 700, height: 330)
            host.appearance = NSAppearance(named: .darkAqua)
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            host.layoutSubtreeIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name + ".png"))
            }
            WidgetOptions.shared.asciiCover = false
        }

        // Tray: a file dragged in from the desktop lands in the Tray.
        play(pairings[2])
        await clip("tray", length: 4.2, output: output, tab: .tray, setup: { clock, _, _ in
            scene(pairings[2].family, clock)
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
        await clip("terminal", length: 6.4, output: output, tab: .terminal, setup: { clock, _, _ in
            scene(pairings[1].family, clock)
        }, beats: beats)
        shell.stop()

        // Timers: a five-minute countdown starts.
        await clip("timers", length: 3.6, output: output, tab: .timers, setup: { clock, _, _ in
            scene(pairings[0].family, clock)
        }, beats: [
            (0.8, { _, model, _ in model.timerService.start(minutes: 5) }),
        ])
        services.timerService.cancel()
        print("Clips rendered in \(output.path)")
    }

    private static func converterReel(output: URL) {
        ThemeStore.shared.selectFamily(.blossom)
        let wheel = ConverterWheel.shared
        let photo = output.appendingPathComponent("Golden hour.png")
        try? NSImage(named: "ThemeBlossom")?.tiffRepresentation.map { data in try data.write(to: photo) }
        wheel.preview([photo], tools: false, hovered: 0)
        let cursor = Clock()
        let host = NSHostingView(rootView: ConverterReelStage(clock: cursor).environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 702)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; window.ignoresMouseEvents = true; window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        let frames = output.appendingPathComponent("clip-converter-reel")
        try! FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let fps = WebsiteDemo234.fps, scale = WebsiteDemo234.timeScale
        Design.demoTimeScale = scale
        defer { Design.demoTimeScale = 1; window.contentView = nil }
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let start = Date(); var previous: (tools: Bool, hovered: Int)?
        for n in 0..<Int(4 * fps) {
            let t = Double(n) / fps
            cursor.t = t
            // Like the real wheel: the wedge under the pointer is the one that lights up.
            let tools = t >= ConverterReelStage.toolsAt
            // Switch with nothing lit: the old index would light the wrong wedge of the new set.
            if tools != previous?.tools { wheel.preview([photo], tools: tools, hovered: nil) }
            let hovered = ConverterReelStage.wedge(at: ConverterReelStage.angle(at: t), count: wheel.actions.count)
            if previous?.tools != tools || previous?.hovered != hovered {
                previous = (tools, hovered)
                withAnimation(Design.spring()) { wheel.hovered = hovered }
            }
            RunLoop.main.run(until: start.addingTimeInterval(t * scale))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: frames.appendingPathComponent(String(format: "f%05d.png", n)))
        }
    }

    private struct ConverterReelStage: View {
        @ObservedObject var clock: Clock
        @ObservedObject var wheel = ConverterWheel.shared
        private static let scale: CGFloat = 1.75

        var body: some View {
            ZStack {
                WebsiteBlossomWallpaper()
                ConverterWheelView(wheel: wheel).scaleEffect(Self.scale)
                Image(systemName: "cursorarrow").font(.system(size: 24)).foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 2)
                    .position(pointer)
            }.frame(width: 1200, height: 702)
        }

        /// Option is "pressed" here: the wheel switches from formats to tools.
        static let toolsAt = 1.8
        /// The pointer's path, in degrees clockwise from 3 o'clock: JPG, HEIC, TIFF, then (tools) Copy
        /// Text and ZIP, eased between stops with a little hand drift so it never sits frozen.
        private static let stops: [(t: Double, degrees: Double)] = [
            (0, -90), (0.25, -90), (0.85, -38.6), (1.05, -38.6), (1.6, 12.9), (1.85, 12.9),
            (2.3, 30), (2.5, 30), (3.4, 150), (4, 150),
        ]

        static func angle(at t: Double) -> Double {
            let next = stops.firstIndex { $0.t > t } ?? stops.count - 1
            let a = stops[max(next - 1, 0)], b = stops[next]
            let x = b.t > a.t ? min(max((t - a.t) / (b.t - a.t), 0), 1) : 1
            return a.degrees + (b.degrees - a.degrees) * x * x * (3 - 2 * x) + 3 * sin(t * 2.3)
        }

        /// Matches `ConverterWheel.segment(at:)`: wedge i is centred on i × step − 90°.
        static func wedge(at degrees: Double, count: Int) -> Int {
            let step = 360 / Double(max(count, 1))
            return Int(((degrees + 90 + step / 2 + 720).truncatingRemainder(dividingBy: 360)) / step) % max(count, 1)
        }

        /// The arrow's tip on the ring at the pointer's angle.
        private var pointer: CGPoint {
            let angle = Self.angle(at: clock.t) * .pi / 180
            let radius = ((ConverterWheel.innerRadius + ConverterWheel.outerRadius) / 2 + 24 + 5 * sin(clock.t * 1.7)) * Self.scale
            // `position` centres the glyph; shift it so the tip (top-left) lands on the ring.
            return CGPoint(x: 600 + cos(angle) * radius + 7, y: 351 + sin(angle) * radius + 11)
        }
    }

    private typealias Beat = (Double, (Clock, NotchViewModel, ShelfStore) -> Void)

    /// Renders one clip with the Nook already open on `tab`.
    private static var only: Set<String>? {
        ProcessInfo.processInfo.environment["MACSPACES_DEMO_CLIPS"].map { Set($0.split(separator: ",").map(String.init)) }
    }

    /// Real-time timeline; ScreenCaptureKit records this window through the macOS compositor.
    /// There is no frame-cache renderer, animation slowdown, pointer or screen-wide capture.
    private static func recordLocal(_ name: String, length: Double, output: URL, window: NSWindow,
                                    clock: Clock, model: NotchViewModel, shelf: ShelfStore, beats: [Beat]) async {
        guard let executable = ProcessInfo.processInfo.environment["MACSPACES_DEMO_RECORDER"] else {
            fatalError("Use Scripts/capture-demos.sh for local captures")
        }
        let signal = output.appendingPathComponent("record-" + name).path
        let recorder = Process()
        recorder.executableURL = URL(fileURLWithPath: executable)
        recorder.arguments = [String(window.windowNumber), output.appendingPathComponent(name + ".mov").path,
                              "1640", "940", signal]
        do { try recorder.run() } catch { fatalError("Cannot start window recorder: \(error)") }
        defer { if recorder.isRunning { recorder.terminate() } }
        let deadline = Date().addingTimeInterval(35)
        while !FileManager.default.fileExists(atPath: signal + ".ready") {
            guard recorder.isRunning, Date() < deadline else {
                fatalError("Window recorder did not produce its first frame. Keep the desktop unlocked; see capture.log.")
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        // Fixed pre-roll, trimmed by the export script. Keep the timeline still until recording is ready.
        try? await Task.sleep(nanoseconds: 400_000_000)
        let start = Date()
        var next = 0
        while Date().timeIntervalSince(start) < length {
            let t = Date().timeIntervalSince(start)
            clock.t = t
            while next < beats.count, t >= beats[next].0 { beats[next].1(clock, model, shelf); next += 1 }
            // Now Playing's native position clock advances from the preview anchor.
            try? await Task.sleep(nanoseconds: 16_666_667)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        do { try Data().write(to: URL(fileURLWithPath: signal + ".stop")) }
        catch { fatalError("Cannot stop capture: \(error)") }
        let finish = Date().addingTimeInterval(20)
        while recorder.isRunning, Date() < finish { try? await Task.sleep(nanoseconds: 50_000_000) }
        guard !recorder.isRunning, recorder.terminationStatus == 0 else { fatalError("Window recording failed: \(name)") }
        for suffix in [".ready", ".stop"] { try? FileManager.default.removeItem(atPath: signal + suffix) }
        print("Local capture finished: \(name)")
    }

    private static func clip(_ name: String, length: Double, output: URL, tab: NotchTab,
                             setup: (Clock, NotchViewModel, ShelfStore) -> Void, beats: [Beat]) async {
        guard only?.contains(name) ?? true else { return }
        let settings = NookSettings.shared
        let savedDock = settings.dockApps
        // Every capture has the same dock (the song plays from Spotify, so Music adds no playlist button).
        if tab != .nook, !savedDock.contains(tab) { settings.dockApps = savedDock + [tab] }
        defer { settings.dockApps = savedDock }
        let services = AppServices.shared
        let frames = output.appendingPathComponent("clip-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: frames)
        try! FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let shelf = ShelfStore(basketID: UUID())
        let model = WebsiteDemoProfile.model(availableWidth: 1512, shelf: shelf)
        model.selectedTab = tab
        model.state = .expanded
        model.isPinned = true
        let clock = Clock()
        setup(clock, model, shelf)
        let local = ProcessInfo.processInfo.environment["MACSPACES_DEMO_LOCAL"] == "1"
        let screen = NSScreen.main ?? NSScreen.screens.first
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 900)
        let previewWidth = min(560, area.width * 0.38)
        let previewScale = local ? previewWidth / stage.width : 1
        let viewport = CGSize(width: stage.width * previewScale, height: stage.height * previewScale)
        let host = NSHostingView(rootView: ClipStage(model: model, clock: clock)
            .environment(\.colorScheme, .dark)
            .scaleEffect(previewScale, anchor: .topLeading)
            .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
            .allowsHitTesting(!local))
        host.frame = NSRect(origin: .zero, size: viewport)
        let window: NSWindow
        if local, let existing = localWindow {
            window = existing
        } else {
            window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            if local {
                localWindow = window
                window.title = "MacSpaces Demo Capture"
                window.level = .normal
                window.collectionBehavior = []
                window.isMovableByWindowBackground = true
                window.isReleasedWhenClosed = false
                window.setFrameOrigin(NSPoint(x: area.maxX - viewport.width - 16,
                                              y: area.maxY - viewport.height - 16))
            } else {
                window.ignoresMouseEvents = true
                window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            }
        }
        window.contentView = host
        if local, !window.isVisible {
            // Show once without activating the app. Page changes reuse this window and
            // never raise it over the owner's other work, follow Spaces, or move the pointer.
            window.orderFront(nil)
            print("Local demo preview: one window, frame=\(window.frame), level=\(window.level.rawValue), Spaces=\(window.collectionBehavior.rawValue)")
        }
        defer { if !local { window.orderOut(nil); window.contentView = nil } }
        // Yield the main actor so native SwiftUI tasks and Core Animation layers can initialize.
        if local {
            StickerCapture.shared.pinnedTime = nil
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            guard model.state == .expanded else { fatalError("Demo panel closed before capture: \(name)") }

        } else {
            RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        }

        if local {
            await recordLocal(name, length: max(3, length), output: output, window: window,
                        clock: clock, model: model, shelf: shelf, beats: beats)
            return
        }
        let fps = WebsiteDemo234.fps, scale = WebsiteDemo234.timeScale
        let writer = DispatchQueue(label: "clip-frame-writer")
        let group = DispatchGroup()
        Design.demoTimeScale = scale
        defer { Design.demoTimeScale = 1 }
        var next = 0
        let start = Date()
        let still = ProcessInfo.processInfo.environment["MACSPACES_DEMO_FAST"] == "1" && ((name.hasPrefix("page-") && name != "page-music") || name == "theme-aurora" || name == "theme-prism")
        for n in 0..<(still ? 1 : Int(length * fps)) {
            let t = Double(n) / fps
            clock.t = t
            while next < beats.count, t >= beats[next].0 { beats[next].1(clock, model, shelf); next += 1 }
            if !still, n > 0 { var info = services.nowPlaying.info; info.elapsed += 1 / fps; services.nowPlaying.setPreviewInfo(info) }
            if StickerCapture.shared.pinnedTime != nil { StickerCapture.shared.pinnedTime = t }
            RunLoop.main.run(until: start.addingTimeInterval(t * scale))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            // Always 2x (1640×940), also on a Mac without a Retina screen, such as CI's.
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(stage.width * 2), pixelsHigh: Int(stage.height * 2),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            bitmap.size = host.bounds.size
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
            Group {
                if let family = clock.wallpaperFamily { SceneWallpaper(family: family) }
                else if let asset = clock.wallpaperAsset { Image(asset).resizable().scaledToFill().frame(width: size.width, height: size.height).clipped() }
                else if ProcessInfo.processInfo.environment["MACSPACES_DEMO_THEME"] == "blossom" { WebsiteBlossomWallpaper() }
                else { DemoWallpaper(colors: clock.wallpaper.map { Color(themeHex: $0) ?? .gray }) }
            }.frame(width: size.width, height: size.height)
            NotchContainerView(viewModel: model)
                .frame(width: size.width, height: size.height, alignment: .top)
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                .fill(.black).frame(width: WebsiteDemoProfile.notchSize.width, height: WebsiteDemoProfile.notchSize.height)
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
