import SwiftUI
import AppKit
import Combine

enum ThemePreset: String, Codable, CaseIterable, Identifiable {
    case midnight
    case frosted
    case graphite
    case ocean
    case sunset
    case acid
    case cobalt
    case forest
    case dracula
    case nord
    case solarizedDark
    case gruvboxDark
    case tokyoNight
    case catppuccinMocha
    case oneDark
    case monokai
    case custom

    var id: String { rawValue }

    static let macSpacesPresets: [ThemePreset] = [
        .midnight, .frosted, .graphite, .ocean, .sunset, .acid, .cobalt, .forest,
    ]

    static let terminalPresets: [ThemePreset] = [
        .dracula, .nord, .solarizedDark, .gruvboxDark,
        .tokyoNight, .catppuccinMocha, .oneDark, .monokai,
    ]

    var title: String {
        switch self {
        case .midnight: return "Midnight"
        case .frosted: return "Glass"
        case .graphite: return "Carbon"
        case .ocean: return "Tidal"
        case .sunset: return "Ember"
        case .acid: return "Acid"
        case .cobalt: return "Cobalt"
        case .forest: return "Forest"
        case .dracula: return "Dracula"
        case .nord: return "Nord"
        case .solarizedDark: return "Solarized Dark"
        case .gruvboxDark: return "Gruvbox Dark"
        case .tokyoNight: return "Tokyo Night"
        case .catppuccinMocha: return "Catppuccin"
        case .oneDark: return "One Dark"
        case .monokai: return "Monokai"
        case .custom: return "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .midnight: return "moon.stars.fill"
        case .frosted: return "circle.dotted"
        case .graphite: return "square.3.layers.3d"
        case .ocean: return "water.waves"
        case .sunset: return "flame.fill"
        case .acid: return "bolt.fill"
        case .cobalt: return "drop.fill"
        case .forest: return "leaf.fill"
        case .dracula: return "moon.haze.fill"
        case .nord: return "snowflake"
        case .solarizedDark: return "sun.haze.fill"
        case .gruvboxDark: return "shippingbox.fill"
        case .tokyoNight: return "building.2.fill"
        case .catppuccinMocha: return "cup.and.saucer.fill"
        case .oneDark: return "chevron.left.forwardslash.chevron.right"
        case .monokai: return "terminal.fill"
        case .custom: return "paintpalette.fill"
        }
    }

    var recommendedAccent: AccentChoice {
        switch self {
        case .midnight: return .blue
        case .frosted: return .cyan
        case .graphite: return .mint
        case .ocean: return .cyan
        case .sunset: return .orange
        case .acid: return .lime
        case .cobalt: return .cyan
        case .forest: return .mint
        case .dracula, .nord, .solarizedDark, .gruvboxDark,
             .tokyoNight, .catppuccinMocha, .oneDark, .monokai:
            return .custom
        case .custom: return .custom
        }
    }

    /// Canonical accent colors from familiar terminal/editor palettes.
    var terminalAccentHex: String? {
        switch self {
        case .dracula: return "#BD93F9"
        case .nord: return "#88C0D0"
        case .solarizedDark: return "#2AA198"
        case .gruvboxDark: return "#FABD2F"
        case .tokyoNight: return "#7AA2F7"
        case .catppuccinMocha: return "#CBA6F7"
        case .oneDark: return "#61AFEF"
        case .monokai: return "#A6E22E"
        default: return nil
        }
    }

    var previewColor: Color {
        if let terminalAccentHex {
            return Color(themeHex: terminalAccentHex) ?? .accentColor
        }
        return recommendedAccent == .custom ? .accentColor : recommendedAccent.color
    }

