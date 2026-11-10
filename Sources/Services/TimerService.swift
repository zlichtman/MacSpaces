import AppKit
import Combine
@preconcurrency import UserNotifications

/// Quick countdown timers. While running, the remaining time is shown as a
/// live activity beside the notch.
@MainActor
final class TimerService: ObservableObject {
    /// The pool's size: `AppServices.allTimers`.
    static let poolSize = 8

    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    /// True while a countdown exists, including while it is paused.
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    /// The name shown on its card and in its notification.
    @Published var name: String = "Timer" {
        didSet { defaults.set(name, forKey: nameKey); if isRunning, !isPaused { scheduleNotification(ask: false) } }
    }

    private var timer: Timer?
    private var endDate: Date?
    private let defaults: UserDefaults
    private let endDateKey: String
    private let totalKey: String
    private let pausedRemainingKey: String
    private let nameKey: String
    /// 0 is the main timer (Home's Timer widget); a new timer takes the first free one.
    let slot: Int
    @Published private(set) var missedDeadline: Date?
    /// When this timer finished, while its done state shows beside the notch.
    @Published private(set) var finishedAt: Date?
    /// What it does as it finishes (its card's When done menu).
    @Published var whenDone: TimerWhenDone = .nothing {
        didSet { defaults.set(whenDone.rawValue, forKey: whenDoneKey); reconcileMusicDemand() }
    }
    /// Which `TimerService.palette` colour it's drawn in.
    @Published var tintIndex: Int {
        didSet { defaults.set(tintIndex, forKey: colourKey) }
    }
    /// A colour beyond the fixed ones: "theme" follows the theme's accent, "clear" its text, an
    /// ink name one of its colours (`VinylInk`), anything else is six hex digits. Nil uses `tintIndex`.
    @Published var tintChoice: String? {
        didSet { defaults.set(tintChoice, forKey: colourChoiceKey) }
    }
    /// False keeps it from the closed notch until it finishes: the alert still shows.
    @Published var showsInNotch = true {
        didSet { defaults.set(showsInNotch, forKey: showsKey) }
    }
    /// Do Not Disturb while it runs (`TimerFocus`).
    @Published var focus = false {
        didSet { defaults.set(focus, forKey: focusKey) }
    }
    private var doneExpiry: Timer?
    private let whenDoneKey: String
    private let colourKey: String
    private let colourChoiceKey: String
    private let showsKey: String
    private let focusKey: String
    private var notificationID: String { "dev.opensource.MacSpaces.timer.\(slot)" }

    init(slot: Int = 0, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.slot = slot
        let prefix = slot == 0 ? "timer" : "timer\(slot + 1)"
        endDateKey = prefix + ".endDate"; totalKey = prefix + ".total"
        pausedRemainingKey = prefix + ".pausedRemaining"; nameKey = prefix + ".name"
        whenDoneKey = prefix + WidgetOptions.Keys.timerWhenDoneSuffix
        colourKey = prefix + WidgetOptions.Keys.timerTintSuffix
        colourChoiceKey = prefix + WidgetOptions.Keys.timerTintChoiceSuffix
        showsKey = prefix + WidgetOptions.Keys.timerShowsInNotchSuffix
        focusKey = prefix + WidgetOptions.Keys.timerFocusSuffix
        tintIndex = defaults.object(forKey: colourKey) as? Int ?? slot
        tintChoice = defaults.string(forKey: colourChoiceKey)
        showsInNotch = defaults.object(forKey: showsKey) as? Bool ?? true
        focus = defaults.bool(forKey: focusKey)
        name = defaults.string(forKey: nameKey) ?? Self.defaultName(slot: slot)
        whenDone = TimerWhenDone(rawValue: defaults.string(forKey: whenDoneKey) ?? "") ?? .nothing
        if let savedEndDate = defaults.object(forKey: endDateKey) as? Date,
           savedEndDate > Date() {
            endDate = savedEndDate
            total = defaults.double(forKey: totalKey)
            remaining = savedEndDate.timeIntervalSinceNow
            isRunning = true
            scheduleTimer()
            scheduleNotification(ask: false)
        } else if defaults.double(forKey: pausedRemainingKey) > 0 {
            remaining = defaults.double(forKey: pausedRemainingKey)
            total = max(defaults.double(forKey: totalKey), remaining)
            isRunning = true
            isPaused = true
        } else {
            missedDeadline = defaults.object(forKey: endDateKey) as? Date
            defaults.removeObject(forKey: endDateKey)
            defaults.removeObject(forKey: totalKey)
        }
    }

