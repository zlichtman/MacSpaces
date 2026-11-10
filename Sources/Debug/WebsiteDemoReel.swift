#if DEBUG
import SwiftUI
import AppKit

/// The site's hero video (`reel`, in `WebsiteDemoClips`), "How MacSpaces works" (script v3):
/// 61.5 s, silent, drawn frame by frame (`clip(rendered:)`) on the tour's stage, in Autumn on the
/// Autumn desktop throughout, with Catacombs by Fog Lake playing and a plain closed notch (no
/// timers, Keep Awake or cover beside it). Each beat shows how it's done as a chip at the bottom
/// left (a click or the keys) with one caption under it, both in the theme's colours, and the drawn
/// pointer does it: hover the notch and Home opens; the dock opens Music with the lyric in time,
/// and the right-click Look menu (the Nook's own themed menu, drawn where its popover opens) turns
/// it to Vinyl, then the Shelf: the owner's playlist (`MACSPACES_DEMO_SHELF`, a JSON list kept
/// outside the repo; its name on the source pill) beside the turntable, the playing song's record
/// sliding out onto the platter; the dock shows Calendar and Weather; the Nook closes, one agent
/// bubble slides out, a click opens the Agents tab and Allow sends the session back to work;
/// KemoSabe hears "Can Sarah come over tonight?" and only the answer reaches Claude; a photo dragged
/// onto the notch waits in the Tray and "harbor" finds the invoice by its words; the framing widens
/// to the whole screen, the MacSpaces menu turns Tape on, the windows line up in a strip and ⌃⌥→
/// twice moves along it; Show Desktop clears them, the Nook opens and closes to the plain notch, and
/// MacSpaces' mark and "macspaces.dev" fade in centred and stay. Everything is synthetic apart from
/// the demo song, the playlist and their covers.
@MainActor
enum WebsiteDemoReel {
    static let length = 61.5
    static let stage = WebsiteDemoNotch.stage
    static let full = CGRect(origin: .zero, size: stage)
    /// The usual framing: the top 940 points of the stage, so the open Nook leaves a band
    /// below it for the chip and caption.
    static let wide: CGRect = {
        let width: CGFloat = 940
        return CGRect(x: (stage.width - width) / 2, y: 0, width: width,
                      height: width * WebsiteDemoNotch.frameSize.height / WebsiteDemoNotch.frameSize.width)
    }()
    /// The poster's moment: Catacombs on the Music page with its lyric landed.
    static let posterAt = 7.0
    /// Close on the notch's row of bubbles for the agent bubble (600 points of the stage).
    static let close: CGRect = {
        let side = AgentPopoutLayout.bubbleSide(forHeight: WebsiteDemoProfile.notchSize.height)
        let centre = stage.width / 2 + AgentPopoutLayout.laneWidth(bubbles: 1, side: side) / 2
        return CGRect(x: centre - 300, y: 0, width: 600, height: 600 * wide.height / wide.width)
    }()
    /// The demo song: Catacombs, in the owner's playlist and one of his demo songs with its lyric.
    static let song = "fog-lake"

    /// Seconds of video. Each beat is the action, then a pause on the result.
    enum Beat {
        static let open = 1.75
        static let music = 5.4, lyric = 6.0
        static let menu1 = 8.4, vinyl = 9.6
        static let menu2 = 11.8, shelf = 13.0
        static let calendar = 16.0, weather = 18.6, resetLook = 17.0
        static let shut = 21.2, out = 21.9, click = 23.9, allow = 25.7
        static let wisp = 28.6, ask = 29.4, think = 30.1, told = 31.7, reply = 33.0
        static let shutForFiles = 35.1, grab = 35.6, dragEnd = 37.0, opensTray = 36.6, drop = 37.2
        static let field = 38.6, typing = 38.9, letter = 0.16
        static let shutForTape = 42.1, widen = 42.6, windowsIn = 42.9
        static let menu = 45.1, tapeOn = 46.5, next1 = 49.0, next2 = 51.3
        static let away = 53.6, narrow = 54.0
        static let reopen = 55.7, shutLast = 56.7
        static let end = 58.0
    }

    /// The beat's how, bottom left: a symbol and a few words, or keycaps.
    struct Hint { let start: Double, end: Double, symbol: String?, keys: [String], label: String }
    static let hints: [Hint] = [
        Hint(start: 0.3, end: 5.0, symbol: "cursorarrow", keys: [], label: "Hover the notch"),
        Hint(start: 5.0, end: 15.0, symbol: "computermouse", keys: [], label: "Right-click, Look"),
        Hint(start: 15.0, end: 21.0, symbol: "cursorarrow.click", keys: [], label: "Click the dock"),
        Hint(start: 21.0, end: 28.0, symbol: "cursorarrow.click", keys: [], label: "Click the bubble"),
        Hint(start: 28.0, end: 35.0, symbol: "keyboard", keys: [], label: "Ask in plain words"),
        Hint(start: 35.0, end: 38.4, symbol: "hand.point.up.left", keys: [], label: "Drag to the notch"),
        Hint(start: 38.4, end: 42.0, symbol: "magnifyingglass", keys: [], label: "Search"),
        Hint(start: 42.0, end: 48.5, symbol: "menubar.rectangle", keys: [], label: "Turn On Tape"),
        Hint(start: 48.5, end: 53.8, symbol: nil, keys: ["⌃", "⌥", "→"], label: ""),
    ]
    struct Caption { let start: Double, end: Double, text: String }
    static let captions: [Caption] = [
        Caption(start: 0.3, end: 5.0, text: "Your notch, turned into a workstation."),
        Caption(start: 5.0, end: 15.0, text: "Your music, three ways."),
        Caption(start: 15.0, end: 21.0, text: "Your day at a glance."),
        Caption(start: 21.0, end: 28.0, text: "Claude Code and Codex, when they need you."),
        Caption(start: 28.0, end: 35.0, text: "Agents get the answer, never your calendar."),
        Caption(start: 35.0, end: 42.0, text: "Your files, held and searchable."),
        Caption(start: 42.0, end: 53.8, text: "Your windows in a strip you scroll."),
    ]

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    static func ease(_ t: Double, _ from: Double, _ to: Double) -> Double { WebsiteDemoAgents.ease(t, from: from, to: to) }
    static func mix(_ a: CGRect, _ b: CGRect, _ p: Double) -> CGRect {
        let p = CGFloat(p)
        return CGRect(x: a.minX + (b.minX - a.minX) * p, y: a.minY + (b.minY - a.minY) * p,
                      width: a.width + (b.width - a.width) * p, height: a.height + (b.height - a.height) * p)
    }