    var previewSwatches: [Color] {
        let hexes: [String]
        switch self {
        case .midnight: hexes = ["#020714", "#0A2952", "#1F8CFF"]
        case .frosted: hexes = ["#DCE8F2", "#74B9D1", "#0DD4F5"]
        case .graphite: hexes = ["#090C0F", "#343B42", "#1AE8A6"]
        case .ocean: hexes = ["#021D2A", "#006B8F", "#0DD4F5"]
        case .sunset: hexes = ["#240606", "#B82106", "#FF7A1F"]
        case .acid: hexes = ["#091105", "#557A08", "#A3F52E"]
        case .cobalt: hexes = ["#061124", "#174B91", "#18C5F1"]
        case .forest: hexes = ["#06140F", "#176B4F", "#1AE8A6"]
        case .dracula: hexes = ["#282A36", "#6272A4", "#BD93F9"]
        case .nord: hexes = ["#2E3440", "#5E81AC", "#88C0D0"]
        case .solarizedDark: hexes = ["#002B36", "#586E75", "#2AA198"]
        case .gruvboxDark: hexes = ["#282828", "#665C54", "#FABD2F"]
        case .tokyoNight: hexes = ["#1A1B26", "#414868", "#7AA2F7"]
        case .catppuccinMocha: hexes = ["#1E1E2E", "#585B70", "#CBA6F7"]
        case .oneDark: hexes = ["#282C34", "#4B5263", "#61AFEF"]
        case .monokai: hexes = ["#272822", "#75715E", "#A6E22E"]
        case .custom: return [previewColor.opacity(0.32), previewColor.opacity(0.68), previewColor]
        }
        return hexes.map { Color(themeHex: $0) ?? .accentColor }
    }
}

enum ThemeSurface {
    case notch, dock

    var other: ThemeSurface { self == .notch ? .dock : .notch }
    var title: String { self == .notch ? "OpenNotch" : "OpenDock" }
}

enum AccentChoice: String, Codable, CaseIterable, Identifiable {
    case blue
    case cyan
    case indigo
    case mint
    case lime
    case orange
    case coral
    case pink
    case violet
    case custom

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: return Color(red: 0.12, green: 0.55, blue: 1.0)
        case .cyan: return Color(red: 0.05, green: 0.83, blue: 0.96)
        case .indigo: return Color(red: 0.35, green: 0.42, blue: 1.0)
        case .mint: return Color(red: 0.10, green: 0.91, blue: 0.65)
        case .lime: return Color(red: 0.64, green: 0.96, blue: 0.18)
        case .orange: return Color(red: 1.0, green: 0.48, blue: 0.12)
        case .coral: return Color(red: 1.0, green: 0.30, blue: 0.24)
        case .pink: return Color(red: 1.0, green: 0.25, blue: 0.55)
        case .violet: return Color(red: 0.62, green: 0.34, blue: 1.0)
        case .custom: return .accentColor
        }
    }
}

/// A widget material system independent from the selected color palette.
enum WidgetVisualStyle: String, Codable, CaseIterable, Identifiable {
    case studio, glass, terminal, soft, signal, orbit, mono, frame

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studio: return "Classic"
        case .glass: return "Glass"
        case .terminal: return "Terminal"
        case .soft: return "Soft"
        case .signal: return "Signal"
        case .orbit: return "Orbit"
        case .mono: return "Mono"
        case .frame: return "Frame"
        }
    }

    var subtitle: String {
        switch self {
        case .studio: return "Clean, balanced, and familiar"
        case .glass: return "Translucent with an inner highlight"
        case .terminal: return "Crisp edges and high-information contrast"
        case .soft: return "Rounder, warmer, and more playful"
        case .signal: return "A compact broadcast-inspired layout"
        case .orbit: return "Circular time and progress geometry"
        case .mono: return "Flat monochrome blocks with editorial type"
        case .frame: return "Open negative space with a precise inset edge"
        }
    }

    var symbol: String {
        switch self {
        case .studio: return "square.3.layers.3d.top.filled"
        case .glass: return "circle.dotted"
        case .terminal: return "terminal.fill"
        case .soft: return "sparkles"
        case .signal: return "waveform"
        case .orbit: return "circle.circle"
        case .mono: return "circle.lefthalf.filled"
        case .frame: return "square.dashed"
        }
    }

    /// Corner radius for widget chrome rendered in this style.
    var chromeRadius: CGFloat {
        switch self {
        case .studio: return 16
        case .glass: return 18
        case .terminal: return 8
        case .soft: return 22
        case .signal: return 13
        case .orbit: return 24
        case .mono: return 10
        case .frame: return 12
        }
    }

    static func styles(for kind: NookWidgetKind) -> [WidgetVisualStyle] {
        switch kind {
        case .media:
            return [.studio, .glass, .terminal, .signal, .mono, .frame]
        case .clock, .timer:
            return [.studio, .glass, .terminal, .orbit, .mono, .frame]
        default:
            return [.studio, .glass, .terminal, .soft, .mono, .frame]
        }
    }

    static func styles(for kind: WidgetKind) -> [WidgetVisualStyle] {
        switch kind {
        case .nowPlaying, .audio:
            return [.studio, .glass, .terminal, .signal, .mono, .frame]
        case .clock, .pomodoro:
            return [.studio, .glass, .terminal, .orbit, .mono, .frame]
        default:
            return [.studio, .glass, .terminal, .soft, .mono, .frame]
        }
    }
}

