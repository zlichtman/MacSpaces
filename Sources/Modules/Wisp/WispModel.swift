import AppKit
import EventKit

/// What Wisp's face shows.
enum WispMood: Equatable {
    case idle, listening, thinking, speaking, happy, surprised, sleepy, confused, love, celebrating
}

/// A small thing the face holds up for a few seconds after Wisp does something: a mug of
/// tea or a stopwatch for a timer, a bell for a reminder, shades for focus, a page for a note.
enum WispProp: Equatable {
    case mug, stopwatch, bell, shades, note
}

/// The prop on show, when it arrived and how long it stays.
struct WispPropShowing: Equatable {
    let prop: WispProp
    let since: Date
    let lasts: TimeInterval
}

/// What answers plain-language chat, as the page's tag names it. Plain requests
/// (`WispCommand`) never need a model; anything else goes to the engine.
struct WispEngine: Equatable {
    /// The tag's text: the model's name, or "Offline".
    let name: String
    /// The tag's tooltip: one line on what this means.
    let detail: String
    /// False when no model answers, so only plain requests work.
    let isModel: Bool
    /// The tag's mark: the maker's logo as a symbol, or the offline mark.
    let symbol: String

    static let appleIntelligence = WispEngine(
        name: "Apple Intelligence",
        detail: "Apple's on-device model answers. Nothing leaves this Mac.",
        isModel: true, symbol: "apple.logo")

    /// No model: plain requests (reminders, notes, focus, timers, your day) still work.
    static func offline(_ reason: String) -> WispEngine {
        WispEngine(name: "Offline", detail: reason, isModel: false, symbol: "bolt.horizontal.circle")
    }
}

struct WispMessage: Identifiable, Equatable {
    enum Role { case user, wisp, notice }
    let id = UUID()
    let role: Role
    let text: String
}

/// Wisp, the notch's offline assistant. It acts on MacSpaces' own features: reminders go
/// to Apple Reminders, notes to Notes, focus and timers to the Timers page, and "my day"
/// reads the calendar. Plain requests work everywhere; on macOS 26 with Apple Intelligence
/// on, Apple's on-device model handles the rest. Nothing leaves the Mac.
@MainActor
final class WispModel: ObservableObject {
    static let shared = WispModel()

    @Published private(set) var messages: [WispMessage] = []
    @Published private(set) var mood: WispMood = .idle
    @Published private(set) var isThinking = false
    /// What the face is holding up, for a few seconds after an action.
    @Published private(set) var prop: WispPropShowing?
    let voice = WispVoice()

    private var moodReset: Task<Void, Never>?
    private var propReset: Task<Void, Never>?
    private var actedThisTurn = false
    /// The turn finished something (a reminder checked off, focus started): sparkles.
    private var celebrateThisTurn = false
    private var brain: AnyObject?

    private init() {
        voice.heard = { [weak self] text in self?.heard(text) }
        voice.finishedSpeaking = { [weak self] in
            guard let self, self.mood == .speaking else { return }
            self.settle()
        }
    }

    /// Why plain-language chat isn't available, or nil when Apple's model is ready.
    var modelUnavailableReason: String? {
        if #available(macOS 26, *) { return WispBrain.unavailableReason }
        return "Plain-language chat needs macOS 26 with Apple Intelligence. Requests like “remind me to call Sam tomorrow” work now."
    }

    /// The model answering plain-language chat, named in the page's tag.
    var engine: WispEngine {
        #if DEBUG
        if let previewEngine { return previewEngine }
        #endif
        let provider = WispProvider.current
        if provider != .apple { return provider.engine }
        return modelUnavailableReason.map(WispEngine.offline) ?? .appleIntelligence
    }

    /// Settings changed what answers: the page's tag updates and the next question starts fresh.
    func providerChanged() {
        objectWillChange.send()
        brain = nil
    }

    #if DEBUG
    /// Captures: show this engine in the tag instead of the real one.
    var previewEngine: WispEngine?
    #endif

    /// The ask field's prompt.
    static let placeholder = "Ask Wisp…"

    // MARK: Asking

