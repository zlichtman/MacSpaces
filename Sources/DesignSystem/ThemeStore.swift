import SwiftUI
import AppKit
import Combine

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
}

@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published var family: ThemeFamily {
        didSet { defaults.set(family.rawValue, forKey: Keys.family) }
    }
    @Published var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode) }
    }
    /// How the Music page sets lyrics (Settings → Appearance → Lyrics).
    @Published var lyricStyle: LyricStyle = .poster {
        didSet { defaults.set(lyricStyle.rawValue, forKey: Keys.lyricStyle) }
    }
    /// The current theme's effect, when it has one. Effects always show (owner, 2.100:
    /// no off switch); Reduce Motion holds them still.
    var activeMotif: ThemeMotif? { family.motif }
    @Published private(set) var systemIsDark = false
    private var appearanceObservation: NSKeyValueObservation?
    var resolvedScheme: ColorScheme { appearanceMode.scheme(systemIsDark: systemIsDark) }

    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }
    /// The in-app opt-in. Read `reduceMotion` rather than this, so the system
    /// accessibility setting is honoured even when the app toggle is off.
    @Published var reduceMotionPreference: Bool {
        didSet { defaults.set(reduceMotionPreference, forKey: Keys.reduceMotion) }
    }
    @Published private(set) var systemReduceMotion: Bool =
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var reduceMotion: Bool { reduceMotionPreference || systemReduceMotion }

    /// Custom theme colours, stored as hex. Changing either refreshes the Nook.
    @Published var customThemeBackground: String = CustomThemeColors.background {
        didSet { defaults.set(customThemeBackground, forKey: CustomThemeColors.backgroundKey) }
    }
    @Published var customThemeAccent: String = CustomThemeColors.accent {
        didSet { defaults.set(customThemeAccent, forKey: CustomThemeColors.accentKey) }
    }
    /// Tinted glass colours, stored as hex.
    @Published var tintedGlassTint: String = TintedGlassColors.tint {
        didSet { defaults.set(tintedGlassTint, forKey: TintedGlassColors.tintKey) }
    }
    @Published var tintedGlassAccent: String = TintedGlassColors.accent {
        didSet { defaults.set(tintedGlassAccent, forKey: TintedGlassColors.accentKey) }
    }
    @Published var tintedGlassStrength: Double = TintedGlassColors.strength {
        didSet { defaults.set(tintedGlassStrength, forKey: TintedGlassColors.strengthKey) }
    }
    @Published var tintedGlassBlurs: Bool = TintedGlassColors.blurs {
        didSet { defaults.set(tintedGlassBlurs, forKey: TintedGlassColors.blurKey) }
    }

    private enum Keys {
        static let family = "theme.family"
        static let appearanceMode = "theme.appearanceMode"
        static let lyricStyle = "lyrics.style"
        static let reduceMotion = "theme.reduceMotion"
        static let haptics = "theme.haptics"
        /// Before 2.38 a theme was a preset ID; it's read once to pick the matching family.
        static let legacyPreset = "theme.notchPreset"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lyricStyle = LyricStyle(rawValue: defaults.string(forKey: Keys.lyricStyle) ?? "") ?? .poster
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        reduceMotionPreference = defaults.bool(forKey: Keys.reduceMotion)
        let savedMode = defaults.string(forKey: Keys.appearanceMode).flatMap(AppearanceMode.init(rawValue:))
        appearanceMode = savedMode ?? .system
        if let saved = defaults.string(forKey: Keys.family).flatMap(ThemeFamily.init(saved:)) {
            family = saved
        } else if let preset = defaults.string(forKey: Keys.legacyPreset) {
            // A pre-2.38 preset opens as its family (old custom colours aren't carried over).
            family = ThemeFamily(legacy: preset) ?? .macspaces
            if savedMode == nil { appearanceMode = preset == "frosted" ? .system : .dark }
            defaults.set(family.rawValue, forKey: Keys.family)
            defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode)
        } else {
            family = .macspaces
        }

        systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] app, _ in
            Task { @MainActor [weak self] in
                self?.systemIsDark = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
        }
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

    var nookForeground: Color {
        let palette = family.palette(family.fixedScheme ?? resolvedScheme)
        return palette.color(palette.foreground)
    }

    /// The theme's accent, for views that don't read `notch` directly.
    var accent: Color { notch.accent }

    var notch: ThemeTokens {
        let resolvedScheme = family.fixedScheme ?? self.resolvedScheme
        let colors = family.palette(resolvedScheme)
        let accent = colors.color(colors.accent)
        let foreground = colors.color(colors.foreground)
        return ThemeTokens(
            surface: colors.color(colors.background),
            surfaceSecondary: colors.color(colors.surface),
            tile: colors.color(colors.surface),
            tileSecondary: accent.opacity(0.10),
            control: accent.opacity(0.10), selected: accent.opacity(0.20),
            border: foreground.opacity(0.16),
            shadow: Color.black.opacity(resolvedScheme == .dark ? 0.4 : 0.12),
            glow: .clear,
            accent: accent, secondaryAccent: accent, colorScheme: resolvedScheme
        )
    }

    func selectFamily(_ selection: ThemeFamily) {
        family = selection
    }

    func reset() {
        family = .macspaces
        appearanceMode = .system
        lyricStyle = .poster
        reduceMotionPreference = false
        hapticsEnabled = true
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
