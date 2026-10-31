import SwiftUI

struct FamilyPalette {
    let background: String
    let surface: String
    let foreground: String
    let accent: String
    init(_ background: String, _ surface: String, _ foreground: String, _ accent: String) {
        self.background = background; self.surface = surface
        self.foreground = foreground; self.accent = accent
    }
    func color(_ hex: String) -> Color { Color(themeHex: hex) ?? .primary }
}

enum ThemeFamily: String, CaseIterable, Identifiable {
    case macspaces, powdermeet, heartable, kemosabe, tsukumo
    case tidal, ember, everforest, carbon, acid, cobalt, midnight
    case solarized, gruvbox, tokyoNight, catppuccin, karma, monokai
    case nord, rosePine, ayu
    case parchment, copper, slate, aubergine, seafoam
    case ruby, citrine, sapphire, indigo, turquoise
    // See-through panes over the desktop (`glassTint`).
    case clear, frost, smoke, glass, tinted
    // Each of these draws a scene that moves while the Nook is open.
    case blossom, lavender, sunflower, wildflower, lotus
    case fern, moss, bamboo, firefly, moonrise
    case aurora, alpine, dune, canyon
    case monsoon, thunderstorm, starlight, autumn, glacier
    // Night scenes (Codex, 3.24): dark photographs with quiet centres.
    case nightBlossom, nightLotus, rainCanopy, obsidianCoast, moonlitDunes
    case rainbow, synthwave, lava, plasma, codeRain, warp, circuit, prism, nebula
    /// The user's own theme: solid, two-tone, glass or a picture (see `CustomTheme`).
    case custom
    /// One of Ghostty's terminal themes, chosen by name (see `GhosttyThemes`).
    case ghostty

    /// Our Terminal palettes, the top of the Terminal list in this order: Noir (saved id
    /// `macspaces`, black and white like the Mac tools' icons, and the default), four quiet
    /// colours, Midnight and Orchid, then the editor favourites from cool to warm.
    static let ownTerminal: [Self] = [.macspaces, .powdermeet, .heartable, .kemosabe, .tsukumo,
                                      .midnight, .karma,
                                      .tokyoNight, .catppuccin, .rosePine, .nord, .solarized,
                                      .everforest, .gruvbox, .monokai]
    /// Themes no drawer offers any more. Each still opens and looks exactly as before for
    /// anyone using it (an update changes no one's theme), and shows at the start of its
    /// drawer only while it's in use.
    static let unlisted: Set<Self> = [
        // Scenes: near-duplicates of a kept one, or too busy behind the Nook.
        .sunflower, .wildflower, .moss, .ember, .tidal, .monsoon, .glacier, .circuit, .plasma, .nebula,
        // Single colours and glass panes, which Custom now builds; Ayu is in Ghostty's library.
        .carbon, .acid, .cobalt, .parchment, .copper, .slate, .aubergine, .seafoam,
        .ruby, .citrine, .sapphire, .indigo, .turquoise, .ayu,
        .clear, .frost, .glass, .smoke, .tinted,
    ]
    var isOffered: Bool { !Self.unlisted.contains(self) }
    var collection: ThemeCollection {
        switch self {
        case .custom: return .custom
        case .ghostty: return .terminal
        default: return motif == nil ? .terminal : .live
        }
    }
    var id: String { rawValue }
    var title: String {
        switch self {
        // Named for how they look, not the apps they came from; saved ids stay.
        case .macspaces: return "Noir"
        case .powdermeet: return "Scarlet"
        case .heartable: return "Rose"
        case .kemosabe: return "Coral"
        case .tsukumo: return "Iris"
        case .karma: return "Orchid"
        case .ghostty: return GhosttyThemes.selected?.name ?? "Ghostty"
        case .tokyoNight: return "Tokyo Night"
        case .rosePine: return "Rosé Pine"
        case .codeRain: return "Code Rain"
        case .nightBlossom: return "Night Blossom"
        case .nightLotus: return "Night Lotus"
        case .rainCanopy: return "Rain Canopy"
        case .obsidianCoast: return "Obsidian Coast"
        case .moonlitDunes: return "Moonlit Dunes"
        // Alpine's saved id stays; it's the Snow theme now.
        case .alpine: return "Snow"
        // The old glass Custom (saved id "tinted", 2.98).
        case .tinted: return "Tinted Glass"
        default: return rawValue.capitalized
        }
    }
    /// Reads a saved family. One Dark was replaced by Karma in 2.38, so a
    /// saved One Dark opens as Karma instead of falling back to the default.
    init?(saved rawValue: String) {
        if let replacement = Self.replaced[rawValue] { self = replacement; return }
        self.init(rawValue: rawValue)
    }
    /// Themes that were retired, and the closest one that replaced each: One Dark
    /// (2.38), and 2.38's Sweets and Studio drawers (2.39).
    static let replaced: [String: ThemeFamily] = [
        "oneDark": .karma,
        "bubblegum": .blossom, "matcha": .moss, "strawberryMilk": .blossom, "lemonDrop": .sunflower,
        "cottonCandy": .lavender, "encore": .carbon, "matinee": .ember, "barista": .everforest,
        "arcade": .synthwave, "parcel": .dune, "newsprint": .macspaces,
        "pulse": .starlight,
        // 2.72: Terminal look-alikes, and the scenes that were retired.
        "dracula": .catppuccin, "tomorrowNight": .slate, "kanagawa": .tokyoNight, "nightOwl": .indigo,
        "fireworks": .starlight, "coral": .tidal, "sandbar": .canyon,
        // 2.97: Noir became the MacSpaces theme; the old MacSpaces blue is Midnight.
        "noir": .macspaces,
        // 2.97: Hologram (2.96 only) was dropped; Rainbow is back in Tech.
        "hologram": .rainbow,
        // 2.98: Bronze glass became Custom glass (saved id "tinted").
        "bronze": .tinted,
    ]
    /// A pre-2.38 preset ID ("midnight", "forest"…) as today's family; nil for its old Custom.
    init?(legacy preset: String) {
        let renamed = ["frosted": "glass", "graphite": "carbon", "ocean": "tidal",
                       "sunset": "ember", "forest": "everforest", "solarizedDark": "solarized",
                       "gruvboxDark": "gruvbox", "catppuccinMocha": "catppuccin"]
        guard preset != "custom", let family = Self(saved: renamed[preset] ?? preset) else { return nil }
        self = family
    }