    /// Inert sample state for widget previews and visual-regression captures.
    /// It deliberately avoids the user's persisted countdown.
    init(previewRemaining: TimeInterval, total: TimeInterval, slot: Int = 0) {
        defaults = UserDefaults(suiteName: "dev.opensource.MacSpaces.VisualQA.\(UUID())")!
        self.slot = slot
        endDateKey = "timer.endDate"; totalKey = "timer.total"; pausedRemainingKey = "timer.pausedRemaining"; nameKey = "qa.timer.name"
        whenDoneKey = "qa.timer.whenDone"
        colourKey = "qa.timer.tint"; colourChoiceKey = "qa.timer.tintChoice"; showsKey = "qa.timer.showsInNotch"; focusKey = "qa.timer.focus"
        tintIndex = slot
        tintChoice = nil
        self.remaining = previewRemaining
        self.total = total
        isRunning = previewRemaining > 0
    }

#if DEBUG
    /// Website captures: shows a countdown in progress without starting or saving one.
    func setPreview(remaining: TimeInterval, total: TimeInterval, paused: Bool = false) {
        self.remaining = remaining; self.total = total; isRunning = remaining > 0; isPaused = paused && remaining > 0
    }

    /// Captures: shows the done state without a countdown having finished.
    func setPreviewFinished(_ finished: Bool) { finishedAt = finished ? Date() : nil }
#endif

    private static func defaultName(slot: Int) -> String { slot == 0 ? "Timer" : "Timer \(slot + 1)" }

    /// Nothing is running and nothing finished is still showing.
    var isIdle: Bool { !isRunning && finishedAt == nil }

    /// A new timer forgets what this slot last did, keeping its colour.
    func prepareForNew(name newName: String?) {
        name = newName ?? Self.defaultName(slot: slot)
        whenDone = .nothing
    }

    var progress: Double {
        total > 0 ? 1 - remaining / total : 0
    }

