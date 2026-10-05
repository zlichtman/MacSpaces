import Foundation
import Combine
import EventKit

/// The next video meeting, for the closed notch: from ten minutes before it
/// starts until five minutes in. Reads today's events from CalendarService,
/// which runs for this only when calendar access was already granted.
@MainActor
final class MeetingCountdown: ObservableObject {
    static let shared = MeetingCountdown()
    static let leadTime: TimeInterval = 10 * 60
    static let graceAfterStart: TimeInterval = 5 * 60

    @Published private(set) var meeting: CalendarEventItem?
    private var timer: Timer?
    private var watch: AnyCancellable?

    /// Calendar access already granted, so following meetings never asks for it.
    static var calendarAllowed: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess
    }

    func start(calendar: CalendarService) {
        guard timer == nil else { return }
        watch = calendar.$todayEvents.sink { [weak self] events in self?.update(events) }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self, weak calendar] _ in
            Task { @MainActor in self?.update(calendar?.todayEvents ?? []) }
        }
    }

    private func update(_ events: [CalendarEventItem]) {
        let next = Self.upcoming(in: events, at: Date())
        if next != meeting { meeting = next }
    }

    nonisolated static func upcoming(in events: [CalendarEventItem], at now: Date) -> CalendarEventItem? {
        events
            .filter { !$0.isAllDay && $0.meetingURL != nil }
            .filter { $0.startDate.timeIntervalSince(now) <= leadTime && now.timeIntervalSince($0.startDate) <= graceAfterStart && $0.endDate > now }
            .min { $0.startDate < $1.startDate }
    }

    /// "in 4m", "now", or "3m in".
    nonisolated static func label(for meeting: CalendarEventItem, at now: Date) -> String {
        let seconds = meeting.startDate.timeIntervalSince(now)
        if seconds > 60 { return "in \(Int((seconds / 60).rounded(.up)))m" }
        if seconds > -60 { return "now" }
        return "\(Int((-seconds / 60).rounded(.down)))m in"
    }
}
