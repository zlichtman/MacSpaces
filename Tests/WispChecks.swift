import Foundation

@main struct WispChecks {
    static func main() {
        when()
        commands()
        replies()
        gateway()
        print("Wisp checks passed: times in words (relative, named days, ISO, bare times), reminders with and without dates, notes, completion, focus, timers, the day question, loose title matching, action lines in model replies, KemoSabe's free-time questions and answers")
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    /// Wednesday 28 October 2026, 14:00.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 14))!

    static func when() {
        precondition(WispWhen.parse("in 20 minutes", now: now, calendar: calendar) == WispWhen(date: now.addingTimeInterval(1200), hasTime: true))
        precondition(WispWhen.parse("in an hour", now: now, calendar: calendar)?.date == now.addingTimeInterval(3600))
        let tomorrow = WispWhen.parse("tomorrow", now: now, calendar: calendar)!
        precondition(!tomorrow.hasTime && calendar.component(.day, from: tomorrow.date) == 29)
        let friday = WispWhen.parse("friday", now: now, calendar: calendar)!
        precondition(calendar.component(.day, from: friday.date) == 30)
        let iso = WispWhen.parse("2026-11-02T09:30", now: now, calendar: calendar)!
        precondition(iso.hasTime && calendar.dateComponents([.month, .day, .hour], from: iso.date) == DateComponents(month: 11, day: 2, hour: 9))
        precondition(WispWhen.parse("call mom", now: now, calendar: calendar) == nil)
        precondition(WispWhen.parse("mom tomorrow", now: now, calendar: calendar) == nil, "A date must be the whole phrase")
    }

    static func commands() {
        guard case let .reminder(title, due)? = WispCommand.parse("remind me to call mom tomorrow", now: now, calendar: calendar) else { preconditionFailure() }
        precondition(title == "call mom" && due?.hasTime == false)
        guard case let .reminder(stretch, soon)? = WispCommand.parse("Remind me to stretch in 30 minutes", now: now, calendar: calendar) else { preconditionFailure() }
        precondition(stretch == "stretch" && soon?.date == now.addingTimeInterval(1800))
        precondition(WispCommand.parse("add buy oat milk", now: now, calendar: calendar) == .reminder(title: "buy oat milk", due: nil))
        precondition(WispCommand.parse("note: door code is 4411") == .note("door code is 4411"))
        precondition(WispCommand.parse("check off milk") == .completeReminder("milk"))
        precondition(WispCommand.parse("Focus") == .focus && WispCommand.parse("stop focus") == .stopFocus)
        precondition(WispCommand.parse("tea timer 4 min") == .timer(seconds: 240, name: "Tea"))
        precondition(WispCommand.parse("set a timer for 10 minutes") == .timer(seconds: 600, name: nil))
        precondition(WispCommand.parse("What's my day?") == .day)
        precondition(WispCommand.parse("tell me a joke") == nil)
        precondition(WispCommand.bestMatch("milk", in: ["Call the dentist", "Buy oat milk"]) == 1)
        precondition(WispCommand.bestMatch("taxes", in: ["Call the dentist"]) == nil)
    }

    static func replies() {
        let reply = WispReply.parse("On it!\nDO: remind me to call Sam tomorrow\n- DO: tea timer 4 min\n`do: my day`")
        precondition(reply.text == "On it!")
        precondition(reply.actions == ["remind me to call Sam tomorrow", "tea timer 4 min", "my day"])
        precondition(reply.actions.compactMap { WispCommand.parse($0, now: now, calendar: calendar) }.count == 3)
        precondition(WispReply.parse("Just chatting.\nDO:") == WispReply(text: "Just chatting.", actions: []))
    }

    static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    static func gateway() {
        // Times read as macOS writes them, with a narrow space before PM.
        func answer(_ question: KemoSabeGateway.Question, _ busy: [DateInterval]) -> String {
            KemoSabeGateway.answer(question, busy: busy, calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        let reply = WispReply.parse("ASK: free tonight\n- ASK: free saturday afternoon")
        precondition(reply.asks == ["free tonight", "free saturday afternoon"] && reply.text.isEmpty && reply.actions.isEmpty)

        // Questions: the window runs from now (14:00 on Wednesday 28th) and is named in plain words.
        let tonight = KemoSabeGateway.question("free tonight", now: now, calendar: calendar)!
        precondition(tonight == KemoSabeGateway.Question(window: DateInterval(start: at(28, 17), end: at(28, 23)), label: "tonight"))
        let today = KemoSabeGateway.question("When is the user free today?", now: now, calendar: calendar)!
        precondition(today.window == DateInterval(start: now, end: at(28, 23)) && today.label == "today", "Today starts now, not at 8")
        let saturday = KemoSabeGateway.question("free saturday afternoon", now: now, calendar: calendar)!
        precondition(saturday == KemoSabeGateway.Question(window: DateInterval(start: at(31, 12), end: at(31, 17)), label: "Saturday afternoon"))
        precondition(KemoSabeGateway.question("free tomorrow", now: now, calendar: calendar)?.label == "tomorrow")
        precondition(KemoSabeGateway.question("free tomorrow morning", now: now, calendar: calendar)?.window.start == at(29, 8))
        precondition(KemoSabeGateway.question("free this morning", now: now, calendar: calendar) == nil, "The morning has passed")
        precondition(KemoSabeGateway.question("free whenever sarah likes", now: now, calendar: calendar) == nil)
        precondition(KemoSabeGateway.question("what's the door code", now: now, calendar: calendar) == nil)

        // Free times: busy blocks overlap, reach outside the window, and short gaps don't count.
        let window = DateInterval(start: at(28, 17), end: at(28, 23))
        let busy = [DateInterval(start: at(28, 16), end: at(28, 18)), DateInterval(start: at(28, 17, 30), end: at(28, 19)),
                    DateInterval(start: at(28, 19, 15), end: at(28, 20))]
        precondition(KemoSabeGateway.freeTimes(busy: busy, in: window) == [DateInterval(start: at(28, 20), end: at(28, 23))])
        precondition(KemoSabeGateway.freeTimes(busy: [], in: window) == [window])

        // Answers carry times only.
        precondition(answer(tonight, busy) == "Free after 8:00 PM tonight.")
        precondition(answer(tonight, []) == "Free all tonight.")
        precondition(answer(tonight, [window]) == "Busy tonight.")
        let split = [DateInterval(start: at(31, 13), end: at(31, 15))]
        precondition(answer(saturday, split) == "Free until 1:00 PM and after 3:00 PM Saturday afternoon.")
        let middle = [DateInterval(start: at(28, 17), end: at(28, 18)), DateInterval(start: at(28, 20), end: at(28, 23))]
        precondition(answer(tonight, middle) == "Free 6:00 PM–8:00 PM tonight.")
    }
}
