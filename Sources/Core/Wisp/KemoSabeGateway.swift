import Foundation

/// KemoSabe, the gateway every cloud agent asks: what a model may learn about the owner's
/// schedule is when they're free, and nothing else. The model asks with `ASK: free tonight`;
/// KemoSabe reads the calendar on this Mac and hands back only free times, never an event's
/// title, place or people. It stands between them whichever face Wisp's page shows.
enum KemoSabeGateway {
    /// A stretch of time the model asked about, with the words to name it in the answer.
    struct Question: Equatable {
        let window: DateInterval
        /// "tonight", "Saturday afternoon", "tomorrow".
        let label: String
    }

    /// Parts of a day, as hours from midnight. A day on its own means waking hours.
    private static let parts: [(words: [String], label: String, from: Int, to: Int)] = [
        (["morning"], "morning", 8, 12),
        (["afternoon"], "afternoon", 12, 17),
        (["evening", "night", "tonight"], "evening", 17, 23),
    ]
    private static let wakingHours = (from: 8, to: 23)

    /// Understands "free tonight", "free saturday afternoon", "free tomorrow", "free 2026-11-14"
    /// and the same with "when is the user free". Nil when it isn't a free-time question or the
    /// time has already passed.
    static func question(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Question? {
        var words = text.lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        for lead in ["when is the user free", "when am i free", "is the user free", "free time", "free"] where words.hasPrefix(lead) {
            words = String(words.dropFirst(lead.count))
            break
        }
        words = words.trimmingCharacters(in: .whitespaces)
        for filler in ["on ", "this "] where words.hasPrefix(filler) { words = String(words.dropFirst(filler.count)) }

        // The part of the day, if one is named, then the day itself ("today" when only a part is).
        var part: (label: String, from: Int, to: Int)?
        var dayWords = words
        if words == "tonight" {
            part = ("evening", 17, 23)
            dayWords = "today"
        } else {
            for candidate in parts {
                for word in candidate.words where words == word || words.hasSuffix(" " + word) {
                    part = (candidate.label, candidate.from, candidate.to)
                    dayWords = String(words.dropLast(word.count)).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        if dayWords.isEmpty || dayWords == "this" { dayWords = "today" }
        let day: Date
        if dayWords == "today" {
            day = calendar.startOfDay(for: now)
        } else if let when = WispWhen.parse(dayWords, now: now, calendar: calendar) {
            day = calendar.startOfDay(for: when.date)
        } else {
            return nil
        }

        let hours = part.map { ($0.from, $0.to) } ?? (wakingHours.from, wakingHours.to)
        guard let start = calendar.date(bySettingHour: hours.0, minute: 0, second: 0, of: day),
              let end = calendar.date(bySettingHour: hours.1, minute: 0, second: 0, of: day) else { return nil }
        let from = max(start, now)
        guard from < end else { return nil }
        return Question(window: DateInterval(start: from, end: end), label: label(day: day, part: part?.label, now: now, calendar: calendar))
    }

    private static func label(day: Date, part: String?, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            switch part {
            case "evening": return "tonight"
            case let part?: return "this \(part)"
            case nil: return "today"
            }
        }
        let name: String
        if calendar.isDate(day, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now) ?? now) {
            name = "tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 0
            formatter.dateFormat = days < 7 ? "EEEE" : "EEEE d MMMM"
            name = formatter.string(from: day)
        }
        return part.map { "\(name) \($0)" } ?? name
    }

    /// The free stretches of `window` once `busy` is taken out, ignoring gaps shorter than
    /// `minimum`. Busy times may overlap or reach outside the window.
    static func freeTimes(busy: [DateInterval], in window: DateInterval, minimum: TimeInterval = 30 * 60) -> [DateInterval] {
        var free: [DateInterval] = []
        var cursor = window.start
        for block in busy.sorted(by: { $0.start < $1.start }) where block.end > cursor && block.start < window.end {
            if block.start > cursor { free.append(DateInterval(start: cursor, end: block.start)) }
            cursor = max(cursor, block.end)
        }
        if cursor < window.end { free.append(DateInterval(start: cursor, end: window.end)) }
        return free.filter { $0.duration >= minimum }
    }

    /// The whole answer the model receives, such as "Free after 7:00 PM tonight."
    static func answer(_ question: Question, busy: [DateInterval], calendar: Calendar = .current, locale: Locale = .current) -> String {
        let free = freeTimes(busy: busy, in: question.window)
        guard !free.isEmpty else { return "Busy \(question.label)." }
        if free.count == 1, free[0] == question.window { return "Free all \(question.label)." }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let spans = free.prefix(4).map { span -> String in
            if span.start == question.window.start { return "until \(formatter.string(from: span.end))" }
            if span.end == question.window.end { return "after \(formatter.string(from: span.start))" }
            return "\(formatter.string(from: span.start))–\(formatter.string(from: span.end))"
        }
        let listed = spans.count == 1 ? spans[0] : spans.dropLast().joined(separator: ", ") + " and " + spans[spans.count - 1]
        return "Free \(listed) \(question.label)."
    }
}
