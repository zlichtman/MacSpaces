import Foundation

/// A moment Wisp was told in words: "in 20 minutes", "tomorrow 3pm", "friday", "2026-11-02".
struct WispWhen: Equatable {
    var date: Date
    /// False for a whole day ("tomorrow", "friday").
    var hasTime: Bool

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> WispWhen? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return iso(trimmed.uppercased(), calendar: calendar)
            ?? relative(trimmed, now: now, calendar: calendar)
            ?? namedDay(trimmed, now: now, calendar: calendar)
            ?? detected(trimmed, now: now, calendar: calendar)
    }

    private static func iso(_ text: String, calendar: Calendar) -> WispWhen? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        for (format, hasTime) in [("yyyy-MM-dd'T'HH:mm", true), ("yyyy-MM-dd HH:mm", true), ("yyyy-MM-dd", false)] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return WispWhen(date: date, hasTime: hasTime) }
        }
        return nil
    }

    /// "in 20 minutes", "in an hour", "in 2 days", "20 min".
    private static func relative(_ text: String, now: Date, calendar: Calendar) -> WispWhen? {
        let pattern = #"^(?:in\s+)?(an?|\d+(?:\.\d+)?)\s*(seconds?|secs?|minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|w)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let amountRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }
        let amountText = String(text[amountRange])
        let amount = amountText.hasPrefix("a") ? 1 : (Double(amountText) ?? 0)
        switch text[unitRange].first ?? "w" {
        case "s": return WispWhen(date: now.addingTimeInterval(amount), hasTime: true)
        case "m": return WispWhen(date: now.addingTimeInterval(amount * 60), hasTime: true)
        case "h": return WispWhen(date: now.addingTimeInterval(amount * 3600), hasTime: true)
        case "d": return calendar.date(byAdding: .day, value: Int(amount), to: calendar.startOfDay(for: now)).map { WispWhen(date: $0, hasTime: false) }
        default: return calendar.date(byAdding: .day, value: Int(amount * 7), to: calendar.startOfDay(for: now)).map { WispWhen(date: $0, hasTime: false) }
        }
    }

    private static func namedDay(_ text: String, now: Date, calendar: Calendar) -> WispWhen? {
        let start = calendar.startOfDay(for: now)
        switch text {
        case "today": return WispWhen(date: start, hasTime: false)
        case "tonight": return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now).map { WispWhen(date: $0, hasTime: true) }
        case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: start).map { WispWhen(date: $0, hasTime: false) }
        default: break
        }
        let name = text.hasPrefix("next ") ? String(text.dropFirst(5)) : text
        // English day names in full ("friday"), whatever the calendar's locale: without one,
        // weekdaySymbols can come back short ("Fri") and the name would fall to the detector.
        var english = calendar
        english.locale = Locale(identifier: "en_US_POSIX")
        let names = english.weekdaySymbols.map { $0.lowercased() } + english.shortWeekdaySymbols.map { $0.lowercased() }
        guard let found = names.firstIndex(of: name) else { return nil }
        let index = found % 7
        var components = DateComponents()
        components.weekday = index + 1
        return calendar.nextDate(after: start, matching: components, matchingPolicy: .nextTime).map { WispWhen(date: $0, hasTime: false) }
    }

    private static func detected(_ text: String, now: Date, calendar: Calendar) -> WispWhen? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              // The whole phrase must be the date, so "mom tomorrow" isn't one.
              match.range.location == 0, match.range.length == (text as NSString).length,
              var date = match.date else { return nil }
        let hasTime = text.range(of: #"\d\s*(am|pm)|\d:\d\d|noon|midnight|morning|evening|afternoon|night"#, options: .regularExpression) != nil
        if !hasTime { date = calendar.startOfDay(for: date) }
        // A bare time already past today means tomorrow.
        if hasTime, date < now, calendar.isDate(date, inSameDayAs: now), !text.contains("today"),
           let next = calendar.date(byAdding: .day, value: 1, to: date) { date = next }
        return WispWhen(date: date, hasTime: hasTime)
    }
}

