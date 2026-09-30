import Foundation
@main enum CodingUsageChecks {
    static func main() throws {
        var a = CodingUsageAccumulator(cutoff: "2026-09-01")
        func data(_ value: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: value) }
        func codex(_ input: Int, _ output: Int, _ cached: Int) -> Data {
            data(["timestamp": "2026-09-28T10:00:00Z", "type": "event_msg", "payload": ["type": "token_count", "info": ["total_token_usage": ["input_tokens": input, "output_tokens": output, "cached_input_tokens": cached]]]])
        }
        a.beginFile("session")
        a.consume(data(["type": "turn_context", "payload": ["model": "model-one"]]), provider: "Codex")
        a.consume(codex(100, 20, 40), provider: "Codex")
        a.consume(codex(100, 20, 40), provider: "Codex")
        precondition(a.rows["Codex:model-one"]?.total == 120, "Cumulative snapshots must not be summed")
        a.consume(data(["type": "turn_context", "payload": ["model": "model-two"]]), provider: "Codex")
        a.consume(codex(160, 30, 60), provider: "Codex")
        precondition(a.rows["Codex:model-two"]?.total == 70, "Attribute only the new model's delta")
        a.beginFile("session")
        a.consume(codex(100, 20, 40), provider: "Codex")
        precondition(a.rows.values.reduce(0) { $0 + $1.total } == 190, "Copied sessions must not duplicate usage")
        func claude(_ output: Int, timestamp: String = "2026-09-28T10:00:00Z") -> Data {
            data(["timestamp": timestamp, "type": "assistant", "message": ["id": "request", "model": "claude-fixture", "usage": ["input_tokens": 10, "cache_read_input_tokens": 50, "cache_creation_input_tokens": 20, "output_tokens": output]]])
        }
        a.consume(claude(5), provider: "Claude"); a.consume(claude(5), provider: "Claude")
        a.consume(claude(15), provider: "Claude")
        precondition(a.rows["Claude:claude-fixture"]?.total == 95, "Stream fragments must deduplicate by request")
        precondition(a.rows["Claude:claude-fixture"]?.cached == 50)
        a.consume(claude(100, timestamp: "2026-08-01T10:00:00Z"), provider: "Claude")
        a.consume(Data("malformed".utf8), provider: "Codex")
        precondition(a.daily["2026-09-28"] == 285)
        print("Coding usage checks passed: cumulative deltas, model changes, copied sessions, streamed responses, cache accounting, date cutoff, malformed data")
    }
}