    func palette(_ scheme: ColorScheme) -> FamilyPalette {
        switch (self, scheme == .dark) {
        // MacSpaces is the Noir palette (2.97); its earlier deep blue is Midnight.
        case (.macspaces, false): return .init("F4F4F2", "FFFFFF", "111111", "6E6E6E")
        case (.macspaces, true): return .init("0B0B0C", "18181A", "F2F2F2", "E8E8E8")
        case (.midnight, false): return .init("F0F5FC", "FFFFFF", "152238", "176BC4")
        case (.midnight, true): return .init("020714", "0C172B", "EEF5FF", "1F8CFF")
        case (.tidal, false): return .init("EDF8FA", "FFFFFF", "143844", "007791")
        case (.tidal, true): return .init("021D2A", "093545", "E5F7FA", "0DD4F5")
        case (.ember, false): return .init("FFF3E8", "FFFAF5", "48271C", "B64712")
        case (.ember, true): return .init("240606", "3D1710", "FFF0E3", "FF7A1F")
        case (.powdermeet, false): return .init("F3F6F8", "FFFFFF", "182330", "C63436")
        case (.powdermeet, true): return .init("0F0F12", "222328", "F5F6F8", "EB3333")
        case (.heartable, false): return .init("FFF4EF", "FFFAF7", "432B2B", "C43266")
        case (.heartable, true): return .init("141016", "1F1824", "F3EEF2", "FF6FA0")
        case (.kemosabe, false): return .init("FAF3EA", "F3E8DA", "1B1529", "D9573F")
        case (.kemosabe, true): return .init("1B1529", "221B33", "F4E4D1", "EF705B")
        case (.tsukumo, false): return .init("F7F3EC", "EEE8DE", "16141C", "7C4DE8")
        case (.tsukumo, true): return .init("0E0D12", "15131B", "F5EFE5", "B794FC")
        case (.everforest, false): return .init("FDF6E3", "F5EFD9", "5C6A72", "53764B")
        case (.everforest, true): return .init("2D353B", "343F40", "D3C6AA", "A7C080")
        case (.carbon, false): return .init("F2F5F4", "FFFFFF", "24332D", "087857")
        case (.carbon, true): return .init("090C0F", "1B2427", "E3ECE8", "1AE8A6")
        case (.acid, false): return .init("F4F7E9", "FCFFF4", "28331B", "4E7110")
        case (.acid, true): return .init("091105", "202B12", "EAF4D6", "A3F52E")
        case (.cobalt, false): return .init("EDF4FC", "FFFFFF", "172C47", "086C9C")
        case (.cobalt, true): return .init("061124", "142C49", "E0EEFC", "18C5F1")
        case (.solarized, false): return .init("FDF6E3", "EEE8D5", "43565C", "147A73")
        case (.solarized, true): return .init("002B36", "073642", "B6C8C8", "2AA198")
        case (.gruvbox, false): return .init("FBF1C7", "F2E5BC", "3C3836", "986B00")
        case (.gruvbox, true): return .init("282828", "3C3836", "EBDBB2", "FABD2F")
        case (.tokyoNight, false): return .init("EDF0F8", "FFFFFF", "343B58", "3456B0")
        case (.tokyoNight, true): return .init("1A1B26", "24283B", "C0CAF5", "7AA2F7")
        case (.catppuccin, false): return .init("EFF1F5", "E6E9EF", "4C4F69", "8839EF")
        case (.catppuccin, true): return .init("1E1E2E", "313244", "CDD6F4", "CBA6F7")
        // Karma: plum and orchid, pink leaning into purple.
        case (.karma, false): return .init("FBF1FA", "FFFFFF", "3B2147", "A0308F")
        case (.karma, true): return .init("1C1027", "2A1839", "F7E8F6", "E774D6")
        case (.monokai, false): return .init("F5F5EC", "FFFFF7", "373A2C", "5B7516")
        case (.monokai, true): return .init("272822", "36372F", "F8F8F2", "A6E22E")
        case (.nord, false): return .init("ECEFF4", "FFFFFF", "2E3440", "426782")
        case (.nord, true): return .init("2E3440", "3B4252", "ECEFF4", "88C0D0")
        case (.rosePine, false): return .init("FAF4ED", "FFFAF3", "575279", "B4637A")
        case (.rosePine, true): return .init("191724", "1F1D2E", "E0DEF4", "EBBCBA")
        case (.ayu, false): return .init("FCFCFC", "F3F4F5", "5C6166", "F2A300")
        case (.ayu, true): return .init("0B0E14", "131721", "BFBDB6", "E6B450")
        // Nature
        case (.blossom, false): return .init("FFF3F6", "FFFFFF", "4A2B35", "D2557A")
        case (.blossom, true): return .init("24161C", "33212A", "FBE9EF", "F59AB5")
        case (.lavender, false): return .init("F6F2FC", "FFFFFF", "3A3150", "7B5BC4")
        case (.lavender, true): return .init("1C1827", "292338", "EDE7F8", "B39DF0")
        case (.aurora, false): return .init("EEF8F5", "FFFFFF", "1F3A37", "16876F")
        case (.aurora, true): return .init("0A1420", "13222F", "E2F4EF", "5CF2B5")
        case (.alpine, false): return .init("F1F4F8", "FFFFFF", "26323F", "3D6FA3")
        case (.alpine, true): return .init("141B24", "1F2A36", "E6EDF5", "8EB8E6")
        case (.moss, false): return .init("F2F4EA", "FBFCF6", "2E3A24", "5B7A2F")
        case (.moss, true): return .init("151A12", "20281B", "E4EBD8", "9CC46A")
        case (.sunflower, false): return .init("FFF9E6", "FFFDF5", "3F3416", "B07A00")
        case (.sunflower, true): return .init("1B170C", "2A2413", "F7EFD6", "FFC83D")
        case (.dune, false): return .init("FAF3E8", "FFFBF4", "45352A", "B3643A")
        case (.dune, true): return .init("1E1712", "2C221A", "F4E7D8", "E59A63")
        case (.monsoon, false): return .init("EEF3F5", "FFFFFF", "22323B", "2F6F8F")
        case (.monsoon, true): return .init("0F1A20", "1A2830", "DDE8EE", "6FB7D9")
        case (.thunderstorm, false): return .init("EFF1F6", "FFFFFF", "262A36", "4A5BC4")
        case (.thunderstorm, true): return .init("12141C", "1E212C", "E3E6F0", "A9B8FF")
        case (.firefly, false): return .init("F2F5EA", "FFFFFF", "26301F", "6B7A1E")
        case (.firefly, true): return .init("0D1410", "18221A", "E4EDD8", "E9F27A")
        case (.starlight, false): return .init("F1F3FB", "FFFFFF", "222A45", "8A6A1E")
        case (.starlight, true): return .init("070B1A", "111733", "E8ECFF", "FFD27A")
        case (.autumn, false): return .init("FBF3EA", "FFFFFF", "3D2A1C", "B3561C")
        case (.autumn, true): return .init("1C130D", "2A1D14", "F4E6D6", "E0873A")
        // Terminal
        // Original quiet Terminal palettes.
        case (.parchment, false): return .init("F8F3E7", "FFFCF3", "3D3426", "826031")
        case (.parchment, true): return .init("211D16", "30291F", "EDE2C9", "D4B77D")
        case (.copper, false): return .init("FAF0E9", "FFFAF6", "422C25", "A14F32")
        case (.copper, true): return .init("211613", "33221C", "F1DDD1", "DB916C")
        case (.slate, false): return .init("F0F3F5", "FAFCFD", "29343E", "496A85")
        case (.slate, true): return .init("182027", "25313B", "E1E9F0", "91B2CF")
        case (.aubergine, false): return .init("F6F0F7", "FFFAFF", "3C2842", "85508F")
        case (.aubergine, true): return .init("211526", "32203A", "EFDFEF", "CC98D2")
        case (.seafoam, false): return .init("EFF8F4", "FAFFFC", "203D34", "28715E")
        case (.seafoam, true): return .init("10231D", "1C342B", "DEF1E8", "86CFB0")
        // Nature: slender canes, fronds, ice, moonlight and coastal contours.
        case (.bamboo, false): return .init("F3F6E8", "FBFDF4", "303A21", "617835")
        case (.bamboo, true): return .init("182012", "26311C", "E6ECD3", "B2C978")
        case (.fern, false): return .init("EDF5ED", "F9FDF8", "233D2A", "33734B")
        case (.fern, true): return .init("102016", "1B3021", "DDEDDD", "7DB58C")
        case (.glacier, false): return .init("ECF8FA", "F8FEFF", "233B45", "32758D")
        case (.glacier, true): return .init("10242C", "1C3540", "DFF1F5", "8AD5E5")
        case (.moonrise, false): return .init("F3F1FA", "FEFCFF", "302E48", "71619B")
        case (.moonrise, true): return .init("171528", "25223C", "E9E4F5", "C1B4E5")
        // Glass: the background is a tint over the blurred desktop, not a solid fill.
        case (.clear, false): return .init("F7F8FA", "FFFFFF", "16181C", "3E4654")
        case (.clear, true): return .init("15171B", "23262C", "F7F8FA", "E4E9F0")
        // Frost is always white frosted glass and Smoke always dark (`fixedScheme`);
        // each keeps a matching pair so either variant reads the same.
        case (.frost, _): return .init("F6F8FB", "FFFFFF", "18202B", "2F6BB3")
        case (.smoke, _): return .init("0B0B0D", "1A1A1E", "F0F0F3", "B9BCC6")
        // Glass: a neutral pane with a calm blue accent (the light pair colours Settings in light mode).
        case (.glass, false): return .init("F4F6F9", "FFFFFF", "171A1F", "2F6FD6")
        case (.glass, true): return .init("1A1D22", "272B31", "F4F6F9", "86B4FF")
        case (.tinted, _): return CustomThemeColors.palette(background: TintedGlassColors.tint, accent: TintedGlassColors.accent)
        // Live
        case (.rainbow, false): return .init("F6F6FA", "FFFFFF", "1E1E28", "B8249A")
        case (.rainbow, true): return .init("0B0B10", "17171F", "F0F0F5", "FF4FD8")
        case (.synthwave, false): return .init("FBF1FF", "FFFFFF", "2C1840", "C2227E")
        case (.synthwave, true): return .init("140A24", "22123A", "F7E8FF", "FF4FB0")
        case (.lava, false): return .init("FFF3EE", "FFFFFF", "3B1C14", "C2461E")
        case (.lava, true): return .init("1A0A0A", "2A1212", "FCE9E2", "FF6A3D")
        case (.plasma, false): return .init("F1F3FF", "FFFFFF", "1E2440", "5436D6")
        case (.plasma, true): return .init("0A0F1F", "141C33", "E6ECFF", "7C5CFF")
        case (.codeRain, false): return .init("F0F8F2", "FFFFFF", "14301C", "17803C")
        case (.codeRain, true): return .init("030A05", "0B160E", "D6F5DC", "3DFF7A")
        case (.warp, false): return .init("F2F3F9", "FFFFFF", "1F2233", "3A5BC4")
        case (.warp, true): return .init("05060C", "10121E", "E8EAF6", "8FB4FF")
        case (.circuit, false): return .init("EEF7F3", "FFFFFF", "17302A", "12806A")
        case (.circuit, true): return .init("06120F", "0F1F1A", "DDF2EA", "2EE6B0")
        case (.prism, false): return .init("F7F7FB", "FFFFFF", "22222E", "5B4BC4")
        case (.prism, true): return .init("0E0E14", "1A1A23", "EEEEF5", "B8A6FF")
        case (.nebula, false): return .init("F5F1FC", "FFFFFF", "271D3F", "8A34C4")
        case (.nebula, true): return .init("0B0717", "17112B", "EEE8FF", "D07BFF")
        // 2.72 Terminal colours: a red, a true yellow, a royal blue and an indigo.
        case (.ruby, false): return .init("FFF2F4", "FFFFFF", "3E1A22", "B01F3C")
        case (.ruby, true): return .init("1A0C10", "2A151B", "F7E6E9", "FF4D6A")
        case (.citrine, false): return .init("FFFCE8", "FFFFFF", "3A3514", "7F6A00")
        case (.citrine, true): return .init("17150A", "26230F", "F5F1D8", "F2DA3C")
        case (.sapphire, false): return .init("EEF2FF", "FFFFFF", "1A2550", "2A50C8")
        case (.sapphire, true): return .init("060C24", "111B3F", "E3E9FF", "4D7CFF")
        case (.indigo, false): return .init("F2F1FF", "FFFFFF", "26234A", "5146C9")
        case (.indigo, true): return .init("110F26", "1C1A3A", "E8E6FF", "8F84FF")
        case (.turquoise, false): return .init("EDF9F8", "FFFFFF", "163B3A", "0A7A74")
        case (.turquoise, true): return .init("071A1A", "102B2B", "DDF5F3", "3DDCCB")
        // New scenes: a meadow, lotus water, red rock.
        case (.wildflower, false): return .init("F6F8EE", "FFFFFF", "2E3524", "B8461F")
        case (.wildflower, true): return .init("141A12", "202819", "E9EEDD", "FF8A5C")
        case (.lotus, false): return .init("EFF7F6", "FFFFFF", "1F3536", "B23D74")
        case (.lotus, true): return .init("0E1A1D", "18292E", "E6F0F0", "F2A2C9")
        // Night scenes: each matches its photograph's quiet centre.
        case (.nightBlossom, false): return .init("FBEFF3", "FFFFFF", "47283A", "C24A72")
        case (.nightBlossom, true): return .init("1C1218", "2A1A23", "FBE9EF", "F59AB5")
        case (.nightLotus, false): return .init("EEF3F8", "FFFFFF", "1E2E3D", "B23D74")
        case (.nightLotus, true): return .init("0A131B", "142130", "E4EDF4", "F2A2C9")
        case (.rainCanopy, false): return .init("EDF4F0", "FFFFFF", "1E3329", "2E7D57")
        case (.rainCanopy, true): return .init("0A1512", "14221D", "DDEBE3", "6FCB9F")
        case (.obsidianCoast, false): return .init("EAF4F6", "FFFFFF", "16303A", "0A7A8F")
        case (.obsidianCoast, true): return .init("061318", "0F2028", "DCEEF2", "4FC3D9")
        case (.moonlitDunes, false): return .init("F8F1E8", "FFFBF5", "45352A", "A65E2E")
        case (.moonlitDunes, true): return .init("140F0B", "211912", "F2E4D2", "D99A5B")
        case (.canyon, false): return .init("FBF0E8", "FFFFFF", "452419", "A8441B")
        case (.canyon, true): return .init("1E110C", "2E1B13", "F5E3D6", "E8743A")
        case (.custom, _): return CustomThemeColors.palette()
        case (.ghostty, _): return GhosttyThemes.selected?.palette ?? ThemeFamily.macspaces.palette(.dark)
        }
    }

