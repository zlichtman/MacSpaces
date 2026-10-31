import AppKit
import SwiftUI

@main struct AppearanceChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "dev.opensource.MacSpaces.AppearanceChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = ThemeStore(defaults: defaults)
        precondition(fresh.family == .macspaces && fresh.nookScheme == .dark,
                     "Fresh installs start with the black-and-white Noir theme (saved id macspaces), dark")
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
        // A Light or System choice saved before 3.24 is dropped: the Nook is always dark.
        defaults.set("light", forKey: "theme.appearanceMode")
        // Registration defaults vanish between launches. A newly selected
        // family must survive even when no legacy preset was ever saved.
        defaults.removeVolatileDomain(forName: UserDefaults.registrationDomain)
        let restored = ThemeStore(defaults: defaults)
        precondition(restored.family == .heartable && restored.nookScheme == .dark && restored.notch.colorScheme == .dark)
        precondition(defaults.object(forKey: "theme.appearanceMode") == nil, "The old appearance setting is removed")
        // Custom reads its colours from the app's own defaults, as the app runs.
        let standard = UserDefaults.standard
        for (key, value) in [(CustomThemeColors.backgroundKey, "F6F8FB" as Any), (CustomTheme.styleKey, "glass"),
                             (CustomTheme.strengthKey, 0.55), (CustomTheme.blurKey, true)] { standard.set(value, forKey: key) }
        precondition(ThemeFamily.custom.fixedScheme == .light, "A white Custom keeps its own light look")
        precondition(ThemeFamily.custom.glassTint == 0.55 && ThemeFamily.custom.glassBlurs, "Custom Glass tints and blurs")
        standard.set(0.0, forKey: CustomTheme.strengthKey); standard.set(false, forKey: CustomTheme.blurKey)
        precondition(ThemeFamily.custom.glassTint == 0 && !ThemeFamily.custom.glassBlurs, "Custom Glass reaches fully clear")
        for key in [CustomThemeColors.backgroundKey, CustomTheme.styleKey, CustomTheme.strengthKey, CustomTheme.blurKey] { standard.removeObject(forKey: key) }
        restored.selectFamily(.tsukumo)
        precondition(ThemeStore(defaults: defaults).family == .tsukumo, "The selected family persists")
        // Every offered family sits in exactly one drawer, and Live fills whole rows of five.
        let drawers = ThemeCollection.allCases.flatMap(\.families)
        precondition(drawers.count == Set(drawers).count, "No theme in two drawers")
        precondition(Set(drawers).union(ThemeFamily.unlisted).union([.ghostty]) == Set(ThemeFamily.allCases)
                     && Set(drawers).isDisjoint(with: ThemeFamily.unlisted), "Each theme offered once or unlisted")
        precondition(ThemeCollection.live.families.count % 5 == 0, "Live holds whole rows of five")
        precondition(ThemeCollection.live.families.contains(.synthwave), "Synthwave stays")
        precondition(ThemeFamily.allCases.allSatisfy { $0.collection.families.contains($0) || !$0.isOffered || $0 == .ghostty }, "Each theme names its drawer")
        // No theme is named after an app.
        precondition(ThemeFamily.ownTerminal.prefix(5).map(\.title) == ["Noir", "Scarlet", "Rose", "Coral", "Iris"], "Our palettes have descriptive names")

        // An update changes nobody's theme: every id saved by 3.34 (`AppearanceBaseline`)
        // opens as the same family with the same palettes, glass, scheme and effect, with
        // a saved Custom and Tinted glass, and their colours are left as they were.
        let customKeys: [String: Any] = [CustomThemeColors.backgroundKey: "2B1E3A", CustomThemeColors.accentKey: "FF8A5B",
                                         TintedGlassColors.tintKey: "5A3F27", TintedGlassColors.accentKey: "8AB4F8",
                                         TintedGlassColors.strengthKey: 0.4, TintedGlassColors.blurKey: false]
        func scheme(_ s: ColorScheme?) -> String { s == nil ? "nil" : s == .dark ? "dark" : "light" }
        func pal(_ p: FamilyPalette) -> String { [p.background, p.surface, p.foreground, p.accent].joined(separator: " ") }
        for (key, value) in customKeys { standard.set(value, forKey: key) }
        for (id, before) in AppearanceBaseline.saved {
            defaults.removePersistentDomain(forName: suite)
            if id.hasPrefix("preset:") { defaults.set(String(id.dropFirst(7)), forKey: "theme.notchPreset") }
            else { defaults.set(id, forKey: "theme.family") }
            let store = ThemeStore(defaults: defaults)
            let f = store.family
            precondition(f.rawValue == before.family, "\(id) opens as \(before.family), not \(f.rawValue)")
            precondition(pal(f.palette(.light)) == before.light && pal(f.palette(.dark)) == before.dark, "\(id) keeps its palettes")
            precondition(f.glassTint == before.glassTint && f.glassBlurs == before.blurs, "\(id) keeps its glass")
            precondition(scheme(f.fixedScheme) == before.scheme && (f.motif?.rawValue ?? "") == before.motif, "\(id) keeps its scheme and effect")
            precondition(ThemeStore(defaults: defaults).family.rawValue == before.family, "\(id) stays after another launch")
        }
        for (key, value) in customKeys {
            precondition((standard.object(forKey: key) as? NSObject)?.isEqual(value) == true, "Opening any theme leaves the saved Custom and Tinted colours alone")
            standard.removeObject(forKey: key)
        }
        precondition(AppearanceBaseline.saved.count >= 109 && ThemeFamily.allCases.filter { $0 != .ghostty }
            .allSatisfy { AppearanceBaseline.saved[$0.rawValue] != nil }, "The baseline covers every theme")
        // The rest of Appearance (lyrics, Reduce Motion, haptics) survives as saved.
        defaults.removePersistentDomain(forName: suite)
        let settings = ThemeStore(defaults: defaults)
        settings.lyricStyle = LyricStyle.allCases.last!; settings.reduceMotionPreference = true; settings.hapticsEnabled = false
        settings.selectFamily(.ruby)
        let reopened = ThemeStore(defaults: defaults)
        precondition(reopened.lyricStyle == LyricStyle.allCases.last! && reopened.reduceMotionPreference && !reopened.hapticsEnabled
                     && reopened.family == .ruby, "Lyrics, Motion and an unlisted theme stay as saved")
        defaults.removePersistentDomain(forName: suite)
        // Any custom background keeps readable text; the scheme follows it.
        for bg in ["000000", "FFFFFF", "777777", "808080", "1B2230", "F2ECBC", "FF0000", "00FF00", "0000FF", "5A5A5A"] {
            UserDefaults.standard.set(bg, forKey: CustomThemeColors.backgroundKey)
            let p = ThemeFamily.custom.palette(.dark)
            precondition(contrast(p.foreground, p.background) >= 4.5 && contrast(p.foreground, p.surface) >= 4.5, "custom \(bg)")
        }
        UserDefaults.standard.removeObject(forKey: CustomThemeColors.backgroundKey)
        // A picture's colours keep the accent readable on its dark background.
        for (r, g, b) in [(0.9, 0.5, 0.3), (0.2, 0.3, 0.9), (0.5, 0.5, 0.5), (1.0, 1.0, 1.0), (0.0, 0.0, 0.0)] {
            let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            let colours = CustomTheme.palette(from: context.makeImage()!)
            precondition(CustomThemeColors.isDark(colours.background) && contrast(colours.accent, colours.background) >= 3, "picture \(r) \(g) \(b)")
        }
        // Ghostty's saved line reads back, and its text always reads at 4.5:1.
        let ayu = GhosttyTheme(saved: "Ayu|0B0E14|BFBDB6|53BDFA|" + String(repeating: "112233", count: 16))!
        precondition(ayu.name == "Ayu" && ayu.ansi.count == 16 && GhosttyTheme(saved: ayu.saved) == ayu)
        let dim = GhosttyTheme(saved: "Dim|202020|303030|5080FF|" + String(repeating: "112233", count: 16))!.palette
        precondition(contrast(dim.foreground, dim.background) >= 4.5, "A dim Ghostty foreground falls back to readable text")
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
            precondition(ThemeStore(defaults: defaults).family == family, "Migration is saved")
        }
        // One Dark became Karma: a saved One Dark family opens as Karma.
        let karmaSuite = "dev.opensource.MacSpaces.KarmaCheck." + UUID().uuidString
        let karmaDefaults = UserDefaults(suiteName: karmaSuite)!
        defer { karmaDefaults.removePersistentDomain(forName: karmaSuite) }
        karmaDefaults.set("oneDark", forKey: "theme.family")
        precondition(ThemeStore(defaults: karmaDefaults).family == .karma, "Saved One Dark must open as Karma")
        // Every Live theme has an effect; Terminal themes have none; every effect belongs to one theme.
        precondition(ThemeCollection.live.families.allSatisfy { $0.motif != nil })
        precondition(ThemeCollection.terminal.families.allSatisfy { $0.motif == nil && $0.glassTint == nil })
        precondition(ThemeFamily.replaced.allSatisfy { ThemeFamily(rawValue: $0.key) == nil && ThemeFamily(saved: $0.key) == $0.value }, "Retired ids still open as before")
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
        terminalOrderChecks()
        customStyleChecks()
        print("Appearance checks passed: theme persistence, the always-dark Nook, legacy preset migration and text contrast.")
    }
    /// The Terminal list's order: ours on top in their curated order, then Ghostty's library
    /// as Ghostty lists it (alphabetical by name, ignoring case), with nothing sorted at run time.
    @MainActor static func terminalOrderChecks() {
        precondition(ThemeFamily.ownTerminal.map(\.title) == ["Noir", "Scarlet", "Rose", "Coral", "Iris", "Midnight", "Orchid",
                                                              "Tokyo Night", "Catppuccin", "Rosé Pine", "Nord", "Solarized",
                                                              "Everforest", "Gruvbox", "Monokai"], "Ours keep their curated order")
        let data = try! Data(contentsOf: URL(fileURLWithPath: "Sources/Resources/ghostty-themes.json"))
        let rows = try! JSONDecoder().decode([[String]].self, from: data)
        precondition(rows.allSatisfy { $0.count == 5 }, "A library row is the five fields a saved theme has")
        let themes = rows.map { GhosttyTheme(row: $0)! }
        precondition(themes.count > 800, "The Ghostty library decodes")
        let names = themes.map { $0.name.lowercased() }
        precondition(zip(names, names.dropFirst()).allSatisfy { $0 < $1 }, "The library is written in Ghostty's order")
        // A saved Ghostty line keeps its five fields: choosing a theme saves what 3.35 saved.
        let saved = themes[0].saved
        precondition(saved.components(separatedBy: "|").count == 5 && GhosttyTheme(saved: saved) == themes[0],
                     "A saved Ghostty theme is unchanged")
        let list = TerminalThemeItem.ordered(own: ThemeFamily.ownTerminal, ghostty: themes)
        precondition(list.count == themes.count + ThemeFamily.ownTerminal.count - GhosttyThemes.originals.count, "Every theme shows once")
        precondition(list.prefix(ThemeFamily.ownTerminal.count) == ThemeFamily.ownTerminal.map(TerminalThemeItem.own)[...], "Ours open the list")
        let ghostty = list.dropFirst(ThemeFamily.ownTerminal.count).map(\.title)
        precondition(ghostty == themes.map(\.name).filter { !Set(GhosttyThemes.originals.values).contains($0) }, "Then Ghostty's, in its order")
        let gruvbox = ghostty.indices.filter { ghostty[$0].hasPrefix("Gruvbox") }
        precondition(gruvbox.count > 1 && gruvbox.last! - gruvbox.first! == gruvbox.count - 1, "A family stays together")
    }

    /// Each Custom style starts on its own default and keeps its own colours; anyone who
    /// used Custom before keeps exactly what they see.
    @MainActor static func customStyleChecks() {
        var names: [String] = []
        func suite() -> UserDefaults {
            let name = "dev.opensource.MacSpaces.AppearanceChecks.custom.\(UUID().uuidString)"
            names.append(name)
            return UserDefaults(suiteName: name)!
        }
        // A 3.35 Glass with only its tint set keeps 3.35's accent, strength and blur.
        let glassUser = suite()
        glassUser.set("custom", forKey: "theme.family")
        glassUser.set("glass", forKey: CustomTheme.styleKey)
        glassUser.set("F6F8FB", forKey: CustomThemeColors.backgroundKey)
        let migrated = ThemeStore(defaults: glassUser)
        precondition(migrated.customStyle == .glass && migrated.customThemeBackground == "F6F8FB" && migrated.customThemeAccent == CustomTheme.Legacy.accent
                     && migrated.customGlassStrength == CustomTheme.Legacy.strength && migrated.customGlassBlurs
                     && migrated.customThemeSecond == CustomTheme.Legacy.second, "A 3.35 Custom keeps its look")
        precondition(glassUser.string(forKey: CustomThemeColors.accentKey) == CustomTheme.Legacy.accent
                     && glassUser.double(forKey: CustomTheme.strengthKey) == CustomTheme.Legacy.strength
                     && glassUser.object(forKey: CustomTheme.blurKey) as? Bool == true, "Its effective values are written once")
        precondition(CustomTheme.saved(.glass, in: glassUser)! == ("F6F8FB", CustomTheme.Legacy.accent)
                     && CustomTheme.saved(.solid, in: glassUser) == nil, "Only the styles it had set up are kept")
        _ = ThemeStore(defaults: glassUser)
        precondition(glassUser.string(forKey: CustomThemeColors.backgroundKey) == "F6F8FB", "The migration runs once")
        // A Solid-only user from 3.34 with nothing stored but the family.
        let solidUser = suite()
        solidUser.set("custom", forKey: "theme.family")
        let solid = ThemeStore(defaults: solidUser)
        precondition(solid.customThemeBackground == CustomTheme.Legacy.background && solid.customThemeAccent == CustomTheme.Legacy.accent,
                     "A saved Custom with no colours keeps 3.34's")
        // Someone who never used Custom: nothing is written; each style starts on its default.
        let fresh = suite()
        let store = ThemeStore(defaults: fresh)
        precondition(fresh.object(forKey: CustomThemeColors.backgroundKey) == nil && fresh.object(forKey: CustomTheme.savedSolidKey) == nil,
                     "Nothing is written for someone who never used Custom")
        precondition(store.customThemeBackground == CustomTheme.Defaults.solid.background && store.customStyleIsDefault, "Solid starts on its default")
        store.selectCustomStyle(.glass)
        let smoke = ThemeFamily.smoke.palette(.dark)
        precondition(store.customThemeBackground == smoke.background && store.customThemeAccent == smoke.accent
                     && store.customGlassStrength == ThemeFamily.smoke.glassTint! && store.customGlassBlurs == ThemeFamily.smoke.glassBlurs,
                     "Glass starts exactly as Smoke")
        store.customThemeAccent = "FF0000"
        store.selectCustomStyle(.twoTone)
        precondition(store.customThemeBackground == CustomTheme.Defaults.twoTone.background
                     && store.customThemeSecond == CustomTheme.Defaults.twoTone.second, "Two-tone starts on its pairing")
        store.selectCustomStyle(.glass)
        precondition(store.customThemeAccent == "FF0000", "A style keeps its own colours")
        store.resetCustomStyle()
        precondition(store.customThemeAccent == smoke.accent && store.customStyleIsDefault, "Reset returns a style to its default")
        let reopened = ThemeStore(defaults: fresh)
        precondition(reopened.family == .custom && reopened.customStyle == .glass && reopened.customThemeAccent == smoke.accent, "The choice persists")
        for name in names { UserDefaults(suiteName: name)!.removePersistentDomain(forName: name) }
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
