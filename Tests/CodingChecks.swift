import Foundation

/// Coding statistics from synthetic Codex and Claude log entries (no real session logs).
@main enum CodingChecks {
    @MainActor static func main() {
        let now = Date()
        let url = URL(fileURLWithPath: "/tmp/synthetic-codex.jsonl")
        func tokenCount(total: Int, last: Int, limits: Bool = false) -> [String: Any] {
            var payload: [String: Any] = ["type": "token_count",
                                          "info": ["total_token_usage": ["input_tokens": total, "output_tokens": 0, "total_tokens": total],
                                                   "last_token_usage": ["input_tokens": last, "output_tokens": 0, "cached_input_tokens": 0]]]
            if limits { payload["rate_limits"] = ["primary": ["used_percent": 42.0, "window_minutes": 300]] }
            return ["payload": payload]
        }

        // A repeated snapshot (same cumulative total) counts once; newer limits still apply (audit 2.75 #9).
        var state = CodingStats.FileState()
        CodingStats.parseCodex(tokenCount(total: 120, last: 120), date: now, url: url, into: &state)
        CodingStats.parseCodex(tokenCount(total: 120, last: 120, limits: true), date: now.addingTimeInterval(1), url: url, into: &state)
        var summary = CodingStats.summarize([url: state], now: now)
        precondition(summary.today["codex"]?.total == 120, "Repeated token_count counted twice: \(summary.today["codex"]?.total ?? 0)")
        precondition(summary.codexLimits.first?.usedPercent == 42, "Limits update from a repeat")
        CodingStats.parseCodex(tokenCount(total: 200, last: 80), date: now.addingTimeInterval(2), url: url, into: &state)
        CodingStats.parseCodex(tokenCount(total: 30, last: 30), date: now.addingTimeInterval(3), url: url, into: &state)
        summary = CodingStats.summarize([url: state], now: now.addingTimeInterval(4))
        precondition(summary.today["codex"]?.total == 230, "New turns and a restarted session count: \(summary.today["codex"]?.total ?? 0)")

        // Only entries from the last 14 days, whatever the file's date (#10).
        let old = CodingStats.Entry(date: now.addingTimeInterval(-100 * 86_400), agent: "claude", model: "fixture-old",
                                    project: "old-project", tokens: .init(input: 999))
        let recent = CodingStats.Entry(date: now.addingTimeInterval(-86_400), agent: "claude", model: "fixture-new",
                                       project: "new-project", tokens: .init(input: 5))
        var mixed = CodingStats.FileState()
        mixed.entries = [old, recent]
        summary = CodingStats.summarize([url: mixed], now: now)
        precondition(summary.models["fixture-old"] == nil && summary.projects["old-project"] == nil, "A 100-day-old entry is outside the rankings")
        precondition(summary.days.keys.allSatisfy { $0 >= Calendar.current.startOfDay(for: now.addingTimeInterval(-CodingStats.window)) })
        precondition(summary.models["fixture-new"] == 5 && summary.projects["new-project"] == 5)
        print("Coding checks passed: repeated Codex snapshots counted once, restarts, limits and the 14-day entry window. Synthetic entries only.")
    }
}
