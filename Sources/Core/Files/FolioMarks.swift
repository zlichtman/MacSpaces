import Foundation

/// What you added to one file on the Folio page: your own tags, a note and a like. Kept by
/// path beside Folio's index (`folio-marks.json`), never inside the file.
struct FolioMark: Codable, Equatable, Sendable {
    var tags: [String] = []
    var note = ""
    var liked = false
    /// Finds the file again if it moved while MacSpaces wasn't running.
    var bookmark: Data?

    init(tags: [String] = [], note: String = "", liked: Bool = false, bookmark: Data? = nil) {
        self.tags = tags; self.note = note; self.liked = liked; self.bookmark = bookmark
    }

    /// A field missing from an older file reads as empty, so a mark never fails to load.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tags = (try? values.decode([String].self, forKey: .tags)) ?? []
        note = (try? values.decode(String.self, forKey: .note)) ?? ""
        liked = (try? values.decode(Bool.self, forKey: .liked)) ?? false
        bookmark = try? values.decode(Data.self, forKey: .bookmark)
    }

    /// Nothing of yours on it: the mark can go.
    var isEmpty: Bool { tags.isEmpty && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !liked }
}

/// Your tags as you typed them: trimmed, inner spaces collapsed, and one spelling of each
/// (the first) whatever its case.
enum FolioTags {
    static func clean(_ tags: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for tag in tags {
            let value = tag.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !value.isEmpty, seen.insert(value.lowercased()).inserted { out.append(value) }
        }
        return out
    }

    /// Typed input split on commas and line breaks; spaces stay inside a tag ("road trip").
    static func parse(_ text: String) -> [String] {
        clean(text.components(separatedBy: CharacterSet(charactersIn: ",\n")))
    }

    static func contains(_ tags: [String], _ tag: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    /// The automatic tags not already among yours, so a tag shows once (yours first).
    static func automatic(_ automatic: [String], without own: [String]) -> [String] {
        clean(automatic).filter { !contains(own, $0) }
    }
}

/// Every mark, by standardised path. Pure, so the check scripts run it as it is.
struct FolioMarkBook: Equatable, Sendable {
    private(set) var marks: [String: FolioMark] = [:]

    init(_ marks: [String: FolioMark] = [:]) { self.marks = marks.filter { !$0.value.isEmpty } }

    func mark(_ path: String) -> FolioMark? { marks[path] }
    func isLiked(_ path: String) -> Bool { marks[path]?.liked == true }
    var likedCount: Int { marks.values.filter(\.liked).count }

    /// Changes one file's mark; an emptied mark goes.
    mutating func update(_ path: String, _ change: (inout FolioMark) -> Void) {
        var mark = marks[path] ?? FolioMark()
        change(&mark)
        marks[path] = mark.isEmpty ? nil : mark
    }

    mutating func addTags(_ tags: [String], to paths: [String]) {
        let new = FolioTags.clean(tags)
        guard !new.isEmpty else { return }
        for path in paths { update(path) { $0.tags = FolioTags.clean($0.tags + new) } }
    }

    mutating func removeTag(_ tag: String, from paths: [String]) {
        for path in paths { update(path) { $0.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame } } }
    }

    mutating func setNote(_ note: String, for paths: [String]) {
        for path in paths { update(path) { $0.note = note } }
    }

    /// Likes them all, or unlikes them when every one is liked already. Returns the new state.
    @discardableResult
    mutating func toggleLike(_ paths: [String]) -> Bool {
        let like = !paths.allSatisfy(isLiked)
        for path in paths { update(path) { $0.liked = like } }
        return like
    }

    /// A file moved or was renamed: its mark goes with it (joining any mark already there).
    mutating func moved(from old: String, to new: String) {
        guard old != new, let mark = marks.removeValue(forKey: old) else { return }
        guard var existing = marks[new] else { marks[new] = mark; return }
        existing.tags = FolioTags.clean(existing.tags + mark.tags)
        if existing.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { existing.note = mark.note }
        existing.liked = existing.liked || mark.liked
        marks[new] = existing
    }

    mutating func forget(_ path: String) { marks[path] = nil }

    mutating func setBookmark(_ bookmark: Data, for path: String) {
        guard marks[path] != nil, marks[path]?.bookmark == nil else { return }
        marks[path]?.bookmark = bookmark
    }

    /// The words search reads from a mark: your tags, then the note.
    func searchText(_ path: String) -> String {
        guard let mark = marks[path] else { return "" }
        return (mark.tags + [mark.note]).joined(separator: " ")
    }
}

/// How Folio's search reads words: lowercase, no accents, every run of non-letters one space.
enum FolioText {
    /// The folded text, with a space first so " word" finds a word's start.
    static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        var out = " "
        out.reserveCapacity(plain.count + 1)
        var space = true
        for character in plain {
            if character.isLetter || character.isNumber { out.append(character); space = false }
            else if !space { out.append(" "); space = true }
        }
        return out
    }

    /// A query split into folded words.
    static func terms(_ query: String) -> [String] {
        fold(query).split(separator: " ").map(String.init)
    }

    /// True when every term starts a word in the folded text.
    static func matches(_ terms: [String], in folded: String) -> Bool {
        terms.allSatisfy { folded.contains(" " + $0) }
    }
}
