import SwiftUI

/// One of Ghostty's terminal themes (the iTerm2-Color-Schemes collection, MIT; see
/// Acknowledgements.txt), from `ghostty-themes.json`, which `Scripts/build-ghostty-themes.py`
/// generates: [name, background, foreground, accent, the sixteen ANSI colours as one string],
/// in Ghostty's own order (alphabetical by name, ignoring case).
struct GhosttyTheme: Identifiable, Hashable {
    let name: String
    /// Which pack it came from; names are unique across packs, so a saved choice finds it.
    var pack: GhosttyLibrary.Pack = .ghostty
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
    /// The name lowercased, for search, with any hidden duplicates' names (`ThemeDuplicates`).
    var searchName: String
    /// Its family and level, for the list (`ThemeDisplayName`).
    let display: ThemeDisplayName
    var id: String { name }

    init?(row: [String]) {
        guard row.count == 5, row[4].count == 96 else { return nil }
        name = row[0]
        background = row[1].uppercased(); foreground = row[2].uppercased(); accent = row[3].uppercased()
        let chars = Array(row[4].uppercased())
        ansi = (0..<16).map { String(chars[$0 * 6..<$0 * 6 + 6]) }
        pill = TerminalPillColours(background: background, accent: accent, ansi: ansi)
        isDark = !pill.isLight
        searchName = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        display = ThemeDisplayName(row[0])
    }

    /// Its own background and accent; the text is its foreground when that reads at
    /// 4.5:1, otherwise white or black as Custom picks it.
    var palette: FamilyPalette {
        let derived = CustomThemeColors.palette(background: background, accent: accent)
        let readable = CustomThemeColors.contrast(foreground, background) >= 4.5
            && CustomThemeColors.contrast(foreground, derived.surface) >= 4.5
        return FamilyPalette(background, derived.surface, readable ? foreground : derived.foreground, accent)
    }

    /// One colour changed (`ThemeColourSlot`), keeping its name and pack.
    func with(_ slot: ThemeColourSlot, hex: String) -> GhosttyTheme? {
        var colours = [background, foreground, accent]
        var inks = ansi
        switch slot {
        case .background: colours[0] = hex
        case .text: colours[1] = hex
        case .accent: colours[2] = hex
        default: inks[slot.ansiIndex] = hex
        }
        var theme = GhosttyTheme(row: [name] + colours + [inks.joined()])
        theme?.pack = pack
        theme?.searchName = searchName
        return theme
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

/// One colour of a theme, in the order the selected theme's dots show them.
enum ThemeColourSlot: Int, CaseIterable, Identifiable {
    case background, text, accent, red, green, yellow, blue, magenta
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .background: return "Background"
        case .text: return "Text"
        case .accent: return "Accent"
        case .red: return "Red"
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        case .magenta: return "Magenta"
        }
    }
    /// Its place in a theme's sixteen ANSI colours; the first three aren't ANSI colours.
    var ansiIndex: Int { rawValue - 2 }

    func hex(in theme: GhosttyTheme) -> String {
        switch self {
        case .background: return theme.background
        case .text: return theme.foreground
        case .accent: return theme.accent
        default: return theme.ansi[ansiIndex]
        }
    }
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
    /// The full name: for search, hover and VoiceOver.
    var title: String {
        switch self {
        case .own(let family): return family.title
        case .ghostty(let theme): return theme.name
        }
    }
    /// What its row says: the family, with the level and tone drawn beside it.
    var familyTitle: String {
        switch self {
        // A night scene sits beside its day version under one name; the moon tells them apart.
        case .own(let family): return family.title.hasPrefix("Night ") ? String(family.title.dropFirst(6)) : family.title
        case .ghostty(let theme): return theme.display.family
        }
    }
    var level: Int? {
        switch self {
        case .own: return nil
        case .ghostty(let theme): return theme.display.level
        }
    }
    /// Our palettes are dark unless they're light only (`ThemeFamily.lightOnly`). A scene goes by
    /// its picture, so Blossom is light and Night Blossom dark.
    var isDark: Bool {
        switch self {
        case .own(let family): return !Self.lightScenes.contains(family) && !ThemeFamily.lightOnly.contains(family)
        case .ghostty(let theme): return theme.isDark
        }
    }
    private static let lightScenes: Set<ThemeFamily> = [.blossom, .lotus, .lavender, .fern, .bamboo, .autumn, .dune, .alpine]

