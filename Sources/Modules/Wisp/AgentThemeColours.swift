import SwiftUI

/// The agent's colours from a theme (Settings → Tsukumo → Agent, the same list as Appearance's).
/// Picking a theme there colours the agent and never changes the Nook's theme. Each of the
/// agent's own palettes is the theme of the same name, so a saved palette id keeps its colours
/// exactly, and each scene has colours picked from its picture; every other theme's are worked
/// out from its background, text and accent (`AgentColours.derived`).
extension AgentPalette {
    /// The agent's own palettes by the theme that carries each one's name. Saved ids stay.
    static let themes: [String: ThemeFamily] = [
        "apricot": .apricot, "pearl": .pearl, "matcha": .matchaLatte, "lavender": .lavender, "sky": .sky,
        "rose": .heartable, "aurora": .aurora, "cocoa": .cocoa, "graphite": .graphite, "butter": .butter,
        "pistachio": .pistachio, "peach": .peach, "porcelain": .porcelain, "moss": .mossGreen, "midnight": .midnight,
        "cherry": .cherry, "ember": .emberGlow, "lagoon": .lagoon, "mulberry": .mulberry, "ink": .ink, "paper": .paper,
    ]

    /// Each scene's colours, picked by hand from its picture (or, for the drawn ones, its effect):
    /// KemoSabe's body from the picture's lightest colour and its face from a deep one, and Wisp's
    /// eyes in the scene's accent. Lavender and Aurora are the agent's palettes of those names.
    static let scenes: [ThemeFamily: (body: String, face: String)] = [
        .blossom: ("F6D5DC", "C9563C"), .nightBlossom: ("E6BCC4", "7E2C47"),
        .lotus: ("F5D0D6", "466F34"), .nightLotus: ("E8C0C8", "1E4752"),
        .fern: ("C4D6A4", "33502A"), .bamboo: ("E2E6BC", "5A7430"),
        .firefly: ("EAF1A6", "274536"), .rainCanopy: ("C9E2D4", "245C4C"),
        .autumn: ("F2D3B4", "B84B1C"), .lava: ("F7BB6E", "5A2418"),
        .canyon: ("EEC29C", "A3421C"), .dune: ("F0CD95", "8A4F22"),
        .moonlitDunes: ("D8B790", "4A2E18"), .obsidianCoast: ("CDE1DE", "1D4B50"),
        .alpine: ("E8EEF5", "3E5A77"), .thunderstorm: ("BDC7DD", "33416A"),
        .moonrise: ("EFE3EC", "4C4F7A"), .starlight: ("E9DDC4", "222B3C"),
        .rainbow: ("FFE4F5", "B8249A"), .codeRain: ("BDF5C9", "0E4222"),
        .warp: ("D8E2FF", "2F45A8"), .synthwave: ("FFD0EB", "5B1F8A"),
    ]

    /// The hand-made colours for a theme: an agent palette under its own id, or a scene's.
    static func handMade(_ family: ThemeFamily) -> AgentPalette? {
        if let id = themes.first(where: { $0.value == family })?.key { return named(id) }
        guard let scene = scenes[family] else { return nil }
        let id: String = TerminalThemeItem.own(family).id
        return AgentPalette(id: id, name: family.title, body: scene.body, accent: scene.face, eye: family.palette(.dark).accent)
    }

    /// What `agent.palette` names, with `agent.themeColours` for a theme picked from the list:
    /// Automatic, Custom and the agent's own palettes as always, a theme by its list id
    /// (`TerminalThemeItem.id`) in the colours saved with it, and anything unknown as Automatic.
    static func resolve(_ id: String?, themeColours: String?) -> AgentPalette {
        guard let id else { return .automatic }
        if let palette = choices.first(where: { $0.id == id }) { return palette }
        guard let name = themeName(id) else { return .automatic }
        let parts: [String] = (themeColours ?? "").split(separator: " ").map(String.init)
        if parts.count == 3, parts.allSatisfy({ CustomThemeColors.clean($0) == $0 }) {
            return AgentPalette(id: id, name: name, body: parts[0], accent: parts[1], eye: parts[2])
        }
        // Colours missing: a scene's are known; anything else shows as Automatic.
        if id.hasPrefix("own."), let family = ThemeFamily(rawValue: String(id.dropFirst(4))), let made = handMade(family) { return made }
        return .automatic
    }

