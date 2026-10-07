import AppKit
import Combine
@preconcurrency import UserNotifications

/// Quick countdown timers. While running, the remaining time is shown as a
/// live activity beside the notch.
@MainActor
final class TimerService: ObservableObject {
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    /// True while a countdown exists, including while it is paused.
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    /// The name shown on its card and in its notification.
    @Published var name: String = "Timer" {
        didSet { UserDefaults.standard.set(name, forKey: nameKey) }
    }

    private var timer: Timer?
    private var endDate: Date?
    private let defaults: UserDefaults
    private let endDateKey: String
    private let totalKey: String
    private let pausedRemainingKey: String
    private let nameKey: String
    /// 0 is the main timer (Home's Timer widget); 1 and 2 are the extra timers on the Timers page.
    let slot: Int

    init(slot: Int = 0) {
        defaults = .standard
        self.slot = slot
        let prefix = slot == 0 ? "timer" : "timer\(slot + 1)"
        endDateKey = prefix + ".endDate"; totalKey = prefix + ".total"
        pausedRemainingKey = prefix + ".pausedRemaining"; nameKey = prefix + ".name"
        name = UserDefaults.standard.string(forKey: nameKey) ?? (slot == 0 ? "Timer" : "Timer \(slot + 1)")
        if let savedEndDate = defaults.object(forKey: endDateKey) as? Date,
           savedEndDate > Date() {
            endDate = savedEndDate
            total = defaults.double(forKey: totalKey)
            remaining = savedEndDate.timeIntervalSinceNow
            isRunning = true
            scheduleTimer()
        } else if defaults.double(forKey: pausedRemainingKey) > 0 {
            remaining = defaults.double(forKey: pausedRemainingKey)
            total = max(defaults.double(forKey: totalKey), remaining)
            isRunning = true
            isPaused = true
        } else {
            defaults.removeObject(forKey: endDateKey)
            defaults.removeObject(forKey: totalKey)
        }
    }

#if DEBUG
    /// Isolated timer state for deterministic visual-regression captures.
    /// It deliberately avoids the user's persisted countdown.
    init(previewRemaining: TimeInterval, total: TimeInterval, slot: Int = 0) {
        defaults = UserDefaults(suiteName: "dev.opensource.MacSpaces.VisualQA.\(UUID())")!
        self.slot = slot
        endDateKey = "timer.endDate"; totalKey = "timer.total"; pausedRemainingKey = "timer.pausedRemaining"; nameKey = "qa.timer.name"
        self.remaining = previewRemaining
        self.total = total
        isRunning = previewRemaining > 0
    }

    /// Website captures: shows a countdown in progress without starting or saving one.
    func setPreview(remaining: TimeInterval, total: TimeInterval) {
        self.remaining = remaining; self.total = total; isRunning = remaining > 0
    }
#endif

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
        run(for: total)
    }

    func pause() {
        guard isRunning, !isPaused, let endDate else { return }
        timer?.invalidate()
        timer = nil
        remaining = max(1, endDate.timeIntervalSinceNow)
        self.endDate = nil
        isPaused = true
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
        }
    }

    private func run(for interval: TimeInterval) {
        timer?.invalidate()
        remaining = interval
        isRunning = true
        isPaused = false
        endDate = Date().addingTimeInterval(interval)
        defaults.set(endDate, forKey: endDateKey)
        defaults.set(total, forKey: totalKey)
        defaults.removeObject(forKey: pausedRemainingKey)
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    func cancel() {
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
        cancel()
        NSSound(named: "Glass")?.play()

        let name = self.name
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let deliver = {
                let content = UNMutableNotificationContent()
                content.title = "\(name) finished"
                content.body = "Your MacSpaces timer finished."
                content.sound = .default
                center.add(UNNotificationRequest(
                    identifier: "dev.opensource.MacSpaces.timer.\(UUID().uuidString)",
                    content: content,
                    trigger: nil
                ))
            }

            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { deliver() }
                }
            } else if settings.authorizationStatus == .authorized ||
                        settings.authorizationStatus == .provisional {
                deliver()
            }
        }
    }
}