    /// What the video shows of the stage at `t`: the usual framing, close on the agent bubble while
    /// it's out, and the whole screen for Tape.
    static func crop(at t: Double) -> CGRect {
        if t >= Beat.shut + 0.1, t < Beat.click + 0.08 { return mix(wide, close, ease(t, Beat.shut + 0.1, Beat.shut + 0.9)) }
        if t >= Beat.click + 0.08, t < Beat.click + 0.6 { return mix(close, wide, ease(t, Beat.click + 0.08, Beat.click + 0.6)) }
        if t >= Beat.widen, t < Beat.narrow { return mix(wide, full, ease(t, Beat.widen, Beat.widen + 1.0)) }
        if t >= Beat.narrow, t < Beat.narrow + 0.9 { return mix(full, wide, ease(t, Beat.narrow, Beat.narrow + 0.9)) }
        return wide
    }

    // MARK: Where things are, in stage points (top-left origin)

    static let notch = CGPoint(x: stage.width / 2 + 6, y: 16)
    /// The right-click on the Music page, and the photo's place on the desktop.
    static let rightClick = CGPoint(x: 905, y: 250)
    static let photoFrom = CGPoint(x: 1120, y: 455)
    /// The agent bubble (from the closed notch, in `render`), Allow on the waiting card and the
    /// Tray's search field, measured from a render.
    static var bubble = CGPoint(x: 930, y: 18)
    static let allow = WebsiteDemoAgents.fallbackAllow
    static let searchField = CGPoint(x: 445, y: 64)
    static var dock: [NotchTab: [NotchTab: CGPoint]] = [:]
    /// The MacSpaces icon in the menu bar while the whole screen shows.
    static let menuIcon = CGPoint(x: 1249, y: 16)

    /// A dock icon's centre with `page` showing, worked out as `NotchHeaderView` lays the dock out.
    static func dockPoint(_ tab: NotchTab, on page: NotchTab, model: NotchViewModel) -> CGPoint {
        let settings = NookSettings.shared
        let size = NotchViewModel.fittedSize(widgets: settings.widgets, tab: page, geometry: model.geometry,
                                             availableWidth: stage.width, sizes: settings.widgetSizes)
        let maximumWidth = min(NotchViewModel.standardPageWidth, size.width) - 16
        let buttons = 1 + (settings.showDockPin ? 1 : 0) + (settings.showDockClose ? 1 : 0)
        let settingsWidth = CGFloat(buttons * 30 + (buttons - 1) * 3 + 8)
        let natural: CGFloat = page == .music ? MusicViewButtons.width(for: AppServices.shared.nowPlaying.info) : 0
        let controls = natural > 0 ? min(natural, max(38, maximumWidth - settingsWidth - 90)) : 0
        let gap: CGFloat = natural > 0 ? 16 : 8
        let pages = settings.dockPages
        let apps = min(CGFloat(pages.count * 33 + 5), max(38, maximumWidth - settingsWidth - controls - gap))
        let row = apps + 8 + (controls > 0 ? controls + 8 : 0) + settingsWidth
        let index = CGFloat(pages.firstIndex(of: tab) ?? 0)
        return CGPoint(x: stage.width / 2 - row / 2 + 4 + index * 33 + 15, y: size.height - NotchViewModel.dockHeight / 2)
    }

    // MARK: The pointer

    /// Where the pointer is at each moment (eased between), when it shows, and when it clicks.
    static var path: [(Double, CGPoint)] = []
    static let shown: [ClosedRange<Double>] = [0.3...14.8, 15.2...20.8, 21.0...27.6, 28.0...29.2, 35.0...39.2, 42.0...47.6, 54.8...57.2]
    static let presses: [Double] = [Beat.music - 0.05, Beat.menu1 - 0.05, Beat.vinyl - 0.05, Beat.menu2 - 0.05, Beat.shelf - 0.05,
                                    Beat.calendar - 0.05, Beat.weather - 0.05, Beat.click - 0.05, Beat.allow - 0.05, Beat.wisp - 0.05,
                                    Beat.field - 0.05, Beat.menu - 0.05, Beat.tapeOn - 0.05]

    static func preparePath(model: NotchViewModel) {
        func d(_ tab: NotchTab, _ page: NotchTab) -> CGPoint { dockPoint(tab, on: page, model: model) }
        let rest = CGPoint(x: 1030, y: 380)
        path = [
            (0.3, CGPoint(x: 1030, y: 400)), (0.6, CGPoint(x: 1030, y: 400)), (1.6, notch), (4.5, notch),
            (Beat.music - 0.1, d(.music, .nook)), (6.6, d(.music, .music)),
            // Right-click the page, rest on the menu a moment, then down to Vinyl.
            (Beat.menu1 - 0.1, rightClick), (Beat.menu1 + 0.4, rightClick),
            (Beat.vinyl - 0.25, lookChoice(1)), (Beat.vinyl + 0.1, lookChoice(1)),
            (Beat.vinyl + 1.0, CGPoint(x: 1010, y: 300)), (Beat.menu2 - 0.1, rightClick), (Beat.menu2 + 0.4, rightClick),
            (Beat.shelf - 0.25, lookChoice(2)), (Beat.shelf + 0.1, lookChoice(2)), (14.4, rest),
            (15.2, rest), (Beat.calendar - 0.1, d(.calendar, .music)), (17.8, d(.calendar, .music)),
            (Beat.weather - 0.1, d(.weather, .calendar)), (20.6, d(.weather, .calendar)),
            (21.0, d(.weather, .weather)), (21.6, CGPoint(x: 960, y: 200)), (22.6, CGPoint(x: 960, y: 200)),
            (Beat.click - 0.15, bubble), (Beat.click + 0.4, bubble), (Beat.allow - 0.15, allow), (Beat.allow + 0.3, allow),
            (27.6, CGPoint(x: allow.x + 90, y: allow.y + 110)),
            (28.0, CGPoint(x: 990, y: 300)), (Beat.wisp - 0.1, d(.wisp, .terminal)), (29.2, d(.wisp, .terminal)),
            (35.0, CGPoint(x: 1010, y: 300)), (Beat.grab - 0.15, photoFrom), (Beat.grab + 0.1, photoFrom),
            (Beat.dragEnd, CGPoint(x: notch.x, y: 22)), (Beat.drop + 0.2, CGPoint(x: notch.x, y: 22)),
            (Beat.field - 0.15, searchField), (39.2, searchField),
            (42.0, CGPoint(x: 1010, y: 300)), (42.4, CGPoint(x: 1160, y: 600)), (44.1, CGPoint(x: 1160, y: 600)),
            (Beat.menu - 0.1, menuIcon), (Beat.menu + 0.3, menuIcon), (Beat.tapeOn - 0.3, tapeRow), (Beat.tapeOn + 0.1, tapeRow),
            (47.6, CGPoint(x: tapeRow.x + 60, y: tapeRow.y + 160)),
            (54.8, CGPoint(x: 1030, y: 380)), (Beat.reopen - 0.1, notch), (56.3, notch), (Beat.shutLast + 0.2, CGPoint(x: 1080, y: 470)),
            (57.2, CGPoint(x: 1090, y: 480)),
        ]
    }