    func send(_ raw: String, spoken: Bool = false) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        messages.append(WispMessage(role: .user, text: text))
        if messages.count > 60 { messages.removeFirst(messages.count - 60) }
        voice.stopSpeaking()
        isThinking = true
        actedThisTurn = false
        celebrateThisTurn = false
        setMood(.thinking)
        Task {
            let reply = await answer(text)
            isThinking = false
            reply.map { say($0, spoken: spoken) }
        }
    }

    private func answer(_ text: String) async -> String? {
        let kind = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        if ["thanks", "thank you", "thx", "ty", "love you", "good job", "nice", "good bot", "you're the best"].contains(kind) {
            flash(.love, after: 2.2)
            return ["Anytime!", "Happy to help.", "You're welcome!"].randomElement()
        }
        if let command = WispCommand.parse(text) {
            let reply = await perform(command)
            flash(celebrateThisTurn ? .celebrating : actedThisTurn ? .happy : .confused, after: celebrateThisTurn ? 2.2 : 1.6)
            return reply
        }
        let provider = WispProvider.current
        if provider != .apple {
            let brain = (self.brain as? WispCloudBrain).flatMap { $0.provider == provider ? $0 : nil } ?? WispCloudBrain(provider: provider)
            self.brain = brain
            do {
                let reply = await carryOut(WispReply.parse(try await brain.respond(to: text)))
                brain.record(reply)
                flash(celebrateThisTurn ? .celebrating : actedThisTurn ? .happy : .idle, after: celebrateThisTurn ? 2.2 : 1.6)
                return reply
            } catch {
                flash(.confused)
                return error.localizedDescription
            }
        }
        if #available(macOS 26, *), WispBrain.unavailableReason == nil {
            let brain = (self.brain as? WispBrain) ?? WispBrain(actions: self)
            self.brain = brain
            do {
                let reply = try await brain.respond(to: text)
                flash(celebrateThisTurn ? .celebrating : actedThisTurn ? .happy : .idle, after: celebrateThisTurn ? 2.2 : 1.6)
                return reply
            } catch {
                flash(.confused)
                return WispBrain.describe(error)
            }
        }
        flash(.confused)
        return "I can do reminders, notes, focus, timers and your day. Try “remind me to call Sam tomorrow” or “tea timer 4 minutes”."
    }

    private func say(_ reply: String, spoken: Bool) {
        let reply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append(WispMessage(role: .wisp, text: reply))
        if spoken {
            setMood(.speaking)
            voice.speak(reply)
        }
    }

    func clearConversation() {
        messages.removeAll()
        brain = nil
    }

    #if DEBUG
    /// Captures: a conversation and a mood, without asking anything.
    func setPreview(_ conversation: [WispMessage], mood: WispMood) {
        moodReset?.cancel()
        messages = conversation
        self.mood = mood
    }
    #endif

    // MARK: Voice

    func toggleListening() {
        if voice.isListening {
            voice.stopListening(deliver: true)
            return
        }
        voice.stopSpeaking()
        setMood(.listening)
        voice.startListening()
    }

    /// The listener stopped by itself or failed to start.
    private func heard(_ text: String?) {
        guard let text else {
            if let problem = voice.problem { messages.append(WispMessage(role: .notice, text: problem)) }
            flash(.confused)
            return
        }
        if mood == .listening { settle() }
        if !text.isEmpty { send(text, spoken: true) }
    }

    // MARK: The face

    /// Poking the face: it startles, then laughs it off.
    func poke() {
        guard !isThinking, !voice.isListening else { return }
        Haptics.tap()
        setMood(.surprised)
        moodReset = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            mood = .happy
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            settle()
        }
    }

    /// After a long quiet spell on its page, Wisp dozes; any interaction wakes it.
    func doze() {
        guard mood == .idle, !isThinking, !voice.isListening else { return }
        mood = .sleepy
    }

    func wake() {
        guard mood == .sleepy else { return }
        setMood(.surprised)
        flash(.idle, after: 0.5)
    }

    /// Holds up a prop for a few seconds; a newer one replaces it.
    func show(_ new: WispProp, for seconds: TimeInterval = 4) {
        propReset?.cancel()
        prop = WispPropShowing(prop: new, since: Date(), lasts: seconds)
        propReset = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((seconds + 0.1) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.prop = nil
        }
    }

    private func setMood(_ new: WispMood) {
        moodReset?.cancel()
        mood = new
    }

    /// Shows a mood for a moment, then settles.
    func flash(_ new: WispMood, after seconds: Double = 1.6) {
        setMood(new)
        guard new != .idle else { return }
        moodReset = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            settle()
        }
    }

    private func settle() {
        guard !voice.isSpeaking, !voice.isListening else { return }
        setMood(.idle)
    }

    // MARK: Doing things

    /// Runs the requests a model asked for. Its words stand when they all worked; a failure,
    /// and what "my day" reads, are added so nothing is claimed that didn't happen.
    private func carryOut(_ reply: WispReply) async -> String {
        var added: [String] = []
        for request in reply.actions {
            guard let command = WispCommand.parse(request) else { continue }
            let actedBefore = actedThisTurn
            actedThisTurn = false
            let result = await perform(command)
            if command == .day || !actedThisTurn { added.append(result) }
            actedThisTurn = actedThisTurn || actedBefore
        }
        let reply = ([reply.text] + added).filter { !$0.isEmpty }.joined(separator: " ")
        return reply.isEmpty ? "Done." : reply
    }

    private func perform(_ command: WispCommand) async -> String {
        switch command {
        case let .reminder(title, due):
            return await addReminder(title: title, due: due)
        case let .completeReminder(query):
            return await completeReminder(matching: query)
        case let .note(text):
            return addNote(text)
        case .focus:
            return startFocus()
        case .stopFocus:
            return stopFocus()
        case let .timer(seconds, name):
            return startTimer(seconds: seconds, name: name)
        case .day:
            return await describeDay()
        }
    }

    func addReminder(title: String, due: WispWhen?) async -> String {
        guard await WispAccess.reminders() else { return "Wisp needs Reminders access. Allow it in Settings › Permissions." }
        guard AppServices.shared.calendar.addReminder(title: title, due: due?.date, dueHasTime: due?.hasTime ?? false) else {
            return AppServices.shared.calendar.reminderError ?? "That reminder didn't save."
        }
        actedThisTurn = true
        show(.bell, for: 3.5)
        return "Added “\(title)”" + (due.map { " for \(Self.describe($0))" } ?? "") + "."
    }

    func completeReminder(matching query: String) async -> String {
        guard await WispAccess.reminders() else { return "Wisp needs Reminders access. Allow it in Settings › Permissions." }
        let open = await WispDay.openReminders()
        guard let index = WispCommand.bestMatch(query, in: open.map(\.title)) else { return "No open reminder matches “\(query)”." }
        let item = TodoItem(id: open[index].id, title: open[index].title, dueDate: nil)
        guard AppServices.shared.calendar.complete(item) else {
            return AppServices.shared.calendar.reminderError ?? "That reminder didn't update."
        }
        actedThisTurn = true
        celebrateThisTurn = true
        return "Checked off “\(item.title)”."
    }

    func addNote(_ text: String) -> String {
        let notes = AppServices.shared.notes
        guard let id = notes.create(), notes.save(id, text: text) else { return notes.error ?? "That note didn't save." }
        actedThisTurn = true
        show(.note, for: 3)
        return "Saved to Notes."
    }

    func startFocus() -> String {
        let focus = PomodoroModel.shared
        if !focus.isRunning { focus.toggle() }
        actedThisTurn = true
        celebrateThisTurn = true
        show(.shades, for: 5)
        return "Focus is on. \(focus.timeText) to go."
    }

    func stopFocus() -> String {
        let focus = PomodoroModel.shared
        guard focus.isRunning else { return "Focus isn't running." }
        focus.toggle()
        actedThisTurn = true
        return "Focus paused."
    }

    func startTimer(seconds: TimeInterval, name: String?) -> String {
        let defaults = UserDefaults.standard
        let shown = max(1, defaults.integer(forKey: "timers.count"))
        let timers = AppServices.shared.allTimers
        guard let index = timers.indices.first(where: { !timers[$0].isRunning && !timers[$0].isPaused }) else {
            return "All three timers are busy."
        }
        // A free timer the Timers page doesn't show yet gets shown.
        if index >= shown { defaults.set(index + 1, forKey: "timers.count") }
        let timer = timers[index]
        if let name { timer.name = name }
        timer.start(seconds: seconds)
        actedThisTurn = true
        let brew = ["tea", "coffee", "brew", "chai", "matcha"]
        show(brew.contains { (name ?? "").lowercased().contains($0) } ? .mug : .stopwatch, for: 4)
        let minutes = Int((seconds / 60).rounded())
        let length = seconds < 60 ? "\(Int(seconds)) seconds" : minutes == 1 ? "1 minute" : "\(minutes) minutes"
        return "\(name ?? "Timer") set for \(length)."
    }

    func describeDay() async -> String {
        let day = await WispDay.today()
        actedThisTurn = true
        return day.summary
    }

    nonisolated static func describe(_ when: WispWhen) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(when.date) { day = "today" }
        else if calendar.isDateInTomorrow(when.date) { day = "tomorrow" }
        else {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("EEEE d MMM")
            day = formatter.string(from: when.date)
        }
        guard when.hasTime else { return day }
        let time = DateFormatter.localizedString(from: when.date, dateStyle: .none, timeStyle: .short)
        return "\(day) at \(time)"
    }
}

