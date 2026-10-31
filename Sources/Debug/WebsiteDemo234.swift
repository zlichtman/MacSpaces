#if DEBUG
import SwiftUI
import AppKit

/// The 2.x website demo: three themed desktops, each showing the Nook drop,
/// Home, and one dock page. Frames are rendered natively at 60 fps by slowing
/// the motion tokens (Design.demoTimeScale) so every frame can be captured.
/// Content is synthetic; no camera, clipboard, calendar or files are read.
@MainActor
enum WebsiteDemo234 {
    static let stage = CGSize(width: 820, height: 470)
    static var fps: Double { Double(ProcessInfo.processInfo.environment["MACSPACES_DEMO_FPS"] ?? "") ?? (ProcessInfo.processInfo.environment["MACSPACES_DEMO_FAST"] == "1" ? 30 : 60) }
    static var timeScale: Double { Double(ProcessInfo.processInfo.environment["MACSPACES_DEMO_SCALE"] ?? "") ?? (ProcessInfo.processInfo.environment["MACSPACES_DEMO_FAST"] == "1" ? 1 : 8) }

    struct Scene {
        let name: String
        let family: ThemeFamily
        let wallpaper: [String]
        let widgets: [(NookWidgetKind, NookWidgetSize)]
        let page: NotchTab
        let lyricStyle: LyricStyle
        /// A made-up track: title, artist, album, and the two colours of its generated cover.
        let track: (String, String, String, NSColor, NSColor)
        /// Original lyric lines, shown one after another.
        let lines: [String]
    }

    /// The classic pairings (real tracks, covers from MACSPACES_DEMO_COVERS, no lyrics
    /// shown, since song lyrics can't be reproduced), then a made-up track with
    /// original lines to show the lyric styles.
    static let scenes: [Scene] = [
        Scene(name: "midnight", family: .midnight, wallpaper: ["#DDE6F3", "#A6BBD8", "#6C87AE", "#344B70"],
              widgets: [(.media, .large), (.timer, .small), (.clock, .small), (.weather, .small), (.systemStats, .small)],
              page: .weather, lyricStyle: .classic,
              track: ("I Melt With You - Rerecorded", "Modern English", "Pillow Lips", NSColor(srgbRed: 0.12, green: 0.2, blue: 0.4, alpha: 1),
                      NSColor(srgbRed: 0.55, green: 0.7, blue: 0.9, alpha: 1)),
              lines: []),
        Scene(name: "everforest", family: .everforest, wallpaper: ["#E4ECD6", "#AFC398", "#6F8C63", "#3E5439"],
              widgets: [(.media, .large), (.timer, .small), (.clock, .small), (.weather, .small), (.systemStats, .small)],
              page: .timers, lyricStyle: .classic,
              track: ("Catacombs", "Fog Lake", "Tragedy Reel", NSColor(srgbRed: 0.2, green: 0.32, blue: 0.24, alpha: 1),
                      NSColor(srgbRed: 0.86, green: 0.78, blue: 0.52, alpha: 1)),
              lines: []),
        Scene(name: "kemosabe", family: .kemosabe, wallpaper: ["#E7DCEB", "#B39CC6", "#7C629A", "#42325A"],
              widgets: [(.media, .large), (.todos, .medium), (.clock, .small), (.pomodoro, .small)],
              page: .calendar, lyricStyle: .classic,
              track: ("Maps - Live at the Royal Albert Hall", "Yeah Yeah Yeahs", "Hidden in Pieces: Live at the Royal Albert Hall", NSColor(srgbRed: 0.3, green: 0.18, blue: 0.42, alpha: 1),
                      NSColor(srgbRed: 0.95, green: 0.6, blue: 0.7, alpha: 1)),
              lines: []),
    ]

    /// Seconds of video: closed, drop open to Home, switch to the Music page while
    /// the lyric lines change, close.
    static let openAt = 0.5, pageAt = 2.4, closeAt = 6.1, sceneLength = 6.7
    static let lineTimes = [0.0, 3.2, 4.1, 5.0]

