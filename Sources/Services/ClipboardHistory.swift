import Foundation

struct ClipboardEntry: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    /// When it was last copied.
    var date: Date
    /// Pinned clips stay at the top (or bottom) of the list and are kept when history is cleared.
    var isFavorite: Bool
    var representations: [[String: Data]] = []
    var sourceName: String = ""
    var sourceBundleID: String = ""
    var tags: [String] = []
    /// When it was first copied, and how many times it has been.
    var firstDate: Date
    var copyCount = 1
    var byteCount: Int { text.utf8.count + representations.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } } }

    init(id: UUID = UUID(), text: String, date: Date = Date(), isFavorite: Bool = false) {
        self.id = id
        self.text = text
        self.date = date
        self.firstDate = date
        self.isFavorite = isFavorite
    }

    /// The same clip under a new identity, so it can sit in the paste queue twice.
    init(copying entry: ClipboardEntry) {
        self.init(text: entry.text)
        representations = entry.representations
        sourceName = entry.sourceName
        sourceBundleID = entry.sourceBundleID
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, date, isFavorite, representations, sourceName, sourceBundleID, tags, firstDate, copyCount
    }

    /// Saved history from earlier versions lacks the newer fields; they get defaults.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        date = try values.decode(Date.self, forKey: .date)
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        representations = try values.decodeIfPresent([[String: Data]].self, forKey: .representations) ?? []
        sourceName = try values.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        sourceBundleID = try values.decodeIfPresent(String.self, forKey: .sourceBundleID) ?? ""
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        firstDate = try values.decodeIfPresent(Date.self, forKey: .firstDate) ?? date
        copyCount = try values.decodeIfPresent(Int.self, forKey: .copyCount) ?? 1
    }

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed
    }

    var isImage: Bool { representations.contains { $0["public.png"] != nil || $0["public.tiff"] != nil } && text == "Image" }
    var imageData: Data? { representations.lazy.compactMap { $0["public.png"] ?? $0["public.tiff"] }.first }
    var fileURLs: [URL] {
        representations.compactMap { $0["public.file-url"].flatMap { String(data: $0, encoding: .utf8) }.flatMap(URL.init(string:)) }
    }

    /// A hex colour such as #3E6A34 or #fff, for a swatch beside the clip.
    var hexColor: (red: Double, green: Double, blue: Double)? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("#"), [4, 7].contains(value.count),
              value.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        var digits = String(value.dropFirst())
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard let number = UInt32(digits, radix: 16) else { return nil }
        return (Double((number >> 16) & 0xFF) / 255, Double((number >> 8) & 0xFF) / 255, Double(number & 0xFF) / 255)
    }
}

/// How the history list is searched.
enum ClipboardSearchMode: String, CaseIterable, Identifiable {
    /// The words appear as typed (ignoring case).
    case exact
    /// The letters appear in order, with anything between them.
    case fuzzy
    /// A regular expression.
    case regex
    /// Exact first; if nothing matches, a regular expression; then fuzzy.
    case mixed
    var id: String { rawValue }
    var title: String { rawValue == "regex" ? "Regular expression" : rawValue.capitalized }
}

/// The order of the history list.
enum ClipboardSortOrder: String, CaseIterable, Identifiable {
    case lastCopied, firstCopied, mostCopied
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lastCopied: return "Last copied"
        case .firstCopied: return "First copied"
        case .mostCopied: return "Most copied"
        }
    }
}

enum ClipboardSearch {
    /// Whether a clip matches the query in this mode; an empty query matches everything.
    static func matches(_ text: String, query: String, mode: ClipboardSearchMode) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        switch mode {
        case .exact: return text.localizedStandardContains(query)
        case .fuzzy: return fuzzy(text, query)
        case .regex: return regex(text, query) ?? false
        case .mixed: return text.localizedStandardContains(query) || regex(text, query) == true || fuzzy(text, query)
        }
    }

    /// The query's letters, in order, anywhere in the text (ignoring case and spaces).
    static func fuzzy(_ text: String, _ query: String) -> Bool {
        let needle = query.lowercased().filter { !$0.isWhitespace }
        var remaining = needle[...]
        for character in text.lowercased() where remaining.first == character {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    /// nil when the pattern isn't a valid expression.
    static func regex(_ text: String, _ pattern: String) -> Bool? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

/// Bounded clipboard values. Disk persistence is an explicit choice owned by ClipboardMonitor.
struct ClipboardHistory {
    private(set) var entries: [ClipboardEntry] = []
    /// How many clips (not counting pins) are kept; changeable in Settings.
    var historyLimit: Int { didSet { historyLimit = max(1, historyLimit); trim() } }
    let favoriteLimit: Int
    let maximumTextBytes = 256 * 1024

    init(historyLimit: Int = 200, favoriteLimit: Int = 50) {
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
            var entry = entries.remove(at: index)
            entry.date = value.date
            entry.copyCount += 1
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
        // Restoring re-records each clip once; keep the saved counts and dates.
        for value in values {
            if let index = entries.firstIndex(where: { $0.id == value.id }) { entries[index] = value }
        }
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
        matching(query, favoritesOnly: favoritesOnly, mode: .exact, order: .lastCopied, pinsFirst: nil)
    }

    /// The list as shown: filtered by the query, sorted, with pins grouped first or last (nil leaves them in place).
    func matching(_ query: String, favoritesOnly: Bool = false, mode: ClipboardSearchMode,
                  order: ClipboardSortOrder, pinsFirst: Bool?) -> [ClipboardEntry] {
        func filtered(_ mode: ClipboardSearchMode) -> [ClipboardEntry] {
            entries.filter {
                (!favoritesOnly || $0.isFavorite)
                    && ([$0.text, $0.sourceName] + $0.tags).contains { field in ClipboardSearch.matches(field, query: query, mode: mode) }
            }
        }
        // Mixed tries exact, then a regular expression, then fuzzy, using the first that finds anything.
        var found = mode == .mixed
            ? [.exact, .regex, .fuzzy].lazy.map(filtered).first { !$0.isEmpty } ?? []
            : filtered(mode)
        switch order {
        case .lastCopied: found.sort { $0.date > $1.date }
        case .firstCopied: found.sort { $0.firstDate < $1.firstDate }
        case .mostCopied: found.sort { ($0.copyCount, $0.date) > ($1.copyCount, $1.date) }
        }
        if let pinsFirst {
            let pins = found.filter(\.isFavorite), rest = found.filter { !$0.isFavorite }
            found = pinsFirst ? pins + rest : rest + pins
        }
        return found
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
