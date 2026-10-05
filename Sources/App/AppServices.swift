import Foundation

/// Services shared by the Nook windows on all displays.
/// Polling is reconciled against the active profiles instead of running just
/// because a feature was used once.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let actions = ActionRegistry()
    private var appPresentations: [UUID: NotchTab] = [:]
    /// Pages closed in the last few seconds still count as demand, so closing
    /// the Nook doesn't stop their services mid-animation and a quick reopen
    /// finds them running. Opening a page starts its services at once.
    private var lingeringTabs: [NotchTab: Date] = [:]
    private var lingerExpiry: DispatchWorkItem?
    private static let lingerDuration: TimeInterval = 4

    func setAppPresentation(id: UUID, tab: NotchTab?) {
        if let previous = appPresentations[id], previous != tab {
            lingeringTabs[previous] = Date().addingTimeInterval(Self.lingerDuration)
            lingerExpiry?.cancel()
            let expiry = DispatchWorkItem { [weak self] in
                self?.reconcileDemand(app: AppSettings.shared, nook: NookSettings.shared)
            }
            lingerExpiry = expiry
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.lingerDuration + 0.1, execute: expiry)
        }
        appPresentations[id] = tab
        reconcileDemand(app: AppSettings.shared, nook: NookSettings.shared)
    }

    lazy var notes = NotesService()
    lazy var messages = MessagesReplyService()
    lazy var nowPlaying = NowPlayingController(actions: actions)
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
    private var quickShellStorage: QuickShell?
    /// The Terminal widget's shell; created on first use.
    var quickShell: QuickShell {
        if let value = quickShellStorage { return value }
        let value = QuickShell()
        quickShellStorage = value
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

    // Factories run only when demand enters the active set. Settings read the
    // catalog and never touch these registrations.
    private lazy var lifecycle = ServiceLifecycle([
        "messages": .init { [unowned self] in ServiceCallbacks(start: { self.messages.start() }, stop: { self.messages.stop() }) },
        "media": .init { [unowned self] in ServiceCallbacks(start: { self.nowPlaying.start() }, stop: { self.nowPlaying.stop() }) },
        "power": .init { [unowned self] in ServiceCallbacks(start: { self.powerMonitor.start() }, stop: { self.powerMonitor.stop() }) },
        "bluetooth": .init { [unowned self] in ServiceCallbacks(start: { self.bluetooth.start() }, stop: { self.bluetooth.stop() }) },
        "feedback": .init { [unowned self] in ServiceCallbacks(start: { self.systemActivity.start() }, stop: { self.systemActivity.stop() }) },
        "lyrics": .init(dependencies: ["media"]) { [unowned self] in
            let service = self.teleprompter
            return ServiceCallbacks(start: { service.start() }, stop: { service.stop() })
        },
        "weather": .init { [unowned self] in
            let service = self.weather
            return ServiceCallbacks(start: { service.startIfNeeded() }, stop: { service.stop() })
        },
        "clipboard": .init { [unowned self] in
            let service = self.clipboard
            return ServiceCallbacks(start: { service.start() }, stop: { service.stop() })
        },
        "stats": .init { [unowned self] in
            let service = self.systemStats
            return ServiceCallbacks(start: { service.start() }, stop: { service.stop() })
        },
        "events": .init { [unowned self] in ServiceCallbacks(start: { self.calendar.startEventsIfNeeded() }, stop: { self.calendar.stopEvents() }) },
        "reminders": .init { [unowned self] in ServiceCallbacks(start: { self.calendar.startRemindersIfNeeded() }, stop: { self.calendar.stopReminders() }) }
    ])

    func reconcileDemand(app: AppSettings, nook: NookSettings) {
        var demand: Set<String> = []
        if app.notchEnabled {
            let now = Date()
            lingeringTabs = lingeringTabs.filter { $0.value > now }
            let tabs = Set(appPresentations.values).union(lingeringTabs.keys)
            if tabs.contains(.music) { demand.formUnion(["media", "lyrics"]) }
            if tabs.contains(.calendar) { demand.insert("events") }
            if tabs.contains(.weather) { demand.insert("weather") }
            if tabs.contains(.reminders) { demand.insert("reminders") }
            if tabs.contains(.system) { demand.formUnion(["stats", "power"]) }
            // History is only useful if it's collected before you open the page.
            if nook.dockApps.contains(.clipboard) { demand.insert("clipboard") }
            let widgets = Set(nook.widgets)
            if nook.showMusicLiveActivity || widgets.contains(.media) { demand.insert("media") }
            if nook.showPowerLiveActivity || widgets.contains(.battery) { demand.insert("power") }
            if widgets.contains(.battery) { demand.insert("bluetooth") }
            // The Media widget shows the current lyric, so lyrics load whenever it's on Home.
            if widgets.contains(.media) { demand.insert("lyrics") }
            if nook.showMicrophoneLiveActivity || nook.showFocusLiveActivity { demand.insert("feedback") }
            let services: [(NookWidgetKind, String)] = [
                (.notifications, "messages"), (.weather, "weather"), (.clipboard, "clipboard"),
                (.systemStats, "stats"), (.calendar, "events"), (.todos, "reminders")
            ]
            for (widget, service) in services where widgets.contains(widget) { demand.insert(service) }
        }
        // The agent alert watches the battery whether or not the Nook is on.
        if AgentPowerAlert.shared.isEnabled { demand.insert("power") }
        do { try lifecycle.reconcile(demand) }
        catch { assertionFailure("Invalid service catalog: \(error)") }
        // Explicitly started countdowns continue independently of panel visibility.
        // Pages in the dock can run these too, so only a removed feature stops them.
        if !app.notchEnabled || !(nook.widgets.contains(.keepAwake) || nook.dockApps.contains(.system)) { keepAwakeStorage?.stop() }
        if !app.notchEnabled || !(nook.widgets.contains(.terminal) || nook.dockApps.contains(.terminal)) { quickShellStorage?.stop() }
        if !app.notchEnabled || !(nook.widgets.contains(.pomodoro) || nook.dockApps.contains(.timers)) { PomodoroModel.shared.stopForRemoval() }
    }
}