    static func run(output: URL) {
        let settings = NookSettings.shared
        let services = AppServices.shared
        let theme = ThemeStore.shared
        let frames = output.appendingPathComponent("frames", isDirectory: true)
        try? FileManager.default.removeItem(at: frames)
        try! FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)

        settings.showTimerLiveActivity = false
        settings.showPowerLiveActivity = false
        settings.dockApps = WebsiteDemoNotch.siteDock
        services.calendar.setAppPreview()
        services.systemStats.setPreview()
        services.clipboard.setPreviewEntries(["Meet at the lake at 5:30", "https://zlichtman.com/open-source",
                                              "Pack the film camera"])
        for text in ["Weekend plans\nCoffee, a long walk, and a new playlist.",
                     "Launch checklist\nNotarize, tag, update the tap."] {
            if let id = services.notes.create() { services.notes.save(id, text: text) }
        }
        previewWeather()
        let timer = TimerService(previewRemaining: 18 * 60 + 19, total: 25 * 60)

        var frameIndex = 0
        let writer = DispatchQueue(label: "demo-frame-writer")
        let group = DispatchGroup()
        Design.demoTimeScale = timeScale
        defer { Design.demoTimeScale = 1 }

        for (sceneIndex, scene) in scenes.enumerated() {
            theme.selectFamily(scene.family)
            theme.lyricStyle = scene.lyricStyle
            let profile = NookProfile(id: UUID(), name: scene.name, widgets: scene.widgets.map(\.0))
            settings.profiles = [profile]
            settings.activeProfileID = profile.id
            for (kind, size) in scene.widgets { settings.setSize(size, for: kind) }
            settings.showMusicLiveActivity = true
            var info = NowPlayingInfo()
            info.title = scene.track.0; info.artist = scene.track.1; info.album = scene.track.2
            info.sourceName = "Music"; info.isPlaying = true; info.elapsed = 74; info.duration = 201
            info.capabilities = [.playPause, .previous, .next, .seek]
            let coverFile = (ProcessInfo.processInfo.environment["MACSPACES_DEMO_COVERS"] ?? "/private/tmp/macspaces-covers")
                + "/\(scene.name).jpg"
            info.artwork = NSImage(contentsOfFile: coverFile) ?? Self.cover(scene.track.3, scene.track.4, seed: sceneIndex)
            services.nowPlaying.setPreviewInfo(info)
            func showLine(_ index: Int) {
                guard scene.lines.indices.contains(index) else {
                    services.teleprompter.setPreview(current: "", upcoming: "", source: .lyrics); return
                }
                services.teleprompter.setPreview(current: scene.lines[index],
                                                 upcoming: index + 1 < scene.lines.count ? scene.lines[index + 1] : "",
                                                 source: .lyrics)
            }
            showLine(0)
            var shownLine = 0

            let model = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true),
                availableWidth: 1512, settings: settings, shelf: ShelfStore(basketID: UUID()),
                nowPlaying: services.nowPlaying, powerMonitor: services.powerMonitor, timerService: timer,
                bluetoothMonitor: services.bluetooth, systemActivityMonitor: services.systemActivity,
                teleprompter: services.teleprompter)
            let host = NSHostingView(rootView: DemoStage(model: model, wallpaper: scene.wallpaper)
                .environment(\.colorScheme, .dark))
            host.frame = NSRect(origin: .zero, size: stage)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()

            var opened = false, paged = false, closed = false
            let start = Date()
            let count = Int(sceneLength * fps)
            for n in 0..<count {
                let t = Double(n) / fps
                if !opened, t >= openAt { opened = true; model.expand() }
                if !paged, t >= pageAt { paged = true; withAnimation(Design.spring()) { model.selectedTab = scene.page } }
                if shownLine + 1 < scene.lines.count, t >= Self.lineTimes[shownLine + 1] { shownLine += 1; showLine(shownLine) }
                if !closed, t >= closeAt { closed = true; model.collapse() }
                RunLoop.main.run(until: start.addingTimeInterval(t * timeScale))
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let url = frames.appendingPathComponent(String(format: "f%05d.png", frameIndex))
                frameIndex += 1
                group.enter()
                writer.async {
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
                    group.leave()
                }
                // Stills for the README: Home fully open, then the dock page.
                if n == Int((pageAt - 0.1) * fps) || n == Int((closeAt - 0.1) * fps) {
                    let still = output.appendingPathComponent("\(sceneIndex + 1)-\(scene.name)-\(n < Int(pageAt * fps) ? "home" : scene.page.rawValue).png")
                    group.enter()
                    writer.async {
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: still)
                        group.leave()
                    }
                }
            }
            window.contentView = nil
        }
        group.wait()
        print("2.x demo: \(frameIndex) frames at \(Int(fps)) fps in \(frames.path)")
    }
}

