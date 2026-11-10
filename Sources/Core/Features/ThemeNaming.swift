import Foundation

/// A theme's name split for the list: its family ("Everforest") and how strong it is (Soft,
/// Medium or Hard, drawn as bars). "Everforest Dark Hard", "Everforest Light (Medium)" and
/// "Everforest Light Soft Lost" all read as Everforest; the moon or sun comes from the colours,
/// and the full name stays for search and hover. Only a word after the first is ever taken, so
/// "Dark Modern" and "Hard Reset" keep their names.
struct ThemeDisplayName: Hashable, Sendable {
    let family: String
    /// 1 Soft, 2 Medium, 3 Hard; nil when the name gives no level.
    let level: Int?

    private static let tones: Set<String> = ["dark", "light"]
    private static let levels = ["soft": 1, "med": 2, "medium": 2, "hard": 3]
    /// Gogh's own mark for its copies, which the pack's tag already says, and the word that
    /// makes iTerm2's plain themes too long to fit ("iTerm2 Dark Background").
    private static let marks: Set<String> = ["lost", "background"]

    /// Lowercase by design, left as they are.
    private static let keptWords: Set<String> = ["iTerm2", "iA"]
    private static let smallWords: Set<String> = ["of", "the", "and", "in", "on", "for"]

    /// Starts with a capital; a name run together with hyphens gets spaces ("boo-shnickle").
    private static func tidied(_ words: [String]) -> [String] {
        words.enumerated().map { index, word in
            if keptWords.contains(word) { return word }
            if word == "Vs" { return "VS" }
            if index > 0, smallWords.contains(word) { return word }
            guard let first = word.first, first.isLowercase else { return word }
            return first.uppercased() + word.dropFirst()
        }
    }

    init(_ name: String) {
        // "12-bit Rainbow" keeps its hyphen; a word of letters doesn't.
        let spaced = name.split(separator: " ").flatMap { word -> [String] in
            word.contains("-") && word.first?.isLetter == true
                ? word.split(separator: "-").map(String.init) : [String(word)]
        }
        let words = spaced
        var kept: [String] = []
        var level: Int?
        for (index, word) in words.enumerated() {
            let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: "(),")).lowercased()
            if index > 0, Self.tones.contains(bare) || Self.marks.contains(bare) { continue }
            if index > 0, let found = Self.levels[bare] { level = found; continue }
            kept.append(word)
        }
        let clean = kept.map { $0.hasSuffix(",") ? String($0.dropLast()) : $0 }
        family = Self.tidied(clean).joined(separator: " ")
        self.level = level
    }
}

/// The Classics pack: the terminal themes people know by name, and the ones iTerm and Apple's
/// Terminal come with. Hand-picked, one version of each, plus its light version where that's
/// famous too; every other version stays in the pack it came from. The Terminal palettes that
/// are Classics (`GhosttyThemes.originals`) stand in for their dark versions.
enum ThemeClassics {
    private static let names: Set<String> = [
        "Afterglow", "Atom One Dark", "Atom One Light", "Ayu Light", "Ayu", "Catppuccin Latte", "Cobalt2",
        "Darcula", "Dracula", "Everforest Light Med", "Grass", "Gruvbox Light", "Homebrew", "Horizon", "Hyper",
        "iTerm2 Dark Background", "iTerm2 Default", "iTerm2 Light Background", "iTerm2 Pastel Dark Background",
        "iTerm2 Smoooooth", "iTerm2 Tango Dark", "iTerm2 Tango Light", "Jellybeans", "Kanagawa Wave", "Linux VT",
        "Man Page", "Material", "Matrix", "Molokai", "Night Owl", "Novel", "Ocean", "Oceanic Next", "One Half Dark",
        "One Half Light", "Palenight", "Poimandres", "Pro", "Railscasts", "Red Sands", "Rose Pine Dawn",
        "Shades Of Purple", "Snazzy", "Solarized Light", "Spacemacs", "Synthwave 84", "Terminal Basic Dark", "Terminal Basic",
        "Tomorrow Night", "Tomorrow", "Twilight", "Wombat", "Xterm", "Zenburn",
    ]

    static func contains(_ name: String) -> Bool { names.contains(name) }
}

/// How the Terminal list orders themes, so versions of one theme sit together: family, dark before
/// light, pack, then level.
struct ThemeSortKey: Comparable {
    let family: String
    let isLight: Bool
    let pack: Int
    let level: Int
    let name: String

    init(name: String, isDark: Bool, pack: Int) {
        let display = ThemeDisplayName(name)
        family = display.family.lowercased()
        isLight = !isDark
        self.pack = pack
        level = display.level ?? 0
        self.name = name.lowercased()
    }

    static func < (a: ThemeSortKey, b: ThemeSortKey) -> Bool {
        if a.family != b.family { return a.family < b.family }
        if a.isLight != b.isLight { return !a.isLight }
        if a.pack != b.pack { return a.pack < b.pack }
        if a.level != b.level { return a.level < b.level }
        return a.name < b.name
    }
}

/// Finds themes whose colours are identical under different names: only the first of a group
/// shows, and the others' names still find it.
enum ThemeDuplicates {
    /// Which name to keep when a group holds one of these: the name people know it by.
    private static let preferred: Set<String> = ["GitHub Dark Default", "TokyoNight", "Zenbones"]

    /// Each hidden name, and the name that stands for it. `names` and `colours` run in parallel.
    static func hidden(names: [String], colours: [String]) -> [String: String] {
        var groups: [String: [String]] = [:]
        for (name, colour) in zip(names, colours) { groups[colour, default: []].append(name) }
        var result: [String: String] = [:]
        for group in groups.values where group.count > 1 {
            let keep = group.first(where: preferred.contains)
                ?? group.min { ($0.count, $0) < ($1.count, $1) } ?? group[0]
            for name in group where name != keep { result[name] = keep }
        }
        return result
    }
}