/// Asks for Reminders or Calendar access only when a request needs it (an explicit action).
enum WispAccess {
    static func reminders() async -> Bool { await ensure(.reminder) }
    static func calendar() async -> Bool { await ensure(.event) }

    private static func ensure(_ type: EKEntityType) async -> Bool {
        let status = EKEventStore.authorizationStatus(for: type)
        if #available(macOS 14, *) {
            if status == .fullAccess { return true }
        } else if status == .authorized {
            return true
        }
        guard status == .notDetermined else { return false }
        let store = EKEventStore()
        if #available(macOS 14, *) {
            return (try? await (type == .event ? store.requestFullAccessToEvents() : store.requestFullAccessToReminders())) ?? false
        }
        return (try? await store.requestAccess(to: type)) ?? false
    }

    static func has(_ type: EKEntityType) -> Bool {
        let status = EKEventStore.authorizationStatus(for: type)
        if #available(macOS 14, *) { return status == .fullAccess }
        return status == .authorized
    }
}

/// Today's events, reminders and focus, read straight from EventKit off the main thread.
struct WispDay {
    var events: [(title: String, start: Date, allDay: Bool)] = []
    var due: [String] = []
    var calendarAllowed = false
    var remindersAllowed = false
    var focusSessions = 0

    struct OpenReminder { let id: String; let title: String }