    static func pointer(at t: Double) -> (point: CGPoint, pressed: Bool, opacity: Double)? {
        guard let range = shown.first(where: { $0.contains(t) }), !path.isEmpty else { return nil }
        let opacity = clamp((t - range.lowerBound) / 0.2) * clamp((range.upperBound - t) / 0.2)
        var point = path[0].1
        if let next = path.firstIndex(where: { $0.0 > t }) {
            if next > 0 {
                let (t0, a) = path[next - 1], (t1, b) = path[next]
                let p = ease(t, t0, t1)
                let lift = sin(p * .pi) * min(18, hypot(b.x - a.x, b.y - a.y) * 0.06)
                point = CGPoint(x: a.x + (b.x - a.x) * p + lift * 0.3, y: a.y + (b.y - a.y) * p - lift)
            }
        } else { point = path[path.count - 1].1 }
        let pressed = presses.contains { t >= $0 && t < $0 + 0.16 }
        return (point, pressed, opacity)
    }

    // MARK: The drawn menus (macOS draws them in their own windows, outside the capture)

    static let row: CGFloat = 22
    /// The Music page's Look menu (`MusicPageMenu`): the Nook's popover under the right-click, its
    /// arrow pointing up at it, a "Look" heading over Standard, Vinyl and Shelf.
    enum LookMenu {
        static let arrow: CGFloat = 11, padding: CGFloat = 6, heading: CGFloat = 14, spacing: CGFloat = 2, row: CGFloat = 26
        static let width: CGFloat = 170 + 2 * padding
        static var top: CGFloat { rightClick.y + arrow }
        static var height: CGFloat { padding * 2 + heading + CGFloat(MusicLook.allCases.count) * (row + spacing) }
        static func rowY(_ index: Int) -> CGFloat { top + padding + heading + spacing + CGFloat(index) * (row + spacing) + row / 2 }
    }
    static func lookChoice(_ index: Int) -> CGPoint { CGPoint(x: rightClick.x - 40, y: LookMenu.rowY(index) + 2) }
    /// The MacSpaces menu's items, as `MenuBarMenu` lists them (nil is a divider).
    static let menuItems: [String?] = ["Open Nook", "Find Action", "Enable Nook", "File Converter", "File Baskets", "Tape", nil,
                                       "Settings", "How to Use MacSpaces", nil, "Check for Updates", nil, "Quit MacSpaces"]
    static var menuTop: CGPoint { CGPoint(x: menuIcon.x - 14, y: WebsiteDemoTape.menuBar + 2) }
    static func menuItemY(_ index: Int) -> CGFloat {
        var y = menuTop.y + 5
        for item in menuItems.prefix(index) { y += item == nil ? 11 : row }
        return y + row / 2
    }
    static var tapeRow: CGPoint { CGPoint(x: menuTop.x + 70, y: menuItemY(5)) }

    // MARK: Rendering

    /// The owner's playlist for the Shelf, from `MACSPACES_DEMO_SHELF`: `{"playlist": name,
    /// "songs": [{title, artists, album, link, coverFile}]}` in its own order. Never committed.
    private struct OwnPlaylist: Decodable {
        struct Entry: Decodable { let title: String; let artists: String; let album: String; let link: String?; let coverFile: String? }
        let playlist: String
        let songs: [Entry]
    }

    static func ownPlaylist() -> (name: String, songs: [SpotifyLibrary.Song])? {
        guard let path = ProcessInfo.processInfo.environment["MACSPACES_DEMO_SHELF"],
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let list = try? JSONDecoder().decode(OwnPlaylist.self, from: data), !list.songs.isEmpty else { return nil }
        let songs = list.songs.map { entry in
            SpotifyLibrary.Song(title: entry.title, artists: entry.artists, album: entry.album,
                                image: entry.coverFile.map { URL(fileURLWithPath: $0) }, link: entry.link.flatMap(URL.init(string:)))
        }
        return (list.playlist, songs)
    }

