import Foundation

struct ClipboardEntry: Identifiable, Equatable {
    let id: UUID
    let text: String
    var date: Date
    var isFavorite: Bool

    init(id: UUID = UUID(), text: String, date: Date = Date(), isFavorite: Bool = false) {
        self.id = id
        self.text = text
        self.date = date
        self.isFavorite = isFavorite
    }

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed
    }
}

/// Deliberately memory-only, including favorites. Limits bound both collection
/// size and large copies; favorites survive normal history eviction, not quit.
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
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= maximumTextBytes else { return }
        if let index = entries.firstIndex(where: { $0.text == text }) {
            var entry = entries.remove(at: index)
            entry.date = date
            entries.insert(entry, at: 0)
        } else {
            entries.insert(ClipboardEntry(text: text, date: date), at: 0)
        }
        trim()
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
            (!favoritesOnly || $0.isFavorite) && (search.isEmpty || $0.text.localizedStandardContains(search))
        }
    }

    private mutating func trim() {
        var ordinary = 0
        entries = entries.filter {
            if $0.isFavorite { return true }
            ordinary += 1
            return ordinary <= historyLimit
        }
    }
}