extension WebsiteDemo234 {
    /// The website's Home still: KemoSabe, a full-size Media tile (artwork wash,
    /// no lyric), a clock over timers, and system stats, with the fuller dock.
    static func runHome(output: URL) {
        let settings = NookSettings.shared
        let services = AppServices.shared
        let theme = ThemeStore.shared
        theme.selectFamily(.kemosabe)
        settings.showMusicLiveActivity = true
        settings.showTimerLiveActivity = false
        settings.showPowerLiveActivity = false
        settings.dockApps = [.music, .calendar, .reminders, .notes, .weather, .timers, .tray]
        services.systemStats.setPreview()
        let widgets: [(NookWidgetKind, NookWidgetSize)] = [(.media, .large), (.clock, .small), (.timer, .small),
                                                           (.systemStats, .medium)]
        let profile = NookProfile(id: UUID(), name: "Home", widgets: widgets.map(\.0))
        settings.profiles = [profile]
        settings.activeProfileID = profile.id
        for (kind, size) in widgets { settings.setSize(size, for: kind) }
        var info = NowPlayingInfo()
        info.title = "Maps - Live at the Royal Albert Hall"; info.artist = "Yeah Yeah Yeahs"
        info.album = "Hidden in Pieces: Live at the Royal Albert Hall"
        info.sourceName = "Music"; info.isPlaying = true; info.elapsed = 11; info.duration = 392
        info.capabilities = [.playPause, .previous, .next, .seek]
        info.artwork = NSImage(contentsOfFile: "/private/tmp/macspaces-maps.jpg")
        services.nowPlaying.setPreviewInfo(info)
        services.teleprompter.setPreview(current: "", upcoming: "", source: .lyrics)
        let timer = TimerService(previewRemaining: 0, total: 0)
        let model = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true),
            availableWidth: 1512, settings: settings, shelf: ShelfStore(basketID: UUID()),
            nowPlaying: services.nowPlaying, powerMonitor: services.powerMonitor, timerService: timer,
            bluetoothMonitor: services.bluetooth, systemActivityMonitor: services.systemActivity,
            teleprompter: services.teleprompter)
        let host = NSHostingView(rootView: DemoStage(model: model, wallpaper: ["#E7DCEB", "#B39CC6", "#7C629A", "#42325A"])
            .environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: stage)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.ignoresMouseEvents = true
        model.expand()
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let url = output.appendingPathComponent("kemosabe-home.png")
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        print("Home still: \(url.path)")
    }
}

