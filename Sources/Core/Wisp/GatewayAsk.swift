import Foundation

/// A question a cloud model asked KemoSabe, once understood.
enum GatewayAsk: Equatable {
    case free(KemoSabeGateway.Question)
    case events(KemoSabeGateway.Question)
    case reminders
    /// Anything else, for Apple's model if allowed.
    case other(String)

    /// What an answer to it carries, for the rules review.
    var kind: GatewayJudge.Kind {
        switch self {
        case .free: return .freeTimes
        case .events: return .events
        case .reminders: return .reminders
        case .other: return .mixed
        }
    }

    /// What was asked, in the chat's words: "when you're free tonight", "what's on tomorrow",
    /// "what's due", or the question itself in quotes.
    var phrase: String {
        switch self {
        case let .free(question): return "when you're free \(question.label)"
        case let .events(question): return "what's on \(question.label)"
        case .reminders: return "what's due"
        case let .other(text): return "“\(text)”"
        }
    }

    /// The chat's small line for one ask: "Claude asked KemoSabe when you're free tonight → Free
    /// after 7:00 PM tonight.", or, when nothing went, "… → KemoSabe didn't share that."
    static func chatLine(service: String, agent: String, phrase: String, answer: String?) -> String {
        "\(service) asked \(agent) \(phrase) → " + (answer ?? withheld(agent))
    }

    /// What the chat says in place of an answer the agent kept back.
    static func withheld(_ agent: String) -> String { "\(agent) didn't share that." }

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> GatewayAsk {
        let words = text.lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        if ["reminders", "reminders due", "due", "what's due", "whats due", "due today", "reminders today"].contains(words) {
            return .reminders
        }
        for lead in ["events", "plans", "calendar", "what is on", "what's on", "whats on"] where words.hasPrefix(lead + " ") || words == lead {
            let rest = String(words.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
            if let question = KemoSabeGateway.question("free " + (rest.isEmpty ? "today" : rest), now: now, calendar: calendar) {
                return .events(question)
            }
        }
        if let question = KemoSabeGateway.question(words, now: now, calendar: calendar), words.contains("free") {
            return .free(question)
        }
        return .other(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension KemoSabeGateway {
    /// Event titles and times in the window, never where, with whom or their notes.
    static func eventsAnswer(_ question: Question, events: [(title: String, start: Date, allDay: Bool)],
                             calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard !events.isEmpty else { return "Nothing on the calendar \(question.label)." }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let listed = events.prefix(6).map { $0.allDay ? "\($0.title) (all day)" : "\($0.title) at \(formatter.string(from: $0.start))" }
        let more = events.count > 6 ? " and \(events.count - 6) more" : ""
        return "\(question.label.prefix(1).uppercased() + question.label.dropFirst()): " + listed.joined(separator: ", ") + more + "."
    }

    static func remindersAnswer(_ due: [String]) -> String {
        guard !due.isEmpty else { return "No reminders due." }
        return "Due: " + due.prefix(6).joined(separator: ", ") + (due.count > 6 ? " and \(due.count - 6) more." : ".")
    }
}
