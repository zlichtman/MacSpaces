#if DEBUG
import SwiftUI
import AppKit

/// Short website clips, one tool each, framed tightly on the open Nook:
/// Music Player (songs skipping, each on its theme), Themes (live themes, each with a song), Tray (a file dropped in), Terminal (a
/// command) and Timers (a countdown starting). Website Poster captures use only verified short excerpts. Frames render natively at a configured sampling rate
/// in slow motion, as in the main demo. Content is synthetic apart from the
/// track names and covers (from MACSPACES_DEMO_COVERS).
@MainActor
enum WebsiteDemoClips {
    static let stage = CGSize(width: 820, height: 470)

    final class Clock: ObservableObject {
        @Published var t: Double = 0
        @Published var wallpaperAsset: String?
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
        Pairing(family: .midnight, wallpaper: ["#DDE6F3", "#A6BBD8", "#6C87AE", "#344B70"], cover: "midnight",
                title: "I Melt With You - Rerecorded", artist: "Modern English", album: "Pillow Lips", duration: 236),
    ]

    static func run(output: URL) {
        let settings = NookSettings.shared
        let services = AppServices.shared
        let theme = ThemeStore.shared
        let covers = ProcessInfo.processInfo.environment["MACSPACES_DEMO_COVERS"] ?? "/private/tmp/macspaces-covers"
        settings.showTimerLiveActivity = false
        settings.showPowerLiveActivity = false
        settings.dockApps = WebsiteDemoNotch.siteDock
        WidgetOptions.shared.clockStyle = .regular
        WidgetOptions.shared.clockPlaces = ["America/Chicago", "Europe/London", "Asia/Tokyo"]
        MeetingControls.shared.setPreview(muted: true, cameraOff: false)
        DictationModel.shared.text = "Here’s the updated plan. I’ll share the design after reviewing our meeting notes."
        services.calendar.setAppPreview()
        services.systemStats.setPreview()
        services.teleprompter.setPreview(current: "", upcoming: "", source: .lyrics)
        theme.appearanceMode = .dark

        func play(_ pairing: Pairing) {
            theme.selectFamily(pairing.family)
            var info = NowPlayingInfo()
            info.title = pairing.title; info.artist = pairing.artist; info.album = pairing.album
            info.sourceName = "Music"; info.isPlaying = true; info.elapsed = 74; info.duration = pairing.duration
            info.capabilities = [.playPause, .previous, .next, .seek]
            info.artwork = NSImage(contentsOfFile: "\(covers)/\(pairing.cover).jpg")
            if let title = ProcessInfo.processInfo.environment["MACSPACES_DEMO_TRACK_TITLE"] {
                info.title = title
                info.artist = ProcessInfo.processInfo.environment["MACSPACES_DEMO_TRACK_ARTIST"] ?? ""
                info.album = ProcessInfo.processInfo.environment["MACSPACES_DEMO_TRACK_ALBUM"] ?? ""
                info.duration = Double(ProcessInfo.processInfo.environment["MACSPACES_DEMO_TRACK_DURATION"] ?? "240") ?? 240
                info.artwork = NSImage(contentsOfFile: ProcessInfo.processInfo.environment["MACSPACES_DEMO_TRACK_COVER"] ?? "")
            }
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

        // Website-only reels keep the native stage and dock constant.
        func scene(_ family: ThemeFamily, _ clock: Clock) {
            theme.selectFamily(family)
            theme.reduceMotionPreference = false
            theme.lyricStyle = .classic
            clock.wallpaperAsset = family == .alpine ? "ThemeSnow" : family == .synthwave ? "ThemeNebula" : "Theme" + family.rawValue.prefix(1).uppercased() + family.rawValue.dropFirst()
            services.teleprompter.setPreview(current: "", upcoming: "", source: .lyrics)
        }
        home([(.media, .large), (.timer, .small), (.weather, .small), (.clock, .small), (.systemStats, .small)])
        // Real songs for the reels (title, artist, album, duration, cover path and an optional short
        // lyric excerpt), from MACSPACES_DEMO_TRACKS, a JSON object keyed by name.
        struct Track: Decodable { let title: String; let artist: String; let album: String; let duration: Double; let cover: String; let lyrics: [String]? }
        let tracks = ProcessInfo.processInfo.environment["MACSPACES_DEMO_TRACKS"]
            .flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
            .flatMap { try? JSONDecoder().decode([String: Track].self, from: $0) } ?? [:]
        func play(_ name: String) {
            guard let track = tracks[name] else { return play(pairings[0]) }
            var info = NowPlayingInfo()
            info.title = track.title; info.artist = track.artist; info.album = track.album
            info.sourceName = "Music"; info.isPlaying = true; info.elapsed = 74; info.duration = track.duration
            info.capabilities = [.playPause, .previous, .next, .seek]
            info.artwork = NSImage(contentsOfFile: track.cover)
            services.nowPlaying.setPreviewInfo(info)
        }
        func lyric(_ text: String) {
            withAnimation(Design.spring()) { services.teleprompter.setPreview(current: text, upcoming: "", source: .lyrics) }
        }
        // Music (owner, 3.2: one reel instead of Music, Lyrics and Themes): each song in the nature
        // theme its cover suggests, with one short lyric excerpt from the track file, skipping on.
        let showcase: [(song: String, family: ThemeFamily, style: LyricStyle)] = [
            ("generationals", .blossom, .stickers), ("phantogram", .firefly, .poster), ("suki", .autumn, .poster),
            ("foglake", .bamboo, .poster), ("blue", .glacier, .poster),
        ]
        let segment = 4.0
        var showcaseBeats: [Beat] = []
        for (index, item) in showcase.enumerated() {
            let start = Double(index) * segment
            if index > 0 {
                showcaseBeats.append((start, { clock, _, _ in
                    withAnimation(.easeInOut(duration: 0.35 * WebsiteDemo234.timeScale)) { scene(item.family, clock); play(item.song) }
                    theme.lyricStyle = item.style
                }))
            }
            for (line, text) in (tracks[item.song]?.lyrics ?? []).prefix(2).enumerated() {
                showcaseBeats.append((start + 0.4 + Double(line) * 1.7, { _, _, _ in lyric(text) }))
            }
        }
        clip("music-showcase", length: Double(showcase.count) * segment, output: output, tab: .music, setup: { clock, _, _ in
            scene(showcase[0].family, clock); play(showcase[0].song); theme.lyricStyle = showcase[0].style
        }, beats: showcaseBeats)
        // The README's first image (owner, 3.2): the Music page in Blossom with a Stickers lyric,
        // over a soft evening desktop; the README uses a settled frame.
        clip("readme-hero", length: 3, output: output, tab: .music, setup: { clock, _, _ in
            theme.selectFamily(.blossom); theme.reduceMotionPreference = false; theme.lyricStyle = .stickers
            clock.wallpaperAsset = nil; clock.wallpaper = ["#8E9BD3", "#A9A3D2", "#D9AFC0", "#EDB9A0"]
            play("generationals")
            services.teleprompter.setPreview(current: tracks["generationals"]?.lyrics?.first ?? "", upcoming: "", source: .lyrics)
        }, beats: [])
        if only?.contains("converter-reel") == true { converterReel(output: output) }

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
            ("theme-blossom", Pairing(family: .blossom, wallpaper: ["#FFF3F6", "#F59AB5", "#A4617F", "#24161C"], cover: "blossom",
                title: "Evening Bloom", artist: "MacSpaces Demo", album: "Petal Light", duration: 236),
                [(.media, .large), (.timer, .small), (.weather, .small), (.clock, .small), (.systemStats, .small)]),
            ("theme-wildflower", Pairing(family: .wildflower, wallpaper: ["#FFF3F6", "#F59AB5", "#A4617F", "#24161C"], cover: "blossom",
                title: "Evening Bloom", artist: "MacSpaces Demo", album: "Petal Light", duration: 236),
                [(.media, .large), (.timer, .small), (.weather, .small), (.clock, .small), (.systemStats, .small)]),
            ("theme-lotus", Pairing(family: .lotus, wallpaper: ["#FFF3F6", "#F59AB5", "#A4617F", "#24161C"], cover: "blossom",
                title: "Evening Bloom", artist: "MacSpaces Demo", album: "Petal Light", duration: 236),
                [(.media, .large), (.timer, .small), (.weather, .small), (.clock, .small), (.systemStats, .small)]),
            ("theme-aurora", Pairing(family: .aurora, wallpaper: ["#FFF3F6", "#F59AB5", "#A4617F", "#24161C"], cover: "blossom",
                title: "Evening Bloom", artist: "MacSpaces Demo", album: "Petal Light", duration: 236),
                [(.media, .large), (.timer, .small), (.weather, .small), (.clock, .small), (.systemStats, .small)]),
            ("theme-prism", Pairing(family: .prism, wallpaper: ["#FFF3F6", "#F59AB5", "#A4617F", "#24161C"], cover: "blossom",
                title: "Evening Bloom", artist: "MacSpaces Demo", album: "Petal Light", duration: 236),
                [(.media, .large), (.timer, .small), (.weather, .small), (.clock, .small), (.systemStats, .small)]),
        ]
        WebsiteDemo234.previewWeather()
        services.timerService.setPreview(remaining: 18 * 60 + 19, total: 25 * 60)
        for (name, look, widgets) in siteLooks {
            home(widgets)
            clip(name, length: 4.0, output: output, tab: .nook, setup: { clock, _, _ in
                play(look); clock.wallpaper = look.wallpaper
                theme.reduceMotionPreference = look.family == .aurora || look.family == .prism
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
            ("page-meetings", .lotus, ["#FFF3F6", "#F59AB5", "#A4617F", "#24161C"], .meetings, nil),
            ("page-dictation", .lavender, ["#FFF3F6", "#F59AB5", "#A4617F", "#24161C"], .dictation, nil),
            ("page-clock", .moonrise, ["#FFF3F6", "#F59AB5", "#A4617F", "#24161C"], .clock, nil),
            ("page-system", .glacier, ["#FFF3F6", "#F59AB5", "#A4617F", "#24161C"], .system, nil),
            ("page-weather", .monsoon, ["#FFF3F6", "#F59AB5", "#A4617F", "#24161C"], .weather, nil),
            ("page-home", .alpine, ["#E4ECD6", "#AFC398", "#6F8C63", "#3E5439"], .nook, nil),
            ("page-calendar", .wildflower, ["#E7DCEB", "#B39CC6", "#7C629A", "#42325A"], .calendar, nil),
            ("page-timers", .tidal, ["#F6DCD2", "#E59A82", "#B64A32", "#521A12"], .timers, nil),
            ("page-notes", .fern, ["#F3E9CF", "#D9C08A", "#A8843F", "#4E3B17"], .notes, nil),
            ("page-prompter", .nebula, ["#E6E1F2", "#B9AEDB", "#7D6FB0", "#3B335C"], .prompter, nil),
            ("page-coding", .starlight, ["#E3EEF3", "#A9C8D6", "#5F8FA6", "#22404F"], .terminal, "agents"),
            ("page-usage", .synthwave, ["#F4DCEF", "#D99DCC", "#9C5198", "#3D1F4D"], .terminal, "usage"),
            ("page-messages", .firefly, ["#DDE6F3", "#A6BBD8", "#6C87AE", "#344B70"], .messages, nil),
            ("page-shortcuts", .synthwave, ["#DCE0F2", "#A3AEDB", "#5F6DAA", "#232A4D"], .shortcuts, nil),
            ("page-tray", .autumn, ["#E4ECD6", "#AFC398", "#6F8C63", "#3E5439"], .tray, nil),
            ("page-music-autumn", .autumn, ["#F6DCD2", "#E59A82", "#B64A32", "#521A12"], .music, nil),
            ("page-music-moss", .moss, ["#E3E9D8", "#A4B98F", "#657B4D", "#263820"], .music, nil),
            ("page-music", .starlight, ["#F6DCD2", "#E59A82", "#B64A32", "#521A12"], .music, nil),
        ]
        home([(.media, .large), (.timer, .small), (.weather, .small), (.clock, .small), (.todos, .small)])
        for (name, family, wallpaper, tab, terminalTab) in pages {
            if let terminalTab { UserDefaults.standard.set(terminalTab, forKey: "terminal.tab") }
            clip(name, length: tab == .music ? 5.0 : (tab == .tray ? 2.5 : 0.5), output: output, tab: tab, setup: { clock, _, shelf in
                play(siteLooks[0].1); theme.selectFamily(family); clock.wallpaper = wallpaper
                theme.reduceMotionPreference = false
                services.timerService.setPreview(remaining: 18 * 60 + 19, total: 25 * 60)
                clock.wallpaperAsset = family == .alpine ? "ThemeSnow" : family == .synthwave ? "ThemeNebula" : "Theme" + family.rawValue.prefix(1).uppercased() + family.rawValue.dropFirst()
                if tab == .music {
                    if name == "page-music" {
                        theme.lyricStyle = .classic
                        services.teleprompter.setPreview(current: "", upcoming: "", source: .lyrics)
                    } else {
                        theme.lyricStyle = .classic
                        services.teleprompter.setPreview(current: "", upcoming: "", source: .lyrics)
                        let key = name == "page-music-autumn" ? "suki" : "foglake"
                        if let path = ProcessInfo.processInfo.environment["MACSPACES_DEMO_PAIRINGS"], let data = FileManager.default.contents(atPath: path),
                           let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                           let song = entries.first(where: { $0["key"] as? String == key }) {
                            var info = NowPlayingInfo()
                            info.title = song["trackName"] as? String ?? ""
                            info.artist = song["artistName"] as? String ?? ""
                            info.album = song["collectionName"] as? String ?? ""
                            info.duration = (song["trackTimeMillis"] as? Double ?? 240000) / 1000
                            info.elapsed = 74; info.sourceName = "Music"; info.isPlaying = true
                            info.capabilities = [.playPause, .previous, .next, .seek]
                            info.artwork = NSImage(contentsOfFile: song["artworkPath"] as? String ?? "")
                            services.nowPlaying.setPreviewInfo(info)
                        }
                    }
                }
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

    private static func clip(_ name: String, length: Double, output: URL, tab: NotchTab,
                             setup: (Clock, NotchViewModel, ShelfStore) -> Void, beats: [Beat]) {
        guard only?.contains(name) ?? true else { return }
        let settings = NookSettings.shared
        let savedDock = settings.dockApps
        // Music has its own secondary controls; leave room for every captured app.
        if tab == .music { settings.dockApps = savedDock.filter { $0 != .calendar && $0 != .notes && $0 != .prompter } }
        else if tab != .nook, !savedDock.contains(tab) { settings.dockApps = savedDock + [tab] }
        defer { settings.dockApps = savedDock }
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
        let still = ProcessInfo.processInfo.environment["MACSPACES_DEMO_FAST"] == "1" && ((name.hasPrefix("page-")) || name == "theme-aurora" || name == "theme-prism")
        for n in 0..<(still ? 1 : Int(length * fps)) {
            let t = Double(n) / fps
            clock.t = t
            if !still { var info = services.nowPlaying.info; info.elapsed = 74 + t; services.nowPlaying.setPreviewInfo(info) }
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
            Group {
                if let asset = clock.wallpaperAsset { Image(asset).resizable().scaledToFill().frame(width: size.width, height: size.height).clipped() }
                else if ProcessInfo.processInfo.environment["MACSPACES_DEMO_THEME"] == "blossom" { WebsiteBlossomWallpaper() }
                else { DemoWallpaper(colors: clock.wallpaper.map { Color(themeHex: $0) ?? .gray }) }
            }.frame(width: size.width, height: size.height)
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