/// What Wisp understands without a language model: the obvious requests, typed or said.
/// The model, where macOS has one, handles everything else.
enum WispCommand: Equatable {
    case reminder(title: String, due: WispWhen?)
    case completeReminder(String)
    case note(String)
    case focus
    case stopFocus
    case timer(seconds: TimeInterval, name: String?)
    case day

    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> WispCommand? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".!?")))
        let lower = text.lowercased()
        let dayQuestions = ["what's my day", "whats my day", "what is my day", "my day", "today", "what's today",
                            "what's on today", "what do i have today", "what's left today", "what's next"]
        if dayQuestions.contains(lower) { return .day }

        if let rest = strip(lower, text, ["remind me to ", "remind me ", "reminder ", "reminder: ", "add reminder ",
                                         "task ", "task: ", "todo ", "todo: ", "to do ", "add task ", "add "]) {
            let (title, due) = splitTime(rest, now: now, calendar: calendar)
            return title.isEmpty ? nil : .reminder(title: title, due: due)
        }
        if let rest = strip(lower, text, ["note: ", "note ", "take a note ", "write down "]) {
            return rest.isEmpty ? nil : .note(rest)
        }
        if let rest = strip(lower, text, ["done: ", "done ", "complete ", "finish ", "check off ", "tick off "]) {
            return rest.isEmpty ? nil : .completeReminder(rest)
        }
        if ["focus", "start focus", "focus now", "start a focus session", "let's focus"].contains(lower) { return .focus }
        if ["stop focus", "end focus", "pause focus", "stop focusing"].contains(lower) { return .stopFocus }
        // "timer 5 minutes", "5 minute timer", "tea timer 4 min", "set a timer for 10 minutes"
        if lower.contains("timer"), let seconds = duration(in: lower) {
            let name = lower.components(separatedBy: "timer").first?
                .replacingOccurrences(of: "set a", with: "").replacingOccurrences(of: "start a", with: "")
                .trimmingCharacters(in: .whitespaces)
            let label = name.flatMap { $0.isEmpty || $0.first?.isNumber == true ? nil : $0.capitalized }
            return .timer(seconds: seconds, name: label)
        }
        return nil
    }

    private static func strip(_ lower: String, _ original: String, _ prefixes: [String]) -> String? {
        for prefix in prefixes where lower.hasPrefix(prefix) {
            return String(original.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// The first "N minutes/hours/seconds" in the text.
    static func duration(in text: String) -> TimeInterval? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*-?\s*(seconds?|secs?|s\b|minutes?|mins?|m\b|hours?|hrs?|h\b)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let amountRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text),
              let amount = Double(text[amountRange]), amount > 0 else { return nil }
        switch text[unitRange].first ?? "m" {
        case "s": return amount
        case "h": return amount * 3600
        default: return amount * 60
        }
    }

    /// Splits "call mom tomorrow 5pm" into ("call mom", tomorrow 5 pm) by trying ever
    /// shorter tails, dropping a joining "at", "on" or "by".
    static func splitTime(_ text: String, now: Date, calendar: Calendar) -> (String, WispWhen?) {
        let words = text.split(separator: " ").map(String.init)
        guard words.count > 1 else { return (text, nil) }
        let joiners: Set<String> = ["at", "on", "by", "due", "for"]
        for start in 1..<words.count {
            var tail = Array(words[start...])
            if let first = tail.first?.lowercased(), joiners.contains(first), tail.count > 1 { tail.removeFirst() }
            guard let when = WispWhen.parse(tail.joined(separator: " "), now: now, calendar: calendar) else { continue }
            var title = words[..<start].joined(separator: " ")
            for joiner in joiners where title.lowercased().hasSuffix(" " + joiner) { title = String(title.dropLast(joiner.count + 1)) }
            return (title.trimmingCharacters(in: .whitespaces), when)
        }
        return (text, nil)
    }

    /// Loose title matching for "check off the milk one".
    static func bestMatch(_ query: String, in titles: [String]) -> Int? {
        let words: (String) -> Set<String> = { Set($0.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 1 }) }
        let wanted = words(query)
        guard !wanted.isEmpty else { return nil }
        let scores = titles.map { title -> Double in
            let have = words(title)
            guard !have.isEmpty else { return 0 }
            return Double(wanted.intersection(have).count) / Double(max(wanted.count, have.count))
        }
        guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }), scores[best] > 0 else { return nil }
        return best
    }
}
