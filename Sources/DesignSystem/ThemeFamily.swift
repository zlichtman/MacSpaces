import SwiftUI

/// A family is selected once; appearance determines its light or dark variant.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    func scheme(systemIsDark: Bool) -> ColorScheme {
        self == .dark || (self == .system && systemIsDark) ? .dark : .light
    }
}

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
    case tidal, ember, everforest, glass, carbon, acid, cobalt
    case nord, solarized, gruvbox, tokyoNight, catppuccin, karma, monokai
    case noir, rosePine, ayu
    case parchment, copper, slate, aubergine, seafoam
    case ruby, citrine, sapphire, indigo
    // Each of these draws a scene that moves while the Nook is open.
    case blossom, lavender, sunflower, wildflower, lotus
    case fern, moss, bamboo, firefly, moonrise
    case aurora, alpine, dune, canyon
    case monsoon, thunderstorm, starlight, autumn, glacier
    case rainbow, synthwave, lava, plasma, codeRain, warp, circuit, prism, nebula
    /// The user's own background and accent (see `CustomThemeColors`).
    case custom

    /// Shared by Settings and the Nook menu. A theme appears in exactly one collection.
    static let signature: [Self] = [.macspaces, .powdermeet, .heartable, .kemosabe, .tsukumo]
    /// Every named palette outside Core, alphabetical. Custom is not a palette.
    static var palettes: [Self] {
        allCases.filter { !signature.contains($0) && $0 != .custom }.sorted { $0.title < $1.title }
    }
    var collection: ThemeCollection {
        ThemeCollection.allCases.first { $0.families.contains(self) } ?? .terminal
    }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .macspaces: return "MacSpaces"
        case .powdermeet: return "PowderMeet"
        case .heartable: return "Heartable"
        case .kemosabe: return "KemoSabe"
        case .tsukumo: return "Tsukumo"
        case .tokyoNight: return "Tokyo Night"
        case .rosePine: return "Rosé Pine"
        case .codeRain: return "Code Rain"
        // Alpine's saved id stays; it's the Snow theme now.
        case .alpine: return "Snow"
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
        "arcade": .synthwave, "parcel": .dune, "newsprint": .noir,
        "pulse": .starlight,
        // 2.72: Terminal look-alikes, and the scenes that were retired.
        "dracula": .catppuccin, "tomorrowNight": .slate, "kanagawa": .tokyoNight, "nightOwl": .indigo,
        "fireworks": .starlight, "coral": .tidal, "sandbar": .canyon,
    ]
    init?(legacy: ThemePreset) {
        switch legacy {
        case .midnight: self = .macspaces
        case .frosted: self = .glass
        case .graphite: self = .carbon
        case .ocean: self = .tidal
        case .sunset: self = .ember
        case .forest: self = .everforest
        case .solarizedDark: self = .solarized
        case .gruvboxDark: self = .gruvbox
        case .catppuccinMocha: self = .catppuccin
        case .oneDark: self = .karma
        case .custom: return nil
        default:
            guard let family = Self(rawValue: legacy.rawValue) ?? Self.replaced[legacy.rawValue] else { return nil }
            self = family
        }
    }

    func palette(_ scheme: ColorScheme) -> FamilyPalette {
        switch (self, scheme == .dark) {
        case (.macspaces, false): return .init("F0F5FC", "FFFFFF", "152238", "176BC4")
        case (.macspaces, true): return .init("020714", "0C172B", "EEF5FF", "1F8CFF")
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
        // Glass: a clear cyan, so it no longer reads as grey.
        case (.glass, false): return .init("ECF8FA", "FFFFFF", "163840", "007A88")
        case (.glass, true): return .init("08222A", "123540", "E0F6F9", "3FE0EE")
        case (.carbon, false): return .init("F2F5F4", "FFFFFF", "24332D", "087857")
        case (.carbon, true): return .init("090C0F", "1B2427", "E3ECE8", "1AE8A6")
        case (.acid, false): return .init("F4F7E9", "FCFFF4", "28331B", "4E7110")
        case (.acid, true): return .init("091105", "202B12", "EAF4D6", "A3F52E")
        case (.cobalt, false): return .init("EDF4FC", "FFFFFF", "172C47", "086C9C")
        case (.cobalt, true): return .init("061124", "142C49", "E0EEFC", "18C5F1")
        case (.nord, false): return .init("ECEFF4", "FFFFFF", "2E3440", "426782")
        case (.nord, true): return .init("2E3440", "3B4252", "ECEFF4", "88C0D0")
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
        case (.noir, false): return .init("F4F4F2", "FFFFFF", "111111", "6E6E6E")
        case (.noir, true): return .init("0B0B0C", "18181A", "F2F2F2", "E8E8E8")
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
        // New scenes: a meadow, lotus water, red rock.
        case (.wildflower, false): return .init("F6F8EE", "FFFFFF", "2E3524", "B8461F")
        case (.wildflower, true): return .init("141A12", "202819", "E9EEDD", "FF8A5C")
        case (.lotus, false): return .init("EFF7F6", "FFFFFF", "1F3536", "B23D74")
        case (.lotus, true): return .init("0E1A1D", "18292E", "E6F0F0", "F2A2C9")
        case (.canyon, false): return .init("FBF0E8", "FFFFFF", "452419", "A8441B")
        case (.canyon, true): return .init("1E110C", "2E1B13", "F5E3D6", "E8743A")
        case (.custom, _): return CustomThemeColors.palette()
        }
    }

    /// Custom follows its own background rather than System/Light/Dark.
    var fixedScheme: ColorScheme? {
        guard self == .custom else { return nil }
        return CustomThemeColors.isDark(CustomThemeColors.background) ? .dark : .light
    }
}

