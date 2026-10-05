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
    /// The main timer's name (Home's Timer widget and the first card on the Timers page).
    @Published var name: String = UserDefaults.standard.string(forKey: "timer.name") ?? "Timer" {
        didSet { UserDefaults.standard.set(name, forKey: "timer.name") }
    }

    private var timer: Timer?
    private var endDate: Date?
    private let defaults: UserDefaults
    private let endDateKey = "timer.endDate"
    private let totalKey = "timer.total"
    private let pausedRemainingKey = "timer.pausedRemaining"

    init() {
        defaults = .standard
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

/// More countdowns beside the main timer, each with its own name and length
/// ("Tea", "Laundry", "Standup"). They keep running while the Nook is closed,
/// survive relaunches, and say their name when they finish.
@MainActor
final class NamedTimers: ObservableObject {
    static let shared = NamedTimers()

    struct Countdown: Identifiable, Codable, Equatable {
        var id = UUID()
        var name: String
        var minutes: Int
        var endDate: Date?
        var pausedRemaining: TimeInterval?
        var isRunning: Bool { endDate != nil || pausedRemaining != nil }
        var isPaused: Bool { pausedRemaining != nil }
        var length: TimeInterval { TimeInterval(minutes * 60) }
        func remaining(at now: Date) -> TimeInterval {
            if let endDate { return max(0, endDate.timeIntervalSince(now)) }
            return pausedRemaining ?? length
        }
    }

    @Published private(set) var timers: [Countdown] = [] { didSet { save() } }
    /// Ticks once a second while any countdown runs, so views refresh.
    @Published private(set) var now = Date()
    private var tick: Timer?
    private let key = "timers.named"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Countdown].self, from: data) {
            timers = saved
        }
        updateTicking()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(timers), forKey: key)
    }

    /// The running countdown that ends soonest, for the closed notch.
    var soonest: Countdown? {
        timers.filter { $0.endDate != nil }.min { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) }
    }

    func add() {
        timers.append(Countdown(name: "Timer \(timers.count + 2)", minutes: 5))
    }

#if DEBUG
    /// QA captures: synthetic timers, never saved over the user's.
    func previewTimers(_ list: [(String, Int)]) {
        let saved = UserDefaults.standard.data(forKey: key)
        timers = list.map { Countdown(name: $0.0, minutes: $0.1) }
        if timers.count > 1 { timers[1].endDate = Date().addingTimeInterval(TimeInterval(list[1].1 * 60 - 312)) }
        UserDefaults.standard.set(saved, forKey: key)
    }
#endif

    func remove(_ id: UUID) { timers.removeAll { $0.id == id }; updateTicking() }

    func rename(_ id: UUID, to name: String) { change(id) { $0.name = name } }

    func setMinutes(_ id: UUID, _ minutes: Int) {
        change(id) { $0.minutes = min(24 * 60, max(1, minutes)) }
    }

    func toggle(_ id: UUID) {
        change(id) { timer in
            if let paused = timer.pausedRemaining {
                timer.endDate = Date().addingTimeInterval(paused); timer.pausedRemaining = nil
            } else if let end = timer.endDate {
                timer.pausedRemaining = max(1, end.timeIntervalSinceNow); timer.endDate = nil
            } else {
                timer.endDate = Date().addingTimeInterval(timer.length)
            }
        }
        updateTicking()
    }

    func reset(_ id: UUID) {
        change(id) { $0.endDate = nil; $0.pausedRemaining = nil }
        updateTicking()
    }

    func extend(_ id: UUID, by seconds: TimeInterval) {
        change(id) { timer in
            if let end = timer.endDate { timer.endDate = end.addingTimeInterval(seconds) }
            else if let paused = timer.pausedRemaining { timer.pausedRemaining = paused + seconds }
        }
    }

    private func change(_ id: UUID, _ edit: (inout Countdown) -> Void) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        edit(&timers[index])
    }

    private func updateTicking() {
        let running = timers.contains { $0.endDate != nil }
        if running, tick == nil {
            tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.step() }
            }
        } else if !running {
            tick?.invalidate(); tick = nil
        }
    }

    private func step() {
        now = Date()
        for timer in timers where timer.endDate.map({ $0 <= now }) == true {
            change(timer.id) { $0.endDate = nil }
            Self.announce(timer.name)
        }
        updateTicking()
    }

    static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return whole >= 3600 ? String(format: "%d:%02d:%02d", whole / 3600, (whole % 3600) / 60, whole % 60)
            : String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// A sound and a notification naming the timer.
    static func announce(_ name: String) {
        NSSound(named: "Glass")?.play()
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(name) finished"
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "dev.opensource.MacSpaces.timer.\(UUID().uuidString)", content: content, trigger: nil))
        }
    }
}
