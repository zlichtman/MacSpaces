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
    case dracula, nord, solarized, gruvbox, tokyoNight, catppuccin, oneDark, monokai
    case noir, rosePine, kanagawa, ayu
    /// The user's own background and accent (see `CustomThemeColors`).
    case custom

    /// Shared by Settings and the Nook menu. A theme appears in exactly one collection.
    static let signature: [Self] = [.macspaces, .powdermeet, .heartable, .kemosabe, .tsukumo]
    /// Named palettes, alphabetical. Custom is offered after them, on its own.
    static var palettes: [Self] {
        allCases.filter { !signature.contains($0) && $0 != .custom }.sorted { $0.title < $1.title }
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
        case .oneDark: return "One Dark"
        case .rosePine: return "Rosé Pine"
        default: return rawValue.capitalized
        }
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
        case (.oneDark, false): return .init("F2F4F7", "FFFFFF", "303744", "236BA4")
        case (.oneDark, true): return .init("282C34", "333842", "D7DAE0", "61AFEF")
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
        case (.custom, _): return CustomThemeColors.palette()
        }
    }

    /// Custom follows its own background rather than System/Light/Dark.
    var fixedScheme: ColorScheme? {
        guard self == .custom else { return nil }
        return CustomThemeColors.isDark(CustomThemeColors.background) ? .dark : .light
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