    /// How strongly a Glass theme tints the blurred desktop behind the open Nook and
    /// its dock; nil for every solid theme. Clear is 0: no blur or tint at all, only
    /// the widgets and buttons over the desktop. Smoke is the dimmest.
    var glassTint: Double? {
        switch self {
        case .clear: return 0
        case .glass: return 0.22
        case .smoke: return 0.50
        case .frost: return 0.55
        case .tinted: return TintedGlassColors.strength
        case .custom: return CustomTheme.style == .glass ? CustomTheme.glassStrength : nil
        default: return nil
        }
    }

    /// Whether a Glass theme blurs the desktop behind its tint. Clear never does;
    /// Tinted leaves it to the user.
    var glassBlurs: Bool {
        switch self {
        case .clear: return false
        case .tinted: return TintedGlassColors.blurs
        case .custom: return CustomTheme.style == .glass && CustomTheme.glassBlurs
        default: return glassTint != nil
        }
    }

    /// Custom and Tinted follow their own colour rather than System/Light/Dark.
    var fixedScheme: ColorScheme? {
        switch self {
        case .custom: return CustomThemeColors.isDark(CustomThemeColors.background) ? .dark : .light
        case .tinted: return CustomThemeColors.isDark(TintedGlassColors.tint) ? .dark : .light
        case .ghostty: return GhosttyThemes.selected.map { CustomThemeColors.isDark($0.background) ? .dark : .light }
        case .frost: return .light
        case .smoke: return .dark
        default: return nil
        }
    }
    /// The themes whose colours the user picks in Appearance settings.
    var isUserColoured: Bool { self == .custom }
}

