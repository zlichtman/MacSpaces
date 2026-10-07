import Combine
import Foundation

/// Coding activity for the Terminal page, read only from this Mac:
/// Claude Code's and Codex's own session logs (token use by day, model and
/// project, plus Codex's plan limits) and, optionally, your public GitHub
/// contribution calendar. Logs are read incrementally (only new lines) and
/// only while the page shows.
@MainActor
final class CodingStats: ObservableObject {
    static let shared = CodingStats()

    struct Tokens: Equatable {
        var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
        var total: Int { input + output + cacheRead + cacheWrite }
        static func + (a: Tokens, b: Tokens) -> Tokens {
            Tokens(input: a.input + b.input, output: a.output + b.output,
                   cacheRead: a.cacheRead + b.cacheRead, cacheWrite: a.cacheWrite + b.cacheWrite)
        }
    }

    struct Limit: Equatable {
        let name: String
        let usedPercent: Double
        let resetsAt: Date?
    }

    struct Summary: Equatable {
        var today: [String: Tokens] = [:]                 // agent → tokens today
        var days: [Date: Tokens] = [:]                    // day → all agents
        var models: [String: Int] = [:]                   // model → tokens (14 days)
        var projects: [String: Int] = [:]                 // project → tokens (14 days)
        var claudeWindow = Tokens()                       // Claude Code, last 5 hours
        var codexLimits: [Limit] = []
    }

    @Published private(set) var summary = Summary()
    @Published private(set) var contributions: ContributionCalendar?
    @Published var githubUser: String {
        didSet { UserDefaults.standard.set(githubUser, forKey: "coding.githubUser"); contributionsFetched = .distantPast; refreshContributions() }
    }

    private var timer: Timer?
    private var scanning = false
    private var contributionsFetched = Date.distantPast
    /// Per log file: how far it has been read, and what it contributed.
    private var files: [URL: FileState] = [:]

    struct FileState {
        var offset: UInt64 = 0
        var entries: [Entry] = []
        var seen = Set<String>()
        var codexLimits: [Limit] = []
        var codexLimitsDate = Date.distantPast
        /// Codex's cumulative session total at the last counted token_count: a
        /// repeat of the same total (e.g. only newer rate limits) isn't counted again.
        var codexTotal: Int?
    }

    /// The rankings and day history cover this many days of entries.
    nonisolated static let window: TimeInterval = 14 * 86_400

    struct Entry {
        let date: Date
        let agent: String
        let model: String
        let project: String
        let tokens: Tokens
    }

    init() {
        githubUser = UserDefaults.standard.string(forKey: "coding.githubUser") ?? Self.ghUser() ?? ""
    }

#if DEBUG
    /// QA captures: synthetic numbers, never the user's logs or GitHub.
    func preview() {
        previewing = true
        var summary = Summary()
        summary.today = ["claude": Tokens(input: 41_000, output: 186_000, cacheRead: 9_800_000, cacheWrite: 640_000),
                         "codex": Tokens(input: 52_000, output: 18_000, cacheRead: 210_000)]
        summary.claudeWindow = Tokens(input: 22_000, output: 94_000, cacheRead: 5_200_000, cacheWrite: 310_000)
        let today = Calendar.current.startOfDay(for: Date())
        for offset in 0..<14 {
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            summary.days[day] = Tokens(output: 60_000 + (offset * 37_000) % 160_000, cacheRead: 2_000_000 + (offset * 910_000) % 9_000_000)
        }
        summary.models = ["claude-opus-5-5": 98_000_000, "claude-sonnet-5-5": 21_000_000, "codex": 4_400_000]
        summary.projects = ["MacSpaces": 61_000_000, "PORTFOLIO": 23_000_000, "Tsukumo": 12_000_000, "Lighthouse": 7_500_000, "Garden": 3_100_000]
        summary.codexLimits = [Limit(name: "5-hour", usedPercent: 38, resetsAt: Date().addingTimeInterval(7_400)),
                               Limit(name: "Weekly", usedPercent: 12, resetsAt: Date().addingTimeInterval(4 * 86_400))]
        self.summary = summary
        var days: [(String, Int)] = []
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        for offset in (0..<364).reversed() {
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            days.append((formatter.string(from: day), offset > 230 ? 0 : (offset * 7 + offset / 3) % 5))
        }
        var counts: [String: Int] = [:]
        for (index, day) in days.enumerated() where day.1 > 0 { counts[day.0] = day.1 * 4 + index % 7 }
        contributions = ContributionCalendar(total: 1_860, days: days, counts: counts)
        githubUser = "octocat"
    }
    private var previewing = false
#else
    private let previewing = false
#endif

