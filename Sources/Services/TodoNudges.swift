import Foundation
import Combine
import UserNotifications

/// A notification when a to-do's time comes (`- [ ] Call Sam @14:30`). Today's are scheduled
/// with the system whenever the notes change and when the day turns over, so nothing here keeps
/// a timer. They're posted only when notifications are already allowed: writing a time in a
/// note never asks; adding a timed to-do in the To-Dos field may, once, as starting a timer does.
@MainActor
final class TodoNudges {
    static let shared = TodoNudges()
    /// Every request this makes starts with this, so only its own are ever replaced.
    nonisolated static let prefix = "todo."

    private var watch: AnyCancellable?
    private var dayObserver: NSObjectProtocol?
    private weak var notes: NotesService?
    /// A newer scheduling drops an older one's result.
    private var generation = 0

    /// Debug harnesses never schedule anything: they run under their own bundle identifiers.
    private static var isRealApp: Bool { Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" }

    func start(notes: NotesService) {
        guard Self.isRealApp, watch == nil else { return }
        self.notes = notes
        // Typing saves about once a second; wait for a pause before reading every note again.
        watch = notes.$notes.debounce(for: .seconds(2), scheduler: RunLoop.main).sink { [weak self] _ in self?.schedule(asking: false) }
        dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.schedule(asking: false) }
        }
        schedule(asking: false)
    }

    /// After a timed to-do is added by hand: the explicit action that may ask for notifications.
    func scheduleAfterAdding() { schedule(asking: true) }

    private func schedule(asking: Bool) {
        guard Self.isRealApp, let notes else { return }
        generation += 1
        let requested = generation
        let active = notes.active
        Task.detached(priority: .utility) {
            let now = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
            let minutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
            // Each to-do with the note it's in, read off the main thread.
            let due = active.flatMap { note in
                NoteTasks.dueLater(NoteTasks.tasks(in: note.current.text, note: note.id), after: minutes).map { (task: $0, from: note.title) }
            }
            let center = UNUserNotificationCenter.current()
            var status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined, asking, !due.isEmpty {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                status = await center.notificationSettings().authorizationStatus
            }
            guard status == .authorized || status == .provisional else { return }
            guard await MainActor.run(body: { TodoNudges.shared.generation == requested }) else { return }
            let stale = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for entry in due {
                guard let time = entry.task.due else { continue }
                let content = UNMutableNotificationContent()
                content.title = entry.task.title
                content.body = entry.from.isEmpty ? "A to-do is due." : "Due now, from \(entry.from)."
                content.sound = .default
                var when = DateComponents()
                when.year = now.year; when.month = now.month; when.day = now.day
                when.hour = time / 60; when.minute = time % 60
                try? await center.add(UNNotificationRequest(identifier: Self.prefix + entry.task.id, content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
            }
        }
    }
}