    /// Readies the reel's Tray, files, agents, songs and looks, then draws it.
    static func render(output: URL, files: URL, sarah: WispMessage, told: WispMessage,
                       clip: (_ stage: @escaping (WebsiteDemoClips.Clock) -> AnyView,
                              _ setup: @escaping (WebsiteDemoClips.Clock, NotchViewModel, ShelfStore) -> Void,
                              _ beats: [WebsiteDemoClips.Beat]) async -> Void) async {
        let services = AppServices.shared, theme = ThemeStore.shared, wisp = WispModel.shared
        let monitor = AgentActivityMonitor.shared, popout = AgentPopout.shared, options = WidgetOptions.shared
        let settings = NookSettings.shared, spotify = SpotifyLibrary.shared
        theme.selectFamily(.autumn)
        // The Tray: the picture pack's files (or drawn ones), then a photo dropped in.
        let folder = files.appendingPathComponent("Reel tray", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pack = WebsiteDemoClips.trayPackFiles(in: folder)
        var trayFiles = pack?.files ?? []
        if pack == nil {
            let lease = folder.appendingPathComponent("Lease summary.pdf")
            WebsiteDemoClips.writeLeasePDF(lease)
            let packing = folder.appendingPathComponent("Packing list.txt")
            try? "Packing list\nBoots, rain shell, map, headlamp, film camera".write(to: packing, atomically: true, encoding: .utf8)
            trayFiles = [lease, WebsiteDemoClips.writeInvoice(folder.appendingPathComponent("Scan 3.png")), packing]
        }
        let picture = NSImage(named: "ThemeAutumn") ?? NSImage(size: NSSize(width: 1200, height: 800))
        // A camera-sized photo (1000 points wide), so its Tray preview is ready moments after the drop.
        let small = NSImage(size: NSSize(width: 1000, height: 1000 * max(picture.size.height, 1) / max(picture.size.width, 1)), flipped: false) { rect in
            picture.draw(in: rect); return true
        }
        let photo = WebsiteDemoClips.writePNG(small, folder.appendingPathComponent("Autumn walk.png"))
        // Two Trays, every file read first (thumbnails, kinds and what Folio found): before the
        // drop, and after it with the photo first, as the app takes a drop.
        let shelf = ShelfStore(basketID: nil), dropped = ShelfStore(basketID: nil)
        shelf.setPreviewItems(trayFiles, selectedIndex: nil)
        dropped.setPreviewItems([photo] + trayFiles, selectedIndex: nil)
        await shelf.waitForFileMetadata()
        await dropped.waitForFileMetadata()
        for _ in 0..<300 where ([photo] + trayFiles).contains(where: { FolioIndex.shared.record(for: $0) == nil }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        FolioIndex.shared.setPreviewMarks(pack?.marks ?? [:])

        // The Shelf: the owner's playlist, its songs and covers in its own order, from
        // `MACSPACES_DEMO_SHELF` (kept outside the repo); Liked Songs is empty, so it shows.
        if let playlist = ownPlaylist() {
            var source = SpotifyLibrary.ShelfSource(id: "own-playlist", name: playlist.name)
            source.image = playlist.songs.first?.image
            source.total = playlist.songs.count
            spotify.setPreview(account: "Listener", top: nil, backups: [], shelf: [(source, playlist.songs)])
            print("Reel: the Shelf shows \(playlist.name), \(playlist.songs.count) songs")
        } else {
            print("Reel: set MACSPACES_DEMO_SHELF to a playlist's JSON for the Shelf; it shows only the playing song")
            let songs = [WebsiteDemoProfile.track(song)].compactMap { $0 }
                .map { SpotifyLibrary.Song(title: $0.title, artists: $0.artist, album: $0.album, image: URL(fileURLWithPath: $0.cover), link: nil) }
            spotify.setPreview(account: "Listener", top: nil, backups: [], shelf: [(SpotifyLibrary.ShelfSource(id: "demo", name: "Demo"), songs)])
        }
        for _ in 0..<40 where spotify.shelfSource == .liked { try? await Task.sleep(nanoseconds: 50_000_000) }
        // KemoSabe in its own colours on Autumn, its art ready before the first frame.
        UserDefaults.standard.removeObject(forKey: WidgetOptions.Keys.agentPalette)
        AgentColours.setGlass(1)
        let look = AgentColours.currentKemoSabe()
        for kind in look.glass > 0.001 ? [KemoSabeArt.Kind.felt, .glass] : [.felt] {
            _ = await KemoSabeArt.make(kind, look: look, small: false)
        }
        WebsiteDemoTape.musicSong = song

        let saved = (look: options.musicLook, ascii: options.asciiCover, style: options.asciiStyle, scene: options.asciiScene,
                     around: options.asciiAround, colours: options.asciiColours, tint: options.albumTint,
                     cover: settings.showMusicLiveActivity)
        let savedTab = UserDefaults.standard.string(forKey: WidgetOptions.Keys.terminalTab)
        defer {
            monitor.preview([]); monitor.spotlight = nil
            popout.setPreview([], mood: .needsYou)
            FolioIndex.shared.setPreviewMarks([:])
            spotify.setPreview(account: nil, top: nil, backups: [])
            SpotifyShelfView.previewRecordOut = nil
            services.calendar.setAppPreview()
            options.musicLook = saved.look; options.asciiCover = saved.ascii; options.asciiStyle = saved.style
            options.asciiScene = saved.scene; options.asciiAround = saved.around; options.asciiColours = saved.colours
            options.albumTint = saved.tint; settings.showMusicLiveActivity = saved.cover
            UserDefaults.standard.removeObject(forKey: MusicView.defaultsKey)
            if let savedTab { UserDefaults.standard.set(savedTab, forKey: WidgetOptions.Keys.terminalTab) }
            else { UserDefaults.standard.removeObject(forKey: WidgetOptions.Keys.terminalTab) }
            WebsiteDemoTape.musicSong = "generationals"
        }
        let model = WebsiteDemoProfile.model(availableWidth: stage.width, shelf: shelf)
        model.screenFrame = CGRect(origin: .zero, size: stage)
        let after = WebsiteDemoProfile.model(availableWidth: stage.width, shelf: dropped)
        after.screenFrame = model.screenFrame
        after.selectedTab = .tray
        after.state = .expanded
        let nook = Nook(model)
        // The agents' sessions count from the bubble's arrival, as the Agents video's do.
        let shift = Beat.out - WebsiteDemoAgents.outAt
        func sessions(_ t: Double) -> [AgentActivityMonitor.Session] {
            WebsiteDemoAgents.sessions(answered: t >= Beat.allow + 0.08, at: t - shift)
        }
        func spring(_ change: () -> Void) { withAnimation(Design.spring()) { change() } }
        let lyric = WebsiteDemoProfile.track(song)?.lyrics?.first ?? ""
        let reply = WispMessage(role: .wisp, text: "You're free after 7, so Sarah can come over tonight.", from: .claude)

        var beats: [WebsiteDemoClips.Beat] = [
            (Beat.open, { _, _, _ in model.expand(to: .nook) }),
            (Beat.music, { _, _, _ in spring { model.selectedTab = .music } }),
            (Beat.lyric, { _, _, _ in spring { services.teleprompter.setPreview(current: lyric, source: .lyrics) } }),
            (Beat.vinyl, { _, _, _ in spring { options.musicLook = .terminal } }),
            (Beat.shelf, { _, _, _ in spring { options.musicLook = .shelf } }),
            (Beat.calendar, { _, _, _ in spring { model.selectedTab = .calendar } }),
            // Out of sight: the page is back to Standard for whoever opens Music next.
            (Beat.resetLook, { _, _, _ in options.musicLook = .standard }),
            (Beat.weather, { _, _, _ in spring { model.selectedTab = .weather } }),
            (Beat.shut, { _, _, _ in
                model.collapse()
                monitor.preview(sessions(Beat.shut)); monitor.spotlight = nil
            }),
            (Beat.out, { _, _, _ in popout.setPreview(monitor.sessions.filter { $0.state == .needsYou }, mood: .needsYou) }),
            (Beat.click + 0.08, { _, _, _ in monitor.spotlight = "b"; model.expand(to: .terminal) }),
            (Beat.allow + 0.08, { _, _, _ in popout.setPreview([], mood: .needsYou) }),
            (Beat.wisp, { _, _, _ in
                monitor.spotlight = nil
                wisp.setPreview([], mood: .idle)
                spring { model.selectedTab = .wisp }
            }),
            (Beat.ask, { _, _, _ in wisp.setPreview([sarah], mood: .listening) }),
            (Beat.think, { _, _, _ in wisp.setPreview([sarah], mood: .thinking) }),
            (Beat.told, { _, _, _ in wisp.setPreview([sarah, told], mood: .thinking) }),
            (Beat.reply, { _, _, _ in wisp.setPreview([sarah, told, reply], mood: .happy) }),
            (Beat.shutForFiles, { _, _, _ in model.collapse() }),
            // The file over the notch opens the Tray, as `openTrayOnFileDrag` does; the drop adds it.
            (Beat.opensTray, { _, _, _ in model.expand(to: .tray) }),
            (Beat.drop, { _, _, _ in nook.model = after }),
            (Beat.shutForTape, { _, _, _ in after.collapse() }),
            // Behind the closed notch: back to Home for the last open.
            (Beat.shutForTape + 1, { _, _, _ in
                after.selectedTab = .nook
                wisp.setPreview([], mood: .idle)
                NotificationCenter.default.post(name: TrayPageView.previewQuery, object: "")
            }),
            (Beat.reopen, { _, _, _ in after.expand(to: .nook) }),
            (Beat.shutLast, { _, _, _ in after.collapse() }),
        ]
        // "harbor", a letter at a time, into the Tray's search.
        for (index, _) in "harbor".enumerated() {
            let typed = String("harbor".prefix(index + 1))
            beats.append((Beat.typing + Double(index) * Beat.letter, { _, _, _ in
                NotificationCenter.default.post(name: TrayPageView.previewQuery, object: typed)
            }))
        }
        // While the Agents tab shows, the sessions' times follow the video's clock, frame by frame.
        let fps = WebsiteDemo234.fps
        for n in Int(Beat.click * fps)..<Int(Beat.wisp * fps) {
            let t = Double(n) / fps
            beats.append((t, { _, _, _ in monitor.preview(sessions(t)) }))
        }
        beats.sort { $0.0 < $1.0 }
        await clip({ clock in AnyView(Stage(nook: nook, clock: clock)) }, { clock, _, _ in
            // The playing song's record slides out of its sleeve onto the platter as the Shelf opens.
            SpotifyShelfView.previewRecordOut = { [clock] in CGFloat(ease(clock.t, Beat.shelf + 0.5, Beat.shelf + 1.6)) }
            theme.selectFamily(.autumn)
            theme.setPreviewSystemReduceMotion(false)
            let track = WebsiteDemoProfile.track(song)
            WebsiteDemoProfile.play(track)
            // The song reaches its lyric as the line lands, so the line is in time.
            if let at = track?.lyricAt {
                var info = services.nowPlaying.info
                info.elapsed = max(0, at - Beat.lyric)
                services.nowPlaying.setPreviewInfo(info)
            }
            AsciiCoverCache.shared.prepareNow(services.nowPlaying.info.artwork)
            services.teleprompter.setPreview(current: "", source: .lyrics)
            // A plain closed notch: no timers, no Keep Awake and no cover beside it.
            for timer in services.allTimers { timer.setPreview(remaining: 0, total: WebsiteDemoProfile.timerTotal) }
            services.keepAwake.stop()
            settings.showMusicLiveActivity = false
            // A made-up morning whose times read as 9:41's, as the Home still's do.
            services.calendar.setAppPreview(todayEvents: WebsiteDemoProfile.homeStillEvents())
            // Standard, then Vinyl's turning record in the cover's own colours, then the Shelf's covers and record.
            options.musicLook = .standard; options.albumTint = false
            options.asciiCover = false; options.asciiStyle = .braille; options.asciiScene = .vinyl
            options.asciiAround = .off; options.asciiColours = .cover
            UserDefaults.standard.set(MusicView.playing.rawValue, forKey: MusicView.defaultsKey)
            MusicView.keepOnReturn = true
            UserDefaults.standard.set(CodingPanel.Tab.agents.rawValue, forKey: WidgetOptions.Keys.terminalTab)
            monitor.preview([]); monitor.spotlight = nil
            popout.setPreview([], mood: .needsYou)
            wisp.setPreview([], mood: .idle)
            // The dock now holds every page the reel opens (KemoSabe's is added for it).
            if let frame = model.closedNotchFrame {
                let target = AgentPopoutLayout.frame(besideNotch: frame, on: CGRect(origin: .zero, size: stage))
                bubble = CGPoint(x: target.midX, y: stage.height - target.midY + 3)
            }
            preparePath(model: model)
        }, beats)
    }

    /// The Nook on the stage; the drop moves it onto the Tray that holds the photo.
    final class Nook: ObservableObject {
        @Published var model: NotchViewModel
        init(_ model: NotchViewModel) { self.model = model }
    }

    /// The whole frame: the stage at `crop(at:)`, the pointer and menus over it, the chip and
    /// caption, and the end card.
    struct Stage: View {
        @ObservedObject var nook: Nook
        @ObservedObject var clock: WebsiteDemoClips.Clock

        var body: some View {
            let t = clock.t
            let size = WebsiteDemoClips.stage
            let crop = WebsiteDemoReel.crop(at: t)
            let scale = size.width / crop.width
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    NotchScene(model: nook.model, clock: clock)
                    Menus(t: t)
                }
                .frame(width: stage.width, height: stage.height, alignment: .topLeading)
                .offset(x: -crop.minX, y: -crop.minY)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
                if let pointer = pointer(at: t) {
                    let point = CGPoint(x: (pointer.point.x - crop.minX) * scale, y: (pointer.point.y - crop.minY) * scale)
                    if t >= Beat.grab + 0.1, t < Beat.drop { DraggedPhoto().position(x: point.x + 6, y: point.y + 4) }
                    Cursor(point: point, pressed: pointer.pressed, opacity: pointer.opacity)
                }
                // A soft shade at the bottom, so the chip and caption read over any scene.
                LinearGradient(colors: [.clear, .black.opacity(0.42)], startPoint: .top, endPoint: .bottom)
                    .frame(width: size.width, height: 130)
                    .offset(y: size.height - 130)
                    .opacity(1 - clamp((t - Beat.end + 0.6) / 0.6))
                HintLine(t: t)
                EndCard(t: t)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        }
    }

    /// The beat's chip, and the caption under it, bottom left, in the theme's colours: the chip in
    /// its accent with the surface's colour for the words, the caption in the Nook's ink on a plate
    /// of its surface. Both rise and fade in, calmly.
    struct HintLine: View {
        let t: Double
        @ObservedObject private var theme = ThemeStore.shared

        var body: some View {
            let hint = hints.first { t >= $0.start && t < $0.end }
            let caption = captions.first { t >= $0.start && t < $0.end }
            let plate = caption.map { clamp((t - $0.start) / 0.35) * clamp(($0.end - t) / 0.3) } ?? 0
            VStack(alignment: .leading, spacing: 9) {
                if let hint {
                    let shown = clamp((t - hint.start) / 0.35) * clamp((hint.end - t) / 0.25)
                    chip(hint)
                        .opacity(shown)
                        .offset(y: CGFloat((1 - shown) * 8))
                }
                if let caption {
                    let shown = clamp((t - caption.start - 0.12) / 0.4) * clamp((caption.end - t) / 0.3)
                    Text(caption.text)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(theme.nookForeground)
                        .fixedSize()
                        .opacity(shown)
                        .offset(y: CGFloat((1 - shown) * 10))
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 13)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.notch.surface.opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.notch.accent.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
                    .opacity(plate)
            }
            .padding(.leading, 16).padding(.bottom, 14)
            .frame(width: WebsiteDemoClips.stage.width, height: WebsiteDemoClips.stage.height, alignment: .bottomLeading)
            .colorScheme(theme.notch.colorScheme)
        }

        @ViewBuilder private func chip(_ hint: Hint) -> some View {
            let ink = theme.notch.surface
            HStack(spacing: 7) {
                if let symbol = hint.symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                ForEach(Array(hint.keys.enumerated()), id: \.offset) { _, key in
                    // Each press lights the keys.
                    let lit = [Beat.next1, Beat.next2].contains { t >= $0 - 0.05 && t < $0 + 0.3 }
                    Text(key).font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(lit ? theme.notch.accent : ink)
                        .frame(minWidth: 26, minHeight: 24)
                        .background(ink.opacity(lit ? 1 : 0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                if !hint.label.isEmpty { Text(hint.label).font(.system(size: 14, weight: .semibold)) }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12).padding(.vertical, hint.keys.isEmpty ? 7 : 5)
            .background(theme.notch.accent, in: Capsule())
            .fixedSize()
        }
    }

    /// MacSpaces' mark and its address, centred over the plain desktop, fading in and staying.
    struct EndCard: View {
        let t: Double

        var body: some View {
            let shown = clamp((t - Beat.end) / 1.0)
            if shown > 0 {
                let p = 1 - pow(1 - shown, 3)
                ZStack {
                    Color.black.opacity(0.3 * p)
                    VStack(spacing: 14) {
                        MacSpacesMark(size: 84)
                        Text("MacSpaces").font(.system(size: 36, weight: .bold))
                        Text("macspaces.dev").font(.system(size: 20, weight: .medium)).opacity(0.88)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
                    .opacity(p)
                    .offset(y: CGFloat(30 + (1 - p) * 12))
                }
                .frame(width: WebsiteDemoClips.stage.width, height: WebsiteDemoClips.stage.height)
            }
        }
    }

    /// The pointer, at a constant size whatever the framing.
    struct Cursor: View {
        let point: CGPoint
        let pressed: Bool
        let opacity: Double

        var body: some View {
            let cursor = NSCursor.arrow
            let image = cursor.image
            Image(nsImage: image)
                .frame(width: image.size.width, height: image.size.height)
                .scaleEffect(pressed ? 0.86 : 1, anchor: UnitPoint(x: cursor.hotSpot.x / image.size.width, y: cursor.hotSpot.y / image.size.height))
                .opacity(opacity)
                .position(x: point.x - cursor.hotSpot.x + image.size.width / 2, y: point.y - cursor.hotSpot.y + image.size.height / 2)
        }
    }

    /// The Autumn desktop, Tape's windows, the menu bar, the Nook and camera, and the agent bubble
    /// where its panel would be, in stage points.
    struct NotchScene: View {
        @ObservedObject var model: NotchViewModel
        @ObservedObject var clock: WebsiteDemoClips.Clock
        @ObservedObject private var popout = AgentPopout.shared

        var body: some View {
            let size = WebsiteDemoReel.stage
            let t = clock.t
            let crop = WebsiteDemoReel.crop(at: t)
            let windows = ReelTape.placed(at: t)
            let tapeOn = t >= Beat.tapeOn + 0.05 && t < Beat.end
            ZStack(alignment: .topLeading) {
                Image("ThemeAutumn").resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
                    .overlay(Color.black.opacity(0.14))
                ZStack(alignment: .topLeading) {
                    ForEach(windows) { window in
                        TapeDemoWindow(app: window.app, focused: window.focused)
                            .frame(width: window.frame.width, height: window.frame.height)
                            .position(x: window.frame.midX, y: window.frame.midY)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .compositingGroup()
                .opacity(windows.first?.opacity ?? 0)
                .environment(\.colorScheme, .light)
                let widened = crop.width > wide.width * 1.3
                DemoMenuBar(height: model.geometry.height, within: crop.minX...crop.maxX, sparse: !widened,
                            app: windows.first(where: \.focused).map { $0.app.name } ?? "Finder", tapeMark: tapeOn,
                            menus: widened ? nil : [], appMenu: crop.width > close.width * 1.2,
                            macSpaces: crop.width > close.width * 1.2)
                    .frame(width: size.width)
                NotchContainerView(viewModel: model)
                    .frame(width: size.width, height: size.height, alignment: .top)
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                    .fill(.black).frame(width: model.geometry.width, height: model.geometry.height)
                    .frame(width: size.width, alignment: .top)
                bubble
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        }

        /// The agent bubble sliding out from under the notch's edge (0.38 s, `AgentPopout.show`)
        /// and tucking back quickly as the click opens the Nook.
        private var bubbleState: (frame: CGRect, alpha: Double)? {
            guard let notch = model.closedNotchFrame else { return nil }
            let screen = CGRect(origin: .zero, size: WebsiteDemoReel.stage)
            let target = AgentPopoutLayout.frame(besideNotch: notch, on: screen)
            let tucked = AgentPopoutLayout.startFrame(besideNotch: notch)
            let t = clock.t, hideAt = Beat.click + 0.08
            func mix(_ p: Double) -> CGRect { target.offsetBy(dx: (tucked.minX - target.minX) * (1 - p), dy: 0) }
            if t < Beat.out || t > Beat.wisp { return nil }
            if t < hideAt {
                let linear = (t - Beat.out) / 0.38
                let p = WebsiteDemoAgents.bezier(linear, 0.2, 0.9, 0.25, 1.05)
                return (mix(linear >= 1 ? 1 : p), clamp(p))
            }
            let hide = (t - hideAt) / 0.12
            guard hide < 1 else { return nil }
            let p = 1 - WebsiteDemoAgents.bezier(hide, 0.42, 0, 0.58, 1)
            return (mix(p), p)
        }

        @ViewBuilder private var bubble: some View {
            if let state = bubbleState {
                AgentPopoutView(popout: popout, stillTime: max(0, clock.t - Beat.out))
                    .frame(width: state.frame.width, height: state.frame.height)
                    .opacity(state.alpha)
                    .position(x: state.frame.midX, y: WebsiteDemoReel.stage.height - state.frame.midY)
            }
        }
    }

    /// The Music page's right-click Look menu and the MacSpaces menu-bar menu, drawn as macOS
    /// draws menus, in stage points.
    struct Menus: View {
        let t: Double

        var body: some View {
            ZStack(alignment: .topLeading) {
                if t >= Beat.menu1, t < Beat.vinyl + 0.06 { ThemedLookMenu(t: t, opened: Beat.menu1, chosen: Beat.vinyl, current: .standard, choosing: .terminal) }
                if t >= Beat.menu2, t < Beat.shelf + 0.06 { ThemedLookMenu(t: t, opened: Beat.menu2, chosen: Beat.shelf, current: .terminal, choosing: .shelf) }
                if t >= Beat.menu, t < Beat.tapeOn + 0.1 { macSpacesMenu }
            }
            .frame(width: stage.width, height: stage.height, alignment: .topLeading)
        }

        private func panel<Content: View>(width: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(5)
                .frame(width: width, alignment: .leading)
                .background(Color(white: 0.17).opacity(0.97), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                .environment(\.colorScheme, .dark)
        }

        private func item(_ text: String, checked: Bool = false, lit: Bool = false, submenu: Bool = false, key: String? = nil) -> some View {
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).opacity(checked ? 1 : 0).frame(width: 12)
                Text(text)
                Spacer(minLength: 12)
                if let key { Text(key).opacity(0.5) }
                if submenu { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).opacity(0.7) }
            }
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(height: row)
            .background(lit ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }

        /// The MacSpaces menu under its menu-bar icon, with Tape chosen.
        private var macSpacesMenu: some View {
            let lit = t >= Beat.tapeOn - 0.3
            let blink = t >= Beat.tapeOn && t < Beat.tapeOn + 0.08
            return panel(width: 236) {
                ForEach(Array(menuItems.enumerated()), id: \.offset) { _, name in
                    if let name {
                        item(name, checked: name == "Enable Nook" || (name == "Tape" && t >= Beat.tapeOn),
                             lit: name == "Tape" && lit && !blink, submenu: name == "File Converter",
                             key: name == "Find Action" ? "⌃⌥Space" : name == "Settings" ? "⌘," : name == "Quit MacSpaces" ? "⌘Q" : nil)
                    } else {
                        Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1).padding(.horizontal, 6).frame(height: 11)
                    }
                }
            }
            .offset(x: menuTop.x, y: menuTop.y)
        }
    }

    /// The Music page's right-click menu as the app shows it (`MusicPageMenu`): the Nook's own
    /// popover in the theme (`NookPopoverContent`'s surface, ink and accent) with its arrow up at
    /// the click, the "Look" heading and `NookMenuRow`s, the current look ticked and the row under
    /// the pointer highlighted as a hovered row is. Drawn here because the popover is a window of
    /// its own, outside what the capture draws.
    struct ThemedLookMenu: View {
        let t: Double
        let opened: Double
        let chosen: Double
        let current: MusicLook
        let choosing: MusicLook
        @ObservedObject private var theme = ThemeStore.shared

        var body: some View {
            let shown = clamp((t - opened) / 0.12)
            let hovered = t >= chosen - 0.3
            let shape = PopoverShape(arrow: LookMenu.arrow, radius: 10)
            VStack(alignment: .leading, spacing: LookMenu.spacing) {
                Text("Look").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.top, 2)
                    .frame(height: LookMenu.heading, alignment: .bottomLeading)
                ForEach(MusicLook.allCases) { look in
                    NookMenuRow(look.title, selected: look == current) {}
                        .background(Color.primary.opacity(hovered && look == choosing ? 0.09 : 0),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(LookMenu.padding)
            .frame(width: LookMenu.width, alignment: .leading)
            .padding(.top, LookMenu.arrow)
            .foregroundStyle(theme.nookForeground)
            .tint(theme.notch.accent)
            .background(shape.fill(theme.notch.surface))
            .overlay(shape.stroke(theme.nookForeground.opacity(0.14), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
            .colorScheme(theme.notch.colorScheme)
            .fixedSize()
            .opacity(shown)
            .scaleEffect(0.96 + 0.04 * shown, anchor: .top)
            .offset(x: rightClick.x - LookMenu.width / 2, y: rightClick.y)
        }
    }

    /// A popover's outline: a rounded panel with its arrow at the top centre.
    struct PopoverShape: Shape {
        let arrow: CGFloat
        let radius: CGFloat

        func path(in rect: CGRect) -> Path {
            let top = rect.minY + arrow, r = radius
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + r, y: top))
            path.addLine(to: CGPoint(x: rect.midX - arrow * 1.3, y: top))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.midX - arrow * 0.45, y: top))
            path.addQuadCurve(to: CGPoint(x: rect.midX + arrow * 1.3, y: top), control: CGPoint(x: rect.midX + arrow * 0.45, y: top))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: top))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.maxX, y: top + r), radius: r)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
            path.addLine(to: CGPoint(x: rect.minX, y: top + r))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: top), tangent2End: CGPoint(x: rect.minX + r, y: top), radius: r)
            path.closeSubpath()
            return path
        }
    }

