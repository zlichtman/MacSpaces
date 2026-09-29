import Foundation
import EventKit
import Combine

struct TodoItem: Identifiable, Equatable {
    let id: String
    let title: String
    let dueDate: Date?
}

/// A value-type boundary around EventKit objects. `EKEvent` is mutable,
/// non-Sendable, and some of its imported properties are implicitly unwrapped.
/// Keeping it out of SwiftUI also lets the slow EventKit query run off-main.
struct CalendarEventItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let notes: String?
    let url: URL?
    let color: CalendarEventColor?
    var isAllDay = false

    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                                       "webex.com", "facetime.apple.com", "whereby.com", "around.co"]

    /// A video-call link from the event's URL, location or notes, if any.
    var meetingURL: URL? {
        if let url, Self.isMeeting(url) { return url }
        let text = [location, notes].compactMap { $0 }.joined(separator: " ")
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url).first(where: Self.isMeeting)
    }

    private static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func isInProgress(at date: Date) -> Bool { startDate <= date && endDate > date }

    func progress(at date: Date) -> Double {
        let length = endDate.timeIntervalSince(startDate)
        return length > 0 ? min(max(date.timeIntervalSince(startDate) / length, 0), 1) : 0
    }
}

struct CalendarEventColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

/// EventKit access for the Calendar and Todos widgets. Permission for each
/// data type is requested lazily, the first time the matching widget appears.
@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var todayEvents: [CalendarEventItem] = []
    /// Tomorrow's timed events, so an empty evening still shows what's next.
    @Published private(set) var tomorrowEvents: [CalendarEventItem] = []
    @Published private(set) var eventsAccessDenied = false
    /// Every event (all-day included) in the weeks shown by the month grid.
    @Published private(set) var monthEvents: [CalendarEventItem] = []
    private var monthAnchor: Date?
    private var monthGeneration = 0
    private var isPreview = false
    @Published private(set) var reminders: [TodoItem] = []
    @Published private(set) var remindersAccessDenied = false

    private let eventStore = EKEventStore()
    private let eventFetchQueue = DispatchQueue(
        label: "dev.opensource.MacSpaces.calendar-fetch",
        qos: .utility
    )
    private var eventsStarted = false
    private var eventsGeneration = 0
    private var remindersStarted = false
    private var remindersGeneration = 0
    private var cancellables: Set<AnyCancellable> = []

    #if DEBUG
    func setAppPreview() {
        precondition(Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces.FeatureQA")
        eventsStarted = true
        eventsAccessDenied = false
        isPreview = true
        let today = Calendar.current.startOfDay(for: Date())
        let sampleDays: [(Int, String, Double, Double, Double)] = [
            (-6, "Studio day", 0.35, 0.55, 0.95), (-2, "Dentist", 0.95, 0.55, 0.2), (1, "Planning", 0.35, 0.55, 0.95),
            (3, "Dinner with Aaron", 0.3, 0.75, 0.45), (8, "Launch review", 0.95, 0.55, 0.2), (12, "Flight to SF", 0.6, 0.45, 0.9)]
        monthEvents = sampleDays.map { offset, title, r, g, b in
            let start = Calendar.current.date(byAdding: .hour, value: offset * 24 + 14, to: today)!
            return .init(id: "month-\(offset)", title: title, startDate: start, endDate: start.addingTimeInterval(3600),
                         location: nil, notes: nil, url: nil, color: .init(red: r, green: g, blue: b, alpha: 1))
        } + [.init(id: "month-allday", title: "Mom's birthday", startDate: today, endDate: today.addingTimeInterval(86400),
                   location: nil, notes: nil, url: nil, color: .init(red: 0.9, green: 0.4, blue: 0.6, alpha: 1), isAllDay: true)]
        todayEvents = [
            .init(id: "sample", title: "Design review", startDate: Date().addingTimeInterval(-600), endDate: Date().addingTimeInterval(1800),
                  location: "https://meet.google.com/abc-defg-hij", notes: nil, url: nil, color: nil),
            .init(id: "sample-2", title: "Lunch with Sam", startDate: Date().addingTimeInterval(5400), endDate: Date().addingTimeInterval(8400),
                  location: "Café", notes: nil, url: nil, color: .init(red: 0.3, green: 0.75, blue: 0.45, alpha: 1)),
            .init(id: "sample-3", title: "Ship build", startDate: Date().addingTimeInterval(10800), endDate: Date().addingTimeInterval(12600),
                  location: nil, notes: nil, url: nil, color: .init(red: 0.95, green: 0.55, blue: 0.2, alpha: 1))
        ]
        monthEvents += todayEvents
        remindersStarted = true
        remindersAccessDenied = false
        reminders = [
            .init(id: "r1", title: "Send Aaron the DayDrop notes", dueDate: Date().addingTimeInterval(-3600)),
            .init(id: "r2", title: "Book flights for October", dueDate: Date().addingTimeInterval(86400)),
            .init(id: "r3", title: "Renew passport", dueDate: nil),
            .init(id: "r4", title: "Pick up dry cleaning", dueDate: Date().addingTimeInterval(7200))
        ]
    }
    #endif

    // MARK: - Events

    func startEventsIfNeeded() {
        guard !eventsStarted else { return }
        eventsStarted = true

        requestEventsAccess { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self, self.eventsStarted else { return }
                self.eventsAccessDenied = !granted
                if granted {
                    self.observeStoreChanges()
                    self.refreshEvents()
                    self.refreshMonth()
                }
            }
        }
    }

    func stopEvents() {
        eventsStarted = false
        eventsGeneration += 1
        stopObservingIfUnused()
    }

    private func refreshEvents() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 2, to: start),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) else { return }

        eventsGeneration += 1
        let generation = eventsGeneration
        eventFetchQueue.async { [weak self] in
            // This store is created and consumed exclusively on this queue.
            let fetchStore = EKEventStore()
            let predicate = fetchStore.predicateForEvents(
                withStart: start,
                end: end,
                calendars: nil
            )
            let items = fetchStore.events(matching: predicate)
                .compactMap { Self.snapshot($0) }
                .filter { $0.endDate > start }
                .sorted { $0.startDate < $1.startDate }

            Task { @MainActor [weak self] in
                guard let self,
                      self.eventsStarted,
                      self.eventsGeneration == generation else { return }
                self.todayEvents = items.filter { $0.startDate < tomorrow }
                self.tomorrowEvents = items.filter { $0.startDate >= tomorrow }
            }
        }
    }

    /// Loads the six weeks around `date`'s month for the calendar grid.
    func loadMonth(containing date: Date) {
        let calendar = Calendar.current
        monthAnchor = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        refreshMonth()
    }

    func events(on day: Date) -> [CalendarEventItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return monthEvents.filter { $0.startDate < end && $0.endDate > start }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
    }

    private func refreshMonth() {
        guard eventsStarted, !eventsAccessDenied, !isPreview, let anchor = monthAnchor else { return }
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -7, to: anchor),
              let end = calendar.date(byAdding: .day, value: 45, to: anchor) else { return }
        monthGeneration += 1
        let generation = monthGeneration
        eventFetchQueue.async { [weak self] in
            let fetchStore = EKEventStore()
            let predicate = fetchStore.predicateForEvents(withStart: start, end: end, calendars: nil)
            let items = fetchStore.events(matching: predicate)
                .compactMap { Self.snapshot($0, includeAllDay: true) }
                .sorted { $0.startDate < $1.startDate }
            Task { @MainActor [weak self] in
                guard let self, self.eventsStarted, self.monthGeneration == generation else { return }
                self.monthEvents = items
            }
        }
    }

    var nextEvent: CalendarEventItem? {
        todayEvents.first { $0.endDate > Date() }
    }

    nonisolated private static func snapshot(
        _ event: EKEvent,
        includeAllDay: Bool = false
    ) -> CalendarEventItem? {
        guard includeAllDay || !event.isAllDay,
              let startDate = event.startDate,
              let endDate = event.endDate else { return nil }

        let baseID = event.eventIdentifier ?? event.calendarItemIdentifier
        let occurrenceID = "\(baseID)-\(startDate.timeIntervalSinceReferenceDate)"
        let color = event.calendar?.cgColor.flatMap(Self.snapshotColor)
        return CalendarEventItem(
            id: occurrenceID,
            title: event.title?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).nonEmpty ?? "Untitled Event",
            startDate: startDate,
            endDate: endDate,
            location: event.location,
            notes: event.notes,
            url: event.url,
            color: color, isAllDay: event.isAllDay
        )
    }

    nonisolated private static func snapshotColor(
        _ color: CGColor
    ) -> CalendarEventColor? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(
            to: colorSpace,
            intent: .defaultIntent,
            options: nil
        ), let components = converted.components, components.count >= 3 else {
            return nil
        }
        return CalendarEventColor(
            red: Double(components[0]),
            green: Double(components[1]),
            blue: Double(components[2]),
            alpha: Double(components.count > 3 ? components[3] : 1)
        )
    }

    // MARK: - Reminders

    func startRemindersIfNeeded() {
        guard !remindersStarted else { return }
        remindersStarted = true

        requestRemindersAccess { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self, self.remindersStarted else { return }
                self.remindersAccessDenied = !granted
                if granted {
                    self.observeStoreChanges()
                    self.refreshReminders()
                }
            }
        }
    }

    private func requestEventsAccess(
        completion: @escaping (Bool) -> Void
    ) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { granted, _ in
                completion(granted)
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, _ in
                completion(granted)
            }
        }
    }

    private func requestRemindersAccess(
        completion: @escaping (Bool) -> Void
    ) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToReminders { granted, _ in
                completion(granted)
            }
        } else {
            eventStore.requestAccess(to: .reminder) { granted, _ in
                completion(granted)
            }
        }
    }

    func stopReminders() {
        remindersStarted = false
        remindersGeneration += 1
        stopObservingIfUnused()
    }

    private func refreshReminders() {
        guard remindersStarted else { return }
        remindersGeneration += 1
        let generation = remindersGeneration
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil)

        eventStore.fetchReminders(matching: predicate) { [weak self] fetched in
            let items = (fetched ?? [])
                .compactMap { reminder -> TodoItem? in
                    guard let title = reminder.title else { return nil }
                    return TodoItem(id: reminder.calendarItemIdentifier,
                                    title: title,
                                    dueDate: reminder.dueDateComponents?.date)
                }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

            Task { @MainActor [weak self] in
                guard let self,
                      self.remindersStarted,
                      self.remindersGeneration == generation else { return }
                self.reminders = items
            }
        }
    }

    func complete(_ item: TodoItem) {
        guard let reminder = eventStore.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        try? eventStore.save(reminder, commit: true)
        reminders.removeAll { $0.id == item.id }
    }

    func addReminder(title: String) {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        try? eventStore.save(reminder, commit: true)
        refreshReminders()
    }

    // MARK: - Change tracking

    private var observingChanges = false

    private func observeStoreChanges() {
        guard !observingChanges else { return }
        observingChanges = true

        NotificationCenter.default
            .publisher(for: .EKEventStoreChanged, object: eventStore)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.eventsStarted && !self.eventsAccessDenied { self.refreshEvents(); self.refreshMonth() }
                if self.remindersStarted && !self.remindersAccessDenied { self.refreshReminders() }
            }
            .store(in: &cancellables)

        // Also refresh periodically so "next event" rolls over during the day.
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.eventsStarted, !self.eventsAccessDenied else { return }
                self.refreshEvents()
            }
            .store(in: &cancellables)
    }

    private func stopObservingIfUnused() {
        guard !eventsStarted, !remindersStarted else { return }
        cancellables.removeAll()
        observingChanges = false
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