    /// A scene that moves while the Nook is open: tagged as live in the list.
    var isLive: Bool {
        guard case .own(let family) = self else { return false }
        return family.collection == .live
    }

    /// A scene's picture, shown small on its row and large when pressed. Scenes that are drawn
    /// rather than photographed have none.
    var photo: String? {
        guard case .own(let family) = self else { return nil }
        return family.motif.flatMap { $0.floralAsset ?? $0.natureAsset }
    }

    var packTitle: String {
        switch self {
        case .own(let family):
            if family == .custom { return "Custom" }
            return GhosttyThemes.originals[family] == nil ? "Editorial" : "Classics"
        case .ghostty(let theme): return ThemeClassics.contains(theme.name) ? "Classics" : theme.pack.title
        }
    }
    private var sortKey: ThemeSortKey {
        switch self {
        case .own(let family): return ThemeSortKey(name: familyTitle, isDark: isDark, pack: 0)
        case .ghostty(let theme): return ThemeSortKey(name: theme.name, isDark: theme.isDark, pack: ThemeClassics.contains(theme.name) ? 0 : theme.pack.order)
        }
    }

    /// Ours on top in their curated order (`ThemeFamily.ownTerminal`), then the library's in its
    /// own order, with its versions of a theme together. A search mixes them, so every Everforest
    /// sits in one run. Ghostty's copies of our editor favourites (`GhosttyThemes.originals`)
    /// are left out so they don't show twice.
    static func ordered(own: [TerminalThemeItem], ghostty: [GhosttyTheme], searching: Bool = false) -> [TerminalThemeItem] {
        let originals = Set(GhosttyThemes.originals.values)
        var list = own
        list.reserveCapacity(own.count + ghostty.count)
        for theme in ghostty where !originals.contains(theme.name) { list.append(.ghostty(theme)) }
        return searching ? list.sorted { $0.sortKey < $1.sortKey } : list
    }
}

