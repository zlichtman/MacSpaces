import Foundation

/// A to-do written in a note as a Markdown checkbox line: `- [ ] Call the plumber ~25m !! @14:30`.
/// `~25m`, `~1h` or `~1h30m` is how long it should take, `!` to `!!!` its priority, and `@14:30`
/// (or `@9am`) when it's due today. The marks stay in the note's text; the title is the rest.
struct NoteTask: Equatable, Identifiable {
    let note: UUID
    /// The line of the note's text it's on, from 0.
    let line: Int
    let title: String
    let done: Bool
    /// The estimate in minutes.
    let minutes: Int?
    /// 0 (none) to 3.
    let priority: Int
    /// Minutes after midnight.
    let due: Int?

    var id: String { "\(note.uuidString)-\(line)" }
}

enum NoteTasks {
    /// A checkbox line's state and what follows the box; nil for any other line.
    static func checkbox(in line: String) -> (done: Bool, rest: String)? {
        var rest = Substring(line).drop(while: { $0 == " " || $0 == "\t" })
        guard let bullet = rest.first, bullet == "-" || bullet == "*" || bullet == "+" else { return nil }
        rest = rest.dropFirst().drop(while: { $0 == " " })
        guard rest.count >= 3, rest.first == "[" else { return nil }
        let mark = rest[rest.index(after: rest.startIndex)]
        guard rest[rest.index(rest.startIndex, offsetBy: 2)] == "]", mark == " " || mark == "x" || mark == "X" else { return nil }
        // A file with Windows line endings leaves a return at the end of each line.
        return (mark != " ", String(rest.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func tasks(in text: String, note: UUID) -> [NoteTask] {
        var tasks: [NoteTask] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            guard let box = checkbox(in: line) else { continue }
            var minutes: Int?, priority = 0, due: Int?, words: [String] = []
            for token in box.rest.split(separator: " ").map(String.init) {
                if minutes == nil, let value = estimate(token) { minutes = value }
                else if priority == 0, !token.isEmpty, token.count <= 3, token.allSatisfy({ $0 == "!" }) { priority = token.count }
                else if due == nil, let value = time(token) { due = value }
                else { words.append(token) }
            }
            let title = words.joined(separator: " ")
            guard !title.isEmpty else { continue }
            tasks.append(NoteTask(note: note, line: index, title: title, done: box.done, minutes: minutes, priority: priority, due: due))
        }
        return tasks
    }

    /// `~25m`, `~2h`, `~1h30m`, `~1.5h`: minutes, 1 to 24 hours' worth.
    static func estimate(_ token: String) -> Int? {
        guard token.hasPrefix("~") else { return nil }
        let body = token.dropFirst().lowercased()
        var total = 0.0, number = "", sawUnit = false
        for character in body {
            if character.isNumber || character == "." { number.append(character); continue }
            guard let value = Double(number), character == "h" || character == "m" else { return nil }
            total += character == "h" ? value * 60 : value
            number = ""; sawUnit = true
        }
        guard sawUnit, number.isEmpty, total >= 1, total <= 24 * 60 else { return nil }
        return Int(total.rounded())
    }

    /// `@14:30`, `@9:05`, `@9am`, `@2:30pm`: minutes after midnight.
    static func time(_ token: String) -> Int? {
        guard token.hasPrefix("@") else { return nil }
        var body = token.dropFirst().lowercased()
        var half: String?
        if body.hasSuffix("am") || body.hasSuffix("pm") { half = String(body.suffix(2)); body = String(body.dropLast(2)) }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, let first = parts.first, var hour = Int(first), first.count <= 2 else { return nil }
        var minute = 0
        if parts.count == 2 { guard parts[1].count == 2, let value = Int(parts[1]) else { return nil }; minute = value }
        else if half == nil { return nil }
        if let half {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (half == "pm" ? 12 : 0)
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// The note's text with that line's box ticked or cleared; nil when the line is no longer
    /// that to-do (the note changed since the list was made).
    static func toggled(_ text: String, task: NoteTask) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(task.line),
              tasks(in: lines[task.line], note: task.note).first.map({ $0.title == task.title && $0.done == task.done }) == true,
              let open = lines[task.line].firstIndex(of: "[") else { return nil }
        let mark = lines[task.line].index(after: open)
        lines[task.line].replaceSubrange(mark...mark, with: task.done ? " " : "x")
        return lines.joined(separator: "\n")
    }

    /// The text with a new to-do on a line of its own at the end.
    static func adding(_ title: String, to text: String) -> String {
        let line = "- [ ] " + title.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return line }
        // "\r\n" is one character to Swift, so the ending is read from the bytes; a file with
        // Windows line endings gets one too.
        let ending = text.contains("\r\n") ? "\r\n" : "\n"
        return text + (text.utf8.last == 10 ? "" : ending) + line
    }

    /// The to-dos still to do, in the order to do them: those with a time first, by time; then
    /// by priority; then as written.
    static func plan(_ tasks: [NoteTask]) -> [NoteTask] {
        tasks.enumerated().filter { !$0.element.done }.sorted { a, b in
            switch (a.element.due, b.element.due) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            if a.element.priority != b.element.priority { return a.element.priority > b.element.priority }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// The to-dos to be reminded of today: still to do, with a time later than `now` (minutes
    /// after midnight). One whose time has passed isn't brought up again.
    static func dueLater(_ tasks: [NoteTask], after now: Int) -> [NoteTask] {
        tasks.filter { !$0.done && ($0.due ?? -1) > now }
    }

    /// The estimates of the to-dos still to do, added up.
    static func minutesLeft(_ tasks: [NoteTask]) -> Int {
        tasks.filter { !$0.done }.compactMap(\.minutes).reduce(0, +)
    }

    /// "25 min", "2 h", "2 h 10 min".
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// "14:30" as the Mac shows times of day.
    static func clock(_ due: Int, uses24Hour: Bool) -> String {
        let hour = due / 60, minute = due % 60
        if uses24Hour { return String(format: "%d:%02d", hour, minute) }
        let shown = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", shown, minute, hour < 12 ? "AM" : "PM")
    }
}