extension WebsiteDemo234 {
    /// Synthetic weather for every capture, so no real location's forecast appears.
    static func previewWeather(at now: Date = Date()) {
        let services = AppServices.shared
        let day: (Int, Int, Double, Double) -> WeatherSnapshot.Day = { offset, code, high, low in
            .init(date: Calendar.current.date(byAdding: .day, value: offset, to: now)!, weatherCode: code, high: high, low: low)
        }
        let hours: [WeatherSnapshot.Hour] = (0..<12).map { offset in
            let date = Calendar.current.date(byAdding: .hour, value: offset, to: now)!
            return .init(date: date,
                  weatherCode: [1, 1, 2, 2, 3, 3, 2, 1, 1, 0, 0, 0][offset],
                  temperature: [18, 19, 19, 18, 17, 16, 15, 14, 14, 13, 12, 12][offset],
                  isDay: (7..<19).contains(Calendar.current.component(.hour, from: date)), precipitationChance: [0, 0, 5, 10, 20, 20, 10, 5, 0, 0, 0, 0][offset])
        }
        services.weather.setPreviewSnapshot(.init(temperature: 18, weatherCode: 1, high: 21, low: 11,
            upcoming: [day(1, 0, 23, 12), day(2, 2, 20, 11), day(3, 61, 16, 10), day(4, 1, 19, 11)],
            hourly: hours, feelsLike: 17, humidity: 52, windSpeed: 9, precipitationChance: 10,
            sunrise: nil, sunset: Calendar.current.date(bySettingHour: 19, minute: 2, second: 0, of: now)))
    }

    /// An original, generated cover: a two-colour gradient with a sun and horizon.
    static func cover(_ top: NSColor, _ bottom: NSColor, seed: Int) -> NSImage {
        NSImage(size: NSSize(width: 360, height: 360), flipped: false) { rect in
            NSGradient(colors: [bottom, top])?.draw(in: rect, angle: 90)
            bottom.withAlphaComponent(0.9).setFill()
            let x = [210, 130, 180][seed % 3]
            NSBezierPath(ovalIn: NSRect(x: x, y: 170, width: 100, height: 100)).fill()
            top.withAlphaComponent(0.85).setFill()
            let hills = NSBezierPath()
            hills.move(to: .zero)
            for step in 0...36 {
                let px = CGFloat(step) * 10
                hills.line(to: NSPoint(x: px, y: 110 + 26 * sin(CGFloat(step) / 6 + CGFloat(seed))))
            }
            hills.line(to: NSPoint(x: 360, y: 0)); hills.close(); hills.fill()
            return true
        }
    }
}

/// The site's tour: the closed notch playing a song, the Nook dropping open onto Home, across
/// to the Clock page, where two places are picked and Match up finds the hours that suit
/// everyone, then closing, on a MacBook-sized desktop.
@MainActor
enum WebsiteDemoNotch {
    final class Clock: ObservableObject { @Published var t: Double = 0 }

    /// The dock in website captures (`WebsiteDemoProfile.dock`).
    static var siteDock: [NotchTab] { WebsiteDemoProfile.dock }

    static func run(output: URL) {
        let services = AppServices.shared
        let theme = ThemeStore.shared
        let frames = output.appendingPathComponent("notch-frames", isDirectory: true)
        try? FileManager.default.removeItem(at: frames)
        try! FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)

        // The shared demo profile (WebsiteDemoProfile): the owner's Home, the Clear look, the
        // site dock, a running timer and Keep Awake on, in the step's theme with its song.
        let env = ProcessInfo.processInfo.environment
        WebsiteDemoProfile.apply(theme: env["MACSPACES_DEMO_HERO_THEME"].flatMap(ThemeFamily.init(rawValue:)) ?? .nightBlossom,
                                 keepAwake: nil)
        defer { WebsiteDemoProfile.finish() }
        let shownTime = WebsiteDemoProfile.shownTime
        Design.demoClockDate = shownTime
        defer { Design.demoClockDate = nil }
        WebsiteDemoProfile.play(WebsiteDemoProfile.environmentTrack)
        let model = WebsiteDemoProfile.model(availableWidth: stage.width)
        model.screenFrame = CGRect(origin: .zero, size: stage)

        // The theme's photo inside the Nook, as the app draws it, panning with its petals: in a
        // SwiftUI Canvas without the breeze's Metal distortion, since `cacheDisplay` leaves out
        // both Core Animation's layers and shaders (the open Nook came out plain).
        ThemeMotifView.flowersUseCoreAnimation = false
        ThemeMotifView.breezeUsesShader = false
        defer { ThemeMotifView.flowersUseCoreAnimation = true; ThemeMotifView.breezeUsesShader = true }
        // The Music page's lyric: Scenes with one short real line of the song.
        theme.lyricStyle = .stickers
        let lyric = ProcessInfo.processInfo.environment["MACSPACES_DEMO_LYRIC"] ?? ""