/// The three drawers in Appearance settings: Terminal (our palettes and Ghostty's in one
/// list), Live (photographs and animated scenes) and Custom.
enum ThemeCollection: String, CaseIterable, Identifiable {
    case terminal, live, custom
    var id: String { rawValue }
    /// The app's own scenes drawer carries the app's name, marked with a house in Settings.
    var title: String { self == .live ? "MacSpaces" : rawValue.capitalized }
    var subtitle: String {
        switch self {
        case .terminal: return "Noir, editor favourites and every Ghostty theme"
        case .live: return "Flowers, forests, earth, sky, night and neon, moving while the Nook is open"
        case .custom: return "Your colours: solid, two-tone, glass or a picture"
        }
    }
    var symbol: String {
        switch self {
        case .terminal: return "terminal"
        case .live: return "house"
        case .custom: return "paintbrush"
        }
    }
    /// The themes each drawer offers. Live is five rows of five in a fixed order: Bloom,
    /// Forest, Earth and water, Sky, Tech.
    var families: [ThemeFamily] {
        switch self {
        case .terminal: return ThemeFamily.ownTerminal
        case .live:
            return [.blossom, .nightBlossom, .lotus, .nightLotus, .lavender,
                    .fern, .bamboo, .firefly, .rainCanopy, .autumn,
                    .lava, .canyon, .dune, .moonlitDunes, .obsidianCoast,
                    .alpine, .thunderstorm, .moonrise, .starlight, .aurora,
                    .rainbow, .codeRain, .warp, .prism, .synthwave]
        case .custom: return [.custom]
        }
    }
    /// The photos this drawer's cards show (each once), for `MotifThumbnails.prepare`.
    var cardPhotos: [String] {
        var seen = Set<String>()
        return families.compactMap { $0.motif.flatMap { $0.floralAsset ?? $0.natureAsset } }
            .filter { seen.insert($0).inserted }
    }
    /// How many a drawer offers: Terminal also counts the Ghostty library once it's loaded.
    /// Ghostty's copies of our editor favourites (`GhosttyThemes.originals`) aren't listed twice.
    @MainActor var count: Int {
        guard self == .terminal, GhosttyThemes.count > 0 else { return families.count }
        return families.count + GhosttyThemes.count - GhosttyThemes.originals.count
    }
}

