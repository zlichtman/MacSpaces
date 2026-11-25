import Foundation

/// The rules the Gateway's old Calendar, Reminders and Answer other questions menus became. The
/// on-device agent now shares by judgement: whatever macOS lets it read, unless the owner's rules
/// say otherwise. These four sentences are the menus' choices, written as rules for existing
/// installs (`migrated`), and MacSpaces decides them in code, exactly as the menus did, before
/// anything is read: no model is needed for them, so they hold on every Mac. The owner can edit or
/// delete them like any rule; an edited one becomes an ordinary rule for Apple's model.
enum GatewayPlainRule: String, CaseIterable {
    case noCalendar = "Never share anything from my calendar."
    case freeTimesOnly = "From my calendar, share only when I'm free or busy."
    case noReminders = "Never share my reminders."
    case setQuestionsOnly = "Answer only questions about when I'm free, my events or what's due."

    /// Letters and digits only, lowercased, so a rule matches whatever its punctuation or spacing.
    static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    init?(line: String) {
        let line = Self.normalized(line)
        guard let rule = Self.allCases.first(where: { Self.normalized($0.rawValue) == line }) else { return nil }
        self = rule
    }

    /// The plain rules among the owner's rules, one per line.
    static func found(in rules: String) -> Set<GatewayPlainRule> {
        Set(rules.components(separatedBy: .newlines).compactMap { GatewayPlainRule(line: $0) })
    }

    /// The owner's other rules, for Apple's model, with the plain ones taken out.
    static func others(in rules: String) -> String {
        rules.components(separatedBy: .newlines).filter { GatewayPlainRule(line: $0) == nil }.joined(separator: "\n")
    }

    /// Whether the plain rules let the agent answer this ask at all.
    static func allows(_ ask: GatewayAsk, under rules: Set<GatewayPlainRule>) -> Bool {
        switch ask {
        case .free: return !rules.contains(.noCalendar)
        case .events: return !rules.contains(.noCalendar) && !rules.contains(.freeTimesOnly)
        case .reminders: return !rules.contains(.noReminders)
        case .other: return !rules.contains(.setQuestionsOnly)
        }
    }

    /// What Apple's model may see to answer other questions under these rules: busy times, events,
    /// and reminders due.
    static func facts(under rules: Set<GatewayPlainRule>) -> (busy: Bool, events: Bool, reminders: Bool) {
        let calendar = !rules.contains(.noCalendar)
        return (calendar && rules.contains(.freeTimesOnly), calendar && !rules.contains(.freeTimesOnly), !rules.contains(.noReminders))
    }

    /// The rules an existing install's menus become, so it shares exactly what it did: Calendar
    /// (`nothing`, `free` or `events`), Reminders (`nothing` or `due`) and Answer other questions.
    static func migrated(calendar: String, reminders: String, appleAnswers: Bool) -> [GatewayPlainRule] {
        var rules: [GatewayPlainRule] = []
        switch calendar {
        case "events": break
        case "free": rules.append(.freeTimesOnly)
        default: rules.append(.noCalendar)
        }
        if reminders != "due" { rules.append(.noReminders) }
        if !appleAnswers { rules.append(.setQuestionsOnly) }
        return rules
    }

    /// The owner's rules with the migrated ones first, each on its own line; nothing is added twice.
    static func merged(_ migrated: [GatewayPlainRule], into rules: String) -> String {
        let present = found(in: rules)
        let added = migrated.filter { !present.contains($0) }.map(\.rawValue)
        let kept = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        return (added + (kept.isEmpty ? [] : [kept])).joined(separator: "\n")
    }
}
