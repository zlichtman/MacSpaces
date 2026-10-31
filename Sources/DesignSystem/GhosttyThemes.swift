import SwiftUI

/// One of Ghostty's terminal themes (the iTerm2-Color-Schemes collection, MIT; see
/// Acknowledgements.txt), from `ghostty-themes.json`, which `Scripts/build-ghostty-themes.py`
/// generates: [name, background, foreground, accent, the sixteen ANSI colours as one string],
/// in Ghostty's own order (alphabetical by name, ignoring case).
struct GhosttyTheme: Identifiable, Hashable {
    let name: String
    let background: String
    let foreground: String
    let accent: String
    /// The sixteen ANSI colours, normal then bright.
    let ansi: [String]
    /// Its Terminal list pill, worked out once when the theme is read (off the main thread
    /// for the library), so drawing a row parses no hex.
    let pill: TerminalPillColours
    /// Worked out once with the pill, so searching and the Dark/Light filter parse no hex.
    let isDark: Bool
    /// The name lowercased, for search.
    let searchName: String
    var id: String { name }

    init?(row: [String]) {
        guard row.count == 5, row[4].count == 96 else { return nil }
        name = row[0]
        background = row[1].uppercased(); foreground = row[2].uppercased(); accent = row[3].uppercased()
        let chars = Array(row[4].uppercased())
        ansi = (0..<16).map { String(chars[$0 * 6..<$0 * 6 + 6]) }
        pill = TerminalPillColours(background: background, accent: accent, ansi: ansi)
        isDark = !pill.isLight
        searchName = name.lowercased()
    }

    /// Its own background and accent; the text is its foreground when that reads at
    /// 4.5:1, otherwise white or black as Custom picks it.
    var palette: FamilyPalette {
        let derived = CustomThemeColors.palette(background: background, accent: accent)
        let readable = CustomThemeColors.contrast(foreground, background) >= 4.5
            && CustomThemeColors.contrast(foreground, derived.surface) >= 4.5
        return FamilyPalette(background, derived.surface, readable ? foreground : derived.foreground, accent)
    }

    /// Saved as one line so the Nook can draw it at launch without reading the library
    /// (the same five fields since 3.35, the same as a library row).
    var saved: String { ([name, background, foreground, accent] + [ansi.joined()]).joined(separator: "|") }
    init?(saved: String) {
        let parts = saved.components(separatedBy: "|")
        guard parts.count == 5 else { return nil }
        self.init(row: parts)
    }
}

enum GhosttyThemes {
    static let selectedKey = "theme.ghostty.selected"
    private static var cache: (line: String, theme: GhosttyTheme?)?

    /// The chosen Ghostty theme, read from its saved line (no library load).
    static var selected: GhosttyTheme? {
        guard let line = UserDefaults.standard.string(forKey: selectedKey) else { return nil }
        if let cache, cache.line == line { return cache.theme }
        let theme = GhosttyTheme(saved: line)
        cache = (line, theme)
        return theme
    }

    /// How many themes the bundled library holds once loaded (0 before).
    @MainActor static var count: Int { GhosttyLibrary.shared.themes.count }

    /// The built-in Terminal themes that are Ghostty themes too, for their cards' ANSI rows.
    static let originals: [ThemeFamily: String] = [
        .everforest: "Everforest Dark Med", .solarized: "iTerm2 Solarized Dark", .gruvbox: "Gruvbox Dark",
        .tokyoNight: "TokyoNight", .catppuccin: "Catppuccin Mocha", .nord: "Nord", .rosePine: "Rose Pine",
        .monokai: "Monokai Classic",
    ]
}

/// A Terminal list pill's colours: the background, then the accent and red, green, yellow,
/// blue and magenta (or, without ANSI colours, the accent in five steps), and whether the
/// background is light enough to need an edge against Settings. Parsed once into sRGB
/// `CGColor`s (the same values `Color(themeHex:)` gives), so drawing a row parses no hex.
struct TerminalPillColours: Hashable {
    let background: CGColor
    let dots: [CGColor]
    let isLight: Bool
    private static let steps: [CGFloat] = [0.95, 0.8, 0.65, 0.5, 0.35]

    init(background: String, accent: String, ansi: [String]?) {
        self.background = Self.colour(background) ?? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let accentColour = Self.colour(accent) ?? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        dots = [accentColour] + (0..<5).map { i in
            ansi.flatMap { Self.colour($0[i + 1]) } ?? accentColour.copy(alpha: Self.steps[i]) ?? accentColour
        }
        isLight = !CustomThemeColors.isDark(background)
    }

