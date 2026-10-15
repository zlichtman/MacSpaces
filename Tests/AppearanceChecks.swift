import AppKit
import SwiftUI

@main struct AppearanceChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "dev.opensource.MacSpaces.AppearanceChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = ThemeStore(defaults: defaults)
        precondition(fresh.family == .macspaces && fresh.appearanceMode == .system,
                     "Fresh installs start with the black-and-white MacSpaces (formerly Noir) theme")
        precondition(ThemeFamily(saved: "noir") == .macspaces, "Noir retains its black-and-white theme")
        precondition(fresh.lyricStyle == .poster, "Fresh installs use Poster lyrics")
        for style in LyricStyle.allCases {
            fresh.lyricStyle = style
            precondition(ThemeStore(defaults: defaults).lyricStyle == style, "Every saved lyric style remains available")
        }
        fresh.selectFamily(.everforest)
        precondition(ThemeStore(defaults: defaults).family == .everforest,
                     "Reinstalling must preserve an explicitly selected theme")
        fresh.reset()
        precondition(fresh.family == .macspaces && fresh.lyricStyle == .poster, "Reset returns to the fresh-install theme and Poster lyrics")
        fresh.selectFamily(.heartable)
        fresh.appearanceMode = .dark
        // Registration defaults vanish between launches. A newly selected
        // family must survive even when no legacy preset was ever saved.
        defaults.removeVolatileDomain(forName: UserDefaults.registrationDomain)
        let restored = ThemeStore(defaults: defaults)
        precondition(restored.family == .heartable && restored.resolvedScheme == .dark)
        restored.selectFamily(.tsukumo)
        precondition(restored.appearanceMode == .dark, "Selecting a family must preserve mode")
        precondition(ThemeStore(defaults: defaults).family == .tsukumo, "The selected family persists")
        // Every family sits in exactly one drawer.
        let drawers = ThemeCollection.allCases.flatMap(\.families)
        precondition(drawers.count == ThemeFamily.allCases.count && Set(drawers) == Set(ThemeFamily.allCases), "Each theme in one drawer")
        // Drawers fill whole rows of five.
        precondition(ThemeCollection.allCases.allSatisfy { $0.families.count % 5 == 0 }, "Each drawer holds a multiple of 5 themes")
        // Any custom background keeps readable text; the scheme follows it.
        for bg in ["000000", "FFFFFF", "777777", "808080", "1B2230", "F2ECBC", "FF0000", "00FF00", "0000FF", "5A5A5A"] {
            UserDefaults.standard.set(bg, forKey: CustomThemeColors.backgroundKey)
            let p = ThemeFamily.custom.palette(.dark)
            precondition(contrast(p.foreground, p.background) >= 4.5 && contrast(p.foreground, p.surface) >= 4.5, "custom \(bg)")
        }
        UserDefaults.standard.removeObject(forKey: CustomThemeColors.backgroundKey)
        // Tinted glass derives readable text from any tint.
        for tint in ["000000", "FFFFFF", "808080", "5A3F27", "F2ECBC", "FF0000", "0000FF"] {
            UserDefaults.standard.set(tint, forKey: TintedGlassColors.tintKey)
            let p = ThemeFamily.tinted.palette(.dark)
            precondition(contrast(p.foreground, p.background) >= 4.5 && contrast(p.foreground, p.surface) >= 4.5, "tinted \(tint)")
        }
        UserDefaults.standard.removeObject(forKey: TintedGlassColors.tintKey)
        // Pre-2.38 preset IDs open as today's family; their old Custom falls back to MacSpaces.
        let presets = ["midnight": ThemeFamily.midnight, "frosted": .glass, "graphite": .carbon, "ocean": .tidal,
                       "sunset": .ember, "forest": .everforest, "solarizedDark": .solarized, "gruvboxDark": .gruvbox,
                       "catppuccinMocha": .catppuccin, "oneDark": .karma, "dracula": .catppuccin, "nord": .nord,
                       "tokyoNight": .tokyoNight, "kemosabe": .kemosabe, "tsukumo": .tsukumo, "custom": .macspaces]
        for (preset, family) in presets {
            defaults.removePersistentDomain(forName: suite)
            defaults.set(preset, forKey: "theme.notchPreset")
            let migrated = ThemeStore(defaults: defaults)
            precondition(migrated.family == family, "Legacy preset \(preset) must open as \(family)")
            if preset != "frosted" { precondition(migrated.appearanceMode == .dark) }
            precondition(ThemeStore(defaults: defaults).family == family, "Migration is saved")
        }
        // One Dark became Karma: a saved One Dark family opens as Karma.
        let karmaSuite = "dev.opensource.MacSpaces.KarmaCheck." + UUID().uuidString
        let karmaDefaults = UserDefaults(suiteName: karmaSuite)!
        defer { karmaDefaults.removePersistentDomain(forName: karmaSuite) }
        karmaDefaults.set("oneDark", forKey: "theme.family")
        precondition(ThemeStore(defaults: karmaDefaults).family == .karma, "Saved One Dark must open as Karma")
        // Retired 2.38 themes open as their replacements, which must still exist.
        precondition(ThemeFamily.replaced.allSatisfy { ThemeFamily(rawValue: $0.key) == nil && ThemeFamily(saved: $0.key) == $0.value })
        // Every scene theme has an effect.
        precondition(ThemeCollection.allCases.filter { ![.core, .terminal, .glass].contains($0) }.allSatisfy { $0.families.allSatisfy { $0.motif != nil } })
        precondition(ThemeFamily.allCases.allSatisfy { ($0.glassTint != nil) == ($0.collection == .glass) }, "Glass drawer is exactly the see-through themes")
        precondition(Set(ThemeFamily.allCases.compactMap(\.motif)).count == ThemeMotif.allCases.count, "Every effect belongs to one theme")
        for family in ThemeFamily.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let palette = family.palette(scheme)
                for surface in [palette.background, palette.surface] {
                    let ratio = contrast(palette.foreground, surface)
                    precondition(ratio >= 4.5, "\(family.title) text contrast: \(ratio)")
                }
            }
        }
        print("Appearance checks passed: family/mode persistence, legacy preset migration, system resolution, and text contrast.")
    }
    static func contrast(_ a: String, _ b: String) -> Double {
        func luminance(_ hex: String) -> Double {
            let rgb = UInt32(hex, radix: 16)!
            let values = [16, 8, 0].map { shift -> Double in
                let c = Double((rgb >> shift) & 255) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