    @MainActor static func today() async -> WispDay {
        var day = WispDay()
        day.focusSessions = PomodoroModel.shared.completedFocusSessions
        day.calendarAllowed = await WispAccess.calendar()
        day.remindersAllowed = WispAccess.has(.reminder)
        let store = EKEventStore()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        if day.calendarAllowed {
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            day.events = await Task.detached {
                store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
                    .map { (title: $0.title ?? "Untitled", start: $0.startDate, allDay: $0.isAllDay) }
            }.value
        }
        if day.remindersAllowed {
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
            day.due = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { reminders in
                    continuation.resume(returning: (reminders ?? []).compactMap(\.title))
                }
            }
        }
        return day
    }

    @MainActor static func openReminders() async -> [OpenReminder] {
        let store = EKEventStore()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map { OpenReminder(id: $0.calendarItemIdentifier, title: $0.title ?? "") })
            }
        }
    }

    var summary: String {
        var parts: [String] = []
        if calendarAllowed {
            let upcoming = events.filter { $0.allDay || $0.start > Date() }
            if upcoming.isEmpty {
                parts.append(events.isEmpty ? "Nothing on your calendar today." : "No more events today.")
            } else {
                let listed = upcoming.prefix(4).map { event in
                    event.allDay ? event.title : "\(event.title) at \(DateFormatter.localizedString(from: event.start, dateStyle: .none, timeStyle: .short))"
                }
                parts.append("Coming up: " + listed.joined(separator: ", ") + ".")
            }
        } else {
            parts.append("I can't see your calendar; allow it in Settings › Permissions.")
        }
        if remindersAllowed {
            parts.append(due.isEmpty ? "No reminders due." : "Due: " + due.prefix(4).joined(separator: ", ") + (due.count > 4 ? " and \(due.count - 4) more." : "."))
        }
        if focusSessions > 0 { parts.append("\(focusSessions) focus session\(focusSessions == 1 ? "" : "s") done.") }
        return parts.joined(separator: " ")
    }
}