    /// `Color(themeHex:)`'s parse, as an sRGB `CGColor`.
    static func colour(_ hex: String) -> CGColor? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        return CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

/// One entry in the Terminal list: one of our palettes or a Ghostty theme.
enum TerminalThemeItem: Identifiable, Hashable {
    case own(ThemeFamily)
    case ghostty(GhosttyTheme)
    var id: String {
        switch self {
        case .own(let family): return "own." + family.rawValue
        case .ghostty(let theme): return "ghostty." + theme.name
        }
    }
    var title: String {
        switch self {
        case .own(let family): return family.title
        case .ghostty(let theme): return theme.name
        }
    }
    /// Ours on top in their curated order (`ThemeFamily.ownTerminal`), then Ghostty's in
    /// its own order (the JSON's, alphabetical), so its families stay together. Nothing is
    /// sorted here. Ghostty's copies of our editor favourites (`GhosttyThemes.originals`)
    /// are left out so they don't show twice.
    static func ordered(own: [ThemeFamily], ghostty: [GhosttyTheme]) -> [TerminalThemeItem] {
        let originals = Set(GhosttyThemes.originals.values)
        var list = own.map(TerminalThemeItem.own)
        list.reserveCapacity(own.count + ghostty.count)
        for theme in ghostty where !originals.contains(theme.name) { list.append(.ghostty(theme)) }
        return list
    }
}

/// The bundled library, read once off the main thread when Settings opens (and, as a
/// fallback, when Appearance shows), so the Terminal drawer has it before anyone opens it.
@MainActor
final class GhosttyLibrary: ObservableObject {
    static let shared = GhosttyLibrary()
    @Published private(set) var themes: [GhosttyTheme] = []
    private var byName: [String: GhosttyTheme] = [:]
    /// Our Terminal palettes' pills, with their Ghostty originals' ANSI colours once loaded.
    private(set) var ownPills: [ThemeFamily: TerminalPillColours] = GhosttyLibrary.ownPills(byName: [:])
    private var requested = false

    func load() {
        guard !requested else { return }
        requested = true
        DispatchQueue.global(qos: .userInitiated).async {
            let rows: [[String]] = Bundle.main.url(forResource: "ghostty-themes", withExtension: "json")
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? JSONDecoder().decode([[String]].self, from: $0) } ?? []
            let themes = rows.compactMap(GhosttyTheme.init(row:))
            let byName = Dictionary(themes.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            let ownPills = GhosttyLibrary.ownPills(byName: byName)
            DispatchQueue.main.async {
                GhosttyLibrary.shared.byName = byName
                GhosttyLibrary.shared.ownPills = ownPills
                GhosttyLibrary.shared.themes = themes
            }
        }
    }

    func theme(named name: String) -> GhosttyTheme? { byName[name] }

    /// The pill for one of our palettes (and an unlisted one in use): its dark palette, with
    /// its Ghostty original's ANSI colours when it has one.
    func pill(_ family: ThemeFamily) -> TerminalPillColours {
        ownPills[family] ?? Self.pill(family, byName: byName)
    }

    nonisolated private static func pill(_ family: ThemeFamily, byName: [String: GhosttyTheme]) -> TerminalPillColours {
        let palette = family.palette(.dark)
        return TerminalPillColours(background: palette.background, accent: palette.accent,
                                   ansi: GhosttyThemes.originals[family].flatMap { byName[$0]?.ansi })
    }

    nonisolated private static func ownPills(byName: [String: GhosttyTheme]) -> [ThemeFamily: TerminalPillColours] {
        Dictionary(uniqueKeysWithValues: ThemeFamily.ownTerminal.map { ($0, pill($0, byName: byName)) })
    }

    /// Every word of the query must start a word of the name or appear in it;
    /// "dark" and "light" also match by background.
    func search(_ query: String, tone: Tone) -> [GhosttyTheme] {
        let words = query.lowercased().split(whereSeparator: { $0 == " " }).map(String.init)
        return themes.filter { theme in
            switch tone {
            case .all: break
            case .dark: if !theme.isDark { return false }
            case .light: if theme.isDark { return false }
            }
            return words.allSatisfy { theme.searchName.contains($0) }
        }
    }

    enum Tone: String, CaseIterable, Identifiable {
        case all, dark, light
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }
}
