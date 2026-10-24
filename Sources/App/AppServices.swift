import Foundation
import EventKit

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
    /// finds them running. Safe dock services also warm while approaching the notch.
    private var lingeringTabs: [NotchTab: Date] = [:]
    private var lingerExpiry: DispatchWorkItem?
    private var presentationReconcile: DispatchWorkItem?
    private var prewarmUntil: Date?
    private var prewarmExpiry: DispatchWorkItem?
    private static let lingerDuration: TimeInterval = 4

    func setAppPresentation(id: UUID, tab: NotchTab?) {
        if appPresentations[id] == nil, tab != nil, NookSettings.shared.dockApps.contains(.mirror) {
            DispatchQueue.main.async { CameraController.shared.prewarm() }
        }
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
        presentationReconcile?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reconcileDemand(app: AppSettings.shared, nook: NookSettings.shared)
        }
        presentationReconcile = work
        // Leave the SwiftUI transaction without adding a visible page-start delay.
        DispatchQueue.main.async(execute: work)
    }

    /// Bounded demand during the hover delay, then while the Nook is open.
    /// Permission requests stay with the page the person actually opens.
    func prewarmDockPages() {
        prewarmUntil = Date().addingTimeInterval(Self.lingerDuration)
        prewarmExpiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in
            self?.reconcileDemand(app: AppSettings.shared, nook: NookSettings.shared)
        }
        prewarmExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lingerDuration + 0.1, execute: expiry)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if NookSettings.shared.dockApps.contains(.music) { self.nowPlaying.prewarm() }
            self.reconcileDemand(app: AppSettings.shared, nook: NookSettings.shared)
            // Look the song's lyrics up while the Nook opens, so Music has them ready.
            if NookSettings.shared.dockApps.contains(.music) { self.teleprompterStorage?.prefetch(for: Self.lingerDuration) }
        }
    }

    static func prewarmedServices(dock: Set<NotchTab>, calendarAllowed: Bool, remindersAllowed: Bool) -> Set<String> {
        var demand: Set<String> = []
        if dock.contains(.weather) { demand.insert("weather") }
        if dock.contains(.system) { demand.formUnion(["stats", "power"]) }
        if dock.contains(.calendar), calendarAllowed { demand.insert("events") }
        if dock.contains(.reminders), remindersAllowed { demand.insert("reminders") }
        return demand
    }

    private static var remindersAllowed: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) { return status == .fullAccess }
        return status == .authorized
    }

    lazy var notes = NotesService()
    lazy var messages = MessagesReplyService()
    lazy var nowPlaying = NowPlayingController(actions: actions)
    let powerMonitor = PowerSourceMonitor()
    let timerService = TimerService()
    /// Up to two more timers beside the main one, shown on the Timers page.
    let extraTimers = [TimerService(slot: 1), TimerService(slot: 2)]
    var allTimers: [TimerService] { [timerService] + extraTimers }
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
            return ServiceCallbacks(start: { service.startIfNeeded(allowLocationPrompt: false) }, stop: { service.stop() })
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
            if !appPresentations.isEmpty || (prewarmUntil.map { $0 > now } ?? false) {
                demand.formUnion(Self.prewarmedServices(dock: Set(nook.dockApps),
                    calendarAllowed: MeetingCountdown.calendarAllowed, remindersAllowed: Self.remindersAllowed))
            }
            if tabs.contains(.music) { demand.formUnion(["media", "lyrics"]) }
            // While the Nook opens, lyrics can be looked up early, but only when the
            // player is already being read: approaching the notch never asks for Automation.
            if (prewarmUntil.map { $0 > now } ?? false), nook.dockApps.contains(.music),
               nook.showMusicLiveActivity || nook.widgets.contains(.media) { demand.insert("lyrics") }
            if tabs.contains(.calendar) { demand.insert("events") }
            if tabs.contains(.weather) { demand.insert("weather") }
            if tabs.contains(.reminders) { demand.insert("reminders") }
            // The System page's battery ring opens the battery popover, which lists devices.
            if tabs.contains(.system) { demand.formUnion(["stats", "power", "bluetooth"]) }
            if tabs.contains(.messages) { demand.insert("messages") }
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
        // A meeting countdown reads today's events, but only with access already granted.
        if app.notchEnabled, nook.showMeetingLiveActivity, MeetingCountdown.calendarAllowed {
            demand.insert("events")
            MeetingCountdown.shared.start(calendar: calendar)
        }
        // Incoming Messages (and their notch banners) work without the widget on Home.
        if UserDefaults.standard.bool(forKey: "messages.incomingEnabled") { demand.insert("messages") }
        // The paste queue works in every app, whether or not the Nook is on.
        if UserDefaults.standard.bool(forKey: "clipboard.pasteQueue") { demand.insert("clipboard") }
        // So does the history shortcut: history has to be collected before it's opened.
        if ClipboardPreferences.shared.shortcut != .off { demand.insert("clipboard") }
        // The agent alert and the lid-closed switch watch the battery whether or not the Nook is on.
        if AgentPowerAlert.shared.isEnabled || LidClosedAwake.shared.isEnabled { demand.insert("power") }
        do { try lifecycle.reconcile(demand) }
        catch { assertionFailure("Invalid service catalog: \(error)") }
        // Explicitly started countdowns continue independently of panel visibility.
        // Pages in the dock can run these too, so only a removed feature stops them.
        if !app.notchEnabled || !(nook.widgets.contains(.keepAwake) || nook.dockApps.contains(.system)) { keepAwakeStorage?.stop() }
        if !app.notchEnabled || !(nook.widgets.contains(.terminal) || nook.dockApps.contains(.terminal)) { quickShellStorage?.stop() }
        if !app.notchEnabled || !(nook.widgets.contains(.pomodoro) || nook.dockApps.contains(.timers)) { PomodoroModel.shared.stopForRemoval() }
    }
}
