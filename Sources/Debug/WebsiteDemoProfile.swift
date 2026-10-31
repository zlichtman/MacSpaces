#if DEBUG
import SwiftUI
import AppKit

/// The one demo profile every website still and video starts from (`WebsiteDemoClips`, the tour
/// `WebsiteDemoNotch`, `WebsiteDemoAgents`, Feature QA's `site-agent-popout`), so they show the app
/// as it is today and can't drift into hand-built old screens: the owner's Home layout at each
/// widget's own fitted size (no saved sizes), the Clear closed-notch look, the site dock, the
/// app's own activity defaults, a real song (never a made-up one), a running timer and Keep Awake
/// on. A capture changes only what its story needs (its page's theme, which page is open).
@MainActor
enum WebsiteDemoProfile {
    /// The owner's Home: Music, the timer over the time, and Keep Awake. Sizes are the widgets'
    /// own (`NookWidgetKind.defaultSize`): small widgets side by side stack, so the timer is the
    /// compact one (+1 and ×) and Keep Awake shows its cup with the time left.
    static let home: [NookWidgetKind] = [.media, .timer, .clock, .keepAwake]
    /// The Home still's theme: Snow, with the owner's I Melt With You (its blue petal cover).
    static let homeTheme: ThemeFamily = .alpine
    /// The closed notch: the Clear look (each activity its own bubble beside the camera, in a row
    /// with the agent bubble). The app's default is Solid; the site shows the Clear look.
    static let look: NotchGeometry.Look = .clear
    /// A 14-inch MacBook Pro's camera housing, in points.
    static let notchSize = CGSize(width: 185, height: 32)
    /// The dock in website captures: a short set so the Nook isn't crowded (owner). A page outside
    /// it is added for its own capture so its icon still lights up.
    static let dock: [NotchTab] = [.music, .weather, .calendar, .clock, .system, .terminal, .tray, .timers]
    /// The clocks stay at 9:41 in the morning (a capture takes many real minutes).
    static var shownTime: Date { Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date() }
    /// The running timer (as Home and the Timers page show it).
    static let timerRemaining: TimeInterval = 18 * 60 + 19, timerTotal: TimeInterval = 25 * 60
    /// Keep Awake's session in stills; videos keep it on with no end, since its countdown follows
    /// the real clock and would race in slowed time.
    static let keepAwakeMinutes = 90

    /// A real song: title, artist, album, length, cover and an optional short lyric excerpt,
    /// with when that line is sung and when the next one starts (LRCLIB's timing, fetched by
    /// the workflow), so the song's position matches the line.
    struct Track: Decodable {
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let cover: String
        let lyrics: [String]?
        var lyricAt: Double? = nil
        var lyricEnd: Double? = nil
    }

    struct MusicSequence: Decodable {
        struct Song: Decodable { let key: String; let theme: String }
        let segmentSeconds: Double
        let posterSeconds: Double
        let songs: [Song]
    }

    static var musicSequence: MusicSequence {
        guard let path = ProcessInfo.processInfo.environment["MACSPACES_DEMO_SEQUENCE"],
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let sequence = try? JSONDecoder().decode(MusicSequence.self, from: data),
              !sequence.songs.isEmpty, sequence.segmentSeconds >= 4 else {
            fatalError("Missing or invalid approved music sequence (MACSPACES_DEMO_SEQUENCE)")
        }
        for song in sequence.songs {
            guard ThemeFamily(rawValue: song.theme) != nil,
                  let track = track(song.key), let line = track.lyrics?.first, !line.isEmpty,
                  track.lyricAt != nil, NSImage(contentsOfFile: track.cover) != nil else {
                fatalError("Incomplete approved music fixture: \(song.key). Run Scripts/capture-demos.sh")
            }
        }
        return sequence
    }

    /// The song for stills: `MACSPACES_DEMO_TRACKS` (a JSON object keyed by name, fetched from
    /// iTunes Search at run time; covers are never committed) under `key`.
    static func track(_ key: String) -> Track? {
        ProcessInfo.processInfo.environment["MACSPACES_DEMO_TRACKS"]
            .flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
            .flatMap { try? JSONDecoder().decode([String: Track].self, from: $0) }?[key]
    }

