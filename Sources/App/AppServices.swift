import Foundation

/// Services shared by the Nook windows on all displays.
/// Polling is reconciled against the active profiles instead of running just
/// because a feature was used once.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let nowPlaying = NowPlayingController()
    let powerMonitor = PowerSourceMonitor()
    let timerService = TimerService()
    private var clipboardStorage: ClipboardMonitor?
    var clipboard: ClipboardMonitor {
        if let value = clipboardStorage { return value }
        let value = ClipboardMonitor()
        clipboardStorage = value
        return value
    }
    private var systemStatsStorage: SystemStatsService?
    var systemStats: SystemStatsService {
        if let value = systemStatsStorage { return value }
        let value = SystemStatsService()
        systemStatsStorage = value
        return value
    }
    private var weatherStorage: WeatherService?
    var weather: WeatherService {
        if let value = weatherStorage { return value }
        let value = WeatherService()
        weatherStorage = value
        return value
    }
    let calendar = CalendarService()
    let shortcuts = ShortcutsService()
    let bluetooth = BluetoothMonitor()
    let systemActivity = SystemActivityMonitor()
    private var keepAwakeStorage: KeepAwakeService?
    var keepAwake: KeepAwakeService {
        if let value = keepAwakeStorage { return value }
        let value = KeepAwakeService()
        keepAwakeStorage = value
        return value
    }
    private var audioMixerStorage: AudioMixerService?
    var audioMixer: AudioMixerService {
        if let value = audioMixerStorage { return value }
        let value = AudioMixerService()
        audioMixerStorage = value
        return value
    }
    private var teleprompterStorage: TeleprompterService?
    var teleprompter: TeleprompterService {
        if let value = teleprompterStorage { return value }
        let value = TeleprompterService(nowPlaying: nowPlaying)
        teleprompterStorage = value
        return value
    }

    private init() {}

    func reconcileDemand(
        app: AppSettings,
        nook: NookSettings
    ) {
        let nookWidgets = nook.widgets

        let needsTeleprompter = app.notchEnabled && nook.showTeleprompterBar

        // The teleprompter is driven entirely by now-playing, so it has to keep
        // that service alive on its own. Without this the bar sits permanently
        // blank whenever no media widget happens to be enabled alongside it.
        let needsNowPlaying =
            app.notchEnabled &&
                (nook.showMusicLiveActivity || nookWidgets.contains(.media))
            || needsTeleprompter
        needsNowPlaying ? nowPlaying.start() : nowPlaying.stop()

        let needsPower = app.notchEnabled &&
            (nook.showPowerLiveActivity || nookWidgets.contains(.battery))
        needsPower ? powerMonitor.start() : powerMonitor.stop()

        let needsBluetooth = app.notchEnabled && nookWidgets.contains(.battery)
        needsBluetooth ? bluetooth.start() : bluetooth.stop()

        let needsSystemActivity = app.notchEnabled && (
            nook.showVolumeLiveActivity
                || nook.showBrightnessLiveActivity
                || nook.showKeyboardBrightnessLiveActivity
                || nook.showMicrophoneLiveActivity
                || nook.showFocusLiveActivity
        )
        needsSystemActivity ? systemActivity.start() : systemActivity.stop()

        if needsTeleprompter { teleprompter.start() } else { teleprompterStorage?.stop() }

        // The session outlives the closed panel, but not the widget itself.
        if !(app.notchEnabled && nookWidgets.contains(.pomodoro)) {
            PomodoroModel.shared.stopForRemoval()
        }

        let needsWeather = app.notchEnabled && nookWidgets.contains(.weather)
        if needsWeather { weather.startIfNeeded() } else { weatherStorage?.stop() }
        let needsClipboard = app.notchEnabled && nookWidgets.contains(.clipboard)
        if needsClipboard { clipboard.start() } else { clipboardStorage?.stop() }

        let needsAudioMixer = app.notchEnabled && nookWidgets.contains(.audioControls)
        if needsAudioMixer { audioMixer.start() } else { audioMixerStorage?.stop() }
        let needsStats = app.notchEnabled && nookWidgets.contains(.systemStats)
        if needsStats { systemStats.start() } else { systemStatsStorage?.stop() }
        if !app.notchEnabled || !nookWidgets.contains(.keepAwake) { keepAwakeStorage?.stop() }

        let needsEvents =
            app.notchEnabled && nookWidgets.contains(.calendar)

        needsEvents ? calendar.startEventsIfNeeded() : calendar.stopEvents()

        let needsReminders =
            app.notchEnabled && nookWidgets.contains(.todos)

        needsReminders ? calendar.startRemindersIfNeeded() : calendar.stopReminders()
    }
}