        let clock = Clock()
        let host = NSHostingView(rootView: NotchStage(model: model, clock: clock).environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: stage)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        // The real pointer must never reach the capture (hover would close the Nook).
        window.ignoresMouseEvents = true
        // On a screen: off it, the display link that steps SwiftUI's animations doesn't run and
        // every frame shows the end state, so each beat was a cut.
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        window.setFrameOrigin(NSPoint(x: screen.minX, y: screen.maxY - stage.height))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let fps = WebsiteDemo234.fps
        // Frames are drawn straight at the site card's 1640×940 from the crop around the Nook (text
        // and shapes are drawn at that size, not scaled up) and written off the main thread.
        func capture() -> NSBitmapImageRep? { Self.capture(host, crop: crop) }
        // Time slows enough that every frame is taken before the next is due: SwiftUI's
        // animations follow the clock, so a late frame skips motion (GitHub's Macs take a
        // few hundred milliseconds a frame). Measured on the busiest pages, Music and the Clock globe.
        var captureCost = 0.0, writeCost = 0.0
        for page in [NotchTab.music, .clock] {
            model.expand(to: page)
            if page == .music { services.teleprompter.setPreview(current: lyric, upcoming: "", source: .lyrics) }
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            _ = capture()
            var captures: [Double] = [], writes: [Double] = []
            for _ in 0..<5 {
                let began = Date()
                guard let bitmap = capture() else { continue }
                let captured = Date()
                _ = bitmap.representation(using: .png, properties: [:])
                captures.append(captured.timeIntervalSince(began)); writes.append(Date().timeIntervalSince(captured))
            }
            // Medians: the first pass of a page builds caches and would overstate it.
            captureCost = max(captureCost, captures.sorted()[captures.count / 2])
            writeCost = max(writeCost, writes.sorted()[writes.count / 2])
        }
        services.teleprompter.setPreview(current: "", upcoming: "", source: .lyrics)
        model.collapse()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        model.selectedTab = .nook
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let cores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        let frameCost = captureCost + writeCost / cores
        let scale = min(90, max(WebsiteDemo234.timeScale, (frameCost * fps * 2.5).rounded(.up)))
        print("Notch demo: a frame takes \(Int(captureCost * 1000)) ms to draw and \(Int(writeCost * 1000)) ms to write; time runs \(Int(scale))x slower")
        fflush(stdout)
        let writer = DispatchQueue(label: "notch-frame-writer", qos: .utility, attributes: .concurrent)
        let inFlight = DispatchSemaphore(value: 6)
        let group = DispatchGroup()
        Design.demoTimeScale = scale
        defer { Design.demoTimeScale = 1; window.orderOut(nil); window.contentView = nil }
        // Beats (seconds of video): the closed notch with the song, open to Home, across to Music
        // where the lyric arrives in Scenes, a short look at the Clock globe (New York ticked, so
        // it turns), close, then the closed notch again so the loop joins up. Frames are taken
        // in slowed time, so the 60 fps encode plays at the app's real speed.
        var done = Set<String>()
        func once(_ key: String, _ at: Double, _ t: Double, _ action: () -> Void) {
            if t >= at, done.insert(key).inserted { action() }
        }
        let start = Date()
        var lateness = 0.0, lateFrames = 0
        for n in 0..<Int(tourLength * fps) {
            let t = Double(n) / fps
            clock.t = t
            once("open", Beat.open, t) { model.expand(to: .nook) }
            once("music", Beat.music, t) { withAnimation(Design.spring()) { model.selectedTab = .music } }
            once("lyric", Beat.lyric, t) {
                withAnimation(Design.spring()) { services.teleprompter.setPreview(current: lyric, upcoming: "", source: .lyrics) }
            }
            once("clock", Beat.clock, t) { withAnimation(Design.spring()) { model.selectedTab = .clock } }
            once("place", Beat.clock + 0.35, t) { NotificationCenter.default.post(name: ClockPage.demoAction, object: matched[0]) }
            once("close", Beat.close, t) { model.collapse() }
            RunLoop.main.run(until: start.addingTimeInterval(t * scale))
            let late = Date().timeIntervalSince(start) / scale - t
            lateness = max(lateness, late)
            if late > 0.5 / fps { lateFrames += 1 }
            if n % 120 == 0 { print("Notch demo: frame \(n), \(String(format: "%.3f", late)) s late"); fflush(stdout) }
            guard let bitmap = capture() else { continue }
            var urls = [frames.appendingPathComponent(String(format: "f%05d.png", n))]
            // The poster: the Music page with the lyric settled.
            if n == Int(posterAt * fps) { urls.append(output.appendingPathComponent("notch-poster.png")) }
            inFlight.wait()
            group.enter()
            writer.async {
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    for url in urls { try? data.write(to: url) }
                }
                inFlight.signal(); group.leave()
            }
        }
        group.wait()
        print("Notch demo: \(Int(tourLength * fps)) frames in \(frames.path); crop \(Int(crop.width))×\(Int(crop.height)) of the stage \(Int(stage.width))×\(Int(stage.height)) on a \(Int(screen.width))×\(Int(screen.height)) screen at \(Int(scale))x slower; \(lateFrames) frames over half a frame late (at most \(String(format: "%.3f", lateness)) s)")
    }

    /// The top of a 14-inch MacBook Pro's screen (1512 points wide, the camera 185 of them), cropped
    /// to the site card's shape, so the Nook (860 at most) sits at its real size with room either side.
    static let stage = CGSize(width: 1512, height: 867)
    /// The site card, in pixels.
    static let frameSize = CGSize(width: 1640, height: 940)
    /// The tour's beats, in seconds of video.
    enum Beat {
        static let open = 0.6, music = 2.8, lyric = 3.15, clock = 7.0, close = 8.7
    }
    static let tourLength = 10.4, posterAt = 5.6
    /// What the tour shows of the stage: the top centre, 800 points wide (the Nook is 620 at
    /// most here), so the Nook fills the site's card at about twice the size a full screen gives.
    static let crop = CGRect(x: (stage.width - 800) / 2, y: 0, width: 800, height: 800 * frameSize.height / frameSize.width)

    /// The part `crop` of a stage (points, top-left origin) drawn at the card's 1640×940.
    static func capture(_ host: NSView, crop: CGRect) -> NSBitmapImageRep? {
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(frameSize.width), pixelsHigh: Int(frameSize.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        let rect = NSRect(x: crop.minX, y: host.isFlipped ? crop.minY : host.bounds.height - crop.maxY,
                          width: crop.width, height: crop.height)
        bitmap.size = rect.size
        host.cacheDisplay(in: rect, to: bitmap)
        return bitmap
    }
    /// The tour turns the Clock globe to the first of these (`WebsiteDemoProfile.places`).
    static let matched = ["America/New_York", "Europe/London"]
}

