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
    /// How the Music page sets lyrics (Settings → Appearance → Lyrics).
    @Published var lyricStyle: LyricStyle = .poster {
        didSet { defaults.set(lyricStyle.rawValue, forKey: Keys.lyricStyle) }
    }
    /// The current theme's effect, when it has one. Effects always show (owner, 2.100:
    /// no off switch); Reduce Motion holds them still.
    var activeMotif: ThemeMotif? { family.motif }
    /// The Nook is always dark (owner, 3.24): every theme shows its dark variant, except
    /// Frost and Smoke, which keep their own (`fixedScheme`).
    var nookScheme: ColorScheme { family.fixedScheme ?? .dark }
    /// The Settings window follows the system's light or dark appearance, in the theme's colours.
    @Published private(set) var systemIsDark = false
    private var appearanceObservation: NSKeyValueObservation?
    var settingsScheme: ColorScheme { family.fixedScheme ?? (systemIsDark ? .dark : .light) }

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
#if DEBUG
    /// Measurements of animated paths run with motion on, whatever the runner's setting.
    func setPreviewSystemReduceMotion(_ on: Bool) { systemReduceMotion = on }
#endif

    /// Custom theme colours, stored as hex. Changing either refreshes the Nook.
    @Published var customThemeBackground: String = CustomThemeColors.background {
        didSet { defaults.set(customThemeBackground, forKey: CustomThemeColors.backgroundKey) }
    }
    @Published var customThemeAccent: String = CustomThemeColors.accent {
        didSet { defaults.set(customThemeAccent, forKey: CustomThemeColors.accentKey) }
    }
    /// Whether Custom's Glass blurs the desktop.
    @Published var customGlassBlurs: Bool = CustomTheme.glassBlurs {
        didSet { defaults.set(customGlassBlurs, forKey: CustomTheme.blurKey) }
    }
    /// Custom's style, second colour (Two-tone) and picture (Picture).
    @Published var customStyle: CustomThemeStyle = CustomTheme.style {
        didSet { defaults.set(customStyle.rawValue, forKey: CustomTheme.styleKey) }
    }
    @Published var customThemeSecond: String = CustomTheme.second {
        didSet { defaults.set(customThemeSecond, forKey: CustomTheme.secondKey) }
    }
    @Published var customImageName: String? = CustomTheme.imageName {
        didSet { defaults.set(customImageName, forKey: CustomTheme.imageKey) }
    }
    /// How much of Custom's Glass tint covers the desktop; 0 is fully clear.
    @Published var customGlassStrength: Double = CustomTheme.glassStrength {
        didSet { defaults.set(customGlassStrength, forKey: CustomTheme.strengthKey) }
    }
    /// The chosen Ghostty theme's name; its colours are saved with it (`GhosttyThemes`).
    @Published private(set) var ghosttyName: String? = GhosttyThemes.selected?.name

    func selectGhostty(_ ghostty: GhosttyTheme) {
        defaults.set(ghostty.saved, forKey: GhosttyThemes.selectedKey)
        ghosttyName = ghostty.name
        family = .ghostty
    }

    /// Uses a picture copied into Application Support, with the colours read from it.
    func setCustomPicture(_ name: String, background: String, accent: String) {
        selectCustomStyle(.image)
        customImageName = name
        customThemeBackground = background
        customThemeAccent = accent
        CustomTheme.save(.image, background: background, accent: accent, in: defaults)
    }

    /// Forgets the picture: deletes the app's copy and clears `theme.custom.image`, so
    /// Picture shows its empty state. The colours it gave stay until changed or reset.
    func removeCustomPicture() {
        customImageName = nil
        CustomTheme.removeImageFiles()
        CustomBackgroundImage.shared.prepare()
    }

    /// Selects Custom in a style. Leaving a style keeps its background and accent for
    /// later; a style seen for the first time starts on its default.
    func selectCustomStyle(_ style: CustomThemeStyle) {
        if style != customStyle {
            CustomTheme.save(customStyle, background: customThemeBackground, accent: customThemeAccent, in: defaults)
            if let saved = CustomTheme.saved(style, in: defaults) {
                customThemeBackground = saved.background
                customThemeAccent = saved.accent
            } else {
                applyDefaults(style)
            }
            customStyle = style
        }
        CustomTheme.save(style, background: customThemeBackground, accent: customThemeAccent, in: defaults)
        family = .custom
    }

    /// Returns the current Custom style to its default look (Picture keeps its picture
    /// and takes its colours from it again).
    func resetCustomStyle() {
        let style = customStyle
        if style == .image, let image = CustomBackgroundImage.shared.image {
            DispatchQueue.global(qos: .userInitiated).async {
                let colours = CustomTheme.palette(from: image)
                DispatchQueue.main.async {
                    let store = ThemeStore.shared
                    guard store.customStyle == .image else { return }
                    store.customThemeBackground = colours.background
                    store.customThemeAccent = colours.accent
                    CustomTheme.save(.image, background: colours.background, accent: colours.accent)
                    store.family = .custom
                }
            }
            return
        }
        applyDefaults(style)
        CustomTheme.save(style, background: customThemeBackground, accent: customThemeAccent, in: defaults)
        family = .custom
    }

    /// Whether the current style looks as its default does (Reset has nothing to do).
    var customStyleIsDefault: Bool {
        let d = CustomTheme.Defaults.of(customStyle)
        switch customStyle {
        case .image: return false
        case .solid: return customThemeBackground == d.background && customThemeAccent == d.accent
        case .twoTone: return customThemeBackground == d.background && customThemeAccent == d.accent && customThemeSecond == d.second
        case .glass:
            return customThemeBackground == d.background && customThemeAccent == d.accent
                && abs(customGlassStrength - (d.strength ?? 0)) < 0.005 && customGlassBlurs == d.blurs
        }
    }

    private func applyDefaults(_ style: CustomThemeStyle) {
        let d = CustomTheme.Defaults.of(style)
        customThemeBackground = d.background
        customThemeAccent = d.accent
        if let second = d.second { customThemeSecond = second }
        if let strength = d.strength { customGlassStrength = strength }
        if let blurs = d.blurs { customGlassBlurs = blurs }
    }

    private enum Keys {
        static let family = "theme.family"
        /// Light, Dark or System until 3.24; removed now that the Nook is always dark.
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
        // Before the per-style defaults reach anyone's unset keys, pin what they see now.
        CustomTheme.migrateStyleDefaults(defaults, family: defaults.string(forKey: Keys.family))
        customThemeBackground = CustomThemeColors.clean(defaults.string(forKey: CustomThemeColors.backgroundKey)) ?? CustomThemeColors.defaultBackground
        customThemeAccent = CustomThemeColors.clean(defaults.string(forKey: CustomThemeColors.accentKey)) ?? CustomThemeColors.defaultAccent
        customThemeSecond = CustomThemeColors.clean(defaults.string(forKey: CustomTheme.secondKey)) ?? CustomTheme.defaultSecond
        customGlassStrength = min(max(defaults.object(forKey: CustomTheme.strengthKey) as? Double ?? CustomTheme.defaultStrength,
                                      CustomTheme.strengthRange.lowerBound), CustomTheme.strengthRange.upperBound)
        customGlassBlurs = defaults.object(forKey: CustomTheme.blurKey) as? Bool ?? CustomTheme.Defaults.glass.blurs!
        customStyle = defaults.string(forKey: CustomTheme.styleKey).flatMap(CustomThemeStyle.init(rawValue:)) ?? .solid
        customImageName = defaults.string(forKey: CustomTheme.imageKey)
        lyricStyle = LyricStyle(rawValue: defaults.string(forKey: Keys.lyricStyle) ?? "") ?? .poster
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        reduceMotionPreference = defaults.bool(forKey: Keys.reduceMotion)
        defaults.removeObject(forKey: Keys.appearanceMode)
        // Every saved theme opens as itself; a renamed one changes only its title.
        if let saved = defaults.string(forKey: Keys.family).flatMap(ThemeFamily.init(saved:)) {
            family = saved
        } else if let preset = defaults.string(forKey: Keys.legacyPreset) {
            // A pre-2.38 preset opens as its family (old custom colours aren't carried over).
            family = ThemeFamily(legacy: preset) ?? .macspaces
            defaults.set(family.rawValue, forKey: Keys.family)
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

    var nookForeground: Color { foreground(nookScheme) }
    /// Text colour for the Settings window's own chrome.
    var settingsForeground: Color { foreground(settingsScheme) }

    /// The theme's accent, for views that don't read `notch` directly.
    var accent: Color { notch.accent }

    var notch: ThemeTokens { tokens(nookScheme) }
    /// The Settings window's chrome; Nook previews inside it keep `notch`.
    var settings: ThemeTokens { tokens(settingsScheme) }

    private func foreground(_ scheme: ColorScheme) -> Color {
        let palette = family.palette(scheme)
        return palette.color(palette.foreground)
    }

    private func tokens(_ scheme: ColorScheme) -> ThemeTokens {
        let colors = family.palette(scheme)
        let accent = colors.color(colors.accent)
        let foreground = colors.color(colors.foreground)
        return ThemeTokens(
            surface: colors.color(colors.background),
            surfaceSecondary: colors.color(colors.surface),
            tile: colors.color(colors.surface),
            tileSecondary: accent.opacity(0.10),
            control: accent.opacity(0.10), selected: accent.opacity(0.20),
            border: foreground.opacity(0.16),
            shadow: Color.black.opacity(scheme == .dark ? 0.4 : 0.12),
            glow: .clear,
            accent: accent, secondaryAccent: accent, colorScheme: scheme
        )
    }

    func selectFamily(_ selection: ThemeFamily) {
        family = selection
    }

    func reset() {
        family = .macspaces
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
