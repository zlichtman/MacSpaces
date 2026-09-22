import Foundation

/// Single container for the long-lived services shared by the Notch and Dock
/// modules, so e.g. now-playing state is fetched once and displayed in both.
/// Polling is reconciled against the active profiles instead of running just
/// because a feature was used once.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let nowPlaying = NowPlayingController()
    let powerMonitor = PowerSourceMonitor()
    let timerService = TimerService()
    lazy var clipboard = ClipboardMonitor()
    lazy var systemStats = SystemStatsService()
    lazy var weather = WeatherService()
    let calendar = CalendarService()
    lazy var crypto = CryptoService()
    let shortcuts = ShortcutsService()
    let bluetooth = BluetoothMonitor()
    let systemActivity = SystemActivityMonitor()
    lazy var audioMixer = AudioMixerService()
    lazy var teleprompter = TeleprompterService(nowPlaying: nowPlaying)

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

        let needsBluetooth = app.notchEnabled && (nook.showBluetoothLiveActivity || nookWidgets.contains(.battery))
        needsBluetooth ? bluetooth.start() : bluetooth.stop()

        let needsSystemActivity = app.notchEnabled && (
            nook.showVolumeLiveActivity
                || nook.showBrightnessLiveActivity
                || nook.showKeyboardBrightnessLiveActivity
                || nook.showMicrophoneLiveActivity
                || nook.showFocusLiveActivity
        )
        needsSystemActivity ? systemActivity.start() : systemActivity.stop()

        needsTeleprompter ? teleprompter.start() : teleprompter.stop()

        let needsWeather = app.notchEnabled && nookWidgets.contains(.weather)
        needsWeather ? weather.startIfNeeded() : weather.stop()
        let needsClipboard = app.notchEnabled && nookWidgets.contains(.clipboard)
        needsClipboard ? clipboard.start() : clipboard.stop()

        let needsEvents =
            app.notchEnabled && nookWidgets.contains(.calendar)

        needsEvents ? calendar.startEventsIfNeeded() : calendar.stopEvents()

        let needsReminders =
            app.notchEnabled && nookWidgets.contains(.todos)

        needsReminders ? calendar.startRemindersIfNeeded() : calendar.stopReminders()
    }
}
