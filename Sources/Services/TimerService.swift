import AppKit
import Combine
@preconcurrency import UserNotifications

/// Quick countdown timers. While running, the remaining time is shown as a
/// live activity beside the notch.
@MainActor
final class TimerService: ObservableObject {
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var isRunning = false

    private var timer: Timer?
    private var endDate: Date?
    private let defaults: UserDefaults
    private let endDateKey = "timer.endDate"
    private let totalKey = "timer.total"

    init() {
        defaults = .standard
        if let savedEndDate = defaults.object(forKey: endDateKey) as? Date,
           savedEndDate > Date() {
            endDate = savedEndDate
            total = defaults.double(forKey: totalKey)
            remaining = savedEndDate.timeIntervalSinceNow
            isRunning = true
            scheduleTimer()
        } else {
            defaults.removeObject(forKey: endDateKey)
            defaults.removeObject(forKey: totalKey)
        }
    }

#if DEBUG
    /// Isolated timer state for deterministic visual-regression captures.
    /// It deliberately avoids the user's persisted countdown.
    init(previewRemaining: TimeInterval, total: TimeInterval) {
        defaults = UserDefaults(suiteName: "dev.opensource.MacSpaces.VisualQA.\(UUID())")!
        self.remaining = previewRemaining
        self.total = total
        isRunning = previewRemaining > 0
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
        cancel()
        total = TimeInterval(minutes * 60)
        remaining = total
        isRunning = true
        endDate = Date().addingTimeInterval(total)
        defaults.set(endDate, forKey: endDateKey)
        defaults.set(total, forKey: totalKey)

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
        remaining = 0
        total = 0
        endDate = nil
        defaults.removeObject(forKey: endDateKey)
        defaults.removeObject(forKey: totalKey)
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

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let deliver = {
                let content = UNMutableNotificationContent()
                content.title = "Timer complete"
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
