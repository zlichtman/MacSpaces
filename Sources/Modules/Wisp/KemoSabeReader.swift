import Foundation

/// The gateway's reader for questions its fixed answers don't cover ("is the user busy with
/// anything on Friday evening?"): Apple's model, on this Mac, sees only what the plain rules let
/// through for the next seven days (`GatewayPlainRule.facts`) and what macOS lets the agent read,
/// follows the owner's rules (`GatewayJudge`) and answers in one sentence, or not at all. Only on
/// macOS 26 with Apple Intelligence.
enum KemoSabeReader {
    static var isAvailable: Bool { GatewayJudge.modelAvailable }

    @MainActor static func answer(_ question: String, service: String) async -> String? {
        guard !question.isEmpty, isAvailable else { return nil }
        let facts = await facts()
        guard facts.count > 1 else { return nil }
        return await GatewayJudge.answer(rules: GatewayPlainRule.others(in: GatewayShare.rules), service: service,
                                         question: question, facts: facts)
    }

    /// What may be read for the next seven days, as plain lines.
    @MainActor private static func facts() async -> [String] {
        let now = Date()
        let week = DateInterval(start: now, duration: 7 * 86_400)
        let format = DateFormatter()
        format.setLocalizedDateFormatFromTemplate("EEEE d MMMM h:mm a")
        let dayOnly = DateFormatter()
        dayOnly.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        var facts = ["It is now \(format.string(from: now))."]
        let allowed = GatewayPlainRule.facts(under: GatewayShare.plainRules)
        if allowed.events, WispAccess.has(.event) {
            for event in await WispDay.events(in: week).prefix(40) {
                facts.append("Event: \(event.title), " + (event.allDay ? "all day \(dayOnly.string(from: event.start))" : format.string(from: event.start)))
            }
        } else if allowed.busy, WispAccess.has(.event) {
            for block in await WispDay.busy(in: week).prefix(40) {
                facts.append("Busy from \(format.string(from: block.start)) to \(format.string(from: block.end)).")
            }
            facts.append("Any time not listed as busy is free.")
        }
        if allowed.reminders, WispAccess.has(.reminder) {
            for title in await WispDay.dueReminders().prefix(20) { facts.append("Reminder due today: \(title)") }
        }
        return facts
    }
}
