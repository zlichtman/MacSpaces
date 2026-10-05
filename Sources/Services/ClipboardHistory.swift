import Foundation

struct ClipboardEntry: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    var date: Date
    var isFavorite: Bool
    var representations: [[String: Data]] = []
    var sourceName: String = ""
    var sourceBundleID: String = ""
    var tags: [String] = []
    var byteCount: Int { text.utf8.count + representations.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } } }

    init(id: UUID = UUID(), text: String, date: Date = Date(), isFavorite: Bool = false) {
        self.id = id
        self.text = text
        self.date = date
        self.isFavorite = isFavorite
    }

    /// The same clip under a new identity, so it can sit in the paste queue twice.
    init(copying entry: ClipboardEntry) {
        self.init(text: entry.text)
        representations = entry.representations
        sourceName = entry.sourceName
        sourceBundleID = entry.sourceBundleID
    }

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed
    }
}

/// Bounded clipboard values. Disk persistence is an explicit choice owned by ClipboardMonitor.
struct ClipboardHistory {
    private(set) var entries: [ClipboardEntry] = []
    let historyLimit: Int
    let favoriteLimit: Int
    let maximumTextBytes = 256 * 1024

    init(historyLimit: Int = 50, favoriteLimit: Int = 50) {
        self.historyLimit = max(1, historyLimit)
        self.favoriteLimit = max(1, favoriteLimit)
    }

    mutating func record(_ text: String, at date: Date = Date()) {
        record(ClipboardEntry(text: text, date: date))
    }

    mutating func record(_ value: ClipboardEntry) {
        guard value.byteCount <= 8 * 1024 * 1024,
              value.text.utf8.count <= maximumTextBytes,
              !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !value.representations.isEmpty else { return }
        if let index = entries.firstIndex(where: { $0.text == value.text && $0.representations == value.representations }) {
            var entry = entries.remove(at: index); entry.date = value.date
            entries.insert(entry, at: 0)
        } else {
            guard !value.isFavorite || entries.filter(\.isFavorite).count < favoriteLimit else { return }
            let favoriteBytes = entries.filter(\.isFavorite).reduce(0) { $0 + $1.byteCount }
            guard favoriteBytes + value.byteCount <= 32 * 1024 * 1024 else { return }
            entries.insert(value, at: 0)
        }
        trim()
    }

    mutating func restore(_ values: [ClipboardEntry]) {
        entries = []
        for value in values.reversed() { record(value) }
    }

    @discardableResult
    mutating func toggleFavorite(_ id: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        if !entries[index].isFavorite && entries.filter(\.isFavorite).count >= favoriteLimit { return false }
        entries[index].isFavorite.toggle()
        trim()
        return true
    }

    mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id } }
    mutating func clear(keepingFavorites: Bool = false) {
        if keepingFavorites { entries.removeAll { !$0.isFavorite } }
        else { entries.removeAll() }
    }

    func matching(_ query: String, favoritesOnly: Bool = false) -> [ClipboardEntry] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter {
            (!favoritesOnly || $0.isFavorite) && (search.isEmpty || ($0.text + " " + $0.sourceName + " " + $0.tags.joined(separator: " ")).localizedStandardContains(search))
        }
    }

    private mutating func trim() {
        var ordinary = 0
        var bytes = entries.filter(\.isFavorite).reduce(0) { $0 + $1.byteCount }
        entries = entries.filter {
            if $0.isFavorite { return true }
            ordinary += 1
            bytes += $0.byteCount
            return ordinary <= historyLimit && bytes <= 32 * 1024 * 1024
        }
    }
}

/// Clips waiting to be pasted one after another: each ⌘V pastes the next.
/// Memory-only, like history; nothing here is ever written to disk.
struct PasteQueue: Equatable {
    enum Order: String, CaseIterable, Identifiable {
        /// The first clip copied is pasted first.
        case inOrder
        /// The most recent clip is pasted first.
        case newestFirst
        var id: String { rawValue }
        var title: String { self == .inOrder ? "In order" : "Newest first" }
    }

    private(set) var items: [ClipboardEntry] = []
    var order: Order = .inOrder
    let limit = 50

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }
    /// The clip the next ⌘V pastes.
    var next: ClipboardEntry? { order == .inOrder ? items.first : items.last }

    mutating func add(_ entry: ClipboardEntry) {
        // Copying the same thing twice in a row is one clip, not two.
        if let last = items.last, last.text == entry.text, last.representations == entry.representations { return }
        items.append(entry)
        if items.count > limit { items.removeFirst(items.count - limit) }
    }

    /// The clip just pasted leaves the queue; returns the one to paste next.
    @discardableResult
    mutating func advance() -> ClipboardEntry? {
        guard !items.isEmpty else { return nil }
        if order == .inOrder { items.removeFirst() } else { items.removeLast() }
        return next
    }

    mutating func remove(_ id: UUID) { items.removeAll { $0.id == id } }
    mutating func clear() { items.removeAll() }
}
