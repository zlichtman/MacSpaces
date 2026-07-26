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
    @Published private(set) var eventsAccessDenied = false
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

    // MARK: - Events

    func startEventsIfNeeded() {
        guard !eventsStarted else { return }
        eventsStarted = true

        eventStore.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor [weak self] in
                guard let self, self.eventsStarted else { return }
                self.eventsAccessDenied = !granted
                if granted {
                    self.observeStoreChanges()
                    self.refreshEvents()
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
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }

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
                .compactMap(Self.snapshot)
                .filter { $0.endDate > start }
                .sorted { $0.startDate < $1.startDate }

            Task { @MainActor [weak self] in
                guard let self,
                      self.eventsStarted,
                      self.eventsGeneration == generation else { return }
                self.todayEvents = items
            }
        }
    }

    var nextEvent: CalendarEventItem? {
        todayEvents.first { $0.endDate > Date() }
    }

    nonisolated private static func snapshot(
        _ event: EKEvent
    ) -> CalendarEventItem? {
        guard !event.isAllDay,
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
            color: color
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

        eventStore.requestFullAccessToReminders { [weak self] granted, _ in
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
                if self.eventsStarted && !self.eventsAccessDenied { self.refreshEvents() }
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