/// The Tinted glass theme (unlisted, kept for anyone using it): a chosen tint over the
/// blurred desktop, and an accent.
/// Text and tiles are derived from the tint the way Custom derives them.
enum TintedGlassColors {
    static let tintKey = "theme.tinted.tint"
    static let accentKey = "theme.tinted.accent"
    static let strengthKey = "theme.tinted.strength"
    static let blurKey = "theme.tinted.blur"
    static let defaultTint = "39414D"
    static let defaultAccent = "8AB4F8"
    static let defaultStrength = 0.35
    /// From barely coloured to nearly solid; the desktop always shows a little.
    static let strengthRange = 0.05...0.85

    /// How much of the tint covers the desktop.
    static var strength: Double {
        let saved = UserDefaults.standard.object(forKey: strengthKey) as? Double ?? defaultStrength
        return min(max(saved, strengthRange.lowerBound), strengthRange.upperBound)
    }
    /// Frosted (blurred) or perfectly clear behind the tint.
    static var blurs: Bool { UserDefaults.standard.object(forKey: blurKey) as? Bool ?? true }

    static var tint: String { CustomThemeColors.clean(UserDefaults.standard.string(forKey: tintKey)) ?? defaultTint }
    static var accent: String { CustomThemeColors.clean(UserDefaults.standard.string(forKey: accentKey)) ?? defaultAccent }
}

