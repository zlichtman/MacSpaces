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
    case dracula, nord, solarized, gruvbox, tokyoNight, catppuccin, karma, monokai
    case noir, rosePine, kanagawa, ayu
    // Nature (2.38)
    case blossom, lavender, aurora, alpine, moss, sunflower, coral, dune
    // Sweets (2.38)
    case bubblegum, matcha, strawberryMilk, lemonDrop, cottonCandy
    // Studio (2.38): original names that only evoke familiar apps and places.
    case encore, matinee, barista, arcade, parcel, newsprint
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
        case .strawberryMilk: return "Strawberry Milk"
        case .lemonDrop: return "Lemon Drop"
        case .cottonCandy: return "Cotton Candy"
        default: return rawValue.capitalized
        }
    }
    /// Reads a saved family. One Dark was replaced by Karma in 2.38, so a
    /// saved One Dark opens as Karma instead of falling back to the default.
    init?(saved rawValue: String) {
        if rawValue == "oneDark" { self = .karma; return }
        self.init(rawValue: rawValue)
    }
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
            guard let family = Self(rawValue: legacy.rawValue) else { return nil }
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
        case (.glass, false): return .init("EDF5F8", "FFFFFF", "20343E", "007D99")
        case (.glass, true): return .init("15252E", "243A46", "E4F2F7", "74CDE2")
        case (.carbon, false): return .init("F2F5F4", "FFFFFF", "24332D", "087857")
        case (.carbon, true): return .init("090C0F", "1B2427", "E3ECE8", "1AE8A6")
        case (.acid, false): return .init("F4F7E9", "FCFFF4", "28331B", "4E7110")
        case (.acid, true): return .init("091105", "202B12", "EAF4D6", "A3F52E")
        case (.cobalt, false): return .init("EDF4FC", "FFFFFF", "172C47", "086C9C")
        case (.cobalt, true): return .init("061124", "142C49", "E0EEFC", "18C5F1")
        case (.dracula, false): return .init("F5F1FA", "FFFFFF", "342F43", "7950AD")
        case (.dracula, true): return .init("282A36", "343746", "F8F8F2", "BD93F9")
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
        case (.kanagawa, false): return .init("F2ECBC", "E7DBA0", "545464", "4D699B")
        case (.kanagawa, true): return .init("1F1F28", "2A2A37", "DCD7BA", "7E9CD8")
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
        case (.coral, false): return .init("FFF4F0", "FFFFFF", "44282A", "D2553F")
        case (.coral, true): return .init("1B1416", "2A1E20", "FCEAE6", "FF8A70")
        case (.dune, false): return .init("FAF3E8", "FFFBF4", "45352A", "B3643A")
        case (.dune, true): return .init("1E1712", "2C221A", "F4E7D8", "E59A63")
        // Sweets
        case (.bubblegum, false): return .init("FFF0F7", "FFFFFF", "4A2440", "E0489A")
        case (.bubblegum, true): return .init("22121C", "321B2A", "FDE6F2", "FF7CC0")
        case (.matcha, false): return .init("F3F6EC", "FFFFFF", "2F3A2A", "5E8A3A")
        case (.matcha, true): return .init("171C14", "222A1D", "E8F0DC", "A8D478")
        case (.strawberryMilk, false): return .init("FFF2F2", "FFFFFF", "4B2A2E", "D9435A")
        case (.strawberryMilk, true): return .init("231517", "332022", "FDE8EA", "FF8095")
        case (.lemonDrop, false): return .init("FFFCE8", "FFFFFF", "3B3616", "A68A00")
        case (.lemonDrop, true): return .init("1C1A0C", "2A2713", "F8F3D4", "F5DC4A")
        case (.cottonCandy, false): return .init("F3F2FF", "FFFFFF", "34305A", "C04FB0")
        case (.cottonCandy, true): return .init("181628", "24213A", "ECEAFF", "F0A6E0")
        // Studio
        case (.encore, false): return .init("F4F7F4", "FFFFFF", "1C2A20", "138A3E")
        case (.encore, true): return .init("0B0D0C", "181C19", "E8F0EA", "2BD968")
        case (.matinee, false): return .init("FAF4F3", "FFFFFF", "2E1E1E", "C21F2A")
        case (.matinee, true): return .init("0E0A0A", "1C1515", "F4E9E8", "E5262F")
        case (.barista, false): return .init("F6F1E7", "FFFCF6", "2B2A22", "1E6B4C")
        case (.barista, true): return .init("14201A", "1D2D25", "EDE6D6", "D8B77A")
        case (.arcade, false): return .init("F2F1FB", "FFFFFF", "2A2748", "5B4FE0")
        case (.arcade, true): return .init("16152B", "222040", "E9E8FF", "8B7CFF")
        case (.parcel, false): return .init("F6F1EA", "FFFFFF", "35281E", "8A5A2B")
        case (.parcel, true): return .init("1C150F", "2A2018", "F1E6D8", "F2B233")
        case (.newsprint, false): return .init("F4F1EA", "FAF8F2", "1C1B19", "B3261E")
        case (.newsprint, true): return .init("141414", "1F1F1F", "EDEAE3", "E4574B")
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
    case core, terminal, nature, sweets, studio
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var subtitle: String {
        switch self {
        case .core: return "The MacSpaces app themes"
        case .terminal: return "Classic editor and terminal palettes, and your own colours"
        case .nature: return "Flowers, skies, mountains and the sea"
        case .sweets: return "Soft, sugary pastels"
        case .studio: return "Inspired by familiar apps, screens and shops"
        }
    }
    var symbol: String {
        switch self {
        case .core: return "sparkles"
        case .terminal: return "terminal"
        case .nature: return "leaf"
        case .sweets: return "birthday.cake"
        case .studio: return "paintbrush"
        }
    }
    var families: [ThemeFamily] {
        switch self {
        case .core: return ThemeFamily.signature
        case .terminal:
            let named: [ThemeFamily] = [.dracula, .nord, .solarized, .gruvbox, .tokyoNight, .catppuccin,
                                        .karma, .monokai, .noir, .rosePine, .kanagawa, .ayu, .everforest]
            return named.sorted { $0.title < $1.title } + [.custom]
        case .nature: return [.blossom, .lavender, .aurora, .alpine, .moss, .sunflower, .coral, .dune, .tidal, .ember]
        case .sweets: return [.bubblegum, .matcha, .strawberryMilk, .lemonDrop, .cottonCandy]
        case .studio: return [.encore, .matinee, .barista, .arcade, .parcel, .newsprint, .glass, .carbon, .acid, .cobalt]
        }
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