    /// The song for videos: `MACSPACES_DEMO_TRACK_*`, set by the Feature QA step.
    static var environmentTrack: Track? {
        let env = ProcessInfo.processInfo.environment
        guard let title = env["MACSPACES_DEMO_TRACK_TITLE"] else { return nil }
        return Track(title: title, artist: env["MACSPACES_DEMO_TRACK_ARTIST"] ?? "", album: env["MACSPACES_DEMO_TRACK_ALBUM"] ?? "",
                     duration: Double(env["MACSPACES_DEMO_TRACK_DURATION"] ?? "") ?? 236,
                     cover: env["MACSPACES_DEMO_TRACK_COVER"] ?? "", lyrics: env["MACSPACES_DEMO_LYRIC"].map { [$0] })
    }

    /// The home still's song, then any video's: I Melt With You by Modern English, then the step's.
    static var homeTrack: Track? { track("home") ?? environmentTrack }

    /// Plays `track` in the app's Now Playing (at its lyric's moment, or 1:14), or says it's missing.
    static func play(_ track: Track?) {
        guard let track else {
            print("Website demo: no song (set MACSPACES_DEMO_TRACKS or MACSPACES_DEMO_TRACK_TITLE); nothing is playing")
            return
        }
        var info = NowPlayingInfo()
        info.title = track.title; info.artist = track.artist; info.album = track.album
        // From Spotify: the Music page then shows Apple Music's playlist button only for Music.
        info.sourceName = "Spotify"; info.sourceBundleID = "com.spotify.client"; info.isPlaying = true; info.elapsed = track.lyricAt.map { max(0, $0 - 0.3) } ?? 74; info.duration = track.duration
        info.capabilities = [.playPause, .previous, .next, .seek]
        info.artwork = NSImage(contentsOfFile: track.cover)
        AppServices.shared.nowPlaying.setPreviewInfo(info)
    }

    /// Sets the app up as the profile has it. `theme` nil keeps the current one; `keepAwake`
    /// is how long Keep Awake runs (nil: until stopped).
    static func apply(theme family: ThemeFamily? = nil, widgets: [NookWidgetKind] = home, keepAwake: Int? = keepAwakeMinutes) {
        let settings = NookSettings.shared
        let services = AppServices.shared
        let theme = ThemeStore.shared
        if let family { theme.selectFamily(family) }
        settings.notchLook = look
        settings.notchlessHint = true
        settings.expandOnHover = false
        settings.openTrayOnFileDrag = true
        // The app's own defaults for what shows beside the closed notch.
        settings.showMusicLiveActivity = true
        settings.showTimerLiveActivity = true
        settings.showPowerLiveActivity = true
        settings.dockApps = dock
        setHome(widgets)
        WidgetOptions.shared.clockStyle = .regular
        WidgetOptions.shared.clockPlaces = places
        services.systemStats.setPreview()
        services.calendar.setAppPreview()
        WebsiteDemo234.previewWeather(at: shownTime)
        services.teleprompter.setPreview(current: "", upcoming: "", source: .lyrics)
        services.timerService.setPreview(remaining: timerRemaining, total: timerTotal)
        // A MacBook on its charger with a healthy battery (the runners have none), and no
        // plug-in moment, so no power bubble shows beside the closed notch.
        services.powerMonitor.setPreview(state: .charging, level: 82, minutesToFull: 38, health: BatteryHealth(maximumCapacity: 87, conditionNormal: true, fetchedAt: Date()),
                                         cycles: 343, activity: false)
        // The clocks stay at 9:41 (`finish` lets them run again).
        Design.demoClockDate = shownTime
        services.keepAwake.start(mode: .system, minutes: keepAwake)
        // Motion on whatever the runner's setting (GitHub's Macs have Reduce Motion on).
        theme.reduceMotionPreference = false
        theme.setPreviewSystemReduceMotion(false)
        theme.lyricStyle = .classic
    }

    /// A Home with these widgets, each at its own size.
    static func setHome(_ widgets: [NookWidgetKind]) {
        let settings = NookSettings.shared
        let profile = NookProfile(id: UUID(), name: "Home", widgets: widgets)
        settings.profiles = [profile]; settings.activeProfileID = profile.id
    }