/// Desktop and notch for the notch video (the file drop has its own Tray clip).
struct WebsiteBlossomWallpaper: View {
    var body: some View {
        GeometryReader { proxy in
            Group {
                if let path = ProcessInfo.processInfo.environment["MACSPACES_DEMO_WALLPAPER"], let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else { Image("ThemeBlossom").resizable().scaledToFill() }
            }
                .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                .overlay(Color(themeHex: "24161C")!.opacity(0.18))
        }
    }
}

private struct NotchStage: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var clock: WebsiteDemoNotch.Clock

    var body: some View {
        let size = WebsiteDemoNotch.stage
        ZStack(alignment: .top) {
            Group {
                // MACSPACES_DEMO_WALLPAPER_ASSET puts a theme photo on the desktop (ThemeNightBlossom
                // for the tour), so the clip matches the other site cards instead of a flat placeholder.
                if let asset = ProcessInfo.processInfo.environment["MACSPACES_DEMO_WALLPAPER_ASSET"] {
                    Image(asset).resizable().scaledToFill().overlay(Color.black.opacity(0.12))
                } else if ProcessInfo.processInfo.environment["MACSPACES_DEMO_THEME"] == "blossom" { WebsiteBlossomWallpaper() }
                else { DemoWallpaper(colors: ["#DDE6F3", "#A6BBD8", "#6C87AE", "#344B70"].map { Color(themeHex: $0) ?? .gray }) }
            }.frame(width: size.width, height: size.height).clipped()
            DemoMenuBar(height: model.geometry.height, within: WebsiteDemoNotch.crop.minX...WebsiteDemoNotch.crop.maxX)
            NotchContainerView(viewModel: model)
                .frame(width: size.width, height: size.height, alignment: .top)
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                .fill(.black).frame(width: model.geometry.width, height: model.geometry.height)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// A plain menu bar either side of the camera, so the tour reads as a Mac's screen. `within`
/// is the stretch of the stage a cropped video shows: the items sit inside it, fewer of them.
/// `sparse` leaves only the clock on the right, clear of the agent bubble.
struct DemoMenuBar: View {
    let height: CGFloat
    var within: ClosedRange<CGFloat>? = nil
    var sparse = false

    var body: some View {
        GeometryReader { proxy in
            let cropped = within != nil
            let span = within ?? 0...proxy.size.width
            HStack(spacing: 0) {
                HStack(spacing: 20) {
                    Image(systemName: "apple.logo").font(.system(size: 14, weight: .medium))
                    Text("Finder").fontWeight(.bold)
                    ForEach(sparse ? ["File", "Edit"] : cropped ? ["File", "Edit", "View"] : ["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { Text($0) }
                }
                Spacer()
                HStack(spacing: 18) {
                    if !sparse {
                        Image(systemName: "battery.75percent")
                        Image(systemName: "wifi")
                    }
                    if !cropped {
                        Image(systemName: "magnifyingglass")
                        Image(systemName: "switch.2")
                    }
                    Text(Design.clockDate(Date()), format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                }
            }
            .padding(.horizontal, 18)
            .frame(width: span.upperBound - span.lowerBound, height: height)
            .offset(x: span.lowerBound)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.92))
        .frame(height: height)
        .background(Color.black.opacity(0.22))
    }
}

struct DraggedFile: View {
    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            VStack(spacing: 3) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white, Color(white: 0.55))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                Text("Trip itinerary.md")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.white)
            }
            .opacity(0.9)
            Image(systemName: "cursorarrow")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .shadow(color: .white, radius: 0.5)
                .offset(x: -30, y: 10)
        }
    }
}

