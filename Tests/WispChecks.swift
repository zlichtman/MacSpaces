import Foundation

@main struct WispChecks {
    static func main() {
        when()
        commands()
        replies()
        gateway()
        approvals()
        sources()
        print("Wisp checks passed: times in words (relative, named days, ISO, bare times), reminders with and without dates, notes, completion, focus, timers, the day question, loose title matching, action lines in model replies, KemoSabe's free-time questions and answers, what each gateway question asks for, the old menus as plain rules, the ask lines and a plain denial, and Ask me before sharing's cards (what goes back for each answer, only the first answer counting, timeouts), and the pages a web answer drew on (the sources tail and links lifted out of the words, web pages only, three sites named, the API's answer after its search, Claude Code's search count)")
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
        precondition(WispCommand.parse("note: buy oat milk") == .note("buy oat milk"))
        precondition(WispCommand.parse("check off milk") == .completeReminder("milk"))
        precondition(WispCommand.parse("remove stretch") == .remove("stretch"))
        precondition(WispCommand.parse("Delete the reminder to call the dentist") == .remove("call the dentist"))
        precondition(WispCommand.parse("cancel my note about tea") == .remove("tea"))
        precondition(WispCommand.parse("Focus") == .focus && WispCommand.parse("stop focus") == .stopFocus)
        precondition(WispCommand.parse("tea timer 4 min") == .timer(seconds: 240, name: "Tea"))
        precondition(WispCommand.parse("set a timer for 10 minutes") == .timer(seconds: 600, name: nil))
        precondition(WispCommand.parse("What's my day?") == .day)
        precondition(WispCommand.parse("tell me a joke") == nil)
        precondition(WispCommand.bestMatch("milk", in: ["Call the dentist", "Buy oat milk"]) == 1)
        precondition(WispCommand.bestMatch("taxes", in: ["Call the dentist"]) == nil)
    }

    static func replies() {
        let reply = WispReply.parse("On it!\nDO: remind me to call the dentist tomorrow\n- DO: tea timer 4 min\n`do: my day`")
        precondition(reply.text == "On it!")
        precondition(reply.actions == ["remind me to call the dentist tomorrow", "tea timer 4 min", "my day"])
        precondition(reply.actions.compactMap { WispCommand.parse($0, now: now, calendar: calendar) }.count == 3)
        precondition(WispReply.parse("Just chatting.\nDO:") == WispReply(text: "Just chatting.", actions: []))
    }

