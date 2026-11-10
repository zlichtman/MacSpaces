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
    /// The Home still (`page-home`, cropped for the README's Home picture): the Home people
    /// would want, at the widgets' own sizes so the real layout engine fits it in the Nook's
    /// 860 points: Music large, today's next events, and the running timer over the time
    /// (Weather as well would pass 860, and Home would scroll).
    /// `MACSPACES_DEMO_HOME_WIDGETS` (raw names, comma separated) tries another layout.
    static var homeStill: [NookWidgetKind] {
        let raw = ProcessInfo.processInfo.environment["MACSPACES_DEMO_HOME_WIDGETS"]?.split(separator: ",")
        return raw.map { $0.compactMap { NookWidgetKind(rawValue: String($0)) } } ?? [.media, .calendar, .timer, .clock]
    }
    /// The Home still's theme and song: Autumn with Seasons by Suki Waterhouse, the Music reel's
    /// pairing, its warm red-gold cover set against the autumn scene. `MACSPACES_DEMO_HOME_THEME`
    /// and `MACSPACES_DEMO_HOME_SONG` (a demo song's key) render the alternates.
    static var homeTheme: ThemeFamily {
        ProcessInfo.processInfo.environment["MACSPACES_DEMO_HOME_THEME"].flatMap(ThemeFamily.init(rawValue:)) ?? .autumn
    }
    static var homeSong: String { ProcessInfo.processInfo.environment["MACSPACES_DEMO_HOME_SONG"] ?? "suki-waterhouse" }

    /// The Home still's day, made up: a 9:15 to 10:30 review (no call link, so no Join chip cuts
    /// its end time short), then coffee at 11:15 and lunch at 12:30, each on the next such time
    /// so none has passed, whatever the real hour.
    static func homeStillEvents(now: Date = Date()) -> [CalendarEventItem] {
        func next(_ hour: Int, _ minute: Int) -> Date {
            let calendar = Calendar.current
            let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
            return today > now.addingTimeInterval(3600) ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
        func color(_ r: Double, _ g: Double, _ b: Double) -> CalendarEventColor { .init(red: r, green: g, blue: b, alpha: 1) }
        let reviewEnd = next(10, 30)
        // 9:15 to 10:30, so every time shown is a morning's whatever hour the render runs at
        // (from the real clock a night render once printed a 2:18 AM start).
        let reviewStart = reviewEnd.addingTimeInterval(-75 * 60)
        let coffee = next(11, 15), lunch = next(12, 30)
        return [
            .init(id: "home-review", title: "Design review", startDate: reviewStart, endDate: reviewEnd,
                  location: "Studio", notes: nil, url: nil, color: color(0.95, 0.55, 0.2)),
            .init(id: "home-coffee", title: "Coffee with Maya", startDate: coffee, endDate: coffee.addingTimeInterval(1800),
                  location: "Corner café", notes: nil, url: nil, color: color(0.85, 0.35, 0.3)),
            .init(id: "home-lunch", title: "Lunch with Sam", startDate: lunch, endDate: lunch.addingTimeInterval(3600),
                  location: nil, notes: nil, url: nil, color: color(0.3, 0.7, 0.45)),
        ]
    }

    /// Sets up the Home still: its Home, song and day (`page-home` sets its theme).
    static func prepareHomeStill() {
        setHome(homeStill)
        play(track(homeSong) ?? homeTrack)
        AppServices.shared.calendar.setAppPreview(todayEvents: homeStillEvents())
    }

    /// Puts back what `prepareHomeStill` changed, for the captures after it.
    static func finishHomeStill() {
        setHome(home)
        AppServices.shared.calendar.setAppPreview()
    }
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
        services.teleprompter.setPreview(current: "", source: .lyrics)
        services.timerService.setPreview(remaining: timerRemaining, total: timerTotal)
        // A MacBook on its charger with a healthy battery (the runners have none), and no
        // plug-in moment, so no power bubble shows beside the closed notch.
        services.powerMonitor.setPreview(state: .charging, level: 82, minutesToFull: 38, health: BatteryHealth(maximumCapacity: 87, conditionNormal: true, fetchedAt: Date()),
                                         cycles: 343, activity: false)
        // The clocks stay at 9:41 (`finish` lets them run again).
        Design.demoClockDate = shownTime
        services.keepAwake.start(mode: .system, minutes: keepAwake)
        // Motion on whatever the runner's setting (GitHub's Macs have Reduce Motion on).
        theme.setPreviewSystemReduceMotion(false)
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

    /// The closed notch's geometry: the camera housing.
    static var geometry: NotchGeometry {
        NotchGeometry(width: notchSize.width, height: notchSize.height, cutout: .notch,
                      notchlessHint: NookSettings.shared.notchlessHint)
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
}
#endif
