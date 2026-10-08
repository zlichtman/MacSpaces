#if DEBUG
import SwiftUI
import AppKit

/// The 2.x website demo: three themed desktops, each showing the Nook drop,
/// Home, and one dock page. Frames are rendered natively at 60 fps by slowing
/// the motion tokens (Design.demoTimeScale) so every frame can be captured.
/// Content is synthetic; no camera, clipboard, calendar or files are read.
@MainActor
enum WebsiteDemo234 {
    static let stage = CGSize(width: 1100, height: 608)
    static let fps = 60.0
    static let timeScale = 8.0

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
        Scene(name: "midnight", family: .macspaces, wallpaper: ["#DDE6F3", "#A6BBD8", "#6C87AE", "#344B70"],
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
        settings.dockApps = [.music, .calendar, .terminal, .timers, .weather, .tray]
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
            theme.appearanceMode = .dark
            theme.lyricStyle = scene.lyricStyle
            theme.animatesEffects = true
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
        theme.appearanceMode = .dark
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
    static func previewWeather() {
        let services = AppServices.shared
        let day: (Int, Int, Double, Double) -> WeatherSnapshot.Day = { offset, code, high, low in
            .init(date: Calendar.current.date(byAdding: .day, value: offset, to: Date())!, weatherCode: code, high: high, low: low)
        }
        let hours: [WeatherSnapshot.Hour] = (0..<12).map { offset in
            .init(date: Calendar.current.date(byAdding: .hour, value: offset, to: Date())!,
                  weatherCode: [1, 1, 2, 2, 3, 3, 2, 1, 1, 0, 0, 0][offset],
                  temperature: [18, 19, 19, 18, 17, 16, 15, 14, 14, 13, 12, 12][offset],
                  isDay: offset < 3, precipitationChance: [0, 0, 5, 10, 20, 20, 10, 5, 0, 0, 0, 0][offset])
        }
        services.weather.setPreviewSnapshot(.init(temperature: 18, weatherCode: 1, high: 21, low: 11,
            upcoming: [day(1, 0, 23, 12), day(2, 2, 20, 11), day(3, 61, 16, 10), day(4, 1, 19, 11)],
            hourly: hours, feelsLike: 17, humidity: 52, windSpeed: 9, precipitationChance: 10,
            sunrise: nil, sunset: Calendar.current.date(bySettingHour: 19, minute: 2, second: 0, of: Date())))
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

/// The notch itself: live activities while closed, a hover peek, a file
/// dragged to the notch (it swells into "Drop to Tray"), then the Tray.
@MainActor
enum WebsiteDemoNotch {
    final class Clock: ObservableObject { @Published var t: Double = 0 }

    static func run(output: URL) {
        let settings = NookSettings.shared
        let services = AppServices.shared
        let theme = ThemeStore.shared
        let frames = output.appendingPathComponent("notch-frames", isDirectory: true)
        try? FileManager.default.removeItem(at: frames)
        try! FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)

        // MACSPACES_DEMO_THEME=everforest renders the same clip in Everforest with Almost Fantasy.
        let green = ProcessInfo.processInfo.environment["MACSPACES_DEMO_THEME"] == "everforest"
        theme.selectFamily(green ? .everforest : .macspaces); theme.appearanceMode = .dark
        settings.expandOnHover = false
        settings.openTrayOnFileDrag = true
        settings.showMusicLiveActivity = true
        settings.showTimerLiveActivity = false
        settings.showPowerLiveActivity = false
        settings.dockApps = [.music, .calendar, .terminal, .timers, .weather, .tray]
        let widgets: [(NookWidgetKind, NookWidgetSize)] = [(.media, .large), (.timer, .small), (.clock, .small),
                                                           (.weather, .small), (.systemStats, .small)]
        let profile = NookProfile(id: UUID(), name: "Notch", widgets: widgets.map(\.0))
        settings.profiles = [profile]; settings.activeProfileID = profile.id
        for (kind, size) in widgets { settings.setSize(size, for: kind) }
        services.systemStats.setPreview()
        services.calendar.setAppPreview()
        WebsiteDemo234.previewWeather()
        services.teleprompter.setPreview(current: "", upcoming: "", source: .lyrics)
        var info = NowPlayingInfo()
        if green {
            info.title = "Almost Fantasy"; info.artist = "Fog Lake"; info.album = "Almost Fantasy"
        } else {
            info.title = "I Melt With You - Rerecorded"; info.artist = "Modern English"; info.album = "Pillow Lips"
        }
        info.sourceName = "Music"
        info.isPlaying = true; info.elapsed = 74; info.duration = 236
        info.capabilities = [.playPause, .previous, .next, .seek]
        info.artwork = NSImage(contentsOfFile: (ProcessInfo.processInfo.environment["MACSPACES_DEMO_COVERS"]
            ?? "/private/tmp/macspaces-covers") + (green ? "/almostfantasy.jpg" : "/midnight.jpg"))
        services.nowPlaying.setPreviewInfo(info)
        let timer = TimerService(previewRemaining: 12 * 60 + 40, total: 25 * 60)

        let shelf = ShelfStore(basketID: UUID())

        let model = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true),
            availableWidth: 1512, settings: settings, shelf: shelf, nowPlaying: services.nowPlaying,
            powerMonitor: services.powerMonitor, timerService: timer, bluetoothMonitor: services.bluetooth,
            systemActivityMonitor: services.systemActivity, teleprompter: services.teleprompter)
        let clock = Clock()
        let host = NSHostingView(rootView: NotchStage(model: model, clock: clock).environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: WebsiteDemo234.stage)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        // The real pointer must never reach the capture (hover would close the Nook).
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))

        let fps = WebsiteDemo234.fps, scale = WebsiteDemo234.timeScale
        let writer = DispatchQueue(label: "notch-frame-writer")
        let group = DispatchGroup()
        Design.demoTimeScale = scale
        defer { Design.demoTimeScale = 1 }
        // Beats (seconds): peek, unpeek, open to Home, Weather, Calendar, back Home, close.
        var done = Set<String>()
        func once(_ key: String, _ at: Double, _ t: Double, _ action: () -> Void) {
            if t >= at, done.insert(key).inserted { action() }
        }
        let start = Date()
        let length = 12.8
        for n in 0..<Int(length * fps) {
            let t = Double(n) / fps
            clock.t = t
            once("peek", 1.0, t) { model.hoverChanged(true) }
            once("unpeek", 2.0, t) { model.hoverChanged(false) }
            once("open", 2.8, t) { model.expand(to: .nook) }
            once("weather", 5.6, t) { withAnimation(Design.spring()) { model.selectedTab = .weather } }
            once("calendar", 8.2, t) { withAnimation(Design.spring()) { model.selectedTab = .calendar } }
            once("home", 10.6, t) { withAnimation(Design.spring()) { model.selectedTab = .nook } }
            once("close", 12.0, t) { model.collapse() }
            RunLoop.main.run(until: start.addingTimeInterval(t * scale))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let url = frames.appendingPathComponent(String(format: "f%05d.png", n))
            group.enter()
            writer.async { try? bitmap.representation(using: .png, properties: [:])?.write(to: url); group.leave() }
        }
        group.wait()
        print("Notch demo: \(Int(length * fps)) frames in \(frames.path)")
    }
}

/// Desktop and notch for the notch video (the file drop has its own Tray clip).
private struct NotchStage: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var clock: WebsiteDemoNotch.Clock

    var body: some View {
        let size = WebsiteDemo234.stage
        ZStack(alignment: .top) {
            DemoWallpaper(colors: (ProcessInfo.processInfo.environment["MACSPACES_DEMO_THEME"] == "everforest" ? ["#E4ECD6", "#AFC398", "#6F8C63", "#3E5439"] : ["#DDE6F3", "#A6BBD8", "#6C87AE", "#344B70"])
                .map { Color(themeHex: $0) ?? .gray })
            NotchContainerView(viewModel: model)
                .frame(width: size.width, height: size.height, alignment: .top)
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                .fill(.black).frame(width: 185, height: 32)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
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