    /// Here (the runner's Chicago) and three places; the tour picks two whose working days
    /// overlap with Chicago's, so Match up has a window to show.
    static let places = ["America/Chicago", "America/New_York", "Europe/London", "Asia/Tokyo"]

    /// Ends what `apply` started that outlives the capture.
    static func finish() {
        AppServices.shared.keepAwake.stop()
        Design.demoClockDate = nil
    }

    /// The closed notch's geometry: the camera housing in the profile's look.
    static var geometry: NotchGeometry {
        NotchGeometry(width: notchSize.width, height: notchSize.height, cutout: .notch,
                      look: NookSettings.shared.notchLook, notchlessHint: NookSettings.shared.notchlessHint)
    }

    /// A Nook on a `width`-point screen, with the app's own services.
    static func model(availableWidth width: CGFloat = 1512, shelf: ShelfStore? = nil) -> NotchViewModel {
        let shelf = shelf ?? ShelfStore(basketID: UUID())
        let services = AppServices.shared
        return NotchViewModel(geometry: geometry, availableWidth: width, settings: NookSettings.shared, shelf: shelf,
                              nowPlaying: services.nowPlaying, powerMonitor: services.powerMonitor, timerService: services.timerService,
                              bluetoothMonitor: services.bluetooth, systemActivityMonitor: services.systemActivity,
                              teleprompter: services.teleprompter)
    }

    /// A photo theme's own scene photo (nil for a drawn scene such as Synthwave, or no scene).
    static func sceneAsset(for family: ThemeFamily) -> String? {
        family.motif.flatMap { $0.floralAsset ?? $0.natureAsset }
    }

    /// The desktop photo for a photo theme (its own scene). Drawn scenes use `SceneWallpaper`.
    static func wallpaper(for family: ThemeFamily) -> String {
        sceneAsset(for: family) ?? "ThemeBlossom"
    }

    /// Readies the Scenes sticker for `line`: the Fluent image the line draws (bundled, or
    /// downloaded from Microsoft's repository as the app would) decoded before any frame, so
    /// captures draw it. Returns whether it's ready.
    @discardableResult
    static func prepareSticker(for line: String) -> Bool {
        guard let emoji = StickerChoice.emoji(for: line) else {
            print("Website demo: text-only lyric, no matching scene for \"\(line)\"")
            return false
        }
        if StickerStore.shared.localFile(emoji) == nil {
            Task.detached { [emoji] in _ = await StickerStore.shared.request(emoji, waitingUpTo: 20) }
            let end = Date().addingTimeInterval(25)
            while StickerStore.shared.localFile(emoji) == nil, Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        }
        guard let images = StickerImages.loadForCapture(emoji, settledOnly: false) else {
            print("Website demo: STICKER MISSING, \(emoji) for \"\(line)\" didn't load")
            return false
        }
        StickerCapture.shared.images[emoji] = images
        print("Website demo: sticker \(emoji) for \"\(line)\" ready (\(images.animated ? "animated" : "still"), bundled \(StickerStore.bundledURL(emoji) != nil))")
        return true
    }
}

/// The desktop behind a capture: the theme's own scene, full screen. A photo theme shows its
/// photo; a drawn one (Synthwave, Rainbow, Code Rain, Warp) its scene at full strength over the
/// theme's own background, so a theme is never shown over another theme's scene.
struct SceneWallpaper: View {
    let family: ThemeFamily

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let asset = WebsiteDemoProfile.sceneAsset(for: family) {
                    Image(asset).resizable().scaledToFill()
                } else if let motif = family.motif {
                    let palette = family.palette(.dark)
                    ZStack {
                        palette.color(palette.background)
                        ThemeMotifView(motif: motif, accent: palette.color(palette.accent), ink: palette.color(palette.foreground),
                                       scale: 1.4, strength: 3, softensCenter: false)
                    }
                } else {
                    let palette = family.palette(.dark)
                    LinearGradient(colors: [palette.color(palette.surface), palette.color(palette.background)], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
    }
}
#endif