/// The drawers in Appearance settings and the Nook's theme menu. Every family
/// belongs to exactly one; Core is the five app themes.
enum ThemeCollection: String, CaseIterable, Identifiable {
    case core, terminal, bloom, forest, earth, water, sky, tech
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var subtitle: String {
        switch self {
        case .core: return "The MacSpaces app themes"
        case .terminal: return "Classic editor and terminal palettes, quiet single colours, and your own"
        case .bloom: return "Flowers in bloom: blossom, sunflowers, lavender, a meadow, lotus"
        case .forest: return "Ferns, moss, bamboo, fireflies and moonrise"
        case .earth: return "Embers, lava, dunes, autumn and red rock"
        case .water: return "Tides, rain, storms, snow and ice"
        case .sky: return "Auroras, starlight, nebulae, prisms and plasma"
        case .tech: return "Neon grids, circuits, code, warp speed and rainbow keys"
        }
    }
    var symbol: String {
        switch self {
        case .core: return "sparkles"
        case .terminal: return "terminal"
        case .bloom: return "camera.macro"
        case .forest: return "tree"
        case .earth: return "mountain.2"
        case .water: return "drop"
        case .sky: return "moon.stars"
        case .tech: return "cpu"
        }
    }
    /// Core keeps its fixed order. The rest run by colour: greys first, then
    /// around the colour wheel from red to pink. Custom always ends Terminal.
    var families: [ThemeFamily] {
        switch self {
        case .core: return ThemeFamily.signature
        case .terminal:
            return Self.byColour([.nord, .solarized, .gruvbox, .tokyoNight, .catppuccin, .karma, .monokai,
                                  .rosePine, .ayu, .everforest, .noir, .glass, .carbon, .cobalt, .acid,
                                  .parchment, .copper, .slate, .aubergine, .seafoam,
                                  .ruby, .citrine, .sapphire, .indigo]) + [.custom]
        case .bloom: return Self.byColour([.blossom, .sunflower, .lavender, .wildflower, .lotus])
        case .forest: return Self.byColour([.fern, .moss, .bamboo, .firefly, .moonrise])
        case .earth: return Self.byColour([.ember, .lava, .dune, .autumn, .canyon])
        case .water: return Self.byColour([.tidal, .monsoon, .thunderstorm, .alpine, .glacier])
        case .sky: return Self.byColour([.aurora, .starlight, .nebula, .prism, .plasma])
        case .tech: return Self.byColour([.synthwave, .circuit, .codeRain, .warp, .rainbow])
        }
    }

    /// Orders themes by their dark accent: near-greys by lightness, then by hue from red.
    static func byColour(_ families: [ThemeFamily]) -> [ThemeFamily] {
        func key(_ family: ThemeFamily) -> (Int, Double, String) {
            let hex = UInt32(family.palette(.dark).accent, radix: 16) ?? 0
            let r = Double((hex >> 16) & 255) / 255, g = Double((hex >> 8) & 255) / 255, b = Double(hex & 255) / 255
            let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
            let saturation = maxC == 0 ? 0 : delta / maxC
            guard saturation > 0.18 else { return (0, maxC, family.rawValue) }
            var hue: Double
            if maxC == r { hue = (g - b) / delta } else if maxC == g { hue = (b - r) / delta + 2 } else { hue = (r - g) / delta + 4 }
            hue = (hue / 6).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            // Pinks close to red wrap to the end, after purple.
            if hue > 0.97 { hue -= 1 }
            return (1, hue, family.rawValue)
        }
        return families.sorted { key($0) < key($1) }
    }
}

/// The Custom theme: a chosen background and accent. The tile colour and a
/// readable text colour are derived, so any choice keeps text at 4.5:1 or better.
enum CustomThemeColors {
    static let backgroundKey = "theme.custom.background"
    static let accentKey = "theme.custom.accent"
    static let defaultBackground = "1B2230"
    static let defaultAccent = "7C9CFF"

    static var background: String { clean(UserDefaults.standard.string(forKey: backgroundKey)) ?? defaultBackground }
    static var accent: String { clean(UserDefaults.standard.string(forKey: accentKey)) ?? defaultAccent }

    static func palette() -> FamilyPalette {
        let bg = background
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