/// A themed desktop: layered waves behind the notch and the Nook.
private struct DemoStage: View {
    @ObservedObject var model: NotchViewModel
    let wallpaper: [String]

    var body: some View {
        ZStack(alignment: .top) {
            DemoWallpaper(colors: wallpaper.map { Color(themeHex: $0) ?? .gray })
            NotchContainerView(viewModel: model)
                .frame(width: WebsiteDemo234.stage.width, height: WebsiteDemo234.stage.height, alignment: .top)
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                .fill(.black).frame(width: 185, height: 32)
        }
        .frame(width: WebsiteDemo234.stage.width, height: WebsiteDemo234.stage.height)
        .clipped()
    }
}

struct DemoWallpaper: View {
    let colors: [Color]

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                colors[0]
                wave(w, h, base: 0.46, amplitude: 0.10, phase: 0.2).fill(colors[1])
                wave(w, h, base: 0.62, amplitude: 0.12, phase: 1.4).fill(colors[2])
                wave(w, h, base: 0.80, amplitude: 0.09, phase: 2.6).fill(colors[3])
            }
        }
    }

    private func wave(_ w: CGFloat, _ h: CGFloat, base: CGFloat, amplitude: CGFloat, phase: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: h))
            for step in 0...80 {
                let x = w * CGFloat(step) / 80
                let y = h * (base + amplitude * sin(CGFloat(step) / 80 * .pi * 1.6 + phase))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: w, y: h))
            path.closeSubpath()
        }
    }
}
#endif