struct ThemeTokens {
    let surface: Color
    let surfaceSecondary: Color
    let tile: Color
    let tileSecondary: Color
    let control: Color
    let selected: Color
    let border: Color
    let shadow: Color
    let glow: Color
    let accent: Color
    let secondaryAccent: Color
    let colorScheme: ColorScheme

    var surfaceGradient: LinearGradient {
        LinearGradient(
            colors: [surfaceSecondary, surface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var tileGradient: LinearGradient {
        LinearGradient(
            colors: [tileSecondary, tile],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published var notchPreset: ThemePreset {
        didSet { defaults.set(notchPreset.rawValue, forKey: Keys.notchPreset) }
    }
    @Published var dockPreset: ThemePreset {
        didSet { defaults.set(dockPreset.rawValue, forKey: Keys.dockPreset) }
    }
    @Published var accentChoice: AccentChoice {
        didSet { defaults.set(accentChoice.rawValue, forKey: Keys.accentChoice) }
    }
    @Published var customAccentHex: String {
        didSet { defaults.set(customAccentHex, forKey: Keys.customAccentHex) }
    }
    @Published var customNotchHex: String {
        didSet { defaults.set(customNotchHex, forKey: Keys.customNotchHex) }
    }
    @Published var customDockHex: String {
        didSet { defaults.set(customDockHex, forKey: Keys.customDockHex) }
    }
    @Published var notchOpacity: Double {
        didSet { defaults.set(notchOpacity, forKey: Keys.notchOpacity) }
    }
    @Published var dockOpacity: Double {
        didSet { defaults.set(dockOpacity, forKey: Keys.dockOpacity) }
    }
    @Published var notchCornerRadius: Double {
        didSet { defaults.set(notchCornerRadius, forKey: Keys.notchCornerRadius) }
    }
    @Published var notchEdgeWidth: Double {
        didSet { defaults.set(notchEdgeWidth, forKey: Keys.notchEdgeWidth) }
    }
    @Published var notchEdgeStrength: Double {
        didSet { defaults.set(notchEdgeStrength, forKey: Keys.notchEdgeStrength) }
    }
    @Published var dockCornerRadius: Double {
        didSet { defaults.set(dockCornerRadius, forKey: Keys.dockCornerRadius) }
    }
    @Published var themeIntensity: Double {
        didSet { defaults.set(themeIntensity, forKey: Keys.themeIntensity) }
    }
    @Published var tileContrast: Double {
        didSet { defaults.set(tileContrast, forKey: Keys.tileContrast) }
    }
    @Published var glowStrength: Double {
        didSet { defaults.set(glowStrength, forKey: Keys.glowStrength) }
    }
    @Published var notchThemeIntensity: Double {
        didSet { defaults.set(notchThemeIntensity, forKey: Keys.notchThemeIntensity) }
    }
    @Published var dockThemeIntensity: Double {
        didSet { defaults.set(dockThemeIntensity, forKey: Keys.dockThemeIntensity) }
    }
    @Published var notchTileContrast: Double {
        didSet { defaults.set(notchTileContrast, forKey: Keys.notchTileContrast) }
    }
    @Published var dockTileContrast: Double {
        didSet { defaults.set(dockTileContrast, forKey: Keys.dockTileContrast) }
    }
    @Published var notchGlowStrength: Double {
        didSet { defaults.set(notchGlowStrength, forKey: Keys.notchGlowStrength) }
    }
    @Published var dockGlowStrength: Double {
        didSet { defaults.set(dockGlowStrength, forKey: Keys.dockGlowStrength) }
    }
    @Published var gradientSurfaces: Bool {
        didSet { defaults.set(gradientSurfaces, forKey: Keys.gradientSurfaces) }
    }
    @Published var compactControls: Bool {
        didSet { defaults.set(compactControls, forKey: Keys.compactControls) }
    }
    /// The in-app opt-in. Read `reduceMotion` rather than this, so the system
    /// accessibility setting is honoured even when the app toggle is off.
    @Published var reduceMotionPreference: Bool {
        didSet { defaults.set(reduceMotionPreference, forKey: Keys.reduceMotion) }
    }

    @Published private(set) var systemReduceMotion: Bool =
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var reduceMotion: Bool { reduceMotionPreference || systemReduceMotion }

    @Published var widgetVisualStyle: WidgetVisualStyle {
        didSet { defaults.set(widgetVisualStyle.rawValue, forKey: Keys.widgetVisualStyle) }
    }

    private enum Keys {
        static let schemaVersion = "theme.schemaVersion"
        static let widgetVisualStyle = "theme.widgetVisualStyle"
        static let notchPreset = "theme.notchPreset"
        static let dockPreset = "theme.dockPreset"
        static let accentChoice = "theme.accentChoice"
        static let customAccentHex = "theme.customAccentHex"
        static let customNotchHex = "theme.customNotchHex"
        static let customDockHex = "theme.customDockHex"
        static let notchOpacity = "theme.notchOpacity"
        static let dockOpacity = "theme.dockOpacity"
        static let notchCornerRadius = "theme.notchCornerRadius"
        static let notchEdgeWidth = "theme.notchEdgeWidth"
        static let notchEdgeStrength = "theme.notchEdgeStrength"
        static let dockCornerRadius = "theme.dockCornerRadius"
        static let themeIntensity = "theme.intensity"
        static let tileContrast = "theme.tileContrast"
        static let glowStrength = "theme.glowStrength"
        static let notchThemeIntensity = "theme.notchIntensity"
        static let dockThemeIntensity = "theme.dockIntensity"
        static let notchTileContrast = "theme.notchTileContrast"
        static let dockTileContrast = "theme.dockTileContrast"
        static let notchGlowStrength = "theme.notchGlowStrength"
        static let dockGlowStrength = "theme.dockGlowStrength"
        static let gradientSurfaces = "theme.gradientSurfaces"
        static let compactControls = "theme.compactControls"
        static let reduceMotion = "theme.reduceMotion"
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Keys.notchPreset: ThemePreset.midnight.rawValue,
            Keys.dockPreset: ThemePreset.midnight.rawValue,
            Keys.accentChoice: AccentChoice.blue.rawValue,
            Keys.customAccentHex: "#20E6A4",
            Keys.customNotchHex: "#101416",
            Keys.customDockHex: "#12191A",
            Keys.notchOpacity: 0.98,
            Keys.dockOpacity: 0.92,
            Keys.notchCornerRadius: 22.0,
            Keys.notchEdgeWidth: 1.4,
            Keys.notchEdgeStrength: 0.78,
            Keys.dockCornerRadius: 20.0,
            Keys.themeIntensity: 0.82,
            Keys.tileContrast: 0.72,
            Keys.glowStrength: 0.0,
            Keys.notchThemeIntensity: 0.82,
            Keys.dockThemeIntensity: 0.82,
            Keys.notchTileContrast: 0.72,
            Keys.dockTileContrast: 0.72,
            Keys.notchGlowStrength: 0.0,
            Keys.dockGlowStrength: 0.0,
            Keys.gradientSurfaces: true,
            Keys.compactControls: false,
            Keys.reduceMotion: false,
            Keys.widgetVisualStyle: WidgetVisualStyle.studio.rawValue,
        ])

        // Pre-release builds intentionally converge once on the shipped
        // Midnight + blue identity. Later user palette choices are preserved.
        if defaults.integer(forKey: Keys.schemaVersion) < 4 {
            defaults.set(ThemePreset.midnight.rawValue, forKey: Keys.notchPreset)
            defaults.set(ThemePreset.midnight.rawValue, forKey: Keys.dockPreset)
            defaults.set(AccentChoice.blue.rawValue, forKey: Keys.accentChoice)
            defaults.set(0.82, forKey: Keys.themeIntensity)
            defaults.set(0.72, forKey: Keys.tileContrast)
            defaults.set(0.24, forKey: Keys.glowStrength)
            defaults.set(true, forKey: Keys.gradientSurfaces)
            defaults.set(4, forKey: Keys.schemaVersion)
        }

        // Ambient glow is an optional flourish, not baseline chrome. Earlier
        // builds persisted 24% as their default, so migrate only that exact
        // untouched value while preserving any value the user chose.
        if defaults.integer(forKey: Keys.schemaVersion) < 5 {
            for key in [
                Keys.glowStrength,
                Keys.notchGlowStrength,
                Keys.dockGlowStrength,
            ] where abs(defaults.double(forKey: key) - 0.24) < 0.000_1 {
                defaults.set(0.0, forKey: key)
            }
            defaults.set(5, forKey: Keys.schemaVersion)
        }

        notchPreset = ThemePreset(rawValue: defaults.string(forKey: Keys.notchPreset) ?? "") ?? .midnight
        dockPreset = ThemePreset(rawValue: defaults.string(forKey: Keys.dockPreset) ?? "") ?? .midnight
        accentChoice = AccentChoice(rawValue: defaults.string(forKey: Keys.accentChoice) ?? "") ?? .blue
        customAccentHex = defaults.string(forKey: Keys.customAccentHex) ?? "#20E6A4"
        customNotchHex = defaults.string(forKey: Keys.customNotchHex) ?? "#101416"
        customDockHex = defaults.string(forKey: Keys.customDockHex) ?? "#12191A"
        notchOpacity = max(defaults.double(forKey: Keys.notchOpacity), 0.84)
        dockOpacity = max(defaults.double(forKey: Keys.dockOpacity), 0.72)
        notchCornerRadius = defaults.double(forKey: Keys.notchCornerRadius)
        notchEdgeWidth = defaults.double(forKey: Keys.notchEdgeWidth)
        notchEdgeStrength = defaults.double(forKey: Keys.notchEdgeStrength)
        dockCornerRadius = defaults.double(forKey: Keys.dockCornerRadius)
        themeIntensity = defaults.double(forKey: Keys.themeIntensity)
        tileContrast = defaults.double(forKey: Keys.tileContrast)
        glowStrength = defaults.double(forKey: Keys.glowStrength)
        notchThemeIntensity = defaults.double(forKey: Keys.notchThemeIntensity)
        dockThemeIntensity = defaults.double(forKey: Keys.dockThemeIntensity)
        notchTileContrast = defaults.double(forKey: Keys.notchTileContrast)
        dockTileContrast = defaults.double(forKey: Keys.dockTileContrast)
        notchGlowStrength = defaults.double(forKey: Keys.notchGlowStrength)
        dockGlowStrength = defaults.double(forKey: Keys.dockGlowStrength)
        gradientSurfaces = defaults.bool(forKey: Keys.gradientSurfaces)
        compactControls = defaults.bool(forKey: Keys.compactControls)
        reduceMotionPreference = defaults.bool(forKey: Keys.reduceMotion)
        widgetVisualStyle = WidgetVisualStyle(rawValue: defaults.string(forKey: Keys.widgetVisualStyle) ?? "") ?? .studio

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.systemReduceMotion =
                    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }

    var accent: Color {
        if accentChoice == .custom {
            return Color(themeHex: customAccentHex) ?? AccentChoice.mint.color
        }
        return accentChoice.color
    }

    var notch: ThemeTokens {
        tokens(for: notchPreset, opacity: notchOpacity, customHex: customNotchHex, isNotch: true)
    }

    var dock: ThemeTokens {
        tokens(for: dockPreset, opacity: dockOpacity, customHex: customDockHex, isNotch: false)
    }

    func preset(for surface: ThemeSurface) -> ThemePreset {
        surface == .notch ? notchPreset : dockPreset
    }

    func setPreset(_ preset: ThemePreset, for surface: ThemeSurface) {
        if surface == .notch {
            notchPreset = preset
        } else {
            dockPreset = preset
        }
    }

    func applyCoordinatedPreset(_ preset: ThemePreset) {
        notchPreset = preset
        dockPreset = preset
        if let terminalAccentHex = preset.terminalAccentHex {
            customAccentHex = terminalAccentHex
            accentChoice = .custom
        } else if preset != .custom {
            accentChoice = preset.recommendedAccent
        }
    }

    func reset() {
        notchPreset = .midnight
        dockPreset = .midnight
        accentChoice = .blue
        customAccentHex = "#20E6A4"
        customNotchHex = "#101416"
        customDockHex = "#12191A"
        notchOpacity = 0.98
        dockOpacity = 0.92
        notchCornerRadius = 22
        notchEdgeWidth = 1.4
        notchEdgeStrength = 0.78
        dockCornerRadius = 20
        themeIntensity = 0.82
        tileContrast = 0.72
        glowStrength = 0
        notchThemeIntensity = 0.82
        dockThemeIntensity = 0.82
        notchTileContrast = 0.72
        dockTileContrast = 0.72
        notchGlowStrength = 0
        dockGlowStrength = 0
        gradientSurfaces = true
        compactControls = false
        reduceMotionPreference = false
        widgetVisualStyle = .studio
    }

    /// Resets one surface without silently changing the other surface's
    /// palette. Widget looks remain profile-owned and are reset with the
    /// corresponding profile store.
    func reset(_ surface: ThemeSurface) {
        switch surface {
        case .notch:
            notchPreset = .midnight
            customNotchHex = "#101416"
            notchOpacity = 0.98
            notchCornerRadius = 22
            notchEdgeWidth = 1.4
            notchEdgeStrength = 0.78
            notchThemeIntensity = 0.82
            notchTileContrast = 0.72
            notchGlowStrength = 0
        case .dock:
            dockPreset = .midnight
            customDockHex = "#12191A"
            dockOpacity = 0.92
            dockCornerRadius = 20
            dockThemeIntensity = 0.82
            dockTileContrast = 0.72
            dockGlowStrength = 0
        }
    }

    private func tokens(
        for preset: ThemePreset,
        opacity: Double,
        customHex: String,
        isNotch: Bool
    ) -> ThemeTokens {
        let minimumOpacity = isNotch ? 0.84 : 0.72
        let safeOpacity = min(max(opacity, minimumOpacity), 1.0)
        let intensity = min(
            max(isNotch ? notchThemeIntensity : dockThemeIntensity, 0),
            1
        )
        let contrast = min(
            max(isNotch ? notchTileContrast : dockTileContrast, 0),
            1
        )
        let glowAmount = min(
            max(isNotch ? notchGlowStrength : dockGlowStrength, 0),
            1
        )
        let base: Color
        let colorWash: Color
        let palette: Color
        let scheme: ColorScheme

        switch preset {
        case .midnight:
            base = Color(red: 0.008, green: 0.014, blue: 0.026)
            colorWash = Color(red: 0.02, green: 0.10, blue: 0.20)
            palette = AccentChoice.blue.color
            scheme = .dark
        case .frosted:
            base = Color(nsColor: .windowBackgroundColor)
            colorWash = AccentChoice.cyan.color
            palette = AccentChoice.cyan.color
            scheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        case .graphite:
            base = Color(red: 0.055, green: 0.065, blue: 0.07)
            colorWash = Color(red: 0.04, green: 0.22, blue: 0.17)
            palette = AccentChoice.mint.color
            scheme = .dark
        case .ocean:
            base = Color(red: 0.008, green: 0.075, blue: 0.11)
            colorWash = Color(red: 0.0, green: 0.42, blue: 0.56)
            palette = AccentChoice.cyan.color
            scheme = .dark
        case .sunset:
            base = Color(red: 0.14, green: 0.025, blue: 0.025)
            colorWash = Color(red: 0.72, green: 0.13, blue: 0.025)
            palette = AccentChoice.orange.color
            scheme = .dark
        case .acid:
            base = Color(red: 0.025, green: 0.038, blue: 0.018)
            colorWash = Color(red: 0.33, green: 0.56, blue: 0.02)
            palette = AccentChoice.lime.color
            scheme = .dark
        case .cobalt:
            base = Color(red: 0.018, green: 0.04, blue: 0.15)
            colorWash = Color(red: 0.035, green: 0.25, blue: 0.74)
            palette = AccentChoice.cyan.color
            scheme = .dark
        case .forest:
            base = Color(red: 0.012, green: 0.07, blue: 0.045)
            colorWash = Color(red: 0.025, green: 0.38, blue: 0.20)
            palette = AccentChoice.mint.color
            scheme = .dark
        case .dracula:
            base = Color(themeHex: "#282A36") ?? .black
            colorWash = Color(themeHex: "#44475A") ?? .gray
            palette = Color(themeHex: "#BD93F9") ?? AccentChoice.violet.color
            scheme = .dark
        case .nord:
            base = Color(themeHex: "#2E3440") ?? .black
            colorWash = Color(themeHex: "#3B4252") ?? .gray
            palette = Color(themeHex: "#88C0D0") ?? AccentChoice.cyan.color
            scheme = .dark
        case .solarizedDark:
            base = Color(themeHex: "#002B36") ?? .black
            colorWash = Color(themeHex: "#073642") ?? .gray
            palette = Color(themeHex: "#2AA198") ?? AccentChoice.mint.color
            scheme = .dark
        case .gruvboxDark:
            base = Color(themeHex: "#282828") ?? .black
            colorWash = Color(themeHex: "#3C3836") ?? .gray
            palette = Color(themeHex: "#FABD2F") ?? AccentChoice.orange.color
            scheme = .dark
        case .tokyoNight:
            base = Color(themeHex: "#1A1B26") ?? .black
            colorWash = Color(themeHex: "#24283B") ?? .gray
            palette = Color(themeHex: "#7AA2F7") ?? AccentChoice.blue.color
            scheme = .dark
        case .catppuccinMocha:
            base = Color(themeHex: "#1E1E2E") ?? .black
            colorWash = Color(themeHex: "#313244") ?? .gray
            palette = Color(themeHex: "#CBA6F7") ?? AccentChoice.violet.color
            scheme = .dark
        case .oneDark:
            base = Color(themeHex: "#282C34") ?? .black
            colorWash = Color(themeHex: "#353B45") ?? .gray
            palette = Color(themeHex: "#61AFEF") ?? AccentChoice.blue.color
            scheme = .dark
        case .monokai:
            base = Color(themeHex: "#272822") ?? .black
            colorWash = Color(themeHex: "#3E3D32") ?? .gray
            palette = Color(themeHex: "#A6E22E") ?? AccentChoice.lime.color
            scheme = .dark
        case .custom:
            base = Color(themeHex: customHex) ?? Color.black
            colorWash = accent
            palette = accent
            scheme = .dark
        }

        let washOpacity = gradientSurfaces ? (0.10 + 0.42 * intensity) : 0
        let tileOpacity = (isNotch ? 0.055 : 0.065) + 0.25 * contrast * intensity
        return ThemeTokens(
            surface: base.opacity(safeOpacity),
            surfaceSecondary: colorWash.opacity(safeOpacity * washOpacity),
            tile: palette.opacity(tileOpacity),
            tileSecondary: Color.white.opacity(0.035 + 0.07 * contrast),
            control: palette.opacity(0.055 + 0.13 * intensity),
            selected: palette.opacity(0.20 + 0.28 * intensity),
            border: palette.opacity(0.13 + 0.24 * intensity),
            shadow: Color.black.opacity(preset == .frosted ? 0.22 : 0.46),
            glow: palette.opacity(0.5 * glowAmount),
            accent: palette,
            secondaryAccent: palette,
            colorScheme: scheme
        )
    }
}

/// Compact surface-specific palette menu for direct controls such as the
/// expanded OpenNotch header. It mirrors the same flat preset model as
/// Settings and never changes the other surface implicitly.
struct SurfacePaletteMenuContent: View {
    let surface: ThemeSurface
    @ObservedObject private var theme = ThemeStore.shared
    var openCustom: (() -> Void)?

    var body: some View {
        ForEach(ThemePreset.macSpacesPresets + ThemePreset.terminalPresets) { preset in
            paletteButton(preset)
        }

        Divider()
        Button {
            theme.setPreset(.custom, for: surface)
            openCustom?()
        } label: {
            Label(
                "Custom Color…",
                systemImage: isActive(.custom) ? "checkmark" : "paintpalette.fill"
            )
        }
    }

    private func paletteButton(_ preset: ThemePreset) -> some View {
        Button {
            theme.setPreset(preset, for: surface)
        } label: {
            Label(
                preset.title,
                systemImage: isActive(preset) ? "checkmark" : preset.symbol
            )
        }
    }

    private func isActive(_ preset: ThemePreset) -> Bool {
        theme.preset(for: surface) == preset
    }
}

extension Color {
    init?(themeHex: String) {
        let cleaned = themeHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension NSColor {
    var themeHexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}
