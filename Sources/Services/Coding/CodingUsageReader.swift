import Foundation

struct CodingUsageRow: Identifiable, Sendable {
    var provider: String
    var model: String
    var input: Int64 = 0
    var output: Int64 = 0
    var cached: Int64 = 0
    var id: String { provider + ":" + model }
    var total: Int64 { input + output }
}
struct CodingUsageSnapshot: Sendable {
    var rows: [CodingUsageRow] = []
    var daily: [String: Int64] = [:]
    var limited = false
    var files = 0
}

/// Retains numeric usage, model identifiers and day totals only; never prompt text.
struct CodingUsageAccumulator {
    private(set) var rows: [String: CodingUsageRow] = [:]
    private(set) var daily: [String: Int64] = [:]
    private var requests: [String: [Int64]] = [:]
    private var seenEvents: Set<String> = []
    var model = "Unknown model"
    var session = ""
    var previous: [Int64] = [0, 0, 0]
    var cutoff: String

    init(cutoff: String) { self.cutoff = cutoff }

    mutating func beginFile(_ id: String) { model = "Unknown model"; session = id; previous = [0, 0, 0] }
    mutating func consume(_ data: Data, provider: String) {
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let timestamp = event["timestamp"] as? String ?? ""
        let day = String(timestamp.prefix(10))
        let recent = day.count == 10 && day >= cutoff
        func number(_ object: [String: Any], _ key: String) -> Int64 {
            let n = (object[key] as? NSNumber)?.int64Value ?? 0
            return max(0, min(n, 1_000_000_000_000))
        }
        if provider == "Codex" {
            guard let payload = event["payload"] as? [String: Any] else { return }
            if event["type"] as? String == "session_meta", let id = payload["id"] as? String { session = id }
            if event["type"] as? String == "turn_context" { model = payload["model"] as? String ?? model }
            guard payload["type"] as? String == "token_count", let info = payload["info"] as? [String: Any],
                  let usage = info["total_token_usage"] as? [String: Any] else { return }
            let totals = [number(usage, "input_tokens"), number(usage, "output_tokens"), number(usage, "cached_input_tokens")]
            let baseline = totals[0] + totals[1] < previous[0] + previous[1] ? [0, 0, 0] : previous
            let delta = zip(totals, baseline).map { max(0, $0 - $1) }
            previous = totals
            let key = session + ":" + totals.map(String.init).joined(separator: ":")
            guard seenEvents.insert(key).inserted, recent else { return }
            add(provider: provider, model: model, values: delta, day: day)
        } else {
            guard recent, event["type"] as? String == "assistant",
                  let message = event["message"] as? [String: Any], let usage = message["usage"] as? [String: Any],
                  let id = message["id"] as? String, let model = message["model"] as? String,
                  model != "<synthetic>" else { return }
            let cached = number(usage, "cache_read_input_tokens")
            let values = [number(usage, "input_tokens") + cached + number(usage, "cache_creation_input_tokens"), number(usage, "output_tokens"), cached]
            let key = provider + ":" + id
            let old = requests[key] ?? [0, 0, 0]
            let delta = zip(values, old).map { max(0, $0 - $1) }
            requests[key] = zip(values, old).map(max)
            add(provider: provider, model: model, values: delta, day: day)
        }
    }
    private mutating func add(provider: String, model: String, values: [Int64], day: String) {
        guard values[0] + values[1] > 0 else { return }
        let key = provider + ":" + model
        var row = rows[key] ?? CodingUsageRow(provider: provider, model: model)
        row.input += values[0]; row.output += values[1]; row.cached += values[2]
        rows[key] = row
        daily[day, default: 0] += values[0] + values[1]
    }
}

struct CodingUsageReader {
    static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> CodingUsageSnapshot {
        let formatter = ISO8601DateFormatter()
        let cutoff = String(formatter.string(from: Date().addingTimeInterval(-30 * 86400)).prefix(10))
        var accumulator = CodingUsageAccumulator(cutoff: cutoff)
        var snapshot = CodingUsageSnapshot()
        var candidates: [(URL, String, Date)] = []
        for (provider, folder) in [("Codex", ".codex/sessions"), ("Claude", ".claude/projects")] {
            let root = home.appendingPathComponent(folder)
            guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey], options: [.skipsPackageDescendants]) else { continue }
            var visited = 0
            for case let url as URL in iterator {
                try Task.checkCancellation()
                visited += 1
                if visited > 10000 { snapshot.limited = true; break }
                let attributes = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
                if attributes?.isSymbolicLink == true { iterator.skipDescendants(); continue }
                guard url.pathExtension == "jsonl" else { continue }
                let date = attributes?.contentModificationDate ?? .distantPast
                if date >= Date().addingTimeInterval(-31 * 86400) { candidates.append((url, provider, date)) }
            }
        }
        candidates.sort { $0.2 > $1.2 }
        var budget = 64 * 1024 * 1024
        if candidates.count > 400 { snapshot.limited = true }
        for (url, provider, _) in candidates.prefix(400) {
            try Task.checkCancellation()
            guard budget > 0 else { snapshot.limited = true; break }
            guard let file = try? FileHandle(forReadingFrom: url) else { snapshot.limited = true; continue }
            defer { try? file.close() }
            accumulator.beginFile(url.lastPathComponent)
            var buffer = Data()
            var droppingOversizedLine = false
            while budget > 0 {
                try Task.checkCancellation()
                guard let chunk = try file.read(upToCount: min(65536, budget)), !chunk.isEmpty else { break }
                budget -= chunk.count; buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 10) {
                    if !droppingOversizedLine { accumulator.consume(Data(buffer[..<newline]), provider: provider) }
                    buffer.removeSubrange(...newline); droppingOversizedLine = false
                }
                if buffer.count > 4 * 1024 * 1024 { buffer.removeAll(); droppingOversizedLine = true; snapshot.limited = true }
            }
            if budget == 0 { snapshot.limited = true }
            // A partial final JSONL line may still be being written; read it next refresh.
            snapshot.files += 1
        }
        snapshot.rows = accumulator.rows.values.sorted { $0.total > $1.total }
        snapshot.daily = accumulator.daily
        return snapshot
    }
}