    static func sources() {
        // Claude Code's own words from a searched answer: the tail goes, the pages stay in order.
        let cli = WispSources.lift("Max Verstappen won the most recent race, the 2026 Las Vegas Grand Prix, on November 21, 2026. Sources: [Silverstone](https://www.silverstone.co.uk/news/f1-2026-las-vegas-grand-prix-results-verstappen-wins-after-race-long-battle-russell), [Al Jazeera](https://www.aljazeera.com/sports/2026/11/22/max-verstappen-las-vegas-grand-prix-f1-norris-piastri-russell-antonelli)")
        precondition(cli.text == "Max Verstappen won the most recent race, the 2026 Las Vegas Grand Prix, on November 21, 2026.", cli.text)
        precondition(cli.pages.map(WispSources.site) == ["silverstone.co.uk", "aljazeera.com"])
        precondition(WispSources.line(service: "Claude", pages: cli.pages) == "Claude searched the web: silverstone.co.uk, aljazeera.com")

        // The same with the list on lines of its own, as Claude Code wrote it under the app's instructions.
        let lines = WispSources.lift("Tomorrow in Chicago looks cold and cloudy, with a high around 40°F.\n\nSources:\n[Meteored](https://www.theweather.com/chicago.htm)\n[timeanddate](https://www.timeanddate.com/weather/usa/chicago/ext)\n[PredictWind](https://www.predictwind.com/weather/united-states/illinois/chicago)\n[The Weather Network](https://www.theweathernetwork.com/en/city/us/illinois/chicago/7-days)")
        precondition(lines.text == "Tomorrow in Chicago looks cold and cloudy, with a high around 40°F.", lines.text)
        precondition(WispSources.line(service: "Claude", pages: lines.pages) == "Claude searched the web: theweather.com, timeanddate.com, predictwind.com and 1 more")

        // A listed tail, bold, with a request after it: the request still reaches Wisp.
        let listed = WispSources.lift("The game is Friday at 7.\n\n**Sources:**\n- [NBA](https://www.nba.com/game/1)\n- https://espn.com/nba/schedule.\nDO: remind me about the game Friday at 6pm")
        precondition(listed.pages.map(\.absoluteString) == ["https://www.nba.com/game/1", "https://espn.com/nba/schedule"], "\(listed.pages)")
        let reply = WispReply.parse(listed.text)
        precondition(reply.text == "The game is Friday at 7." && reply.actions == ["remind me about the game Friday at 6pm"], "\(reply)")

        // A link in the words keeps its words; the same page isn't listed twice.
        let inline = WispSources.lift("It opens at 9 ([National Park Service](https://www.nps.gov/glac/hours.htm)). Sources: [NPS](https://www.nps.gov/glac/hours.htm) and [Wikipedia](https://en.wikipedia.org/wiki/Glacier_National_Park_(U.S.))")
        precondition(inline.text == "It opens at 9 (National Park Service).", inline.text)
        precondition(inline.pages.map(\.absoluteString) == ["https://www.nps.gov/glac/hours.htm", "https://en.wikipedia.org/wiki/Glacier_National_Park_(U.S.)"], "\(inline.pages)")

        // Words that aren't a sources list stay, and so does an address the user asked for.
        let plain = WispSources.lift("My sources: mostly the park's own site. It's at https://www.nps.gov/glac.")
        precondition(plain.text == "My sources: mostly the park's own site. It's at https://www.nps.gov/glac." && plain.pages.isEmpty, plain.text)
        precondition(WispSources.lift("Just chatting.") == WispSources(text: "Just chatting.", pages: []))

        // Only web pages: a link that isn't http or https is never offered.
        precondition(WispSources.page("javascript:alert(1)") == nil && WispSources.page("file:///etc/hosts") == nil)
        precondition(WispSources.page("https://localhost/x") == nil && WispSources.page("https://nps.gov/glac).")?.absoluteString == "https://nps.gov/glac")
        let odd = WispSources.lift("See [this](file:///etc/hosts) page.")
        precondition(odd.text == "See [this](file:///etc/hosts) page." && odd.pages.isEmpty, odd.text)

        // The API's blocks, as its documentation shapes them: the words after the search are the
        // answer, split where a citation ends, and the words before it never are.
        let look: [String: Any] = ["type": "text", "text": "I'll search for when Claude Shannon was born."]
        let search: [String: Any] = ["type": "server_tool_use", "id": "srvtoolu_01", "name": "web_search", "input": ["query": "claude shannon birth date"]]
        let result: [String: Any] = ["type": "web_search_tool_result", "tool_use_id": "srvtoolu_01", "content": [
            ["type": "web_search_result", "url": "https://en.wikipedia.org/wiki/Claude_Shannon", "title": "Claude Shannon", "encrypted_content": "EqgfCio", "page_age": "April 30, 2025"]]]
        let cite: [String: Any] = ["type": "web_search_result_location", "url": "https://en.wikipedia.org/wiki/Claude_Shannon", "title": "Claude Shannon",
                                   "encrypted_index": "Eo8BCio", "cited_text": "Claude Elwood Shannon (April 30, 1916"]
        let born: [String: Any] = ["type": "text", "text": "Claude Shannon was born on April 30, 1916", "citations": [cite]]
        let place: [String: Any] = ["type": "text", "text": ", in Petoskey, Michigan.", "citations": [cite]]
        let answered = WispSources.answer(in: [look, search, result, born, place])
        precondition(answered.text == "Claude Shannon was born on April 30, 1916, in Petoskey, Michigan." && answered.searched, answered.text)
        precondition(answered.pages.map(\.absoluteString) == ["https://en.wikipedia.org/wiki/Claude_Shannon"])
        // A search with nothing after it, or one still on its way, is no answer: "I'll search" isn't shown as one.
        precondition(WispSources.answer(in: [look, search, result]).text.isEmpty && WispSources.answer(in: [look, search, result]).searched)
        precondition(WispSources.answer(in: [look, search]).text.isEmpty)
        // A search that failed still has Claude's words after it; no search at all is just the words.
        let failed: [String: Any] = ["type": "web_search_tool_result", "tool_use_id": "srvtoolu_01",
                                     "content": ["type": "web_search_tool_result_error", "error_code": "max_uses_exceeded"]]
        let sorry: [String: Any] = ["type": "text", "text": "I couldn't search just now."]
        precondition(WispSources.answer(in: [look, search, failed, sorry]).text == "I couldn't search just now.")
        let plainAnswer = WispSources.answer(in: [["type": "text", "text": "17 times 23 is 391."]])
        precondition(plainAnswer.text == "17 times 23 is 391." && !plainAnswer.searched && plainAnswer.pages.isEmpty)

        // Claude Code counts searches under the model that ran them, which may not be the one answering.
        precondition(WispSources.searched(claudeCode: #"{"result":"Cold and cloudy.","modelUsage":{"claude-sonnet-5-5":{"webSearchRequests":0},"claude-haiku-5-5":{"webSearchRequests":2}}}"#))
        precondition(!WispSources.searched(claudeCode: #"{"result":"391.","modelUsage":{"claude-sonnet-5-5":{"webSearchRequests":0}}}"#))
        precondition(!WispSources.searched(claudeCode: "not json") && !WispSources.searched(claudeCode: #"{"result":"Hi."}"#))

        // The line names three sites at most, each once, and never the model's title for a page.
        let many = ["https://a.com/1", "https://www.a.com/2", "https://b.org", "https://c.net", "https://d.io", "https://e.dev"].compactMap(WispSources.page)
        precondition(WispSources.line(service: "Claude", pages: many) == "Claude searched the web: a.com, b.org, c.net and 2 more")
        precondition(WispSources.sites(many).shown.first?.page.absoluteString == "https://a.com/1")
        precondition(WispSources.line(service: "Claude", pages: []) == "Claude searched the web")
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
        precondition(KemoSabeGateway.question("free whenever robin likes", now: now, calendar: calendar) == nil)
        precondition(KemoSabeGateway.question("what's the door code", now: now, calendar: calendar) == nil)

        // What a question asks for, so the Gateway card's levels can decide.
        precondition(GatewayAsk.parse("free tonight", now: now, calendar: calendar) == .free(tonight))
        precondition(GatewayAsk.parse("events tomorrow", now: now, calendar: calendar)
                     == .events(KemoSabeGateway.question("free tomorrow", now: now, calendar: calendar)!))
        precondition(GatewayAsk.parse("plans tonight", now: now, calendar: calendar) == .events(tonight))
        precondition(GatewayAsk.parse("Reminders due", now: now, calendar: calendar) == .reminders)
        precondition(GatewayAsk.parse("what's the door code", now: now, calendar: calendar) == .other("what's the door code"))
        let events = [(title: "Dinner", start: at(28, 19), allDay: false), (title: "Holiday", start: at(28, 0), allDay: true)]
        precondition(KemoSabeGateway.eventsAnswer(tonight, events: events, calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
                        .replacingOccurrences(of: "\u{202F}", with: " ") == "Tonight: Dinner at 7:00 PM, Holiday (all day).")
        precondition(KemoSabeGateway.remindersAnswer([]) == "No reminders due.")

        // Gateway rules: one by one; injected text stays data.
        precondition(GatewayJudge.split("Only Claude may know my schedule. Other services get nothing.\n- Don't share reminders\n\n") ==
                     ["Only Claude may know my schedule. Other services get nothing.", "Don't share reminders"])
        precondition(GatewayJudge.split("  \n.\n") == [] && GatewayJudge.split(String(repeating: "Rule.\n", count: 30)).count == 12)

        // The old Gateway menus as plain rules: each install shares exactly what its menus did.
        let free = GatewayAsk.parse("free tonight", now: now, calendar: calendar)
        let eventsAsk = GatewayAsk.parse("events tomorrow", now: now, calendar: calendar)
        let other = GatewayAsk.other("is the user busy friday?")
        func allowed(_ rules: [GatewayPlainRule]) -> [Bool] {
            [free, eventsAsk, .reminders, other].map { GatewayPlainRule.allows($0, under: Set(rules)) }
        }
        precondition(allowed(GatewayPlainRule.migrated(calendar: "nothing", reminders: "nothing", appleAnswers: false)) == [false, false, false, false],
                     "Unset menus shared nothing, and still share nothing")
        precondition(allowed(GatewayPlainRule.migrated(calendar: "free", reminders: "nothing", appleAnswers: false)) == [true, false, false, false])
        precondition(allowed(GatewayPlainRule.migrated(calendar: "events", reminders: "due", appleAnswers: false)) == [true, true, true, false])
        precondition(allowed(GatewayPlainRule.migrated(calendar: "events", reminders: "due", appleAnswers: true)) == [true, true, true, true])
        precondition(GatewayPlainRule.migrated(calendar: "events", reminders: "due", appleAnswers: true).isEmpty, "Everything allowed needs no rule")
        precondition(allowed([]) == [true, true, true, true], "A new install shares by judgement")
        let freeFacts = GatewayPlainRule.facts(under: [.freeTimesOnly, .noReminders])
        precondition(freeFacts.busy && !freeFacts.events && !freeFacts.reminders, "Free times only: the reader sees busy times, nothing else")
        let merged = GatewayPlainRule.merged([.freeTimesOnly, .noReminders], into: "Never mention Robin.\n")
        precondition(merged == "From my calendar, share only when I'm free or busy.\nNever share my reminders.\nNever mention Robin.")
        precondition(GatewayPlainRule.found(in: merged) == [.freeTimesOnly, .noReminders])
        precondition(GatewayPlainRule.merged([.noReminders], into: merged) == merged, "A rule already there isn't added twice")
        precondition(GatewayJudge.split(merged) == ["Never mention Robin."], "Plain rules are decided in code, not by the model")
        precondition(GatewayPlainRule(line: "  - never share my REMINDERS ") == .noReminders, "Plain rules match however they're typed")
        precondition(GatewayPlainRule(line: "Never share my reminders with Claude.") == nil, "An edited rule is an ordinary rule")
        // A denial is said plainly in the chat, in the agent's own name.
        let denied = GatewayAsk.chatLine(service: "Claude", agent: "KemoSabe", phrase: eventsAsk.phrase,
                                         answer: GatewayPlainRule.allows(eventsAsk, under: [.noCalendar]) ? "Tomorrow: Lunch at 12:30 PM." : nil)
        precondition(denied == "Claude asked KemoSabe what's on tomorrow → KemoSabe didn't share that.")
        precondition(GatewayJudge.plainlyBreaks(rule: "Only Claude may know my schedule.", service: "Another service", draft: "Free until 7.", kind: .freeTimes) != nil,
                     "Only Claude: another service is someone else")
        let facts = ["Event: Dinner with Robin, Wednesday 7:00 PM", "Reminder due today: Pick up prescription"]
        precondition(GatewayJudge.kind(of: "You need to pick up a prescription.", facts: facts) == .reminders)
        precondition(GatewayJudge.kind(of: "Dinner at 7, then the prescription.", facts: facts) == .mixed)
        precondition(GatewayJudge.kind(of: "Busy from 7 on Wednesday.", facts: facts) == .freeTimes)
        precondition(GatewayJudge.reviewPrompt(rule: "Never mention Robin.", service: "Claude", question: "q", draft: "d", kind: .reminders).hasPrefix("The user's rule: Never mention Robin."))
        let medical = "Never share anything about medical or doctor appointments, prescriptions or health."
        precondition(GatewayJudge.plainlyBreaks(rule: medical, service: "Claude", draft: "Friday: Doctor appointment at 10:00 AM.", kind: .events) != nil)
        precondition(GatewayJudge.plainlyBreaks(rule: medical, service: "Claude", draft: "Due: Pick up prescription.", kind: .reminders) != nil)
        precondition(GatewayJudge.plainlyBreaks(rule: medical, service: "Claude", draft: "Tomorrow: Team standup at 9:00 AM.", kind: .events) == nil)
        precondition(GatewayJudge.plainlyBreaks(rule: "Never mention Robin.", service: "Claude", draft: "Tonight: Dinner with Robin.", kind: .events) != nil)
        precondition(GatewayJudge.plainlyBreaks(rule: "Never mention Robin.", service: "Claude", draft: "Free until 7:00 PM tonight.", kind: .freeTimes) == nil)
        precondition(GatewayJudge.plainlyBreaks(rule: "Don't share my reminders with anyone.", service: "Claude", draft: "Due: Call the bank.", kind: .reminders) != nil)
        precondition(GatewayJudge.plainlyBreaks(rule: "Don't share my reminders with anyone.", service: "Claude", draft: "Free until 7:00 PM tonight.", kind: .freeTimes) == nil)
        let timesOnly = "Share dates and times, but never what an event is or who it's with."
        precondition(GatewayJudge.plainlyBreaks(rule: timesOnly, service: "Claude", draft: "Saturday: Flight to Denver at 6:00 AM.", kind: .events) != nil)
        precondition(GatewayJudge.plainlyBreaks(rule: timesOnly, service: "Claude", draft: "Free after 9:00 AM Saturday.", kind: .freeTimes) == nil)
        let onlyClaude = "Only Claude may know my schedule. Other services get nothing."
        precondition(GatewayJudge.plainlyBreaks(rule: onlyClaude, service: "OpenAI", draft: "Free until 7.", kind: .freeTimes) != nil)
        precondition(GatewayJudge.plainlyBreaks(rule: onlyClaude, service: "Claude", draft: "Free until 7.", kind: .freeTimes) == nil)
        let freeOnly = "OpenAI may only know when I'm free, nothing else."
        precondition(GatewayJudge.plainlyBreaks(rule: freeOnly, service: "OpenAI", draft: "Thursday: Team standup at 9:00 AM.", kind: .events) != nil)
        precondition(GatewayJudge.plainlyBreaks(rule: freeOnly, service: "OpenAI", draft: "Free until 4:00 PM Tuesday.", kind: .freeTimes) == nil)
        precondition(GatewayJudge.plainlyBreaks(rule: freeOnly, service: "Claude", draft: "Thursday: Team standup at 9:00 AM.", kind: .events) == nil)
        precondition(GatewayJudge.plainlyBreaks(rule: "Keep my therapy private.", service: "Claude", draft: "Tuesday: Therapy at 4:00 PM.", kind: .events) != nil)
        precondition(GatewayJudge.plainlyBreaks(rule: "Only Gemini may see my reminders.", service: "Claude", draft: "Due: Renew passport.", kind: .reminders) != nil)
        precondition(GatewayJudge.plainlyBreaks(rule: "Only Gemini may see my reminders.", service: "Claude", draft: "Free until 7.", kind: .freeTimes) == nil)
        precondition(GatewayJudge.answerInstructions(rules: "").contains("I can't say") && !GatewayJudge.answerInstructions(rules: "").contains("rules, which"))
        precondition(GatewayJudge.cleaned(String(repeating: "a", count: 5_000)).count == GatewayJudge.rulesLimit)
        precondition(GatewayJudge.spoken("I can't say.") == nil && GatewayJudge.spoken("\"Free after 7 tonight.\"") == "Free after 7 tonight.")

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

    /// Ask me before sharing: what each answer sends and shows, the first answer counting, and timeouts.
    static func approvals() {
        let card = GatewayApproval(service: "Claude", question: "free tonight", draft: "Free after 8:00 PM tonight.", asked: now)
        precondition(card.modelLine(.share) == "free tonight: Free after 8:00 PM tonight.")
        precondition(card.modelLine(.decline) == "free tonight: The user declined to share that.")
        precondition(card.modelLine(.timedOut) == card.modelLine(.decline), "A card left alone declines, saying no more than a decline")
        precondition(!card.modelLine(.decline).contains("8:00"), "A declined draft never reaches the model")
        precondition(card.chatLine(.share) == (true, "Claude asked KemoSabe “free tonight” → Free after 8:00 PM tonight."))
        precondition(card.chatLine(.decline) == (false, "You didn't share that with Claude."))
        // The chat's small ask lines, and a denial said plainly.
        let tonightAsk = GatewayAsk.parse("free tonight", now: now, calendar: calendar)
        precondition(GatewayAsk.chatLine(service: "Claude", agent: "KemoSabe", phrase: tonightAsk.phrase, answer: "Free after 7:00 PM tonight.")
                     == "Claude asked KemoSabe when you're free tonight → Free after 7:00 PM tonight.")
        precondition(GatewayAsk.chatLine(service: "Claude", agent: "Wisp", phrase: GatewayAsk.reminders.phrase, answer: nil)
                     == "Claude asked Wisp what's due → Wisp didn't share that.")
        let named = GatewayApproval(service: "Claude", question: "free tonight", draft: "Free after 8:00 PM tonight.", asked: now,
                                    agent: "Wisp", phrase: tonightAsk.phrase)
        precondition(named.chatLine(.share) == (true, "Claude asked Wisp when you're free tonight → Free after 8:00 PM tonight."))
        precondition(card.chatLine(.timedOut) == (false, "Not shared with Claude: no answer in 2 minutes."))
        precondition(card.deadline == now.addingTimeInterval(120))
        precondition(card.secondsLeft(at: now) == 120 && card.secondsLeft(at: now.addingTimeInterval(54.2)) == 66)
        precondition(card.secondsLeft(at: now.addingTimeInterval(500)) == 0)
        precondition(GatewayApproval.countdown(120) == "2:00" && GatewayApproval.countdown(65) == "1:05" && GatewayApproval.countdown(-3) == "0:00")

        var book = GatewayApprovalBook()
        let second = GatewayApproval(service: "Claude", question: "reminders due", draft: "Due: Renew passport.", asked: now.addingTimeInterval(30))
        book.add(card)
        book.add(second)
        book.add(card)
        precondition(book.waiting.count == 2 && book.first == card, "A card is added once, oldest first")
        precondition(book.expired(at: now.addingTimeInterval(119)).isEmpty)
        precondition(book.expired(at: now.addingTimeInterval(120)) == [card.id])
        precondition(book.expired(at: now.addingTimeInterval(200)) == [card.id, second.id])
        precondition(book.resolve(card.id) == card)
        precondition(book.resolve(card.id) == nil, "Only the first answer counts")
        precondition(book.first == second && book.expired(at: now.addingTimeInterval(130)).isEmpty)
        precondition(book.resolve(UUID()) == nil)
        precondition(book.resolve(second.id) == second && book.waiting.isEmpty && book.first == nil)
    }
}
