import Foundation

/// Lyrics already found, kept on disk (Caches) so a song plays its lyrics at once
/// the next time, even after relaunching, without asking LRCLIB again. LRCLIB can
/// take seconds per search when it's busy. Timed lyrics stay until evicted;
/// plain lyrics are looked up again after a week (timed ones may have been added)
/// and "none found" after a day. Network failures are never stored, but LRCLIB's
/// definite "no match" is, even when lyrics.ovh (the fallback) couldn't be reached:
/// that "none" is looked up again after `partialRecheck`, so replaying the song shows
/// its no-lyrics layout at once instead of waiting on lyrics.ovh again.
actor LyricsCache {
    static let shared = LyricsCache()

    struct Entry: Codable, Sendable {
        var lines: [LyricLine]
        var timed: Bool
        var saved: Date
        /// A "none" from LRCLIB alone (lyrics.ovh unreachable): looked up again from then.
        /// Unset (every older entry) follows the usual rule.
        var recheck: Date? = nil

        /// Whether to look the song up again.
        func isStale(at now: Date = Date()) -> Bool {
            if timed && !lines.isEmpty { return false }
            if lines.isEmpty, let recheck { return now >= recheck }
            return now.timeIntervalSince(saved) > (lines.isEmpty ? 86_400 : 7 * 86_400)
        }
    }

    private struct Store: Codable {
        var version = 1
        var entries: [String: Entry] = [:]
    }

    static let limit = 500
    static let partialRecheck: TimeInterval = 6 * 3600
    private let url: URL?
    private var entries: [String: Entry]?
    private var saveTask: Task<Void, Never>?

    init(url: URL? = LyricsCache.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.opensource.MacSpaces", isDirectory: true)
            .appendingPathComponent("lyrics.json")
    }

    func entry(for key: String) -> Entry? {
        loadIfNeeded()
        return entries?[key]
    }

    func store(_ entry: Entry, for key: String) {
        loadIfNeeded()
        entries?[key] = entry
        if let count = entries?.count, count > Self.limit {
            // Drop the oldest tenth at once rather than one per insert.
            let oldest = entries!.sorted { $0.value.saved < $1.value.saved }.prefix(count - Self.limit + Self.limit / 10)
            for (key, _) in oldest { entries?[key] = nil }
        }
        scheduleSave()
    }

    private func loadIfNeeded() {
        guard entries == nil else { return }
        guard let url, let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(Store.self, from: data), store.version == 1 else {
            entries = [:]
            return
        }
        entries = store.entries
    }

    /// Several songs' worth of changes are written together, a moment later.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    func save() {
        guard let url, let entries else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Store(entries: entries)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
