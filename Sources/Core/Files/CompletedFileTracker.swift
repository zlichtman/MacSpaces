import Foundation

/// Stable metadata is a completion heuristic for ordinary files. Browser partial
/// names are excluded independently; only items arriving after activation qualify.
struct CompletedFileTracker {
    struct Fingerprint: Equatable, Sendable { let bytes: Int; let modified: Date }
    private var seen: Set<URL>
    private var candidates: [URL: (fingerprint: Fingerprint, since: Date)] = [:]
    init(existing: Set<URL>) { seen = existing }
    mutating func poll(_ files: [URL: Fingerprint], at now: Date) -> [URL] {
        candidates = candidates.filter { files[$0.key] != nil }
        var completed: [URL] = []
        for (url, fingerprint) in files where !seen.contains(url) {
            let name = url.lastPathComponent.lowercased()
            guard !name.hasPrefix("."), !["crdownload", "download", "part", "partial", "tmp"].contains(url.pathExtension.lowercased()), fingerprint.bytes > 0 else { continue }
            if let candidate = candidates[url], candidate.fingerprint == fingerprint, now.timeIntervalSince(candidate.since) >= 6 {
                completed.append(url); seen.insert(url); candidates[url] = nil
            } else if candidates[url]?.fingerprint != fingerprint {
                candidates[url] = (fingerprint, now)
            }
        }
        return completed.sorted { $0.path < $1.path }
    }
}