    func start() {
        guard timer == nil, !previewing else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        refreshContributions()
        guard !scanning else { return }
        scanning = true
        let previous = files
        Task.detached(priority: .utility) {
            let (states, summary) = Self.scan(previous)
            await MainActor.run {
                self.files = states
                self.summary = summary
                self.scanning = false
            }
        }
    }

    // MARK: Logs

    nonisolated static func scan(_ previous: [URL: FileState]) -> ([URL: FileState], Summary) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cutoff = Date().addingTimeInterval(-window)
        var states: [URL: FileState] = [:]
        for (agent, root) in [("claude", home.appendingPathComponent(".claude/projects")),
                              ("codex", home.appendingPathComponent(".codex/sessions"))] {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                guard let modified = values?.contentModificationDate, modified >= cutoff else { continue }
                var state = previous[url] ?? FileState()
                let size = UInt64(values?.fileSize ?? 0)
                if size < state.offset { state = FileState() }   // rewritten: start over
                if size > state.offset { read(url, agent: agent, into: &state) }
                // Entries leave as the window moves on, even in a file still being written.
                state.entries.removeAll { $0.date < cutoff }
                states[url] = state
            }
        }
        return (states, summarize(states))
    }

    nonisolated static func read(_ url: URL, agent: String, into state: inout FileState) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: state.offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        // Only complete lines; a half-written last line is read next time.
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return }
        let complete = data[data.startIndex...lastNewline]
        state.offset += UInt64(complete.count)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainISO = ISO8601DateFormatter()
        for line in complete.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            let stamp = object["timestamp"] as? String ?? ""
            let date = iso.date(from: stamp) ?? plainISO.date(from: stamp) ?? Date()
            if agent == "claude" { parseClaude(object, date: date, into: &state) } else { parseCodex(object, date: date, url: url, into: &state) }
        }
    }

    /// A Claude Code assistant message with usage. The same message can be
    /// logged more than once, so each message/request pair counts once.
    nonisolated static func parseClaude(_ object: [String: Any], date: Date, into state: inout FileState) {
        guard object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return }
        let key = "\(message["id"] as? String ?? "")|\(object["requestId"] as? String ?? "")"
        guard state.seen.insert(key).inserted else { return }
        let tokens = Tokens(input: usage["input_tokens"] as? Int ?? 0, output: usage["output_tokens"] as? Int ?? 0,
                            cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                            cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0)
        let project = ((object["cwd"] as? String ?? "") as NSString).lastPathComponent
        state.entries.append(Entry(date: date, agent: "claude", model: message["model"] as? String ?? "claude",
                                   project: project, tokens: tokens))
    }

    /// Codex logs a token count after each turn; `last_token_usage` is that turn's share.
    nonisolated static func parseCodex(_ object: [String: Any], date: Date, url: URL, into state: inout FileState) {
        guard let payload = object["payload"] as? [String: Any] else { return }
        if payload["type"] as? String == "token_count" {
            if let info = payload["info"] as? [String: Any], let last = info["last_token_usage"] as? [String: Any],
               countsNewUsage(info, into: &state) {
                let cached = last["cached_input_tokens"] as? Int ?? 0
                let tokens = Tokens(input: max(0, (last["input_tokens"] as? Int ?? 0) - cached),
                                    output: last["output_tokens"] as? Int ?? 0, cacheRead: cached,
                                    cacheWrite: last["cache_write_input_tokens"] as? Int ?? 0)
                state.entries.append(Entry(date: date, agent: "codex", model: "codex", project: "", tokens: tokens))
            }
            if let limits = payload["rate_limits"] as? [String: Any], date >= state.codexLimitsDate {
                state.codexLimits = ["primary", "secondary"].compactMap { key in
                    guard let window = limits[key] as? [String: Any], let used = window["used_percent"] as? Double else { return nil }
                    let minutes = window["window_minutes"] as? Int ?? 0
                    let name = minutes >= 1440 * 6 ? "Weekly" : minutes >= 60 ? "\(minutes / 60)-hour" : "\(minutes)-minute"
                    let reset = (window["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:))
                    return Limit(name: name, usedPercent: used, resetsAt: reset)
                }
                state.codexLimitsDate = date
            }
        } else if payload["type"] as? String == "turn_context" || payload["cwd"] != nil {
            // Session metadata carries the project folder for later entries.
        }
    }

    /// Whether a token_count reports new usage: its cumulative total moved on from the
    /// last one counted. A lower total means the session restarted; it counts afresh.
    nonisolated static func countsNewUsage(_ info: [String: Any], into state: inout FileState) -> Bool {
        guard let total = info["total_token_usage"] as? [String: Any] else { return true }
        let value = total["total_tokens"] as? Int ?? ((total["input_tokens"] as? Int ?? 0) + (total["output_tokens"] as? Int ?? 0))
        defer { state.codexTotal = value }
        guard let previous = state.codexTotal else { return true }
        return value != previous
    }

    nonisolated static func summarize(_ states: [URL: FileState], now: Date = Date()) -> Summary {
        var summary = Summary()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let window = now.addingTimeInterval(-5 * 3600)
        let cutoff = now.addingTimeInterval(-Self.window)
        var newestLimits: (Date, [Limit]) = (.distantPast, [])
        for state in states.values {
            if state.codexLimitsDate > newestLimits.0, !state.codexLimits.isEmpty { newestLimits = (state.codexLimitsDate, state.codexLimits) }
            for entry in state.entries where entry.date >= cutoff {
                let day = calendar.startOfDay(for: entry.date)
                summary.days[day, default: Tokens()] = summary.days[day, default: Tokens()] + entry.tokens
                if day == today { summary.today[entry.agent, default: Tokens()] = summary.today[entry.agent, default: Tokens()] + entry.tokens }
                summary.models[entry.model, default: 0] += entry.tokens.total
                if !entry.project.isEmpty { summary.projects[entry.project, default: 0] += entry.tokens.total }
                if entry.agent == "claude", entry.date >= window { summary.claudeWindow = summary.claudeWindow + entry.tokens }
            }
        }
        summary.codexLimits = newestLimits.1
        return summary
    }

    // MARK: GitHub

    struct ContributionCalendar: Equatable {
        let total: Int
        /// (date, level 0–4) for each day, oldest first.
        let days: [(String, Int)]
        /// Contributions per day (yyyy-MM-dd), from the calendar's tooltips.
        var counts: [String: Int] = [:]
        static func == (a: Self, b: Self) -> Bool {
            a.total == b.total && a.days.map(\.0) == b.days.map(\.0) && a.days.map(\.1) == b.days.map(\.1) && a.counts == b.counts
        }

        struct Stats: Equatable {
            var currentStreak = 0, longestStreak = 0, thisWeek = 0, thisMonth = 0, activeDays = 0
            var bestDay: String?
            var bestDayCount = 0
            var busiestWeekday: String?
            /// The last twelve months, oldest first: (short month name, contributions).
            var months: [String] = []
            var monthTotals: [Int] = []
        }

        /// Streaks, this week and month, the best day and weekday, and monthly totals.
        func stats(today: Date = Date(), calendar: Calendar = .current) -> Stats {
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
            func count(_ day: (String, Int)) -> Int { counts[day.0] ?? (day.1 > 0 ? day.1 : 0) }
            var stats = Stats()
            var run = 0
            for day in days {
                if count(day) > 0 { run += 1; stats.activeDays += 1; stats.longestStreak = max(stats.longestStreak, run) } else { run = 0 }
            }
            // The current streak counts back from today (or yesterday, if today is still empty).
            let todayKey = formatter.string(from: today)
            var recent = days.filter { $0.0 <= todayKey }
            if let last = recent.last, last.0 == todayKey, count(last) == 0 { recent.removeLast() }
            for day in recent.reversed() { if count(day) > 0 { stats.currentStreak += 1 } else { break } }
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
            var weekdays = [Int](repeating: 0, count: 7)
            var monthTotals: [String: Int] = [:]
            for day in days {
                guard let date = formatter.date(from: day.0), !counts.isEmpty || day.1 > 0 else { continue }
                let value = count(day)
                if date >= weekStart && date <= today { stats.thisWeek += value }
                if date >= monthStart && date <= today { stats.thisMonth += value }
                weekdays[calendar.component(.weekday, from: date) - 1] += value
                monthTotals[String(day.0.prefix(7)), default: 0] += value
                if value > stats.bestDayCount { stats.bestDayCount = value; stats.bestDay = day.0 }
            }
            if let best = weekdays.indices.max(by: { weekdays[$0] < weekdays[$1] }), weekdays[best] > 0 {
                stats.busiestWeekday = calendar.weekdaySymbols[best]
            }
            for offset in (0..<12).reversed() {
                guard let month = calendar.date(byAdding: .month, value: -offset, to: today) else { continue }
                let key = String(formatter.string(from: month).prefix(7))
                stats.months.append(calendar.shortMonthSymbols[calendar.component(.month, from: month) - 1])
                stats.monthTotals.append(monthTotals[key] ?? 0)
            }
            return stats
        }
    }

    /// Reads the public calendar (the same as on your profile; no token) at most hourly.
    func refreshContributions() {
        guard !previewing else { return }
        let user = githubUser.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, Date().timeIntervalSince(contributionsFetched) > 3600 else { return }
        contributionsFetched = Date()
        Task.detached(priority: .utility) {
            guard let url = URL(string: "https://github.com/users/\(user)/contributions") else { return }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("MacSpaces", forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
            let calendar = Self.parseContributions(String(decoding: data, as: UTF8.self))
            await MainActor.run { self.contributions = calendar }
        }
    }

    nonisolated static func parseContributions(_ html: String) -> ContributionCalendar? {
        var days: [(String, Int)] = []
        let pattern = try? NSRegularExpression(pattern: #"data-date="(\d{4}-\d{2}-\d{2})"[^>]*data-level="(\d)""#)
        for match in pattern?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? [] {
            guard let date = Range(match.range(at: 1), in: html), let level = Range(match.range(at: 2), in: html) else { continue }
            days.append((String(html[date]), Int(html[level]) ?? 0))
        }
        guard days.count > 100 else { return nil }
        days.sort { $0.0 < $1.0 }
        // Each day's count is in a tooltip tied to its cell's id.
        var dateForID: [String: String] = [:]
        let cell = try? NSRegularExpression(pattern: #"data-date="(\d{4}-\d{2}-\d{2})"[^>]*?id="([^"]+)""#)
        for match in cell?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? [] {
            guard let date = Range(match.range(at: 1), in: html), let id = Range(match.range(at: 2), in: html) else { continue }
            dateForID[String(html[id])] = String(html[date])
        }
        var counts: [String: Int] = [:]
        let tip = try? NSRegularExpression(pattern: #"<tool-tip[^>]*?for="([^"]+)"[^>]*>([\d,]+) contributions?"#)
        for match in tip?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? [] {
            guard let id = Range(match.range(at: 1), in: html), let number = Range(match.range(at: 2), in: html),
                  let date = dateForID[String(html[id])] else { continue }
            counts[date] = Int(html[number].replacingOccurrences(of: ",", with: ""))
        }
        let flat = html.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let total = flat.range(of: #"([\d,]+) contributions? in the last year"#, options: .regularExpression)
            .map { String(flat[$0]).components(separatedBy: " ").first?.replacingOccurrences(of: ",", with: "") ?? "0" }
            .flatMap(Int.init) ?? 0
        return ContributionCalendar(total: total, days: days, counts: counts)
    }

    /// The GitHub CLI's signed-in user, if `gh` is set up.
    nonisolated static func ghUser() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/gh/hosts.yml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("user:") {
                let name = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
        }
        return nil
    }

    static func format(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000_000...: return String(format: "%.1fB", Double(tokens) / 1e9)
        case 1_000_000...: return String(format: "%.1fM", Double(tokens) / 1e6)
        case 1_000...: return String(format: "%.0fK", Double(tokens) / 1e3)
        default: return "\(tokens)"
        }
    }
}
