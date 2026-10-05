import AppKit
import SwiftUI

// ThemeStore's compatibility style API accepts widget kinds, but these checks
// exercise appearance independently of widget services or real user data.
enum NookWidgetKind { case placeholder }

@main struct AppearanceChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "dev.opensource.MacSpaces.AppearanceChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = ThemeStore(defaults: defaults)
        precondition(fresh.family == .macspaces && fresh.appearanceMode == .system)
        fresh.selectFamily(.heartable)
        fresh.appearanceMode = .dark
        // Registration defaults vanish between launches. A newly selected
        // family must survive even when no legacy preset was ever saved.
        defaults.removeVolatileDomain(forName: UserDefaults.registrationDomain)
        let restored = ThemeStore(defaults: defaults)
        precondition(restored.family == .heartable && restored.resolvedScheme == .dark)
        restored.selectFamily(.tsukumo)
        precondition(restored.appearanceMode == .dark, "Selecting a family must preserve mode")
        restored.customNotchHex = "#123456"
        restored.setPreset(.custom, for: .notch)
        let custom = ThemeStore(defaults: defaults)
        precondition(custom.family == nil && custom.notchPreset == .custom)
        precondition(custom.customNotchHex == "#123456")
        custom.setPreset(.nord, for: .notch)
        let legacy = ThemeStore(defaults: defaults)
        precondition(legacy.family == .nord && legacy.notchPreset == .nord)
        precondition(AppearanceMode.system.scheme(systemIsDark: true) == .dark)
        precondition(AppearanceMode.system.scheme(systemIsDark: false) == .light)
        precondition(AppearanceMode.light.scheme(systemIsDark: true) == .light)
        precondition(AppearanceMode.dark.scheme(systemIsDark: false) == .dark)
        precondition(ThemeFamily.signature == [.macspaces, .powdermeet, .heartable, .kemosabe, .tsukumo])
        let catalog = ThemeFamily.signature + ThemeFamily.palettes + [.custom]
        precondition(!ThemeFamily.palettes.contains(.custom))
        // Every family sits in exactly one drawer; Core is the app themes; Custom ends Terminal.
        let drawers = ThemeCollection.allCases.flatMap(\.families)
        precondition(drawers.count == ThemeFamily.allCases.count && Set(drawers) == Set(ThemeFamily.allCases), "Each theme in one drawer")
        precondition(ThemeCollection.core.families == ThemeFamily.signature && ThemeCollection.terminal.families.last == .custom)
        precondition(ThemeFamily.allCases.allSatisfy { $0.collection.families.contains($0) })
        // Drawers fill whole rows of five.
        precondition(ThemeCollection.allCases.allSatisfy { $0.families.count % 5 == 0 }, "Each drawer holds a multiple of 5 themes")
        // Any custom background keeps readable text; the scheme follows it.
        for bg in ["000000", "FFFFFF", "777777", "808080", "1B2230", "F2ECBC", "FF0000", "00FF00", "0000FF", "5A5A5A"] {
            UserDefaults.standard.set(bg, forKey: CustomThemeColors.backgroundKey)
            let p = ThemeFamily.custom.palette(.dark)
            precondition(contrast(p.foreground, p.background) >= 4.5 && contrast(p.foreground, p.surface) >= 4.5, "custom \(bg)")
        }
        UserDefaults.standard.removeObject(forKey: CustomThemeColors.backgroundKey)
        precondition(Set(catalog).count == catalog.count && Set(catalog) == Set(ThemeFamily.allCases))
        precondition(ThemeFamily.palettes.contains(.catppuccin) && ThemeFamily.palettes.contains(.everforest))
        for preset in ThemePreset.allCases {
            defaults.removePersistentDomain(forName: suite)
            defaults.set(preset.rawValue, forKey: "theme.notchPreset")
            defaults.set("#123456", forKey: "theme.customNotchHex")
            defaults.set("#AB2345", forKey: "theme.customAccentHex")
            defaults.set(1, forKey: "theme.schemaVersion")
            let migrated = ThemeStore(defaults: defaults)
            precondition(migrated.notchPreset == preset, "Never overwrite saved IDs")
            precondition(migrated.customNotchHex == "#123456" && migrated.customAccentHex == "#AB2345")
            precondition(migrated.family == ThemeFamily(legacy: preset), "Legacy catalog migration failed")
            if preset != .custom && preset != .frosted { precondition(migrated.appearanceMode == .dark) }
        }
        // One Dark became Karma: a saved One Dark family opens as Karma.
        let karmaSuite = "dev.opensource.MacSpaces.KarmaCheck." + UUID().uuidString
        let karmaDefaults = UserDefaults(suiteName: karmaSuite)!
        defer { karmaDefaults.removePersistentDomain(forName: karmaSuite) }
        karmaDefaults.set("oneDark", forKey: "theme.family")
        precondition(ThemeStore(defaults: karmaDefaults).family == .karma, "Saved One Dark must open as Karma")
        precondition(ThemeFamily(legacy: .oneDark) == .karma && ThemeFamily.palettes.contains(.karma))
        precondition(ThemeFamily(rawValue: "oneDark") == nil && ThemeFamily(saved: "karma") == .karma)
        // Retired 2.38 themes open as their replacements, which must still exist.
        precondition(ThemeFamily.replaced.allSatisfy { ThemeFamily(rawValue: $0.key) == nil && ThemeFamily(saved: $0.key) == $0.value })
        // Pulse was replaced by Fireworks in 2.47.
        precondition(ThemeFamily(saved: "pulse") == .fireworks && ThemeFamily.fireworks.motif == .fireworks)
        for family in ThemeFamily.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let palette = family.palette(scheme)
                for surface in [palette.background, palette.surface] {
                    let ratio = contrast(palette.foreground, surface)
                    precondition(ratio >= 4.5, "\(family.title) text contrast: \(ratio)")
                }
            }
        }
        print("Appearance checks passed: family/mode persistence, legacy and custom preservation, system resolution, and text contrast.")
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