    /// A photo being dragged: its thumbnail and name, as Finder draws a drag.
    struct DraggedPhoto: View {
        var body: some View {
            VStack(spacing: 4) {
                Group {
                    if let picture = NSImage(named: "ThemeAutumn") { Image(nsImage: picture).resizable().scaledToFill() } else { Color.orange }
                }
                .frame(width: 70, height: 50).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.4), radius: 7, y: 3)
                Text("Autumn walk.png")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.white)
            }
            .opacity(0.92)
            .fixedSize()
            .offset(x: 30, y: 30)
        }
    }
}

/// Tape in the reel: the drawn app windows loose on the desktop, lined up into Tape's strip as it
/// turns on (`Strip` and `StripLayout`, Centre always on, parked at the edges as `Animator` parks
/// them), moved along by Next Column twice, then swept off the screen by Show Desktop.
@MainActor
enum ReelTape {
    typealias App = WebsiteDemoTape.App
    typealias Beat = WebsiteDemoReel.Beat
    static let geometry = WebsiteDemoTape.geometry, options = WebsiteDemoTape.options
    static let move = 0.6

    static let strips: [Strip] = {
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
        var next = centred(strip), steps = [next]
        for _ in 0..<2 { next.perform(.focus(.right)); next = centred(next); steps.append(next) }
        return steps
    }()