/// The bundled library, read once off the main thread when Settings opens (and, as a
/// fallback, when Appearance shows), so the Terminal drawer has it before anyone opens it.
@MainActor
final class GhosttyLibrary: ObservableObject {
    static let shared = GhosttyLibrary()
    @Published private(set) var themes: [GhosttyTheme] = []
    private var byName: [String: GhosttyTheme] = [:]
    private var hiddenNames: [String: String] = [:]
    /// Themes the user has recoloured, by `TerminalThemeItem.id`, as saved lines. Their originals
    /// stay in `originals` for Reset.
    private var edits: [String: String] = UserDefaults.standard.dictionary(forKey: GhosttyLibrary.editsKey) as? [String: String] ?? [:]
    private var originals: [String: GhosttyTheme] = [:]
    /// Changes when a colour does, so the list redraws its pills.
    @Published private(set) var editRevision = 0
    static let editsKey = "theme.ghostty.edits"
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
            // The other packs join Ghostty's in one alphabetical list, so families stay together.
            let extras: [String: [[String]]] = Bundle.main.url(forResource: "theme-packs", withExtension: "json")
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? JSONDecoder().decode([String: [[String]]].self, from: $0) } ?? [:]
            var themes = rows.compactMap(GhosttyTheme.init(row:))
            for pack in Pack.allCases where pack.resourceKey != nil {
                themes += (extras[pack.resourceKey ?? ""] ?? []).compactMap(GhosttyTheme.init(row:)).map { theme in
                    var theme = theme
                    theme.pack = pack
                    return theme
                }
            }
            // Every name keeps finding its colours, so a saved choice of a hidden copy still opens.
            let byName = Dictionary(themes.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            let hidden = ThemeDuplicates.hidden(names: themes.map(\.name), colours: themes.map { [$0.background, $0.foreground, $0.accent, $0.ansi.joined()].joined() })
            themes.removeAll { hidden[$0.name] != nil }
            for (name, keep) in hidden {
                guard let index = themes.firstIndex(where: { $0.name == keep }) else { continue }
                themes[index].searchName += " " + name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            }
            let keys = Dictionary(themes.map { ($0.name, ThemeSortKey(name: $0.name, isDark: $0.isDark, pack: $0.pack.order)) },
                                  uniquingKeysWith: { a, _ in a })
            themes.sort { keys[$0.name]! < keys[$1.name]! }
            let ownPills = GhosttyLibrary.ownPills(byName: byName)
            DispatchQueue.main.async {
                GhosttyLibrary.shared.byName = byName
                GhosttyLibrary.shared.hiddenNames = hidden
                GhosttyLibrary.shared.applySavedEdits()
                GhosttyLibrary.shared.ownPills = ownPills
                GhosttyLibrary.shared.themes = themes
            }
        }
    }

    func theme(named name: String) -> GhosttyTheme? { byName[name] }

    // MARK: Recolouring

    func isEdited(_ item: TerminalThemeItem) -> Bool { edits[item.id] != nil }

    /// A scene's colours belong to its picture, so they show but don't change here.
    func isEditable(_ item: TerminalThemeItem) -> Bool { !item.isLive }

    /// The list entry for a `TerminalThemeItem.id`: nil for Custom or a retired theme.
    func item(id: String) -> TerminalThemeItem? {
        if id.hasPrefix("own.") {
            return ThemeFamily(rawValue: String(id.dropFirst(4))).flatMap { family in
                ThemeFamily.ownTerminal.contains(family) || ThemeCollection.live.families.contains(family) ? .own(family) : nil
            }
        }
        guard id.hasPrefix("ghostty.") else { return nil }
        return byName[String(id.dropFirst(8))].map(TerminalThemeItem.ghostty)
    }

    /// The theme in `item` as it is now, edits included. One of our palettes becomes a theme
    /// here, with its original's ANSI colours or a set worked out from its accent. Custom isn't
    /// one; a scene's colours show the same way, without being editable (`isEditable`).
    func current(_ item: TerminalThemeItem) -> GhosttyTheme? {
        if case .own(.custom) = item { return nil }
        if let line = edits[item.id], var edited = GhosttyTheme(saved: line) {
            if case .ghostty(let theme) = item { edited.pack = theme.pack; edited.searchName = theme.searchName }
            return edited
        }
        switch item {
        case .ghostty(let theme): return originals[theme.name] ?? theme
        case .own(let family):
            let palette = family.palette(.dark)
            let picks = GhosttyThemes.originals[family].flatMap { byName[$0]?.ansi }
                ?? { () -> [String] in
                    let inks = ThemeInks.hexes(ansi: nil, accent: palette.accent, surface: palette.background, foreground: palette.foreground)
                    return [palette.background] + inks + [palette.foreground] + [palette.background] + inks + [palette.foreground]
                }()
            return GhosttyTheme(row: [family.title, palette.background, palette.foreground, palette.accent, picks.joined()])
        }
    }

    /// Changes one colour of a theme and uses it. Edits stay with the theme until Reset.
    func recolour(_ item: TerminalThemeItem, _ slot: ThemeColourSlot, hex: String) {
        guard isEditable(item), let edited = current(item)?.with(slot, hex: hex) else { return }
        edits[item.id] = edited.saved
        UserDefaults.standard.set(edits, forKey: Self.editsKey)
        store(edited, for: item)
        ThemeStore.shared.selectGhostty(edited)
        editRevision += 1
    }

    /// Back to the theme as it came, still in use.
    func resetColours(_ item: TerminalThemeItem) {
        edits[item.id] = nil
        UserDefaults.standard.set(edits, forKey: Self.editsKey)
        switch item {
        case .ghostty(let theme):
            guard let original = originals[theme.name] else { break }
            store(original, for: item)
            ThemeStore.shared.selectGhostty(original)
        case .own(let family):
            ownPills[family] = Self.pill(family, byName: byName)
            ThemeStore.shared.selectFamily(family)
        }
        editRevision += 1
    }

    /// Drops every recolour, saved and shown, for Reset; unlike `resetColours` it selects nothing.
    func forgetEdits() {
        let edited = Array(edits.keys)
        edits = [:]
        UserDefaults.standard.removeObject(forKey: Self.editsKey)
        for id in edited {
            if id.hasPrefix("own."), let family = ThemeFamily(rawValue: String(id.dropFirst(4))) {
                ownPills[family] = Self.pill(family, byName: byName)
            } else if id.hasPrefix("ghostty."), let original = originals[String(id.dropFirst(8))] {
                store(original, for: .ghostty(original))
            }
        }
        editRevision += 1
    }

    /// Uses a theme from the list, with its edits.
    func use(_ item: TerminalThemeItem) {
        if isEdited(item), let edited = current(item) { ThemeStore.shared.selectGhostty(edited); return }
        switch item {
        case .own(let family): ThemeStore.shared.selectFamily(family)
        case .ghostty(let ghostty): ThemeStore.shared.selectGhostty(current(item) ?? ghostty)
        }
    }

    private func store(_ theme: GhosttyTheme, for item: TerminalThemeItem) {
        switch item {
        case .ghostty(let original):
            byName[original.name] = theme
            if let index = themes.firstIndex(where: { $0.name == original.name }) { themes[index] = theme }
        case .own(let family):
            ownPills[family] = theme.pill
        }
    }

    private func applySavedEdits() {
        originals = byName
        for (id, line) in edits {
            guard var edited = GhosttyTheme(saved: line) else { continue }
            if id.hasPrefix("own."), let family = ThemeFamily(rawValue: String(id.dropFirst(4))) {
                ownPills[family] = edited.pill
            } else if let original = byName[edited.name] {
                edited.pack = original.pack
                edited.searchName = original.searchName
                store(edited, for: .ghostty(original))
            }
        }
    }

    /// The name a theme shows under: its own, or the one standing for it if it's a hidden copy.
    func shownName(_ name: String) -> String { hiddenNames[name] ?? name }

    /// The pill for one of our palettes (and an unlisted one in use): its dark palette, with
    /// its Ghostty original's ANSI colours when it has one.
    func pill(_ family: ThemeFamily) -> TerminalPillColours {
        ownPills[family] ?? Self.pill(family, byName: byName)
    }

    nonisolated private static func pill(_ family: ThemeFamily, byName: [String: GhosttyTheme]) -> TerminalPillColours {
        let palette = family.palette(.dark)
        // A scene's dots are a set worked out from its accent, so it reads like every other row.
        let scene = family.collection == .live
            ? [palette.background] + ThemeInks.hexes(ansi: nil, accent: palette.accent, surface: palette.background, foreground: palette.foreground)
            : nil
        return TerminalPillColours(background: palette.background, accent: palette.accent,
                                   ansi: scene ?? GhosttyThemes.originals[family].flatMap { byName[$0]?.ansi })
    }

    nonisolated private static func ownPills(byName: [String: GhosttyTheme]) -> [ThemeFamily: TerminalPillColours] {
        Dictionary(uniqueKeysWithValues: ThemeFamily.ownTerminal.map { ($0, pill($0, byName: byName)) })
    }

    /// Every word of the query must start a word of the name or appear in it;
    /// "dark" and "light" also match by background.
    func search(_ query: String, tone: Tone, pack: Pack? = nil, classicsOnly: Bool = false) -> [GhosttyTheme] {
        let words = query.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split(whereSeparator: { $0 == " " }).map(String.init)
        return themes.filter { theme in
            // A theme sits in one pack: a Classic isn't listed again under where it came from.
            if let pack, theme.pack != pack || ThemeClassics.contains(theme.name) { return false }
            if classicsOnly, !ThemeClassics.contains(theme.name) { return false }
            switch tone {
            case .all: break
            case .dark: if !theme.isDark { return false }
            case .light: if theme.isDark { return false }
            }
            return words.allSatisfy { theme.searchName.contains($0) }
        }
    }

    /// Where a theme came from: the Terminal drawer's other filter.
    enum Pack: String, CaseIterable, Identifiable {
        case ghostty, base16, gogh
        var id: String { rawValue }
        var title: String {
            switch self {
            case .ghostty: return "Ghostty"
            case .base16: return "Base16"
            case .gogh: return "Gogh"
            }
        }
        /// Where it sorts among a theme's versions, after our own (0).
        var order: Int { self == .base16 ? 1 : self == .ghostty ? 2 : 3 }
        /// Its list in theme-packs.json; Ghostty's has its own file.
        var resourceKey: String? { self == .ghostty ? nil : title }
    }

    enum Tone: String, CaseIterable, Identifiable {
        case all, dark, light
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }
}