/// The Custom theme: a chosen background and accent. The tile colour and a
/// readable text colour are derived, so any choice keeps text at 4.5:1 or better.
enum CustomThemeColors {
    static let backgroundKey = "theme.custom.background"
    static let accentKey = "theme.custom.accent"
    /// Solid's default (`CustomTheme.Defaults.solid`); anyone who used Custom before it
    /// keeps what they had (`CustomTheme.migrateStyleDefaults`).
    static let defaultBackground = "121A2B"
    static let defaultAccent = "FFB077"

    static var background: String { clean(UserDefaults.standard.string(forKey: backgroundKey)) ?? defaultBackground }
    static var accent: String { clean(UserDefaults.standard.string(forKey: accentKey)) ?? defaultAccent }

    static func palette() -> FamilyPalette { palette(background: background, accent: accent) }

    static func palette(background bg: String, accent: String) -> FamilyPalette {
        // Pure white or black: whichever reads better. One of them always
        // reaches 4.5:1 against any background.
        let foreground = contrast(bg, "FFFFFF") >= contrast(bg, "000000") ? "FFFFFF" : "000000"
        // Tiles move a little toward the text colour, unless that would cost legibility.
        var surface = mix(bg, foreground, 0.07)
        if contrast(surface, foreground) < 4.5 { surface = mix(bg, foreground == "000000" ? "FFFFFF" : "000000", 0.07) }
        return .init(bg, surface, foreground, accent)
    }

    static func isDark(_ hex: String) -> Bool { luminance(hex) < 0.25 }

    static func clean(_ hex: String?) -> String? {
        guard let hex else { return nil }
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        return value.count == 6 && UInt32(value, radix: 16) != nil ? value : nil
    }

    static func contrast(_ a: String, _ b: String) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    static func luminance(_ hex: String) -> Double {
        let (r, g, b) = components(hex)
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private static func components(_ hex: String) -> (Double, Double, Double) {
        let v = UInt32(hex, radix: 16) ?? 0
        return (Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }

    private static func mix(_ a: String, _ b: String, _ t: Double) -> String {
        let (ar, ag, ab) = components(a), (br, bg, bb) = components(b)
        func channel(_ x: Double, _ y: Double) -> Int { Int(((x + (y - x) * t) * 255).rounded()) }
        return String(format: "%02X%02X%02X", channel(ar, br), channel(ag, bg), channel(ab, bb))
    }
}
