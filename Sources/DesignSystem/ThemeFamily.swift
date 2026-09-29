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

    /// Shared by Settings and the Nook menu. A theme appears in exactly one collection.
    static let signature: [Self] = [.macspaces, .powdermeet, .heartable, .kemosabe, .tsukumo]
    static var palettes: [Self] {
        allCases.filter { !signature.contains($0) }.sorted { $0.title < $1.title }
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
        }
    }
}