    /// A list id's name: one of ours by its title, a library theme by its own.
    static func themeName(_ id: String) -> String? {
        if id.hasPrefix("own.") { return ThemeFamily(rawValue: String(id.dropFirst(4)))?.title }
        if id.hasPrefix("ghostty.") { return String(id.dropFirst(8)) }
        return nil
    }

    /// The list id this palette shows as picked: its theme's, and nil for Automatic (each
    /// character's own colours, which no row offers) and for Custom, whose colours show in the
    /// wells with no row picked.
    var themeItemID: String? {
        if id == Self.automatic.id { return nil }
        if let family = Self.themes[id] { return TerminalThemeItem.own(family).id }
        return Self.themeName(id) == nil ? nil : id
    }
}

extension AgentColours {
    /// A theme's agent colours, the same way for every theme: KemoSabe's body is the theme's
    /// lightest colour (its background when light, its text when dark) with 30% of the accent,
    /// lifted toward white until it reads on a dark Nook; its face is the accent, darkened until
    /// it reads at 3:1 on the body; Wisp's eyes are the accent itself, made legible on the Nook
    /// as they're drawn (`WispFaceStyle`, `KemoSabeRGB.legible`).
    static func derived(id: String, name: String, background: String, foreground: String, accent: String) -> AgentPalette {
        let bg = KemoSabeRGB(hex: background), fg = KemoSabeRGB(hex: foreground), tint = KemoSabeRGB(hex: accent)
        let base: KemoSabeRGB = bg.luminance > fg.luminance ? bg : fg
        var body: KemoSabeRGB = base.mixed(tint, 0.3)
        for _ in 0..<10 where body.luminance < 0.5 { body = body.mixed(.white, 0.15) }
        var face: KemoSabeRGB = tint
        for _ in 0..<12 where KemoSabeRGB.contrast(face, body) < 3 { face = face.mixed(.black, 0.15) }
        return AgentPalette(id: id, name: name, body: body.hex, accent: face.hex, eye: tint.hex)
    }

    /// The colours a theme from the list gives the agent.
    @MainActor static func palette(for item: TerminalThemeItem) -> AgentPalette {
        if case .own(let family) = item, let made = AgentPalette.handMade(family) { return made }
        guard let theme = GhosttyLibrary.shared.current(item) else { return .automatic }
        return derived(id: item.id, name: item.title, background: theme.background, foreground: theme.foreground, accent: theme.accent)
    }

    /// A new install's agent starts in Noir, the Nook's own starting theme. An existing install
    /// keeps what it has (unset is Automatic, each character's own colours): this runs only while
    /// `WelcomeWindow.noteInstall` still marks the copy as new and no palette is saved.
    @MainActor static func startNewInstall(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: WelcomeWindow.seenKey) == nil,
              defaults.object(forKey: WidgetOptions.Keys.agentPalette) == nil else { return }
        choose(TerminalThemeItem.own(.macspaces), defaults)
    }

    /// Picks a theme's colours for the agent; the Nook's theme stays as it is. One of the agent's
    /// own palettes is saved by its id, as before; any other theme by its list id, with its colours
    /// (`agent.themeColours`), so they draw without reading the library.
    @MainActor static func choose(_ item: TerminalThemeItem, _ defaults: UserDefaults = .standard) {
        let palette = palette(for: item)
        if AgentPalette.themes[palette.id] == nil {
            let colours: [String] = [palette.body, palette.accent, palette.eye ?? palette.accent]
            defaults.set(colours.joined(separator: " "), forKey: WidgetOptions.Keys.agentThemeColours)
        }
        choose(palette, defaults)
    }
}

extension KemoSabeRGB {
    /// Six hex digits.
    var hex: String {
        func byte(_ c: Double) -> Int { Int((max(0, min(1, c)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    static func contrast(_ a: KemoSabeRGB, _ b: KemoSabeRGB) -> Double {
        let x = a.luminance, y = b.luminance
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
