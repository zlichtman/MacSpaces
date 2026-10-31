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
    /// Text found in an image clip (on this Mac), so images are searchable.
    var recognizedText = ""
    /// A pin's letter in the history popup (⌃A, ⌃B…), kept for as long as it stays pinned.
    var pinKey: String?
    /// Written by hand rather than copied.
    var isSnippet: Bool { sourceName == ClipboardEntry.snippetSource }
    static let snippetSource = "Snippet"
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
        case id, text, date, isFavorite, representations, sourceName, sourceBundleID, tags, firstDate, copyCount, recognizedText, pinKey
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
        recognizedText = try values.decodeIfPresent(String.self, forKey: .recognizedText) ?? ""
        pinKey = try values.decodeIfPresent(String.self, forKey: .pinKey)
    }

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed
    }

    enum Kind: String { case text, link, image, file, color }

    /// What sort of clip this is, for `@image`, `@link` and friends in search.
    var kind: Kind {
        if isImage { return .image }
        if !fileURLs.isEmpty { return .file }
        if hexColor != nil || representations.contains(where: { $0["com.apple.cocoa.pasteboard.color"] != nil }) { return .color }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme), !trimmed.contains(" ") { return .link }
        return .text
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

    /// Pin letters for the popup's ⌃ shortcuts; N, P and U are taken by navigation.
    static let pinLetters = "abcdefghijklmoqrstvwxyz".map(String.init)

    /// Whether another clip can be pinned (pins, snippets and collections share the limit).
    var canPin: Bool { entries.filter(\.isFavorite).count < favoriteLimit }
    var pinLimitMessage: String { "You can keep up to \(favoriteLimit) pins and snippets. Unpin one to add another." }

    mutating func record(_ text: String, at date: Date = Date()) {
        record(ClipboardEntry(text: text, date: date))
    }

    /// Records a copy; one already in history moves to the top instead. Returns
    /// the identity it is kept under (the earlier clip's when merged), or nil if refused.
    @discardableResult
    mutating func record(_ value: ClipboardEntry) -> UUID? {
        guard accepts(value) else { return nil }
        let id: UUID
        if let index = entries.firstIndex(where: { $0.text == value.text && $0.representations == value.representations }) {
            var entry = entries.remove(at: index)
            entry.date = value.date
            entry.copyCount += 1
            entries.insert(entry, at: 0)
            id = entry.id
        } else {
            guard !value.isFavorite || canPin else { return nil }
            let favoriteBytes = entries.filter(\.isFavorite).reduce(0) { $0 + $1.byteCount }
            guard favoriteBytes + value.byteCount <= 32 * 1024 * 1024 else { return nil }
            entries.insert(value, at: 0)
            id = value.id
        }
        trim()
        assignPinKeys()
        return entries.contains { $0.id == id } ? id : nil
    }

    private func accepts(_ value: ClipboardEntry) -> Bool {
        value.byteCount <= 8 * 1024 * 1024 && value.text.utf8.count <= maximumTextBytes
            && (!value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !value.representations.isEmpty)
    }

    /// Clips from another app's history (Maccy), merged by date: the newest clips
    /// overall are kept, so older imports never push out newer clips. A clip
    /// already here keeps its own newer date and gains the import's pin; pins past
    /// the limit come in as ordinary clips. Returns the clips the import landed in.
    @discardableResult
    mutating func merge(_ imported: [ClipboardEntry]) -> Set<UUID> {
        var byText: [String: [Int]] = [:]
        for (position, entry) in entries.enumerated() { byText[entry.text, default: []].append(position) }
        var pins = entries.filter(\.isFavorite).count
        var pinBytes = entries.filter(\.isFavorite).reduce(0) { $0 + $1.byteCount }
        var usedKeys = Set(entries.compactMap { $0.isFavorite ? $0.pinKey : nil })
        var landed: Set<UUID> = []
        func canPin(_ clip: ClipboardEntry) -> Bool {
            pins < favoriteLimit && pinBytes + clip.byteCount <= 32 * 1024 * 1024
        }
        func claim(_ key: String?) -> String? {
            guard let key, usedKeys.insert(key).inserted else { return nil }
            return key
        }
        for var clip in imported where accepts(clip) {
            if let position = byText[clip.text]?.first(where: { entries[$0].representations == clip.representations }) {
                var existing = entries[position]
                existing.date = max(existing.date, clip.date)
                existing.firstDate = min(existing.firstDate, clip.firstDate)
                existing.copyCount = max(existing.copyCount, clip.copyCount)
                if clip.isFavorite, !existing.isFavorite, canPin(existing) {
                    existing.isFavorite = true; pins += 1; pinBytes += existing.byteCount
                    existing.pinKey = claim(clip.pinKey)
                }
                entries[position] = existing
                landed.insert(existing.id)
                continue
            }
            if clip.isFavorite, canPin(clip) {
                pins += 1; pinBytes += clip.byteCount
                clip.pinKey = claim(clip.pinKey)
            } else {
                clip.isFavorite = false; clip.pinKey = nil
            }
            byText[clip.text, default: []].append(entries.count)
            entries.append(clip)
            landed.insert(clip.id)
        }
        // Newest first, as if every clip had been copied here; equal dates keep their order.
        entries = entries.enumerated()
            .sorted { ($0.element.date, -$0.offset) > ($1.element.date, -$1.offset) }
            .map(\.element)
        trim()
        assignPinKeys()
        return landed.filter { id in entries.contains { $0.id == id } }
    }

    /// How many of these clips are in history now, as ordinary clips and as pins.
    func kept(_ ids: Set<UUID>) -> (clips: Int, pins: Int) {
        let kept = entries.filter { ids.contains($0.id) }
        return (kept.filter { !$0.isFavorite }.count, kept.filter(\.isFavorite).count)
    }

    mutating func restore(_ values: [ClipboardEntry]) {
        entries = []
        for value in values.reversed() { record(value) }
        // Restoring re-records each clip once; keep the saved counts and dates.
        for value in values {
            if let index = entries.firstIndex(where: { $0.id == value.id }) { entries[index] = value }
        }
        assignPinKeys()
    }

    @discardableResult
    mutating func toggleFavorite(_ id: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        if !entries[index].isFavorite && !canPin { return false }
        entries[index].isFavorite.toggle()
        trim()
        assignPinKeys()
        return true
    }

    mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id }; assignPinKeys() }

    mutating func update(_ id: UUID, _ change: (inout ClipboardEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
        assignPinKeys()
    }

    /// Files a clip in a collection, which keeps it like a pin; nil takes it out.
    /// Refused (false) when filing would pin a clip past the pin limit.
    @discardableResult
    mutating func setCollection(_ id: UUID, to name: String?) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        if name != nil, !entries[index].isFavorite, !canPin { return false }
        entries[index].tags = name.map { [$0] } ?? []
        if name != nil { entries[index].isFavorite = true }
        assignPinKeys()
        return true
    }

    /// Each pin keeps the letter it was given, however the list is sorted or
    /// recopied; new pins take the first free letter, the earliest-copied first.
    private mutating func assignPinKeys() {
        var used = Set<String>()
        for index in entries.indices {
            if entries[index].isFavorite, let key = entries[index].pinKey, Self.pinLetters.contains(key), used.insert(key).inserted { continue }
            if entries[index].pinKey != nil { entries[index].pinKey = nil }
        }
        var free = Self.pinLetters.filter { !used.contains($0) }[...]
        guard !free.isEmpty else { return }
        let waiting = entries.indices.filter { entries[$0].isFavorite && entries[$0].pinKey == nil }
            .sorted { (entries[$0].firstDate, entries[$0].id.uuidString) < (entries[$1].firstDate, entries[$1].id.uuidString) }
        for index in waiting {
            guard let key = free.popFirst() else { break }
            entries[index].pinKey = key
        }
    }

    /// A clip written by hand; kept like a pin.
    @discardableResult
    mutating func addSnippet(_ text: String, collection: String? = nil) -> ClipboardEntry? {
        var snippet = ClipboardEntry(text: text, isFavorite: true)
        snippet.sourceName = ClipboardEntry.snippetSource
        if let collection, !collection.isEmpty { snippet.tags = [collection] }
        guard canPin, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        entries.insert(snippet, at: 0)
        assignPinKeys()
        return entries.first
    }

    /// Clips not copied for `days` days go; pins and snippets stay.
    mutating func removeUnused(olderThan days: Int, now: Date = Date()) {
        guard days > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        entries.removeAll { !$0.isFavorite && $0.date < cutoff }
    }

    /// Every collection name in use, for menus.
    var collections: [String] { Array(Set(entries.flatMap(\.tags))).sorted() }
    mutating func clear(keepingFavorites: Bool = false) {
        if keepingFavorites { entries.removeAll { !$0.isFavorite } }
        else { entries.removeAll() }
    }

    func matching(_ query: String, favoritesOnly: Bool = false) -> [ClipboardEntry] {
        matching(query, favoritesOnly: favoritesOnly, mode: .exact, order: .lastCopied, pinsFirst: nil)
    }

    /// The list as shown: filtered by the query, sorted, with pins grouped first or last (nil leaves them in place).
    /// `@image`, `@link`, `@file`, `@color`, `@text`, `@pinned` and `@snippet` filter by kind,
    /// any other `@word` by the app a clip came from, and `#word` by collection.
    func matching(_ rawQuery: String, favoritesOnly: Bool = false, mode: ClipboardSearchMode,
                  order: ClipboardSortOrder, pinsFirst: Bool?) -> [ClipboardEntry] {
        let (query, filters) = ClipboardQuery.parse(rawQuery)
        let entries = self.entries.filter { filters.allSatisfy($0.passes) }
        func filtered(_ mode: ClipboardSearchMode) -> [ClipboardEntry] {
            entries.filter {
                (!favoritesOnly || $0.isFavorite)
                    && ([$0.text, $0.sourceName, $0.recognizedText] + $0.tags).contains { field in ClipboardSearch.matches(field, query: query, mode: mode) }
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

extension ClipboardHistory {
    /// What outlives quitting MacSpaces, in words, from the settings that decide it:
    /// Keep history after quitting, Clear history when MacSpaces quits, and Keep pins and snippets.
    static func retentionNote(savesHistory: Bool, clearsOnQuit: Bool, keepsPins: Bool) -> String {
        if savesHistory && !clearsOnQuit { return "History, pins and snippets are saved on this Mac, encrypted, and kept after MacSpaces quits." }
        let history = savesHistory ? "History is saved on this Mac, encrypted, and cleared when MacSpaces quits"
            : "History stays in memory and clears when MacSpaces quits"
        // Saved history keeps its pins even when cleared on quit.
        return history + (keepsPins || savesHistory ? "; pins and snippets are kept, encrypted." : ", along with pins and snippets.")
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

/// Search words that filter instead of matching text.
enum ClipboardQuery {
    enum Filter: Equatable {
        case kind(ClipboardEntry.Kind), pinned, snippet, app(String), collection(String)
    }

    static func parse(_ query: String) -> (text: String, filters: [Filter]) {
        var words: [String] = [], filters: [Filter] = []
        for word in query.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
            let lower = word.lowercased()
            if lower.hasPrefix("@"), lower.count > 1 {
                let name = String(lower.dropFirst())
                switch name {
                case "image", "images", "img": filters.append(.kind(.image))
                case "link", "links", "url", "urls": filters.append(.kind(.link))
                case "file", "files": filters.append(.kind(.file))
                case "color", "colour", "colors", "colours": filters.append(.kind(.color))
                case "text": filters.append(.kind(.text))
                case "pin", "pins", "pinned": filters.append(.pinned)
                case "snippet", "snippets": filters.append(.snippet)
                default: filters.append(.app(name))
                }
            } else if lower.hasPrefix("#"), lower.count > 1 {
                filters.append(.collection(String(lower.dropFirst())))
            } else {
                words.append(word)
            }
        }
        return (words.joined(separator: " "), filters)
    }
}

extension ClipboardEntry {
    func passes(_ filter: ClipboardQuery.Filter) -> Bool {
        switch filter {
        case .kind(let kind): return self.kind == kind
        case .pinned: return isFavorite
        case .snippet: return isSnippet
        case .app(let name): return sourceName.lowercased().replacingOccurrences(of: " ", with: "").contains(name)
        case .collection(let name): return tags.contains { $0.lowercased() == name || $0.lowercased().hasPrefix(name) }
        }
    }

    /// The text with its case changed, for "Copy as".
    func text(as style: CaseStyle) -> String {
        switch style {
        case .upper: return text.uppercased()
        case .lower: return text.lowercased()
        case .title: return text.capitalized
        case .plain: return text
        }
    }

    enum CaseStyle: String, CaseIterable, Identifiable {
        case plain, upper, lower, title
        var id: String { rawValue }
        var title: String {
            switch self {
            case .plain: return "Plain Text"
            case .upper: return "UPPERCASE"
            case .lower: return "lowercase"
            case .title: return "Title Case"
            }
        }
    }
}