    var remainingText: String {
        let seconds = Int(remaining.rounded())
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func start(minutes: Int) {
        start(seconds: TimeInterval(minutes * 60))
    }

    func start(seconds: TimeInterval) {
        cancel()
        total = max(1, seconds)
        missedDeadline = nil
        run(for: total, askForNotifications: true)
    }

    func pause() {
        guard isRunning, !isPaused, let endDate else { return }
        timer?.invalidate()
        timer = nil
        remaining = max(1, endDate.timeIntervalSinceNow)
        self.endDate = nil
        isPaused = true
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        defaults.removeObject(forKey: endDateKey)
        defaults.set(remaining, forKey: pausedRemainingKey)
    }

    func resume() {
        guard isRunning, isPaused else { return }
        run(for: remaining)
    }

    func togglePause() { isPaused ? resume() : pause() }

    /// Adds time to the running countdown, or starts one when idle.
    func extend(by seconds: TimeInterval) {
        guard isRunning else { start(seconds: seconds); return }
        total += seconds
        remaining += seconds
        defaults.set(total, forKey: totalKey)
        if isPaused {
            defaults.set(remaining, forKey: pausedRemainingKey)
        } else if let endDate {
            self.endDate = endDate.addingTimeInterval(seconds)
            defaults.set(self.endDate, forKey: endDateKey)
            scheduleNotification(ask: false)
        }
    }

    private func run(for interval: TimeInterval, askForNotifications: Bool = false) {
        timer?.invalidate()
        remaining = interval
        isRunning = true
        isPaused = false
        endDate = Date().addingTimeInterval(interval)
        defaults.set(endDate, forKey: endDateKey)
        defaults.set(total, forKey: totalKey)
        defaults.removeObject(forKey: pausedRemainingKey)
        scheduleTimer()
        scheduleNotification(ask: askForNotifications)
        if whenDone == .pauseMusic { reconcileMusicDemand() }
    }

    private func scheduleNotification(ask: Bool) {
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces", let deadline = endDate else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            let deliver: @Sendable (Bool) -> Void = { allowed in
                guard allowed else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.endDate == deadline, self.isRunning, !self.isPaused else { return }
                    let content = UNMutableNotificationContent()
                    content.title = self.name + " finished"
                    content.body = "Your MacSpaces timer finished."
                    content.sound = .default
                    center.add(UNNotificationRequest(identifier: self.notificationID, content: content,
                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)))
                }
            }
            if settings.authorizationStatus == .notDetermined && ask {
                center.requestAuthorization(options: [.alert, .sound]) { allowed, _ in deliver(allowed) }
            } else { deliver(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional) }
        }
    }

    private func scheduleTimer() {
        // Common modes keep the countdown moving while a menu is open.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel(clearNotification: Bool = true) {
        if clearNotification { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID]) }
        acknowledge()
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
        remaining = 0
        total = 0
        endDate = nil
        defaults.removeObject(forKey: endDateKey)
        defaults.removeObject(forKey: totalKey)
        defaults.removeObject(forKey: pausedRemainingKey)
        if focus { focus = false }
        if !showsInNotch { showsInNotch = true }
        // Later, so a pause sent as it finished isn't dropped with the service.
        if whenDone == .pauseMusic { reconcileMusicDemand(after: 3) }
    }

    /// The done state has been seen: it leaves the notch.
    func acknowledge() {
        doneExpiry?.invalidate()
        doneExpiry = nil
        if finishedAt != nil { finishedAt = nil }
    }

    /// A countdown that will pause music keeps the player being read until it ends, even with
    /// nothing else needing it (the song's activity off and no Media widget).
    var needsPlayer: Bool { isRunning && whenDone == .pauseMusic }

    private func reconcileMusicDemand(after delay: TimeInterval = 0) {
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            AppServices.shared.reconcileDemand(app: AppSettings.shared, nook: NookSettings.shared)
        }
    }

    private func tick() {
        guard let endDate else { return }
        let updatedRemaining = endDate.timeIntervalSinceNow
        guard updatedRemaining > 0 else {
            finished()
            return
        }
        remaining = updatedRemaining
    }

    private func finished() {
        let action = whenDone
        cancel(clearNotification: false)
        NSSound(named: "Glass")?.play()

        missedDeadline = Date()
        finishedAt = Date()
        let expiry = Timer(timeInterval: TimerDone.duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.acknowledge() }
        }
        RunLoop.main.add(expiry, forMode: .common)
        doneExpiry = expiry
        let player = AppServices.shared.nowPlaying
        if TimerDone.shouldPauseMusic(action, isPlaying: player.displayIsPlaying) { player.togglePlayPause() }
        // Another slot: this one's alert is still showing.
        if action == .startBreak { AppServices.shared.startTimer(seconds: TimerDone.breakSeconds, name: "Break") }
    }
}

/// Every timer as one thing to observe, for views that show them together.
@MainActor
final class TimerPool: ObservableObject {
    let all: [TimerService]
    private var observers: [AnyCancellable] = []

    init(_ timers: [TimerService]) {
        all = timers
        observers = timers.map { timer in
            timer.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        }
    }

    var running: [TimerService] { all.filter(\.isRunning) }
}