    /// The windows as they were before Tape: overlapping, where they were left.
    static let loose: [App: CGRect] = [
        .notes: CGRect(x: 70, y: 150, width: 470, height: 520),
        .code: CGRect(x: 780, y: 190, width: 650, height: 560),
        .music: CGRect(x: 1110, y: 96, width: 340, height: 500),
        .browser: CGRect(x: 330, y: 74, width: 820, height: 640),
    ]

    struct Placed: Identifiable {
        let app: App
        let frame: CGRect
        let opacity: Double
        let focused: Bool
        var id: Int { app.rawValue }
    }

    static func frames(_ strip: Strip) -> [App: CGRect] {
        var result: [App: CGRect] = [:]
        for (id, rect) in StripLayout.frames(for: strip, screen: geometry, options: options) {
            if let app = App.of(id) { result[app] = StripLayout.parked(rect, on: geometry) }
        }
        return result
    }

    static func placed(at t: Double) -> [Placed] {
        guard t >= Beat.windowsIn, t < Beat.narrow + 0.9 else { return [] }
        var now: [App: CGRect]
        var focused = App.browser
        if t < Beat.tapeOn {
            now = loose
        } else if t < Beat.next1 {
            let target = frames(strips[0]), p = WebsiteDemoReel.ease(t, Beat.tapeOn, Beat.tapeOn + 0.8)
            now = target.reduce(into: [:]) { $0[$1.key] = FrameMotion.interpolate(from: loose[$1.key] ?? $1.value, to: $1.value, progress: p) }
        } else {
            let index = t < Beat.next2 ? 1 : 2
            let at = index == 1 ? Beat.next1 : Beat.next2
            let before = frames(strips[index - 1]), target = frames(strips[index])
            let p = WebsiteDemoReel.ease(t, at, at + move)
            now = target.reduce(into: [:]) { $0[$1.key] = FrameMotion.interpolate(from: before[$1.key] ?? $1.value, to: $1.value, progress: p) }
            focused = index == 1 ? .code : .music
        }
        let shown = WebsiteDemoReel.clamp((t - Beat.windowsIn) / 0.8)
        // Show Desktop: every window slides out past the nearest side of the screen.
        let away = WebsiteDemoReel.ease(t, Beat.away, Beat.away + 0.8)
        var windows: [Placed] = []
        for app in App.allCases {
            guard var frame = now[app] else { continue }
            if away > 0 {
                let left = frame.midX < WebsiteDemoTape.screen.width / 2
                frame = frame.offsetBy(dx: CGFloat(away) * (left ? -(frame.maxX + 40) : WebsiteDemoTape.screen.width - frame.minX + 40), dy: 0)
            }
            windows.append(Placed(app: app, frame: frame, opacity: shown, focused: app == focused))
        }
        // The focused window is in front; parked ones sit behind the strip.
        windows.sort { a, b in
            func rank(_ p: Placed) -> Int { p.focused ? 2 : (p.frame.minX < 0 || p.frame.maxX > WebsiteDemoTape.screen.width ? 0 : 1) }
            return rank(a) < rank(b)
        }
        return windows
    }
}

extension WebsiteDemoClips {
    /// The site's hero video (`WebsiteDemoReel`), drawn frame by frame at a fixed rate.
    static func reel(output: URL, files: URL, sarah: WispMessage, told: WispMessage) async {
        await WebsiteDemoReel.render(output: output, files: files, sarah: sarah, told: told) { stage, setup, beats in
            // Its busiest pages come after the closed notch it's timed on, so time runs slower still.
            await clip("reel", length: WebsiteDemoReel.length, output: output, tab: .wisp, rendered: true, onScreen: true,
                       costFactor: 4, stageView: stage, setup: setup, beats: beats)
        }
    }
}
#endif
