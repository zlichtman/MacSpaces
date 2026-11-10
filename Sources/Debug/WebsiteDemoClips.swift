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
        /// A plain desktop, over the asset and colours.
        @Published var plainStage = false
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
        // the widgets' own sizes, the site dock, a running timer, Keep Awake on and
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
            theme.setPreviewSystemReduceMotion(false)
            clock.plainStage = true
            services.teleprompter.setPreview(current: "", source: .lyrics)
        }
        /// Three timers on the Timers page, one paused, and the bubbles they spin out.
        func previewTimers() {
            let timers = services.allTimers
            timers[0].name = "Deep work"; timers[0].setPreview(remaining: WebsiteDemoProfile.timerRemaining, total: WebsiteDemoProfile.timerTotal)
            timers[1].name = "Tea"; timers[1].setPreview(remaining: 3 * 60 + 42, total: 5 * 60)
            timers[2].name = "Laundry"; timers[2].setPreview(remaining: 41 * 60 + 8, total: 60 * 60, paused: true)
        }
        func lyric(_ text: String) {
            withAnimation(Design.spring()) { services.teleprompter.setPreview(current: text, source: .lyrics) }
        }
        // The original reel's songs, themes and excerpts. One approved manifest drives CI and local capture.
        let showcase = sequence.songs.map { (song: $0.key, family: ThemeFamily(rawValue: $0.theme)!) }
        let segment = sequence.segmentSeconds
        // Only the player, from the first frame: no Home.
        var showcaseBeats: [Beat] = []
        func sing(_ key: String) {
            guard let line = tracks[key]?.lyrics?.first else { return }
            lyric(line)
        }
        for (index, item) in showcase.enumerated() {
            let start = Double(index) * segment
            if index > 0 {
                showcaseBeats.append((start - 0.35, { _, _, _ in lyric("") }))
                showcaseBeats.append((start, { clock, _, _ in
                    withAnimation(.easeInOut(duration: 0.35 * WebsiteDemo234.timeScale)) { scene(item.family, clock); play(item.song) }
                }))
            }
            showcaseBeats.append((start + 0.4, { _, _, _ in sing(item.song) }))
        }
        showcaseBeats.sort { $0.0 < $1.0 }
        await clip("music-showcase", length: Double(showcase.count) * segment, output: output, tab: .music, setup: { clock, _, _ in
            scene(showcase[0].family, clock); play(showcase[0].song)
        }, beats: showcaseBeats)
        // The Vinyl look across the same songs, always moving: the vinyl turning, the cover under
        // rain, the pulse. Each character in its cover's true colour, with no cover tint, on a dark
        // terminal theme whose own background carries the cover's colour: the sea's teal, Phantogram's
        // yellow, Loveland's red, Fog Lake's olive, Pillow Lips' blue.
        if only?.contains("music-terminal") ?? true {
            GhosttyLibrary.shared.load()
            for _ in 0..<100 where GhosttyLibrary.shared.themes.isEmpty { try? await Task.sleep(nanoseconds: 50_000_000) }
        }
        let terminalReel: [(ghostty: String, song: String, style: AsciiStyle, cover: AsciiScene, around: AsciiAround)] = [
            ("Poltergeist", "generationals", .braille, .vinyl, .off),
            ("Mono Yellow", "phantogram", .braille, .cover, .rain),
            ("Blood Moon", "suki-waterhouse", .braille, .pulse, .off),
            ("Pumpkin Patch", "fog-lake", .braille, .vinyl, .rain),
            ("Tomorrow Night Blue", "modern-english", .braille, .vinyl, .off),
        ]
        let tinted = WidgetOptions.shared.albumTint
        func terminalLook(_ item: (ghostty: String, song: String, style: AsciiStyle, cover: AsciiScene, around: AsciiAround), _ clock: Clock) {
            let options = WidgetOptions.shared
            options.musicLook = .terminal
            options.albumTint = false
            options.asciiStyle = item.style; options.asciiScene = item.cover; options.asciiAround = item.around
            options.asciiColours = .cover; options.asciiDetail = .medium
            scene(.tokyoNight, clock)
            if let found = GhosttyLibrary.shared.theme(named: item.ghostty) { theme.selectGhostty(found) }
            play(item.song)
            AsciiCoverCache.shared.prepareNow(services.nowPlaying.info.artwork)
        }
        var terminalBeats: [Beat] = []
        for (index, item) in terminalReel.enumerated() {
            let start = Double(index) * segment
            if index > 0 {
                terminalBeats.append((start - 0.35, { _, _, _ in lyric("") }))
                terminalBeats.append((start, { clock, _, _ in terminalLook(item, clock) }))
            }
            terminalBeats.append((start + 0.4, { _, _, _ in sing(item.song) }))
        }
        terminalBeats.sort { $0.0 < $1.0 }
        await clip("music-terminal", length: Double(terminalReel.count) * segment, output: output, tab: .music, setup: { clock, _, _ in
            terminalLook(terminalReel[0], clock)
        }, beats: terminalBeats)
        WidgetOptions.shared.musicLook = .standard
        WidgetOptions.shared.albumTint = tinted
        WidgetOptions.shared.asciiAround = .off
        WidgetOptions.shared.asciiColours = .theme
        WidgetOptions.shared.asciiScene = .vinyl
        // A settled still for every original song, captured independently of the transition timing.
        for (index, item) in showcase.enumerated() {
            let name = String(format: "music-%02d-%@", index + 1, item.song)
            await clip(name, length: 3, output: output, tab: .music, setup: { clock, _, _ in
                scene(item.family, clock); play(item.song)
                sing(item.song)
            }, beats: [])
        }
        // The README's first image (owner, 3.2): the Music page in Blossom with a Poster lyric,
        // over a soft evening desktop; the README uses a settled frame.
        await clip("readme-hero", length: 3, output: output, tab: .music, setup: { clock, _, _ in
            theme.selectFamily(.blossom); theme.setPreviewSystemReduceMotion(false)
            clock.wallpaperAsset = nil; clock.wallpaper = ["#8E9BD3", "#A9A3D2", "#D9AFC0", "#EDB9A0"]
            play("generationals")
            services.teleprompter.setPreview(current: tracks["generationals"]?.lyrics?.first ?? "", source: .lyrics)
        }, beats: [])
        if only?.contains("converter-reel") == true { converterReel(output: output) }

        // The site's tour: Home, the player and its lyric, the Terminal look, Timers, the globe, then
        // closing to the bubbles beside the camera.
        await clip("tour", length: 21.5, output: output, tab: .nook, setup: { clock, _, _ in
            scene(.nightBlossom, clock); play("generationals")
            previewTimers()
            AgentActivityMonitor.shared.preview()
        }, beats: [
            (2.2, { _, model, _ in withAnimation(Design.spring()) { model.selectedTab = .music } }),
            (2.6, { _, _, _ in sing("generationals") }),
            (5.6, { _, _, _ in withAnimation(Design.spring()) { WidgetOptions.shared.musicLook = .terminal } }),
            (8.6, { _, model, _ in
                UserDefaults.standard.set(CodingPanel.Tab.agents.rawValue, forKey: WidgetOptions.Keys.terminalTab)
                withAnimation(Design.spring()) { model.selectedTab = .terminal }
            }),
            (9.0, { _, _, _ in WidgetOptions.shared.musicLook = .standard }),
            (11.2, { _, model, _ in withAnimation(Design.spring()) { model.selectedTab = .timers } }),
            (13.6, { _, model, _ in withAnimation(Design.spring()) { model.selectedTab = .clock } }),
            (14.0, { _, _, _ in NotificationCenter.default.post(name: ClockPage.demoAction, object: WebsiteDemoNotch.matched[0]) }),
            (14.8, { _, _, _ in NotificationCenter.default.post(name: ClockPage.demoAction, object: WebsiteDemoNotch.matched[1]) }),
            (15.6, { _, _, _ in NotificationCenter.default.post(name: ClockPage.demoAction, object: true) }),
            // Closed again, just the song: its cover and its sound, balanced either side of the camera.
            (18.4, { _, _, _ in for timer in services.allTimers { timer.setPreview(remaining: 0, total: 1500) } }),
            (18.6, { _, model, _ in model.isPinned = false; model.collapse() }),
        ])
        WidgetOptions.shared.musicLook = .standard
        // The cover's tint on a plain theme: for checking only, not on the site.
        await clip("page-music-tint", length: 3, output: output, tab: .music, setup: { clock, _, _ in
            scene(.macspaces, clock); play("phantogram"); sing("phantogram")
        }, beats: [])
        // The Music section: the Terminal look with its own lyric line, and where the sound plays.
        await clip("page-music-terminal", length: 3.5, output: output, tab: .music, setup: { clock, _, _ in
            scene(.nightBlossom, clock); play("generationals")
            WidgetOptions.shared.musicLook = .terminal
            sing("generationals")
        }, beats: [])
        WidgetOptions.shared.musicLook = .standard
        await clip("page-music-devices", length: 3, output: output, tab: .music, setup: { clock, _, _ in
            scene(.blossom, clock); play("generationals")
            AudioOutputs.shared.setPreview([
                AudioOutput(id: 1, name: "MacBook Pro Speakers", symbol: AudioOutputSymbol.symbol(name: "MacBook Pro Speakers", transport: .builtIn)),
                AudioOutput(id: 2, name: "AirPods Pro", symbol: AudioOutputSymbol.symbol(name: "AirPods Pro", transport: .bluetooth)),
                AudioOutput(id: 3, name: "Studio Display", symbol: AudioOutputSymbol.symbol(name: "Studio Display", transport: .display)),
                AudioOutput(id: 4, name: "Living Room", symbol: AudioOutputSymbol.symbol(name: "Living Room", transport: .airPlay)),
            ], current: 2)
            UserDefaults.standard.set(MusicView.devices.rawValue, forKey: MusicView.defaultsKey)
            MusicView.keepOnReturn = true
        }, beats: [])
        UserDefaults.standard.removeObject(forKey: MusicView.defaultsKey)
        // The Themes section: a living scene, and themes from the terminal library, on the real Nook.
        if only?.contains("page-theme-terminal") ?? true {
            GhosttyLibrary.shared.load()
            for _ in 0..<100 where GhosttyLibrary.shared.themes.isEmpty { try? await Task.sleep(nanoseconds: 50_000_000) }
        }
        for (name, ghostty) in [("page-theme-terminal", "Kanagawa Wave"), ("page-theme-terminal-light", "Rose Pine Dawn")] {
            await clip(name, length: 3, output: output, tab: .nook, setup: { clock, _, _ in
                scene(.nightBlossom, clock); play("home")
                if let found = GhosttyLibrary.shared.theme(named: ghostty) { theme.selectGhostty(found) }
            }, beats: [])
        }

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
                theme.setPreviewSystemReduceMotion(family == .aurora || family == .prism)
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
        // The Tray looks like someone's real files: the picture pack's poster, panorama and two
        // paintings, a lease PDF, an invoice scan and a packing list, with your tags and a note on the
        // poster (selected, so its details show). Without the pack, drawn pictures and plain notes.
        let trayPack = trayPackFiles(in: trayFolder)
        var trayFiles: [URL] = trayPack?.files ?? []
        if trayPack == nil {
        for (name, text) in [("Launch plan.md", "# Launch plan\n\n" + (1...14).map { "- Step \($0): notarize, tag, update the tap" }.joined(separator: "\n")),
                             ("Budget.csv", "Item,Cost\n" + (1...14).map { "Line \($0),\($0 * 120)" }.joined(separator: "\n")),
                             ("Interview notes.txt", (1...16).map { "Question \($0): what would make the first week easier?" }.joined(separator: "\n\n")),
                             ("Site copy.md", "# Site copy\n\n" + (1...12).map { "Section \($0): one short, plain line about it." }.joined(separator: "\n\n"))] {
            let url = trayFolder.appendingPathComponent(name)
            try? text.write(to: url, atomically: true, encoding: .utf8)
            trayFiles.append(url)
        }
        // Made-up pictures (a gradient sky, a sun and hills), never album art.
        for (name, sky, hills, sun) in [
            ("Trail photo.png", [(0.56, 0.78, 0.93), (0.78, 0.88, 0.9), (0.98, 0.9, 0.76)], (0.2, 0.42, 0.34), (1.0, 0.97, 0.85)),
            ("Banner final.png", [(0.1, 0.13, 0.3), (0.32, 0.2, 0.5), (0.95, 0.5, 0.42)], (0.22, 0.12, 0.3), (1.0, 0.82, 0.55)),
            ("Poster draft.png", [(0.99, 0.72, 0.62), (0.86, 0.46, 0.6), (0.33, 0.2, 0.42)], (0.42, 0.26, 0.38), (1.0, 0.9, 0.7)),
        ] {
            let url = trayFolder.appendingPathComponent(name)
            let picture = NSImage(size: NSSize(width: 1200, height: 800), flipped: false) { rect in
                NSGradient(colors: sky.map { NSColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: 1) })?.draw(in: rect, angle: -90)
                NSColor(srgbRed: sun.0, green: sun.1, blue: sun.2, alpha: 1).setFill()
                NSBezierPath(ovalIn: NSRect(x: 760, y: 380, width: 170, height: 170)).fill()
                for (i, shade) in [1.0, 0.72, 0.48].enumerated() {
                    NSColor(srgbRed: hills.0 * shade, green: hills.1 * shade, blue: hills.2 * shade, alpha: 1).setFill()
                    let hill = NSBezierPath(); hill.move(to: .zero)
                    for x in stride(from: 0, through: 1200, by: 30) {
                        hill.line(to: NSPoint(x: CGFloat(x), y: 250 - CGFloat(i) * 70 + 50 * sin(CGFloat(x) / 170 + CGFloat(i) * 1.9)))
                    }
                    hill.line(to: NSPoint(x: 1200, y: 0)); hill.close(); hill.fill()
                }
                return true
            }
            if let tiff = picture.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: url); trayFiles.insert(url, at: 0)
            }
        }
        }
        // The Tray's files read first (thumbnails, kinds and what Folio found), so the details are whole.
        var trayStore: ShelfStore?
        if only?.contains("page-tray") ?? true {
            let store = ShelfStore(basketID: nil)
            store.setPreviewItems(trayFiles, selectedIndex: 0)
            await store.waitForFileMetadata()
            for _ in 0..<300 where trayFiles.contains(where: { FolioIndex.shared.record(for: $0) == nil }) {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            trayStore = store
        }
        // Every page on an offered theme, over that theme's own scene (owner).
        let pages: [(String, ThemeFamily, NotchTab, String?)] = [
            ("page-meetings", .lotus, .meetings, nil),
            // Dictation is Studio's Dictate.
            ("page-dictation", .lavender, .prompter, nil),
            ("page-clock", .moonrise, .clock, nil),
            ("page-system", .alpine, .system, nil),
            ("page-life", .dune, .calendar, nil),
            ("page-weather", .rainCanopy, .weather, nil),
            // Home: the Home still's own widgets, song and day (`WebsiteDemoProfile.homeStill`).
            ("page-home", WebsiteDemoProfile.homeTheme, .nook, nil),
            ("page-calendar", .autumn, .calendar, nil),
            ("page-timers", .obsidianCoast, .timers, nil),
            ("page-notes", .fern, .notes, nil),
            ("page-prompter", .aurora, .prompter, nil),
            ("page-coding", .thunderstorm, .terminal, "agents"),
            ("page-usage", .lava, .terminal, "usage"),
            ("page-homebrew", .bamboo, .terminal, "homebrew"),
            ("page-shortcuts", .synthwave, .shortcuts, nil),
            // Blossom, like the clipboard and File Converter captures beside it.
            ("page-tray", .blossom, .tray, nil),
            // Music: Put a Light On in Blossom, its real line in Scenes, so the star plays.
            ("page-music", .blossom, .music, nil),
        ]
        func brew(_ kind: HomebrewPackage.Kind, _ name: String, _ title: String? = nil, _ installed: String, _ latest: String? = nil) -> HomebrewPackage {
            HomebrewPackage(kind: kind, name: name, title: title ?? name, installed: installed, latest: latest ?? installed,
                            outdated: latest != nil, pinned: false, autoUpdates: false)
        }
        let homebrewSample = [
            brew(.formula, "node", nil, "24.9.0", "24.11.1"), brew(.formula, "gh", nil, "2.81.0", "2.83.0"),
            brew(.cask, "visual-studio-code", "Visual Studio Code", "1.105.0", "1.106.1"), brew(.formula, "ffmpeg", nil, "8.0.1"),
            brew(.formula, "git", nil, "2.51.2"), brew(.formula, "python@3.14", nil, "3.14.0"), brew(.formula, "ripgrep", nil, "15.1.0"),
            brew(.cask, "iterm2", "iTerm2", "3.6.4"), brew(.formula, "xcodegen", nil, "2.44.1"),
        ].sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        // Agents: the synthetic sessions with prompts short enough to show whole.
        var sessions = AgentActivityMonitor.shared.sessions
        for index in sessions.indices {
            if sessions[index].prompt == "Make the status bar show every running job" { sessions[index].prompt = "Show every running job" }
            if sessions[index].reply != nil { sessions[index].reply = "Updated the client to v3. All 48 tests pass."; sessions[index].prompt = nil }
        }
        AgentActivityMonitor.shared.preview(sessions)
        for (name, family, tab, terminalTab) in pages {
            if let terminalTab { UserDefaults.standard.set(terminalTab, forKey: WidgetOptions.Keys.terminalTab) }
            if tab == .tray { FolioIndex.shared.setPreviewMarks(trayPack?.marks ?? [:]) }
            await clip(name, length: tab == .music ? 3.5 : (tab == .tray ? 2.5 : 0.5), output: output, tab: tab,
                       tray: tab == .tray ? trayStore : nil, setup: { clock, _, shelf in
                scene(family, clock)
                StudioModel.shared.section = name == "page-dictation" ? .dictate : .scripts
                play("home")
                services.timerService.setPreview(remaining: WebsiteDemoProfile.timerRemaining, total: WebsiteDemoProfile.timerTotal)
                if name == "page-music", let line = tracks["generationals"]?.lyrics?.first {
                    play("generationals")
                    services.teleprompter.setPreview(current: line, source: .lyrics)
                }
                if name == "page-home" { WebsiteDemoProfile.prepareHomeStill() }
                if tab == .tray, trayStore == nil { shelf.setPreviewItems(trayFiles, selectedIndex: 0) }
                if name == "page-homebrew" { HomebrewStore.shared.setPreview(packages: homebrewSample, listsUpdated: Date().addingTimeInterval(-7200)) }
                // Calendar shows the month; Life shows a synthetic birthday's life in weeks.
                UserDefaults.standard.set(name == "page-life", forKey: "calendar.showsLife")
                if name == "page-life" {
                    WidgetOptions.shared.birthday = Calendar.current.date(from: DateComponents(year: 1995, month: 6, day: 1, hour: 12))
                    WidgetOptions.shared.lifespan = 80
                }
            }, beats: [])
            if tab == .tray { FolioIndex.shared.setPreviewMarks([:]) }
            if name == "page-home" { WebsiteDemoProfile.finishHomeStill() }
        }

        // Wisp, with Claude behind it (the tag): a reminder, then a tea timer, each reply holding
        // up its prop. Stills: the greeting, and the finished conversation.
        let wisp = WispModel.shared
        wisp.previewEngine = WispEngine(name: "Claude", detail: "", isModel: true, symbol: "key.horizontal", partner: .claude)
        let ask = WispMessage(role: .user, text: "Remind me to call the dentist tomorrow at 10")
        let added = WispMessage(role: .wisp, text: "Added “call the dentist” for tomorrow at 10:00.")
        let tea = WispMessage(role: .user, text: "Tea timer, 4 minutes")
        let brewing = WispMessage(role: .wisp, text: "Tea's on. I'll ping you in 4 minutes.")
        // Calendar to Life: enter a birthday and your life appears in weeks.
        await clip("calendar-life", length: 7, output: output, tab: .calendar, setup: { clock, _, _ in
            scene(.dune, clock); play("home")
            WidgetOptions.shared.birthday = nil
            UserDefaults.standard.set(false, forKey: "calendar.showsLife")
        }, beats: [
            (2.0, { _, _, _ in withAnimation(Design.spring()) { UserDefaults.standard.set(true, forKey: "calendar.showsLife") } }),
            (4.0, { _, _, _ in withAnimation(Design.spring()) {
                WidgetOptions.shared.birthday = Calendar.current.date(from: DateComponents(year: 1995, month: 6, day: 1))
            } }),
        ])
        UserDefaults.standard.set(false, forKey: "calendar.showsLife")
        // Clock: choose two places, then Match up finds the hours that work for both.
        await clip("clock-match", length: 8, output: output, tab: .clock, setup: { clock, _, _ in
            scene(.moonrise, clock); play("home")
        }, beats: [
            (1.4, { _, _, _ in NotificationCenter.default.post(name: ClockPage.demoAction, object: WebsiteDemoNotch.matched[0]) }),
            (2.8, { _, _, _ in NotificationCenter.default.post(name: ClockPage.demoAction, object: WebsiteDemoNotch.matched[1]) }),
            (4.2, { _, _, _ in NotificationCenter.default.post(name: ClockPage.demoAction, object: true) }),
        ])
        // Tape: windows side by side in a strip, laid out by Tape's own code (WebsiteDemoTape).
        await clip("tape", length: WebsiteDemoTape.length, output: output, tab: .nook,
                   stageView: { AnyView(WebsiteDemoTape.Stage(clock: $0)) }, setup: { _, _, _ in }, beats: [])
        // The two README stills differ (owner): the greeting is Wisp itself, the on-device agent
        // (the talk-to menu shows Wisp, the field asks "Ask Wisp…"), its eyes in Aurora, the agent
        // palette named for the Aurora scene behind it; the conversation is Claude's, its mark on
        // each reply, Wisp's eyes in Rose over the pink Lotus scene.
        let claudeEngine = wisp.previewEngine
        func eyes(_ palette: String) {
            UserDefaults.standard.set(palette, forKey: WidgetOptions.Keys.agentPalette)
            UserDefaults.standard.set(0.0, forKey: WidgetOptions.Keys.agentGlassLevel)
        }
        await clip("page-wisp-hello", length: 0.5, output: output, tab: .wisp, setup: { clock, _, _ in
            scene(.aurora, clock)
            eyes("aurora")
            wisp.previewEngine = WispEngine(name: WispCharacter.wisp.title, detail: "Wisp answers on this Mac. Nothing leaves it.",
                                            isModel: true, symbol: "apple.logo")
            wisp.setPreview([], mood: .idle)
        }, beats: [])
        wisp.previewEngine = claudeEngine
        await clip("page-wisp", length: 0.5, output: output, tab: .wisp, setup: { clock, _, _ in
            scene(.lotus, clock)
            eyes("rose")
            // The conversation as it reads, Claude's replies with its mark, Wisp's eyes open and no prop.
            let fromClaude = [ask, added, tea, brewing].map { $0.role == .wisp ? WispMessage(role: .wisp, text: $0.text, from: .claude) : $0 }
            wisp.setPreview(fromClaude, mood: .idle)
        }, beats: [])
        UserDefaults.standard.removeObject(forKey: WidgetOptions.Keys.agentPalette)
        UserDefaults.standard.removeObject(forKey: WidgetOptions.Keys.agentGlassLevel)
        await clip("wisp", length: 8, output: output, tab: .wisp, setup: { clock, _, _ in
            scene(.nightBlossom, clock)
            wisp.setPreview([], mood: .idle)
        }, beats: [
            (1.0, { _, _, _ in wisp.setPreview([ask], mood: .thinking) }),
            (2.0, { _, _, _ in wisp.setPreview([ask, added], mood: .happy); wisp.show(.bell, for: 2.4) }),
            (4.6, { _, _, _ in wisp.setPreview([ask, added, tea], mood: .thinking) }),
            (5.5, { _, _, _ in wisp.setPreview([ask, added, tea, brewing], mood: .idle) }),
        ])
        // Tsukumo's Sarah demo in the Nook: glass KemoSabe in Lavender over the Lavender scene,
        // moving as it does in the app: you ask Claude, Claude asks KemoSabe, the gateway, when
        // you're free, only that answer ("Free after 7") reaches Claude, and Claude replies. 8 s,
        // drawn frame by frame at a fixed rate (a live recording of the glass couldn't keep up).
        let sarah = WispMessage(role: .user, text: "Can Sarah come over tonight?")
        // The ask line as the chat builds it: "Claude asked KemoSabe when you're free tonight → …".
        let told = WispMessage(role: .shared, text: GatewayAsk.chatLine(service: WispProvider.claude.title, agent: WispCharacter.kemosabe.title,
                                                                        phrase: GatewayAsk.parse("free tonight").phrase,
                                                                        answer: "Free after 7:00\u{202F}PM tonight."))
        let works = WispMessage(role: .wisp, text: "You're free after 7, so Sarah can come over tonight. Want a reminder to tidy up at 6:30?", from: .claude)
        UserDefaults.standard.set(WispCharacter.kemosabe.rawValue, forKey: WidgetOptions.Keys.wispCharacter)
        // Glass KemoSabe in Lavender, over the Lavender scene (owner: cute and happy).
        eyes("lavender")
        AgentColours.setGlass(1)
        if only.map({ $0.contains("kemosabe-sarah") || $0.contains("reel") }) ?? true {
            // The art's repaint in the palette's colours is ready before the first frame.
            theme.selectFamily(.lavender)
            let look = AgentColours.currentKemoSabe()
            for kind in look.glass > 0.001 ? [KemoSabeArt.Kind.felt, .glass] : [.felt] {
                _ = await KemoSabeArt.make(kind, look: look, small: false)
            }
        }
        // The talk-to menu at the top left shows Claude with its mark, and the field asks "Ask Claude…".
        UserDefaults.standard.set(WispProvider.claude.rawValue, forKey: WispProvider.key)
        await clip("kemosabe-sarah", length: 8, output: output, tab: .wisp, rendered: true, setup: { clock, _, _ in
            scene(.lavender, clock)
            wisp.setPreview([], mood: .idle)
        }, beats: [
            (0.8, { _, _, _ in wisp.setPreview([sarah], mood: .listening) }),
            (1.5, { _, _, _ in wisp.setPreview([sarah], mood: .thinking) }),
            (3.1, { _, _, _ in wisp.setPreview([sarah, told], mood: .thinking) }),
            (4.5, { _, _, _ in wisp.setPreview([sarah, told, works], mood: .happy) }),
            (6.3, { _, _, _ in wisp.setPreview([sarah, told, works], mood: .idle) }),
        ])
        // The site's hero video (`reel`, WebsiteDemoReel.swift), with KemoSabe and Claude set up as above.
        if only?.contains("reel") ?? true {
            await reel(output: output, files: files, sarah: sarah, told: told)
        }
        UserDefaults.standard.removeObject(forKey: WispProvider.key)
        UserDefaults.standard.removeObject(forKey: WidgetOptions.Keys.wispCharacter)
        UserDefaults.standard.removeObject(forKey: WidgetOptions.Keys.agentPalette)
        UserDefaults.standard.removeObject(forKey: WidgetOptions.Keys.agentGlassLevel)
        wisp.setPreview([], mood: .idle)
        wisp.previewEngine = nil

        // Heartable's views, for the site (`page-stats`, `page-backups`, `page-backup-compare`,
        // `page-shelf`): Stats (Spotify's top songs for three ranges), Backups, one backup's
        // changes since the one before, and the Shelf with a Euphoric playlist, all of the owner's
        // demo songs and covers. Each shot plays one of them in a theme whose colours go with its
        // cover: Stats in the Blossom scene the Music reel matched, the others in strong terminal
        // themes, with the cover tint off so the covers' colours show true. No account name shows.
        // `page-music-views-connect` (Connect before sign-in) is a check, drawn only when named.
        let spotify = SpotifyLibrary.shared
        func song(_ key: String) -> SpotifyLibrary.Song? {
            tracks[key].map { SpotifyLibrary.Song(title: $0.title, artists: $0.artist, album: $0.album,
                                                  image: URL(fileURLWithPath: $0.cover), link: nil) }
        }
        let keys = sequence.songs.map(\.key)
        func matched(_ key: String) -> ThemeFamily {
            sequence.songs.first { $0.key == key }.flatMap { ThemeFamily(rawValue: $0.theme) } ?? .blossom
        }
        /// Stats' wall is fifty tiles: the five songs ranked in `order`, then the rest of the wall
        /// filled from them in a fixed shuffle, never the same cover beside or above itself.
        func wall(_ order: [Int], seed: UInt64) -> [Int] {
            var picks = order, state = seed
            while picks.count < 50 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let index = picks.count
                let banned = Set([index % 10 > 0 ? picks[index - 1] : -1, index >= 10 ? picks[index - 10] : -1])
                let choices = (0..<keys.count).filter { !banned.contains($0) }
                picks.append(choices[Int((state >> 33) % UInt64(choices.count))])
            }
            return picks
        }
        let orders = [[0, 1, 2, 3, 4], [1, 0, 3, 2, 4], [0, 3, 4, 1, 2]]
        var top = SpotifyLibrary.Top(fetched: Date())
        for (index, (range, order)) in zip(SpotifyLibrary.Range.allCases, orders).enumerated() {
            let picks = wall(order, seed: UInt64(41 + index))
            top.songs[range.rawValue] = picks.compactMap { song(keys[$0]) }
            top.artists[range.rawValue] = picks.compactMap { index in
                tracks[keys[index]].map { SpotifyLibrary.Artist(name: $0.artist, image: URL(fileURLWithPath: $0.cover)) }
            }
        }
        // Weekly backups at 9:41, the demo clocks' time, so every capture reads the same.
        let now = Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date()
        let backups = [0, 7, 14, 21].map { days in
            SpotifyLibrary.Backup(date: Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now, likedSongs: 1_284 - days,
                                  playlists: 37, playlistSongs: 2_906 - days * 3, followed: 12, folder: "\(days)")
        }
        // Since last week: two songs liked, one unliked, two added to the Euphoric playlist.
        let playlist = "Euphoric"
        func saved(_ key: String, _ playlist: String) -> SpotifyBackupSong? {
            tracks[key].map { SpotifyBackupSong(title: $0.title, artists: $0.artist, album: $0.album, isrc: "", link: "", playlist: playlist) }
        }
        // Each of the five songs once, never the same song twice in the list.
        let liked = SpotifyBackupDiff.likedSongs
        let thisWeek = [saved("phantogram", liked), saved("fog-lake", liked),
                        saved("suki-waterhouse", playlist), saved("modern-english", playlist)].compactMap { $0 }
        let lastWeek = [saved("generationals", liked)].compactMap { $0 }
        let changes = SpotifyBackupDiff(current: thisWeek, previous: lastWeek)
        // The Euphoric playlist, its cover the first song's.
        let euphoricOrder = ["phantogram", "generationals", "modern-english", "suki-waterhouse", "fog-lake"]
        var euphoric = SpotifyLibrary.ShelfSource(id: "euphoric", name: playlist)
        euphoric.image = tracks[euphoricOrder[0]].map { URL(fileURLWithPath: $0.cover) }
        euphoric.total = euphoricOrder.count
        let shelfSongs = euphoricOrder.compactMap(song)
        // Each shot's song and theme: Stats with Put a Light On first in Blossom, Backups with
        // Seasons in Blood Moon (deep red), the changes with I Melt With You in Measured Dark's
        // deep teal, and the Shelf in Duckbones with Mouthful of Diamonds (yellow on black) turning on
        // the turntable beside the Euphoric crate, its lyric beside the source.
        let views: [(name: String, view: MusicView, connected: Bool, song: String, ghostty: String?)] = [
            ("page-stats", .stats, true, "generationals", nil), ("page-backups", .backups, true, "suki-waterhouse", "Blood Moon"),
            ("page-backup-compare", .backups, true, "modern-english", "Measured Dark"), ("page-shelf", .playing, true, "phantogram", "Duckbones"),
            ("page-music-views-connect", .stats, false, "generationals", nil),
        ]
        if views.contains(where: { $0.ghostty != nil && (only?.contains($0.name) ?? true) }) {
            GhosttyLibrary.shared.load()
            for _ in 0..<100 where GhosttyLibrary.shared.themes.isEmpty { try? await Task.sleep(nanoseconds: 50_000_000) }
        }
        let heartableTint = WidgetOptions.shared.albumTint
        let heartableAscii = WidgetOptions.shared.asciiCover
        WidgetOptions.shared.albumTint = false
        for item in views where only?.contains(item.name) ?? (item.name != "page-music-views-connect") {
            // A neutral name, never the owner's: Backups says "Connected as Listener".
            spotify.setPreview(account: item.connected ? "Listener" : nil, top: item.connected ? top : nil,
                               backups: item.connected ? backups : [], shelf: [(euphoric, shelfSongs)])
            UserDefaults.standard.set(item.view.rawValue, forKey: MusicView.defaultsKey)
            // The page opens on the player unless told to keep its view (as after opening a song from Stats).
            MusicView.keepOnReturn = true
            MusicBackupsView.previewComparison = item.name == "page-backup-compare" ? (backups[0].id, changes) : nil
            // The Shelf moves from the empty Liked Songs to Euphoric before it's captured.
            if item.name == "page-shelf" {
                for _ in 0..<40 where spotify.shelfSource == .liked { try? await Task.sleep(nanoseconds: 50_000_000) }
            }
            WidgetOptions.shared.musicLook = item.name == "page-shelf" ? .shelf : .standard
            // The Shelf's sleeves and record as pictures: the crate of covers and the black vinyl.
            if item.name == "page-shelf" { WidgetOptions.shared.asciiCover = false }
            await clip(item.name, length: 3, output: output, tab: .music, setup: { clock, _, _ in
                scene(matched(item.song), clock)
                if let name = item.ghostty, let found = GhosttyLibrary.shared.theme(named: name) { theme.selectGhostty(found) }
                play(item.song)
                if item.name == "page-shelf" { sing(item.song) }
            }, beats: [])
        }
        WidgetOptions.shared.albumTint = heartableTint
        WidgetOptions.shared.asciiCover = heartableAscii
        MusicBackupsView.previewComparison = nil
        WidgetOptions.shared.musicLook = .standard
        spotify.setPreview(account: nil, top: nil, backups: [])
        UserDefaults.standard.removeObject(forKey: MusicView.defaultsKey)

        // Folio, for the site (`page-folio-*`): the library in Rows with a picture's details (your
        // tags, a note and a like), a hand-laid Board, the viewer, a search finding the words in a
        // picture, Colors and Links. The files are the Folio check renders' (`folioFiles`: the app's
        // scene pictures and drawn text), each read for real first.
        let folioNames: Set<String> = ["page-folio-library", "page-folio-board", "page-folio-viewer",
                                       "page-folio-search", "page-folio-colors", "page-folio-links"]
        if only.map({ !$0.isDisjoint(with: folioNames) }) ?? true {
            let folder = output.appendingPathComponent("folio-files", isDirectory: true)
            let made = folioFiles(in: folder, pictures: scenePictures(in: folder), usingPack: true)
            let library = ShelfStore(basketID: nil)
            await prepareFolio(made, tray: library)
            FolioSwatches.shared.setPreview([])
            await prepareFolioColors(made)
            FolioLinks.shared.setPreview()
            await prepareFolioLinks(site: true)
            func path(_ url: URL?) -> String { url?.standardizedFileURL.path ?? "" }
            FolioIndex.shared.setPreviewMarks([
                path(made.panorama): FolioMark(tags: ["Montana", "road trip"], note: "Going-to-the-Sun Road opens in late June. Start at Logan Pass.", liked: true),
                path(made.poster): FolioMark(tags: ["studio"], liked: true),
                path(made.pictures[1]): FolioMark(liked: true),
                path(made.invoice): FolioMark(tags: ["taxes 2026"], note: "Paid on the 20th"),
            ])
            FolioBoards.shared.setPreview([FolioPlace.tray.key: [
                path(made.panorama): FolioBoardSpot(x: 14, y: 12, width: 230, z: 3),
                path(made.poster): FolioBoardSpot(x: 262, y: 30, width: 92, z: 5),
                path(made.portrait): FolioBoardSpot(x: 196, y: 70, width: 70, z: 6),
                path(made.invoice): FolioBoardSpot(x: 34, y: 104, width: 96, z: 2),
                path(made.pictures[0]): FolioBoardSpot(x: 300, y: 150, width: 120, z: 1),
                // Every file has a spot, so nothing is laid out below the board.
                path(made.pdf): FolioBoardSpot(x: 152, y: 140, width: 58, z: 4),
                path(made.notes): FolioBoardSpot(x: 226, y: 184, width: 52, z: 7),
            ]])
            // The viewer's sharp picture is made first, as the check renders do.
            if let item = library.items.first(where: { $0.url == made.panorama }) {
                _ = await FolioViewerImages.image(for: item.url, modified: library.info[item.id]?.modified, isImage: true)
            }
            let clips = ClipboardMonitor()
            clips.setPreviewEntries(["Meet at the north entrance, 7 pm", "https://www.nps.gov/glac/planyourvisit/conditions.htm", "#F59AB5", "Invoice 1042 paid",
                                     "#2E5E4E", "let total = items.reduce(0, +)", "https://en.wikipedia.org/wiki/Alphonse_Mucha", "Table for four at 7"])
            struct Shot { let name: String; let family: ThemeFamily; var place = FolioPlace.all; var query = ""
                          var view: FolioViewMode? = nil; var select: URL? = nil; var viewer = false }
            let shots = [
                Shot(name: "page-folio-library", family: .blossom, view: .rows, select: made.panorama),
                Shot(name: "page-folio-board", family: .fern, place: .tray, view: .board),
                Shot(name: "page-folio-viewer", family: .midnight, select: made.panorama, viewer: true),
                Shot(name: "page-folio-search", family: .blossom, query: "harbor", view: .rows, select: made.invoice),
                Shot(name: "page-folio-colors", family: .lavender, place: .colors),
                Shot(name: "page-folio-links", family: .autumn, place: .links),
            ]
            // The Nook's Tray is the library already read, so every thumbnail is there from the first frame.
            for shot in shots {
                await clip(shot.name, length: 3, output: output, tab: .tray, tray: library, setup: { clock, _, shelf in
                    scene(shot.family, clock)
                    play("home")
                    let selected = shelf.items.first { $0.url == shot.select }
                    shelf.select(selected)
                    let viewing = shot.viewer ? selected?.id : nil
                    TrayPageView.previewStart = TrayPageView.PreviewStart(clipboard: clips, place: shot.place, query: shot.query,
                                                                          viewing: viewing, view: shot.view)
                }, beats: [])
            }
            TrayPageView.previewStart = nil
            FolioIndex.shared.setPreviewMarks([:])
            FolioBoards.shared.setPreview([:])
            FolioSwatches.shared.setPreview([])
            FolioLinks.shared.setPreview()
            BasketWindowController.shared.setPreviewBaskets([])
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
            let steps: [(AsciiStyle, AsciiScene)] = [(.classic, .pulse), (.blocks, .orb), (.contour, .spiral), (.braille, .cover)]
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
            let host = NSHostingView(rootView: MusicPlayerCard().padding(20).frame(width: 700).background(Color(nsColor: .windowBackgroundColor)))
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

    /// The Tools images, on the site's page colour: the clipboard, a basket of real pictures
    /// and the converter (`MACSPACES_DEMO_KIND=tools`).
    static func runTools(output: URL) async {
        WebsiteDemoProfile.apply()
        defer { WebsiteDemoProfile.finish() }
        ThemeStore.shared.selectFamily(.blossom)
        let page = Color(red: 250 / 255, green: 247 / 255, blue: 241 / 255)
        func shoot<V: View>(_ view: V, size: NSSize, name: String) {
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(page).environment(\.colorScheme, .dark))
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
            bitmap.size = size
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name + ".png"))
            window.contentView = nil
        }
        let monitor = ClipboardMonitor()
        monitor.setPreviewEntries(["Spring workspace\nShare the launch kit", "https://example.com/launch-notes", "#F59AB5", "brew upgrade",
                                   "Meet at the north entrance", "Invoice 1042", "#24161C", "let total = items.reduce(0, +)",
                                   "Weekend plan", "Flight AB 123, seat 14C", "Table for four at 7"])
        if let first = monitor.entries.first { _ = monitor.toggleFavorite(first) }
        let model = ClipboardPopup.shared.model
        model.open(monitor: monitor)
        model.setCursor(0)
        shoot(ClipboardPopupView(model: model).frame(width: 660, height: 440)
                .background(ThemeStore.shared.notch.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8),
              size: NSSize(width: 720, height: 500), name: "clipboard")
        let urls = scenePictures(in: output.appendingPathComponent("Basket files", isDirectory: true))
        // The walkthrough's pages; `MACSPACES_DEMO_ONLY=welcome` stops here.
        if ProcessInfo.processInfo.environment["MACSPACES_DEMO_ONLY"] == "welcome" {
            welcomeChecks { shoot($0, size: $1, name: $2) }
            return
        }
        // The Music page's Shelf, its fallback and its source menu; `MACSPACES_DEMO_ONLY=shelf` stops here.
        if ProcessInfo.processInfo.environment["MACSPACES_DEMO_ONLY"] == "shelf" {
            await shelfChecks(output: output, pictures: urls) { shoot($0, size: $1, name: $2) }
            return
        }
        let store = ShelfStore(basketID: UUID())
        store.setPreviewItems(urls, selectedIndex: 0)
        await store.waitForFileMetadata()
        shoot(BasketPanelView(manager: BasketWindowController.shared, store: store, basket: FileBasket(name: "Weekend trip"))
                .frame(width: 380, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8),
              size: NSSize(width: 440, height: 310), name: "basket")
        // Ask me before sharing's cards; `MACSPACES_DEMO_ONLY=ask` stops here.
        askChecks { shoot($0, size: $1, name: $2) }
        if ProcessInfo.processInfo.environment["MACSPACES_DEMO_ONLY"] == "ask" { return }
        // Studio: reading, takes and voices; `MACSPACES_DEMO_ONLY=studio` stops here.
        studioChecks { shoot($0, size: $1, name: $2) }
        if ProcessInfo.processInfo.environment["MACSPACES_DEMO_ONLY"] == "studio" { return }
        // Settings › Tsukumo › Voice: the models' drawer closed, open with nothing downloaded, and
        // open with models in, a download running and a voice waiting in Studio.
        // `MACSPACES_DEMO_ONLY=voices` stops here.
        if RecordedVoices.shared.isAvailable {
            let voices = RecordedVoices.shared
            UserDefaults.standard.set(true, forKey: WidgetOptions.Keys.recordedVoicesDrawer)
            func voiceCard(_ name: String) {
                shoot(SettingsCard("Voice", systemImage: "waveform") { VoiceSettings(agent: "KemoSabe") }
                        .padding(20).frame(width: 720).background(ThemeStore.shared.settings.surface),
                      size: NSSize(width: 720, height: 420), name: name)
            }
            voices.setPreview(states: [:], voices: [])
            voiceCard("check-voices-empty")
            let gb: Int64 = 1_000_000_000
            let waiting = RecordedVoice(id: UUID(), name: "Host", transcript: "Welcome back to the show.", fingerprint: nil,
                                        seconds: 12, created: Date(), approved: false)
            voices.setPreview(states: ["sorting": .downloaded(bytes: 263_000_000), "standard-small": .downloaded(bytes: 2 * gb),
                                       "standard": .partial(bytes: gb)],
                              voices: [waiting, RecordedVoice(id: UUID(), name: "Narrator", transcript: "Welcome back to the show.",
                                                              fingerprint: nil, seconds: 20, created: Date(), consent: "mine")],
                              job: RecordedVoices.Job(kind: .download("standard"), stage: "Downloading", fraction: 0.4))
            voiceCard("check-voices-saved")
            voices.setPreview(states: [:], voices: [])
            UserDefaults.standard.set(false, forKey: WidgetOptions.Keys.recordedVoicesDrawer)
            voiceCard("check-voices-closed")
        }
        if ProcessInfo.processInfo.environment["MACSPACES_DEMO_ONLY"] == "voices" { return }

        // KemoSabe in felt and glass, in four palettes, its repaints made first; `MACSPACES_DEMO_ONLY=glass` stops here.
        let palettes = ["apricot", "lavender", "cherry", "midnight"]
        for id in palettes {
            for glass in [0.0, 1.0] {
                let look = KemoSabeLook(AgentPalette.named(id), glass: glass)
                _ = await KemoSabeArt.make(glass > 0.5 ? .glass : .felt, look: look, small: true)
            }
        }
        shoot(VStack(spacing: 8) {
            ForEach([0.0, 1.0], id: \.self) { glass in
                HStack(spacing: 8) {
                    ForEach(palettes, id: \.self) { id in
                        KemoSabeFace(mood: .idle, size: 92, look: KemoSabeLook(AgentPalette.named(id), glass: glass), still: true)
                    }
                }
            }
        }.padding(16).background(ThemeStore.shared.notch.surface), size: NSSize(width: 432, height: 232), name: "check-kemosabe-glass-levels")
        if ProcessInfo.processInfo.environment["MACSPACES_DEMO_ONLY"] == "glass" { return }
        // The Agent card's theme list, KemoSabe's glass and motion, Wisp in glass; `MACSPACES_DEMO_ONLY=agent` stops here.
        await agentPanelChecks { shoot($0, size: $1, name: $2) }
        if ProcessInfo.processInfo.environment["MACSPACES_DEMO_ONLY"] == "agent" { return }
        await folioChecks(output: output, pictures: urls) { shoot($0, size: $1, name: $2) }
        // `MACSPACES_DEMO_ONLY=folio` stops after Folio's checks, for a quick look at the page.
        if ProcessInfo.processInfo.environment["MACSPACES_DEMO_ONLY"] == "folio" { return }
        converterReel(output: output)

        // Checks only, never published: what this release changed, drawn here rather than on GitHub.
        let theme = ThemeStore.shared
        theme.selectFamily(.fern)
        let songs = (1...50).map { SpotifyLibrary.Song(title: "A rather long song title \($0)", artists: "Artist \($0)", album: "Album", image: nil, link: nil) }
        var top = SpotifyLibrary.Top(fetched: Date())
        for range in SpotifyLibrary.Range.allCases { top.songs[range.rawValue] = songs }
        SpotifyLibrary.shared.setPreview(account: "sample", top: top, backups: [])
        let pageSize = NSSize(width: 580, height: 300)
        shoot(MusicStatsView().frame(width: pageSize.width, height: pageSize.height + MusicStatsCaptionBar.panelGrowth)
                .background(theme.notch.surface).foregroundStyle(theme.nookForeground),
              size: NSSize(width: pageSize.width, height: pageSize.height + MusicStatsCaptionBar.panelGrowth), name: "check-stats")
        shoot(MusicBackupsView().frame(width: pageSize.width, height: pageSize.height)
                .background(theme.notch.surface).foregroundStyle(theme.nookForeground),
              size: pageSize, name: "check-backups")
        UserDefaults.standard.set(true, forKey: WidgetOptions.Keys.closedNotchDrawer)
        shoot(ClosedNotchCard().padding(20).frame(width: 720, height: 620).background(theme.settings.surface),
              size: NSSize(width: 720, height: 620), name: "check-closed-notch")
        let shelfSongs = (0..<9).map { index -> SpotifyLibrary.Song in
            var song = songs[index % songs.count]
            song.image = urls[index % urls.count]
            return song
        }
        await shelfChecks(output: output, pictures: urls) { shoot($0, size: $1, name: $2) }
        UserDefaults.standard.set(WispCharacter.kemosabe.rawValue, forKey: WidgetOptions.Keys.wispCharacter)
        shoot(KemoSabeFace(mood: .idle, size: 92).padding(20).background(theme.notch.surface), size: NSSize(width: 132, height: 132), name: "check-kemosabe")
        shoot(KemoSabeFace(mood: .idle, size: 92, look: .glass).padding(20).background(theme.notch.surface), size: NSSize(width: 132, height: 132), name: "check-kemosabe-glass")
        // A few palettes, and the thinking pose in Apricot and Glass.
        for id in ["lavender", "ink", "moss", "paper"] {
            shoot(KemoSabeFace(mood: .idle, size: 92, look: KemoSabeLook(AgentPalette.named(id))).padding(20).background(theme.notch.surface), size: NSSize(width: 132, height: 132), name: "check-kemosabe-\(id)")
        }
        shoot(KemoSabeFace(mood: .thinking, size: 92).padding(20).background(theme.notch.surface), size: NSSize(width: 132, height: 132), name: "check-kemosabe-thinking")
        shoot(KemoSabeFace(mood: .thinking, size: 92, look: .glass).padding(20).background(theme.notch.surface), size: NSSize(width: 132, height: 132), name: "check-kemosabe-glass-thinking")
        shoot(TsukumoSettingsPane().frame(width: 700, height: 900).background(ThemeStore.shared.settings.surface),
              size: NSSize(width: 700, height: 900), name: "check-tsukumo-settings")
        welcomeChecks { shoot($0, size: $1, name: $2) }
        // KemoSabe picked: the colours as theme cards, Lavender at half glass, then Custom with its pickers.
        UserDefaults.standard.set("lavender", forKey: WidgetOptions.Keys.agentPalette)
        UserDefaults.standard.set(0.5, forKey: WidgetOptions.Keys.agentGlass)
        shoot(TsukumoSettingsPane().frame(width: 700, height: 1100).background(ThemeStore.shared.settings.surface),
              size: NSSize(width: 700, height: 1100), name: "check-kemosabe-looks")
        UserDefaults.standard.set(AgentPalette.custom.id, forKey: WidgetOptions.Keys.agentPalette)
        UserDefaults.standard.set("BFE3F5", forKey: WidgetOptions.Keys.agentCustomBody)
        UserDefaults.standard.set("2F5C8A", forKey: WidgetOptions.Keys.agentCustomFace)
        UserDefaults.standard.removeObject(forKey: WidgetOptions.Keys.agentGlass)
        shoot(TsukumoSettingsPane().frame(width: 700, height: 1100).background(ThemeStore.shared.settings.surface),
              size: NSSize(width: 700, height: 1100), name: "check-kemosabe-custom")
        // Wisp picked, in Apricot: its eyes take the palette.
        UserDefaults.standard.set(WispCharacter.wisp.rawValue, forKey: WidgetOptions.Keys.wispCharacter)
        UserDefaults.standard.set(AgentPalette.apricot.id, forKey: WidgetOptions.Keys.agentPalette)
        shoot(TsukumoSettingsPane().frame(width: 700, height: 1100).background(ThemeStore.shared.settings.surface),
              size: NSSize(width: 700, height: 1100), name: "check-agent-wisp-colours")
        for key in [WidgetOptions.Keys.agentPalette, WidgetOptions.Keys.agentCustomBody, WidgetOptions.Keys.agentCustomFace,
                    WidgetOptions.Keys.kemoSabeLook, WidgetOptions.Keys.wispCharacter] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // KemoSabe, the gateway: Settings with Claude and sharing on, then the Sarah question in the chat.
        UserDefaults.standard.set(WispProvider.claude.rawValue, forKey: WispProvider.key)
        UserDefaults.standard.set("Never share anything about my health.", forKey: WidgetOptions.Keys.gatewayRules)
        shoot(TsukumoSettingsPane().frame(width: 700, height: 900).background(ThemeStore.shared.settings.surface),
              size: NSSize(width: 700, height: 900), name: "check-gateway-settings")
        let wisp = WispModel.shared
        wisp.previewEngine = WispEngine(name: "Claude", detail: "", isModel: true, symbol: "key.horizontal", partner: .claude)
        wisp.setPreview([
            WispMessage(role: .user, text: "Can Sarah come over tonight?"),
            WispMessage(role: .shared, text: "Claude asked KemoSabe when you're free tonight → Free after 7:00\u{202F}PM tonight."),
            WispMessage(role: .wisp, text: "You're free after 7, so tonight works. Want a reminder to tidy up at 6:30?", from: .claude),
        ], mood: .idle)
        shoot(WispPage(model: wisp, onEditingChanged: { _ in }).padding(12).frame(width: 640, height: 300)
                .background(theme.notch.surface).foregroundStyle(theme.nookForeground),
              size: NSSize(width: 640, height: 300), name: "check-gateway-chat")
        // The Sarah demo's last frame, in KemoSabe's Coral theme, as the site video ends.
        ThemeStore.shared.selectFamily(.kemosabe)
        UserDefaults.standard.set(WispCharacter.kemosabe.rawValue, forKey: WidgetOptions.Keys.wispCharacter)
        wisp.setPreview([
            WispMessage(role: .user, text: "Can Sarah come over tonight?"),
            WispMessage(role: .shared, text: "Claude asked KemoSabe when you're free tonight → Free after 7:00\u{202F}PM tonight."),
            WispMessage(role: .wisp, text: "You're free after 7, so Sarah can come over tonight. Want a reminder to tidy up at 6:30?", from: .claude),
        ], mood: .idle)
        shoot(WispPage(model: wisp, onEditingChanged: { _ in }).padding(12).frame(width: 640, height: 300)
                .background(ThemeStore.shared.notch.surface).foregroundStyle(ThemeStore.shared.nookForeground),
              size: NSSize(width: 640, height: 300), name: "check-kemosabe-sarah")
        // A rule denial, for the denial demo: the ask line says plainly that KemoSabe didn't share,
        // built the way the chat builds it, and Claude carries on without it.
        let health = GatewayAsk.other("does the user have a doctor appointment this week?")
        let denial = GatewayAsk.chatLine(service: WispProvider.claude.title, agent: WispCharacter.kemosabe.title, phrase: health.phrase, answer: nil)
        precondition(denial.hasSuffix("→ KemoSabe didn't share that."), "A rule denial reads as a plain line in the chat")
        wisp.setPreview([
            WispMessage(role: .user, text: "Should I move my workout for a doctor's appointment this week?"),
            WispMessage(role: .withheld, text: denial),
            WispMessage(role: .wisp, text: "KemoSabe kept that private, so I can't see your appointments. Tell me the day and I'll suggest a new workout time.", from: .claude),
        ], mood: .idle)
        shoot(WispPage(model: wisp, onEditingChanged: { _ in }).padding(12).frame(width: 640, height: 300)
                .background(ThemeStore.shared.notch.surface).foregroundStyle(ThemeStore.shared.nookForeground),
              size: NSSize(width: 640, height: 300), name: "check-gateway-denial")
        UserDefaults.standard.removeObject(forKey: WidgetOptions.Keys.wispCharacter)
        ThemeStore.shared.selectFamily(.blossom)
        wisp.setPreview([], mood: .idle)
        wisp.previewEngine = nil
        UserDefaults.standard.removeObject(forKey: WispProvider.key)
        UserDefaults.standard.removeObject(forKey: WidgetOptions.Keys.gatewayRules)
        for (family, name) in [(ThemeFamily.midnight, "midnight"), (.everforest, "everforest")] {
            ThemeStore.shared.selectFamily(family)
            let settings = ThemeStore.shared.settings
            shoot(TapeSettingsPane().frame(width: 700, height: 300).background(settings.surface),
                  size: NSSize(width: 700, height: 300), name: "check-tape-off-\(name)")
            let preview = TapeController(settings: TapeSettings(), previewOnly: true, permissionCheck: { false }, registerShortcuts: false)
            shoot(TapeSettingsPane(previewController: preview).frame(width: 700, height: 1500).background(settings.surface),
                  size: NSSize(width: 700, height: 1500), name: "check-tape-on-\(name)")
            for page in [SettingsDestination.heartable, .folio] {
                SettingsNavigationModel.shared.open(page)
                shoot(SettingsView().frame(width: 1000, height: 760), size: NSSize(width: 1000, height: 760),
                      name: "check-settings-\(page.rawValue)-\(name)")
            }
        }
        ThemeStore.shared.selectFamily(.blossom)
        func backupSong(_ song: SpotifyLibrary.Song, _ playlist: String) -> SpotifyBackupSong {
            SpotifyBackupSong(title: song.title, artists: song.artists, album: song.album, isrc: "", link: "", playlist: playlist)
        }
        let sample = SpotifyBackupDiff(current: Array(shelfSongs.prefix(3)).map { backupSong($0, SpotifyBackupDiff.likedSongs) } + [backupSong(shelfSongs[3], "Road trip")],
                                       previous: [backupSong(shelfSongs[4], SpotifyBackupDiff.likedSongs), backupSong(shelfSongs[5], "Road trip")])
        shoot(BackupChangesCard(title: "Today, 9:41 AM, since Oct 30, 5:04 PM", difference: sample, problem: nil, onBack: {})
                .frame(width: 360, height: 260).padding(14)
                .background(theme.notch.surface).foregroundStyle(theme.nookForeground),
              size: NSSize(width: 388, height: 288), name: "check-changes")
        shoot(VStack(alignment: .leading, spacing: 10) {
            MusicViewButtons(nowPlaying: AppServices.shared.nowPlaying).padding(4)
                .background(Capsule().fill(theme.nookForeground.opacity(0.08)))
            MusicPageHeader("Stats") { EmptyView() }
        }
        .padding(20).frame(width: 420, height: 220, alignment: .topLeading)
        .background(theme.notch.surface).foregroundStyle(theme.nookForeground),
              size: NSSize(width: 420, height: 220), name: "check-heartable")
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
                Color(red: 250 / 255, green: 247 / 255, blue: 241 / 255)
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

    typealias Beat = (Double, (Clock, NotchViewModel, ShelfStore) -> Void)

    /// Renders one clip with the Nook already open on `tab`.
    static var only: Set<String>? {
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

    /// `stageView` draws the whole stage in place of the open Nook (the Tape video's screen of windows).
    /// `rendered` draws the clip frame by frame from the window's own drawing at a fixed rate, also
    /// in a local run (which otherwise records the window live), for clips a live recording can't
    /// keep up with. The frames land in `clip-<name>`, and the export script makes the movie.
    /// `onScreen` puts a drawn clip's window on the screen (off it, the display link that steps
    /// SwiftUI's animations stops, so the Nook's open and close would cut); `costFactor` is how
    /// much slower than a measured frame time runs, more for a clip whose busiest page comes later.
    static func clip(_ name: String, length: Double, output: URL, tab: NotchTab, tray: ShelfStore? = nil,
                             rendered: Bool = false, onScreen: Bool = false, costFactor: Double = 1.5,
                             stageView: ((Clock) -> AnyView)? = nil,
                             setup: (Clock, NotchViewModel, ShelfStore) -> Void, beats: [Beat]) async {
        guard only?.contains(name) ?? true else { return }
        // `MACSPACES_DEMO_RENDERED=1` draws every clip frame by frame: a check that needs no Screen
        // Recording or unlocked desktop (no Metal shaders, so never for published stills).
        let rendered = rendered || ProcessInfo.processInfo.environment["MACSPACES_DEMO_RENDERED"] == "1"
        // The flower scenes' Core Animation layers draw nothing in this scaled stage; their
        // Canvas draws the same photo and petals, as the other scenes do.
        ThemeMotifView.flowersUseCoreAnimation = false
        defer { ThemeMotifView.flowersUseCoreAnimation = true }
        // Drawn frames have no Metal: the photo scenes' breeze is off so the scene still shows.
        if rendered { ThemeMotifView.breezeUsesShader = false }
        defer { ThemeMotifView.breezeUsesShader = true }
        let settings = NookSettings.shared
        let savedDock = settings.dockApps
        // Every capture has the same dock (the song plays from Spotify, so Music adds no playlist button).
        if tab != .nook, !savedDock.contains(tab) { settings.dockApps = savedDock + [tab] }
        defer { settings.dockApps = savedDock }
        let services = AppServices.shared
        let frames = output.appendingPathComponent("clip-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: frames)
        try! FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let shelf = tray ?? ShelfStore(basketID: UUID())
        let model = WebsiteDemoProfile.model(availableWidth: 1512, shelf: shelf)
        model.selectedTab = tab
        model.state = .expanded
        model.isPinned = true
        let clock = Clock()
        setup(clock, model, shelf)
        let local = ProcessInfo.processInfo.environment["MACSPACES_DEMO_LOCAL"] == "1"
        let screen = NSScreen.main ?? NSScreen.screens.first
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 900)
        // Twice this is the exported 1640 px wide, so the recording is never scaled up.
        let previewWidth = min(stage.width, area.width * 0.6)
        let previewScale = local ? previewWidth / stage.width : 1
        let viewport = CGSize(width: stage.width * previewScale, height: stage.height * previewScale)
        let host = NSHostingView(rootView: (stageView?(clock) ?? AnyView(ClipStage(model: model, clock: clock)))
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
            } else if onScreen {
                window.ignoresMouseEvents = true
                window.isReleasedWhenClosed = false
                let frame = screen?.frame ?? area
                window.setFrameOrigin(NSPoint(x: frame.minX, y: frame.maxY - viewport.height))
                window.orderFrontRegardless()
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
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            guard model.state == .expanded else { fatalError("Demo panel closed before capture: \(name)") }

        } else {
            RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        }

        if local, !rendered {
            await recordLocal(name, length: max(3, length), output: output, window: window,
                        clock: clock, model: model, shelf: shelf, beats: beats)
            return
        }
        func frame() -> NSBitmapImageRep? {
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            // Always 2x (1640×940), also on a Mac without a Retina screen, such as CI's.
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(stage.width * 2), pixelsHigh: Int(stage.height * 2),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return bitmap
        }
        let fps = WebsiteDemo234.fps
        var scale = WebsiteDemo234.timeScale
        if rendered {
            // Time slows so every frame is drawn before the next is due, as the Agents video does.
            var costs: [Double] = []
            for _ in 0..<5 {
                let began = Date()
                _ = frame()?.representation(using: .png, properties: [:])
                costs.append(Date().timeIntervalSince(began))
            }
            let cost = costs.sorted()[costs.count / 2]
            scale = min(90, max(scale, 8, (cost * fps * costFactor).rounded(.up)))
            print("Clip \(name): a frame takes \(Int(cost * 1000)) ms; time runs \(Int(scale))x slower at \(Int(fps)) fps"); fflush(stdout)
        }
        let writer = DispatchQueue(label: "clip-frame-writer", qos: .utility, attributes: .concurrent)
        let inFlight = DispatchSemaphore(value: 6)
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
            RunLoop.main.run(until: start.addingTimeInterval(t * scale))
            guard let bitmap = frame() else { continue }
            let url = frames.appendingPathComponent(String(format: "f%05d.png", n))
            inFlight.wait()
            group.enter()
            writer.async { try? bitmap.representation(using: .png, properties: [:])?.write(to: url); inFlight.signal(); group.leave() }
        }
        group.wait()
        if rendered { print("Clip \(name): \(Int(length * fps)) frames drawn in \(frames.path)"); fflush(stdout) }
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
                // The website's own background, so the Nook sits straight on the page with no
                // box around it, and the theme stays inside the Nook, as on a real Mac.
                if clock.plainStage { Color(red: 250 / 255, green: 247 / 255, blue: 241 / 255) }
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

#if DEBUG
extension WebsiteDemoClips {
    /// Checks only: Ask me before sharing (`GatewayApprovalCard`) in Midnight and Everforest. The
    /// Wisp page with two cards waiting in one turn (check-ask-page-<theme>), one card alone as it
    /// looks focused and not (check-ask-card-<theme>), a long draft (check-ask-long-<theme>), the
    /// card answered both ways (check-ask-answered-<theme>), and the chat card with it on.
    @MainActor
    static func askChecks(shoot: (AnyView, NSSize, String) -> Void) {
        let theme = ThemeStore.shared, wisp = WispModel.shared, defaults = UserDefaults.standard
        let was = theme.family
        defaults.set(WispProvider.claude.rawValue, forKey: WispProvider.key)
        defaults.set(true, forKey: WidgetOptions.Keys.gatewayAskFirst)
        wisp.previewEngine = WispEngine(name: "Claude", detail: "", isModel: true, symbol: "key.horizontal", partner: .claude)
        let tonight = GatewayApproval(service: "Claude", question: "free tonight", draft: "Free after 7:00\u{202F}PM tonight.")
        let due = GatewayApproval(service: "Claude", question: "reminders due", draft: "Due: Renew passport, Book the dentist.")
        let long = GatewayApproval(service: "Claude", question: "events saturday",
                                   draft: "Saturday: Brunch with Jamie at 10:30\u{202F}AM, Farmers market (all day), Climbing at 2:00\u{202F}PM, Dinner at Lucia's at 7:30\u{202F}PM.")
        let ask = WispMessage(role: .user, text: "Can Sarah come over tonight? And what's left on my list?")
        func card(_ approval: GatewayApproval) -> WispMessage { WispMessage(role: .approval, text: approval.draft, approval: approval) }
        func page(_ name: String) {
            shoot(AnyView(WispPage(model: wisp, onEditingChanged: { _ in }).padding(12).frame(width: 640, height: 320)
                    .background(theme.notch.surface).foregroundStyle(theme.nookForeground)),
                  NSSize(width: 640, height: 320), name)
        }
        for (name, family) in [("midnight", ThemeFamily.midnight), ("everforest", .everforest)] {
            theme.selectFamily(family)
            wisp.setPreview([ask, card(tonight), card(due)], mood: .thinking)
            page("check-ask-page-\(name)")
            shoot(AnyView(VStack(alignment: .leading, spacing: 10) {
                GatewayApprovalCard(card: tonight, focused: true) { _ in }
                GatewayApprovalCard(card: due, focused: false) { _ in }
            }.frame(width: 420).padding(16).background(theme.notch.surface)), NSSize(width: 452, height: 300), "check-ask-card-\(name)")
            wisp.setPreview([WispMessage(role: .user, text: "Am I around Saturday?"), card(long)], mood: .thinking)
            page("check-ask-long-\(name)")
            wisp.setPreview([ask, WispMessage(role: .shared, text: tonight.chatLine(.share).text),
                             WispMessage(role: .notice, text: due.chatLine(.decline).text),
                             WispMessage(role: .wisp, text: "You're free after 7, so tonight works. Want a reminder to tidy up at 6:30?", from: .claude)], mood: .idle)
            page("check-ask-answered-\(name)")
        }
        theme.selectFamily(was)
        shoot(AnyView(TsukumoSettingsPane().frame(width: 700, height: 900).background(theme.settings.surface)),
              NSSize(width: 700, height: 900), "check-ask-settings")
        wisp.setPreview([], mood: .idle)
        wisp.previewEngine = nil
        for key in [WispProvider.key, WidgetOptions.Keys.gatewayCalendar, WidgetOptions.Keys.gatewayReminders, WidgetOptions.Keys.gatewayAskFirst] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Checks only, reported in check-folio-watch.txt: watching a real folder takes only files that
    /// arrive after it's added, never a browser's partial download, and removing the folder
    /// forgets its list without touching a file.
    @MainActor
    static func watchedFolderCheck(output: URL) async {
        let fm = FileManager.default
        let live = output.appendingPathComponent("Watched/Live", isDirectory: true)
        let arrived = live.appendingPathComponent("Arrived.txt"), already = live.appendingPathComponent("Already here.txt")
        try? fm.removeItem(at: live)
        try? fm.createDirectory(at: live, withIntermediateDirectories: true)
        try? Data("here first".utf8).write(to: already)
        guard let id = FolioWatchedFolders.shared.watchForCheck(live) else { return }
        let store = FolioWatchedFolders.shared.store(for: id)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let started = Date()
        try? Data("arrived".utf8).write(to: arrived)
        try? Data("half".utf8).write(to: live.appendingPathComponent("Movie.mp4.crdownload"))
        for _ in 0..<60 where !store.items.contains(where: { $0.name == "Arrived.txt" }) {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        var lines = [String(format: "taken after %.1f s: ", Date().timeIntervalSince(started)) + store.items.map(\.name).joined(separator: ", ")]
        lines.append("arrived taken: \(store.items.contains { $0.name == "Arrived.txt" })")
        lines.append("already-there ignored: \(!store.items.contains { $0.name == "Already here.txt" })")
        lines.append("partial ignored: \(!store.items.contains { $0.name.hasSuffix(".crdownload") })")
        FolioWatchedFolders.shared.remove(id)
        let forgotten = FolioWatchedFolders.shared.folders.isEmpty && !FolioLibrary.holds(arrived.standardizedFileURL.path)
        lines.append("folder forgotten: \(forgotten)")
        lines.append("files untouched: \(fm.fileExists(atPath: arrived.path) && fm.fileExists(atPath: already.path))")
        try? lines.joined(separator: "\n").write(to: output.appendingPathComponent("check-folio-watch.txt"), atomically: true, encoding: .utf8)
    }

    /// Checks only: the Folio page in each place, searching, finding similar pictures, with a
    /// selection's details and empty, in a light and a dark theme, Midnight and Everforest,
    /// once the files have been read, and what Vision read from each (check-folio.txt). Every
    /// file is made here from the app's own scene pictures and drawn text.
    @MainActor
    static func folioChecks(output: URL, pictures: [URL], shoot: (AnyView, NSSize, String) -> Void) async {
        guard pictures.count >= 3 else { return }
        let files = output.appendingPathComponent("Basket files", isDirectory: true)
        let made = folioFiles(in: files, pictures: pictures)
        let invoice = made.invoice, poster = made.poster, pdf = made.pdf, notes = made.notes
        let panorama = made.panorama, portrait = made.portrait, lavender = made.lavender
        func cut(_ asset: String, _ aspect: CGFloat, _ name: String) -> URL? { cutScene(asset, aspect, name, in: files) }

        let tray = ShelfStore(basketID: nil)
        await prepareFolio(made, tray: tray)
        let all = tray.items.map(\.url) + BasketWindowController.shared.loadedStores.flatMap { $0.items.map(\.url) }
        let report = Array(Set(all)).sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url -> String in
            let record = FolioIndex.shared.record(for: url)
            return "\(url.lastPathComponent): tags \(record?.tags ?? []) · print \(record?.print != nil) · text \((record?.text ?? "").replacingOccurrences(of: "\n", with: " / "))"
        }.joined(separator: "\n")
        try? report.write(to: output.appendingPathComponent("check-folio.txt"), atomically: true, encoding: .utf8)

        let clips = ClipboardMonitor()
        clips.setPreviewEntries(["Meet at the north entrance, 7 pm", "https://example.com/launch-notes", "#F59AB5", "Invoice 1042 paid",
                                 "#2E5E4E", "let total = items.reduce(0, +)", "https://harbor.example.org/tickets", "Table for four at 7"])
        let theme = ThemeStore.shared
        let basket = BasketWindowController.shared.baskets.first?.id
        // No tags, notes or likes of a previous run; the marks checks below add their own.
        FolioIndex.shared.setPreviewMarks([:])
        func page(_ name: String, place: FolioPlace = .all, query: String = "", similar: URL? = nil, store: ShelfStore? = nil,
                  clipboard: ClipboardMonitor? = nil, viewing: UUID? = nil, view: FolioViewMode = .rows) {
            shoot(AnyView(TrayPageView(tray: store ?? tray, isDropTargeted: .constant(false), clipboard: clipboard ?? clips,
                                       place: place, query: query, similarTo: similar, viewing: viewing, view: view)
                    .frame(width: 580, height: 280).padding(12)
                    .background(theme.notch.surface).foregroundStyle(theme.nookForeground)
                    .environment(\.colorScheme, theme.notch.colorScheme).tint(theme.notch.accent)),
                  NSSize(width: 604, height: 304), "check-folio-" + name)
        }
        for family in [ThemeFamily.macspaces, .frost, .midnight, .everforest] {
            theme.selectFamily(family)
            let look = family == .macspaces ? "" : "-" + family.rawValue
            tray.select(nil)
            page("all" + look)
            if let item = tray.items.first { tray.select(item) }
            page("details" + look)
            tray.select(nil)
            if family == .macspaces || family == .frost { page("clipboard" + look, place: .clipboard) }
        }
        theme.selectFamily(.macspaces)
        page("tray", place: .tray)
        if let basket { page("basket", place: .basket(basket)) }
        page("pictures", place: .smart(.pictures))
        page("with-text", place: .smart(.withText))
        page("search", query: "harbor")
        page("search-elsewhere", place: .basket(BasketWindowController.shared.baskets.last?.id ?? UUID()), query: "invoice")
        page("similar", similar: pictures[2])
        if let item = tray.items.first(where: { $0.url == panorama }) { tray.select(item) }
        page("details-picture")
        tray.select(nil)

        // The views: each in the default theme and Frost, the list and a board with a selection,
        // and a board laid out by hand (then tidied).
        for family in [ThemeFamily.macspaces, .frost] {
            theme.selectFamily(family)
            let look = family == .macspaces ? "" : "-" + family.rawValue
            for mode in FolioViewMode.allCases { page("view-" + mode.rawValue + look, view: mode) }
        }
        theme.selectFamily(.macspaces)
        if let item = tray.items.first(where: { $0.url == panorama }) {
            tray.select(item)
            page("view-list-selected", view: .list)
            page("view-columns-selected", view: .columns)
            tray.select(nil)
        }
        page("view-list-tray", place: .tray, view: .list)
        func spotPath(_ url: URL?) -> String { url?.standardizedFileURL.path ?? "" }
        FolioBoards.shared.setPreview([FolioPlace.tray.key: [
            spotPath(panorama): FolioBoardSpot(x: 14, y: 12, width: 230, z: 3),
            spotPath(poster): FolioBoardSpot(x: 262, y: 30, width: 92, z: 5),
            spotPath(portrait): FolioBoardSpot(x: 196, y: 70, width: 70, z: 6),
            spotPath(invoice): FolioBoardSpot(x: 20, y: 112, width: 120, z: 2),
            spotPath(pictures[0]): FolioBoardSpot(x: 300, y: 150, width: 120, z: 1),
        ]])
        page("view-board-placed", place: .tray, view: .board)
        if let item = tray.items.first(where: { $0.url == poster }) {
            tray.select(item)
            page("view-board-placed-selected", place: .tray, view: .board)
            tray.select(nil)
        }
        theme.selectFamily(.midnight)
        page("view-board-placed-midnight", place: .tray, view: .board)
        theme.selectFamily(.macspaces)
        FolioBoards.shared.setPreview([:])
        page("view-board-tidy", place: .tray, view: .board)
        page("view-infinity-search", query: "harbor", view: .infinity)

        // The Trash: references removed 2, 12 and 27 days ago (one from a basket), a selection's
        // details with Put Back, the list, Frost and Midnight, then empty.
        let moodboard = BasketWindowController.shared.baskets.last.map { "basket:" + $0.id.uuidString } ?? "tray"
        FolioTrash.shared.setPreview([(url: poster, daysAgo: 2, from: "tray"), (url: lavender ?? poster, daysAgo: 12, from: moodboard),
                                      (url: notes, daysAgo: 27, from: "tray")])
        await FolioTrash.shared.store.waitForFileMetadata()
        page("trash", place: .trash)
        if let item = FolioTrash.shared.store.items.dropFirst().first {
            FolioTrash.shared.store.select(item)
            page("trash-details", place: .trash)
            FolioTrash.shared.store.select(nil)
        }
        page("trash-list", place: .trash, view: .list)
        for family in [ThemeFamily.frost, .midnight] {
            theme.selectFamily(family)
            page("trash-" + family.rawValue, place: .trash)
        }
        theme.selectFamily(.macspaces)
        FolioTrash.shared.setPreview([])
        page("trash-empty", place: .trash)

        // Colors: a pasted palette, a colour from the picker and a picture's Save Colors (read
        // for real, off the main thread), in the default theme, Frost and Midnight, a search and
        // empty. check-folio-colors.txt lists what was saved.
        FolioSwatches.shared.setPreview([])
        page("colors-empty", place: .colors)
        await prepareFolioColors(made)
        try? FolioSwatches.shared.book.swatches.map { "\($0.hex) \(FolioHex.name($0.hex)) from \($0.source)" }.joined(separator: "\n")
            .write(to: output.appendingPathComponent("check-folio-colors.txt"), atomically: true, encoding: .utf8)
        page("colors", place: .colors)
        for family in [ThemeFamily.frost, .midnight] {
            theme.selectFamily(family)
            page("colors-" + family.rawValue, place: .colors)
        }
        theme.selectFamily(.macspaces)
        page("colors-search", place: .colors, query: "orange")
        FolioSwatches.shared.setPreview([])

        // Links: four addresses through a stubbed fetcher (never the network): a page with a
        // title and preview picture, one with only a title, a picture's own address, and one that
        // times out. check-folio-links.txt lists what each card got.
        FolioLinks.shared.setPreview()
        page("links-empty", place: .links)
        await prepareFolioLinks()
        try? FolioLinks.shared.book.links.map { "\($0.address): title \u{201C}\($0.title)\u{201D} · preview \($0.preview != nil) · fetched \($0.fetched)" }
            .joined(separator: "\n").write(to: output.appendingPathComponent("check-folio-links.txt"), atomically: true, encoding: .utf8)
        page("links", place: .links)
        for family in [ThemeFamily.frost, .midnight] {
            theme.selectFamily(family)
            page("links-" + family.rawValue, place: .links)
        }
        theme.selectFamily(.macspaces)
        page("links-search", place: .links, query: "harbor")
        FolioLinks.shared.setPreview()

        // Your own tags, a note and likes: details, the Liked folder, a search that finds a tag
        // and a note, and the full-size viewer on a picture and on a PDF.
        func path(_ url: URL?) -> String { url?.standardizedFileURL.path ?? "" }
        FolioIndex.shared.setPreviewMarks([
            path(panorama): FolioMark(tags: ["Iceland", "road trip"], note: "Ferry from the north pier at 7:40, then the coast road.", liked: true),
            path(poster): FolioMark(tags: ["studio"], liked: true),
            path(pictures[1]): FolioMark(liked: true),
            path(invoice): FolioMark(tags: ["taxes 2026"], note: "Paid on the 20th"),
        ])
        if let item = tray.items.first(where: { $0.url == panorama }) { tray.select(item) }
        page("details-marks")
        for family in [ThemeFamily.midnight, .everforest] {
            theme.selectFamily(family)
            page("details-marks-" + family.rawValue)
        }
        theme.selectFamily(.macspaces)
        tray.select(nil)
        page("all-liked")
        page("liked", place: .smart(.liked))
        page("search-tag", query: "road trip")
        page("search-note", query: "pier")
        if let item = tray.items.first(where: { $0.url == invoice }), let other = tray.items.first(where: { $0.url == poster }) {
            tray.setSelection([item.id, other.id], focus: item.id)
            page("details-marks-several")
            tray.select(nil)
        }
        // The page waits for nothing while it's drawn, so the viewer's sharp pictures are made first.
        for item in tray.items where [panorama, pdf, notes].contains(item.url) {
            let info = tray.info[item.id]
            _ = await FolioViewerImages.image(for: item.url, modified: info?.modified, isImage: info?.isImage == true)
        }
        if let item = tray.items.first(where: { $0.url == panorama }) {
            tray.select(item)
            page("viewer", viewing: item.id)
            theme.selectFamily(.midnight)
            page("viewer-midnight", viewing: item.id)
            theme.selectFamily(.macspaces)
        }
        if let item = tray.items.first(where: { $0.url == pdf }) {
            tray.select(item)
            page("viewer-pdf", viewing: item.id)
        }
        if let item = tray.items.first(where: { $0.url == notes }) {
            tray.select(item)
            page("viewer-text", viewing: item.id)
        }
        tray.select(nil)
        FolioIndex.shared.setPreviewMarks([:])

        // Watched folders: a folder's new files as a place of its own, an empty one, and the
        // Settings card (empty, then with both).
        let drops = output.appendingPathComponent("Watched/Design drops", isDirectory: true)
        let quiet = output.appendingPathComponent("Watched/Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: drops, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: quiet, withIntermediateDirectories: true)
        let arrivals = [("ThemeAutumn", 1.5, "Cover draft.png"), ("ThemeSnow", 0.75, "Poster B.png"), ("ThemeFern", 1.0, "Leaf study.png")]
            .compactMap { asset, aspect, name -> URL? in
                guard let made = cut(asset, aspect, "watched " + name) else { return nil }
                let url = drops.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.moveItem(at: made, to: url)
                return url
            }
        func settingsCard(_ name: String) {
            shoot(AnyView(FolioSourcesCard().padding(20).frame(width: 720, height: 420, alignment: .top)
                    .background(theme.settings.surface)),
                  NSSize(width: 720, height: 420), "check-folio-" + name)
        }
        FolioWatchedFolders.shared.setPreviewFolders([])
        settingsCard("settings-watched-empty")
        FolioWatchedFolders.shared.setPreviewFolders([(drops, arrivals), (quiet, [])])
        for store in FolioWatchedFolders.shared.loadedStores { await store.waitForFileMetadata() }
        if let folder = FolioWatchedFolders.shared.folders.first {
            page("watched", place: .watched(folder.id))
        }
        if let folder = FolioWatchedFolders.shared.folders.last {
            page("watched-empty", place: .watched(folder.id))
        }
        page("all-watched")
        settingsCard("settings-watched")
        FolioWatchedFolders.shared.setPreviewFolders([])
        await watchedFolderCheck(output: output)
        let empty = ShelfStore(basketID: nil)
        empty.setPreviewItems([])
        BasketWindowController.shared.setPreviewBaskets([])
        let none = ClipboardMonitor()
        none.setPreviewEntries([])
        page("empty", store: empty, clipboard: none)
    }

    /// Three of the app's own scene photos as picture files (never album art), for the basket
    /// image and Folio.
    @MainActor
    static func scenePictures(in folder: URL) -> [URL] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (name, asset) in [("Trail photo.png", "ThemeFern"), ("Lake house.png", "ThemeAutumn"), ("Snow day.png", "ThemeSnow")] {
            let url = folder.appendingPathComponent(name)
            if let data = NSImage(named: asset)?.tiffRepresentation, let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
                try? png.write(to: url); urls.append(url)
            }
        }
        return urls
    }

    /// The Tray still's files from the picture pack (`folioPackFolder`), with your tags and notes on
    /// them, or nil without the pack: the Mucha print as a poster draft, the glacier panorama, the
    /// Hokusai and Hammershøi, a lease summary PDF whose first page reads as one, an invoice scan and a list.
    @MainActor
    static func trayPackFiles(in folder: URL) -> (files: [URL], marks: [String: FolioMark])? {
        func copy(_ pack: String, _ name: String) -> URL? {
            let source = folioPackFolder.appendingPathComponent(pack)
            guard FileManager.default.fileExists(atPath: source.path) else { return nil }
            let url = folder.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
            do { try FileManager.default.copyItem(at: source, to: url) } catch { return nil }
            return url
        }
        guard let poster = copy("poster-mucha-job.jpg", "Poster draft.jpg"),
              let panorama = copy("glacier-panorama.jpg", "Glacier panorama.jpg"),
              let wave = copy("art-great-wave.jpg", "Great wave.jpg"),
              let room = copy("art-hammershoi.jpg", "Music room.jpg") else { return nil }
        let pdf = folder.appendingPathComponent("Lease summary.pdf")
        writeLeasePDF(pdf)
        let scan = writeInvoice(folder.appendingPathComponent("Scan 3.png"))
        let packing = folder.appendingPathComponent("Packing list.txt")
        try? "Packing list\nBoots, rain shell, map, headlamp, film camera".write(to: packing, atomically: true, encoding: .utf8)
        func path(_ url: URL) -> String { url.standardizedFileURL.path }
        let marks: [String: FolioMark] = [
            path(poster): FolioMark(tags: ["print", "studio"], note: "Send to the print shop by Friday, A2 matte.", liked: true),
            path(panorama): FolioMark(tags: ["road trip"], liked: true),
            path(pdf): FolioMark(tags: ["home"], note: "Sign and return by May 20"),
        ]
        return ([poster, panorama, wave, pdf, room, scan, packing], marks)
    }

    /// A lease summary PDF whose first page reads as one: a heading band, the terms in two
    /// columns, and a short paragraph.
    static func writeLeasePDF(_ pdf: URL) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        if let context = CGContext(pdf as CFURL, mediaBox: &box, nil) {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSColor(srgbRed: 0.16, green: 0.27, blue: 0.42, alpha: 1).setFill()
            NSRect(x: 0, y: 712, width: 612, height: 80).fill()
            ("Lease summary" as NSString).draw(at: NSPoint(x: 56, y: 736), withAttributes: [
                .font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.white])
            let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.darkGray]
            let value: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black]
            for (row, (name, text)) in [("Unit", "4B, 210 Harbor Street"), ("Term", "12 months from June 1"), ("Rent", "$1,850 a month"),
                                        ("Deposit", "$1,850, returned in 30 days"), ("Utilities", "Water and heat included")].enumerated() {
                let y = 660 - CGFloat(row) * 34
                (name as NSString).draw(at: NSPoint(x: 56, y: y), withAttributes: label)
                (text as NSString).draw(at: NSPoint(x: 180, y: y), withAttributes: value)
                NSColor(white: 0.85, alpha: 1).setFill(); NSRect(x: 56, y: y - 10, width: 500, height: 1).fill()
            }
            ("Pets are welcome with notice. The building has bike storage and a shared garden on the roof. Renewal is offered two months before the term ends." as NSString)
                .draw(in: NSRect(x: 56, y: 330, width: 500, height: 130), withAttributes: value)
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage(); context.closePDF()
        }
    }

    /// A scanned-looking invoice from a small studio: its name and mark, the number and date, two
    /// lines of work and the total, on warm paper.
    @discardableResult
    static func writeInvoice(_ url: URL) -> URL {
        let image = NSImage(size: NSSize(width: 850, height: 1100), flipped: true) { rect in
            NSColor(srgbRed: 0.985, green: 0.975, blue: 0.955, alpha: 1).setFill(); rect.fill()
            let ink = NSColor(srgbRed: 0.13, green: 0.2, blue: 0.3, alpha: 1)
            ink.setFill(); NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 74, height: 74), xRadius: 16, yRadius: 16).fill()
            ("BH" as NSString).draw(at: NSPoint(x: 84, y: 86), withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .heavy), .foregroundColor: NSColor.white])
            func text(_ string: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ colour: NSColor = .black) {
                (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: colour])
            }
            text("Blue Harbor Studio", 164, 78, 32, .bold, ink)
            text("Photography and design", 164, 120, 20, .regular, .darkGray)
            text("INVOICE", 70, 220, 46, .heavy, ink)
            text("No. 1042", 70, 286, 22, .medium, .darkGray)
            text("March 14, 2026", 560, 286, 22, .medium, .darkGray)
            NSColor(white: 0.8, alpha: 1).setFill(); NSRect(x: 70, y: 360, width: 710, height: 2).fill()
            text("Description", 70, 380, 20, .semibold, .darkGray); text("Amount", 660, 380, 20, .semibold, .darkGray)
            for (row, (item, amount)) in [("Product photography, half day", "$360.00"), ("Retouching, six images", "$120.00")].enumerated() {
                let y = 440 + CGFloat(row) * 56
                text(item, 70, y, 24); text(amount, 660, y, 24)
                NSColor(white: 0.88, alpha: 1).setFill(); NSRect(x: 70, y: y + 42, width: 710, height: 1).fill()
            }
            text("Total due", 440, 600, 28, .bold, ink); text("$480.00", 640, 600, 28, .bold, ink)
            text("Thank you! Payment within 14 days.", 70, 980, 20, .regular, .gray)
            return true
        }
        return writePNG(image, url)
    }

    /// Folio's sample library: drawn text (an invoice scan, a poster), a PDF, a text file, and
    /// scene pictures cut to different shapes, beside the three `scenePictures`.
    struct FolioFiles {
        let invoice: URL, poster: URL, pdf: URL, notes: URL
        let panorama: URL?, portrait: URL?, blossom: URL?, lavender: URL?
        let pictures: [URL]
        var tray: [URL] { [invoice, pictures[0], panorama, pdf, poster, portrait, notes].compactMap { $0 } }
        /// The trail photo is in the Tray and a basket: All Items shows it once.
        var baskets: [(String, [URL])] {
            [("Weekend trip", Array(pictures[1...]) + [pictures[0]]), ("Moodboard", [blossom, lavender].compactMap { $0 })]
        }
    }

    static func writePNG(_ image: NSImage, _ url: URL) -> URL {
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
        return url
    }

    /// A scene picture cut to a shape (width over height).
    @MainActor
    static func cutScene(_ asset: String, _ aspect: CGFloat, _ name: String, in folder: URL) -> URL? {
        guard let source = NSImage(named: asset) else { return nil }
        let size = aspect >= 1 ? NSSize(width: 1200, height: 1200 / aspect) : NSSize(width: 900 * aspect, height: 900)
        let image = NSImage(size: size, flipped: false) { rect in
            let scale = max(rect.width / source.size.width, rect.height / source.size.height)
            let drawn = NSSize(width: source.size.width * scale, height: source.size.height * scale)
            source.draw(in: NSRect(x: (rect.width - drawn.width) / 2, y: (rect.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
            return true
        }
        return writePNG(image, folder.appendingPathComponent(name))
    }

    /// The site's picture pack (public-domain and CC0 photographs and art, outside the repo): named
    /// files in `~/Library/Caches/MacSpaces-demo-pack/folio`, listed with their credits in CREDITS.tsv.
    /// Each is copied under its display name. Without the folder the scene pictures are used.
    static let folioPackFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/MacSpaces-demo-pack/folio", isDirectory: true)

    @MainActor
    static func folioPackFiles(in folder: URL) -> (poster: URL, panorama: URL, portrait: URL, blossom: URL, lavender: URL, pictures: [URL])? {
        func copy(_ pack: String, _ name: String) -> URL? {
            let source = folioPackFolder.appendingPathComponent(pack)
            guard FileManager.default.fileExists(atPath: source.path) else { return nil }
            let url = folder.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
            do { try FileManager.default.copyItem(at: source, to: url) } catch { return nil }
            return url
        }
        guard let poster = copy("poster-mucha-job.jpg", "Poster.jpg"),
              let panorama = copy("glacier-panorama.jpg", "Glacier panorama.jpg"),
              let portrait = copy("portrait-blossom.jpg", "Portrait.jpg"),
              let blossom = copy("blossom.jpg", "Blossom.jpg"),
              let lavender = copy("lavender.jpg", "Lavender field.jpg"),
              let music = copy("art-hammershoi.jpg", "Music room.jpg"),
              let dome = copy("architecture-pantheon.jpg", "Pantheon.jpg"),
              let wave = copy("art-great-wave.jpg", "Great wave.jpg") else { return nil }
        return (poster, panorama, portrait, blossom, lavender, [music, dome, wave])
    }

    @MainActor
    static func folioFiles(in folder: URL, pictures: [URL], usingPack: Bool = false) -> FolioFiles {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func drawn(_ size: NSSize, _ text: String, _ points: CGFloat) -> NSImage {
            NSImage(size: size, flipped: false) { rect in
                NSColor.white.setFill(); rect.fill()
                (text as NSString).draw(in: rect.insetBy(dx: size.width * 0.07, dy: size.height * 0.09),
                                        withAttributes: [.font: NSFont.systemFont(ofSize: points, weight: .semibold), .foregroundColor: NSColor.black])
                return true
            }
        }
        let invoiceText = "INVOICE\nBlue Harbor Studio\nMarch 14, 2026\nTotal due: $480.00"
        let invoice = writePNG(drawn(NSSize(width: 900, height: 600), invoiceText, 64), folder.appendingPathComponent("Scan 3.png"))
        let posterText = "OPEN\nSTUDIO\nNIGHT\n\nFriday 7 pm\nHarbor Hall"
        let poster = writePNG(drawn(NSSize(width: 640, height: 900), posterText, 92), folder.appendingPathComponent("Poster.png"))
        let pdf = folder.appendingPathComponent("Lease summary.pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        if let context = CGContext(pdf as CFURL, mediaBox: &box, nil) {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let lease = "Lease summary\n\nUnit 4B, 210 Harbor Street\nTerm: 12 months from June 1\nRent: $1,850 a month"
            (lease as NSString).draw(in: box.insetBy(dx: 60, dy: 80),
                                     withAttributes: [.font: NSFont.systemFont(ofSize: 26, weight: .regular), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage(); context.closePDF()
        }
        let notes = folder.appendingPathComponent("Packing list.txt")
        try? "Packing list\nBoots, rain shell, map, headlamp".write(to: notes, atomically: true, encoding: .utf8)
        if usingPack, let pack = folioPackFiles(in: folder) {
            // The site's stills: a scanned-looking invoice and a lease summary that reads as one.
            writeInvoice(invoice)
            writeLeasePDF(pdf)
            return FolioFiles(invoice: invoice, poster: pack.poster, pdf: pdf, notes: notes, panorama: pack.panorama,
                              portrait: pack.portrait, blossom: pack.blossom, lavender: pack.lavender, pictures: pack.pictures)
        }
        return FolioFiles(invoice: invoice, poster: poster, pdf: pdf, notes: notes,
                          panorama: cutScene("ThemeGlacier", 2.6, "Glacier panorama.png", in: folder),
                          portrait: cutScene("ThemeDune", 0.66, "Dune portrait.png", in: folder),
                          blossom: cutScene("ThemeBlossom", 1.25, "Blossom.png", in: folder),
                          lavender: cutScene("ThemeLavender", 0.8, "Lavender field.png", in: folder),
                          pictures: pictures)
    }

    /// Puts the files in `tray` and the two baskets, then waits until each is read: its
    /// thumbnail, and what Vision found in it.
    @MainActor
    static func prepareFolio(_ files: FolioFiles, tray: ShelfStore) async {
        tray.setPreviewItems(files.tray, selectedIndex: nil)
        BasketWindowController.shared.setPreviewBaskets(files.baskets)
        await tray.waitForFileMetadata()
        for store in BasketWindowController.shared.loadedStores { await store.waitForFileMetadata() }
        let all = tray.items.map(\.url) + BasketWindowController.shared.loadedStores.flatMap { $0.items.map(\.url) }
        for _ in 0..<400 where all.contains(where: { FolioIndex.shared.record(for: $0) == nil }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Colors: a pasted palette, a colour from the picker and a picture's Save Colors (read for
    /// real, off the main thread).
    @MainActor
    static func prepareFolioColors(_ files: FolioFiles) async {
        _ = FolioDrops.take("#264653, #2A9D8F, #E9C46A, #F4A261, #E76F51")
        FolioSwatches.shared.add(NSColor(srgbRed: 0.96, green: 0.6, blue: 0.71, alpha: 1))
        if let blossom = files.blossom { _ = await FolioSwatches.shared.saveColors(from: blossom) }
    }

    /// Links: four addresses through a stubbed fetcher (never the network): a page with a title
    /// and preview picture, one with only a title, a picture's own address, and one that times out.
    /// For the site, four real pages under their real titles and hosts, each previewed by the pack
    /// picture of what it's about (the Hokusai, Glacier, the Mucha print, the Pantheon's dome);
    /// without the pack, the app's scene pictures stand in.
    @MainActor
    static func prepareFolioLinks(site: Bool = false) async {
        func png(_ asset: String) -> Data {
            guard let image = NSImage(named: asset), let tiff = image.tiffRepresentation else { return Data() }
            return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) ?? Data()
        }
        func packed(_ file: String, else asset: String) -> (String, Data) {
            if let data = try? Data(contentsOf: folioPackFolder.appendingPathComponent(file)) { return ("image/jpeg", data) }
            return ("image/png", png(asset))
        }
        func page(_ title: String, _ image: String) -> (String, Data) {
            ("text/html; charset=utf-8", Data("<html><head><title>\(title)</title><meta property=\"og:title\" content=\"\(title)\"><meta property=\"og:image\" content=\"\(image)\"></head></html>".utf8))
        }
        if site {
            let wave = "https://en.wikipedia.org/wiki/The_Great_Wave_off_Kanagawa", glacier = "https://www.nps.gov/glac/index.htm"
            let mucha = "https://www.muchafoundation.org/en/gallery/themes/theme/advertising-posters/object/job"
            let pantheon = "https://en.wikipedia.org/wiki/Pantheon,_Rome"
            let waveImage = "https://upload.wikimedia.org/wikipedia/commons/0/0a/The_Great_Wave_off_Kanagawa.jpg"
            let glacierImage = "https://www.nps.gov/common/uploads/banner_image/imr/homepage/glac-highline.jpg"
            let muchaImage = "https://www.muchafoundation.org/images/gallery/job-1896.jpg"
            let pantheonImage = "https://upload.wikimedia.org/wikipedia/commons/2/2b/Pantheon_dome_interior.jpg"
            let pages: [String: (String, Data)] = [
                wave: page("The Great Wave off Kanagawa - Wikipedia", waveImage), waveImage: packed("art-great-wave.jpg", else: "ThemeTidal"),
                glacier: page("Glacier National Park (U.S. National Park Service)", glacierImage),
                glacierImage: packed("glacier-panorama.jpg", else: "ThemeGlacier"),
                mucha: page("Job, 1896 | Mucha Foundation", muchaImage), muchaImage: packed("poster-mucha-job.jpg", else: "ThemeAutumn"),
                pantheon: page("Pantheon, Rome - Wikipedia", pantheonImage), pantheonImage: packed("architecture-pantheon.jpg", else: "ThemeSnow"),
            ]
            let realTransport = FolioLinkFetch.transport
            FolioLinkFetch.transport = { request, _ in
                guard let url = request.url, let page = pages[url.absoluteString],
                      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": page.0]) else {
                    throw URLError(.timedOut)
                }
                return (page.1, response)
            }
            FolioLinks.shared.add([pantheon, mucha, glacier, wave].compactMap(URL.init(string:)))
            await FolioLinks.shared.waitForFetches()
            FolioLinkFetch.transport = realTransport
            return
        }
        let tickets = """
            <html><head><title>Tickets</title><meta property="og:title" content="Harbor Hall: Open Studio Night tickets">
            <meta property="og:image" content="/cover.png"></head><body><script>alert(1)</script></body></html>
            """
        let guide = """
            <html><head><meta property="og:title" content="The coast road: a three-day guide">
            <meta property="og:image" content="https://coast.example.com/glacier.png"></head></html>
            """
        let pages: [String: (String, Data)] = [
            "https://harbor.example.org/tickets": ("text/html; charset=utf-8", Data(tickets.utf8)),
            "https://harbor.example.org/cover.png": ("image/png", png("ThemeAutumn")),
            "https://example.com/launch-notes": ("text/html", Data("<html><head><title>Launch notes &amp; plans</title></head></html>".utf8)),
            "https://images.example.net/fern.png": ("image/png", png("ThemeFern")),
            "https://coast.example.com/guide": ("text/html", Data(guide.utf8)),
            "https://coast.example.com/glacier.png": ("image/png", png("ThemeGlacier")),
        ]
        let realTransport = FolioLinkFetch.transport
        FolioLinkFetch.transport = { request, _ in
            guard let url = request.url, let page = pages[url.absoluteString],
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": page.0]) else {
                throw URLError(.timedOut)
            }
            return (page.1, response)
        }
        let addresses = ["https://slow.example.net/article", "https://images.example.net/fern.png", "https://example.com/launch-notes",
                         "https://harbor.example.org/tickets"]
        FolioLinks.shared.add(addresses.compactMap(URL.init(string:)))
        await FolioLinks.shared.waitForFetches()
        FolioLinkFetch.transport = realTransport
    }
}
#endif

#if DEBUG
extension WebsiteDemoClips {
    /// The walkthrough's first page, Heartable's (with its Look picker) and Tape's, as a new
    /// install sees them: `check-welcome-<page>.png`.
    @MainActor static func welcomeChecks(shoot: (AnyView, NSSize, String) -> Void) {
        for page in [WelcomePage.notch, .heartable, .tape] {
            WelcomeWindow.shared.page = page
            shoot(AnyView(WelcomeView(model: WelcomeWindow.shared)), NSSize(width: 640, height: 560), "check-welcome-\(page.title.lowercased())")
        }
    }
}
#endif
