import SwiftUI

/// The agent's colours (Settings → Tsukumo → Agent): one palette for Wisp and KemoSabe, picked
/// from the theme list (`AgentThemeColours.swift`). Each
/// character has a plain drawing and the palette tints it: KemoSabe's body and face, and Wisp's
/// eyes and smile. Automatic (saved as "automatic", and what unset means) is each one's own colours
/// (Wisp black or white, KemoSabe in its saved look, unset Apricot, its original art); the list has
/// no row for it, since Apricot is that art. Custom is two colours of your own, made from the wells. The ids are what `agent.palette` saves, so they never change.
struct AgentPalette: Identifiable, Hashable {
    let id: String
    let name: String
    /// KemoSabe's body, and the face (KemoSabe's eyes, smile and cheeks; Wisp's eyes), as hex.
    let body: String
    let accent: String
    /// Wisp's eyes, when they aren't the face colour (a theme's accent).
    var eye: String? = nil

    /// Each character's own colours, saved as "automatic" as it always was; named Original in the
    /// Agent card's header, with no row in the list.
    static let automatic = AgentPalette(id: "automatic", name: "Original", body: "F4E8DC", accent: "F07558")
    static let custom = AgentPalette(id: "custom", name: "Custom", body: "F4E8DC", accent: "F07558")
    /// KemoSabe's original art.
    static let apricot = AgentPalette(id: "apricot", name: "Apricot", body: "F4E8DC", accent: "F07558")
    /// 3.95's glass KemoSabe's colours.
    static let pearl = AgentPalette(id: "pearl", name: "Pearl", body: "F3EEF8", accent: "EF705B")

    /// Apricot and Pearl, then Tsukumo's companion palettes. Glass is no longer a palette but how
    /// see-through KemoSabe is (`agent.glass`).
    static let palettes: [AgentPalette] = [apricot, pearl] + [
        ("matcha", "Matcha", "DCD89A", "6E7238"), ("lavender", "Lavender", "E2D9F5", "8563BD"),
        ("sky", "Sky", "D0E7F4", "397AA4"), ("rose", "Rose", "F5D7DD", "B74F76"),
        ("aurora", "Aurora", "CBEAE1", "8276AE"), ("cocoa", "Cocoa", "E5CCAD", "815036"),
        ("graphite", "Graphite", "D5D3CF", "66656D"), ("butter", "Butter", "F5E5A6", "B47B35"),
        ("pistachio", "Pistachio", "CBECD2", "2E7355"), ("peach", "Peach", "F3D0B8", "C96956"),
        ("porcelain", "Porcelain", "F0ECE5", "8091A2"), ("moss", "Moss", "91AD94", "344C3F"),
        ("midnight", "Midnight", "BFCBDC", "6D87AC"), ("cherry", "Cherry", "EDC8CC", "AE435C"),
        ("ember", "Ember", "F0A678", "913E49"), ("lagoon", "Lagoon", "A7DCD8", "235D70"),
        ("mulberry", "Mulberry", "CFA3CA", "663C6B"), ("ink", "Ink", "7685B6", "FFF0CF"),
        ("paper", "Paper", "EEECE2", "353D4C"),
    ].map { AgentPalette(id: $0.0, name: $0.1, body: $0.2, accent: $0.3) }

    /// What the Agent card offers, in order.
    static let choices: [AgentPalette] = [automatic] + palettes + [custom]

    static func named(_ id: String?) -> AgentPalette { choices.first { $0.id == id } ?? automatic }
}

/// What KemoSabe's art (`KemoSabeArt`) is repainted with: its body and face as hex, and
/// how see-through it is (0 solid felt, 1 frosted glass).
struct KemoSabeLook: Hashable {
    var body: String
    var face: String
    /// 0 felt to 1 frosted glass: the felt art itself, see-through (`KemoSabeFace`).
    var glass: Double = 0

    static let apricot = KemoSabeLook(body: AgentPalette.apricot.body, face: AgentPalette.apricot.accent)
    /// 3.95's glass KemoSabe, now Pearl at full glass.
    static let glass = KemoSabeLook(body: AgentPalette.pearl.body, face: AgentPalette.pearl.accent, glass: 1)

    init(body: String, face: String, glass: Double = 0) {
        self.body = body; self.face = face; self.glass = glass
    }

    init(_ palette: AgentPalette, glass: Double = 0) {
        self.init(body: palette.body, face: palette.accent, glass: glass)
    }
}

/// The agent's colour settings as a view reads them, so it redraws when they change. Every key
/// keeps what an existing user had: unset `agent.palette` is Automatic, which shows Wisp in black
/// or white as before and KemoSabe in the look picked for it before palettes were shared
/// (`kemosabe.look`: unset is Apricot, "glass" is Pearl at full glass); unset `agent.glassLevel`
/// is KemoSabe's earlier glass, felt or full (`agent.glass`, else that saved look's), and Wisp solid.
struct AgentColourSettings: DynamicProperty {
    @AppStorage(WidgetOptions.Keys.agentPalette) var paletteID = AgentPalette.automatic.id
    @AppStorage(WidgetOptions.Keys.agentThemeColours) var themeColours: String?
    @AppStorage(WidgetOptions.Keys.agentGlass) var savedGlass: Double?
    @AppStorage(WidgetOptions.Keys.agentGlassLevel) var glassLevel: Double?
    @AppStorage(WidgetOptions.Keys.agentCustomBody) var customBody = AgentPalette.apricot.body
    @AppStorage(WidgetOptions.Keys.agentCustomFace) var customFace = AgentPalette.apricot.accent
    @AppStorage(WidgetOptions.Keys.kemoSabeLook) var savedLook: String?

    var palette: AgentPalette { AgentPalette.resolve(paletteID, themeColours: themeColours) }
    /// KemoSabe's glass.
    var glass: Double { AgentColours.glass(level: glassLevel, saved: savedGlass, look: savedLook) }
    /// Wisp's glass: only the level, so nobody's Wisp turns to glass on its own.
    var wispGlass: Double { AgentColours.wispGlass(level: glassLevel) }

    /// KemoSabe painted in `palette` (the picked one when nil).
    func kemoSabe(_ palette: AgentPalette? = nil) -> KemoSabeLook {
        AgentColours.kemoSabe(palette ?? self.palette, custom: (customBody, customFace), look: savedLook, glass: glass)
    }

    /// The colour `palette` gives Wisp's eyes, or nil for plain black or white.
    func wispEye(_ palette: AgentPalette? = nil) -> KemoSabeRGB? {
        AgentColours.wispEye(palette ?? self.palette, customFace: customFace)
    }
}

/// How the shared palette resolves for each character, and picking one.
enum AgentColours {
    /// KemoSabe's glass: the level, else its earlier switch, which showed glass from 0.5 up.
    static func glass(level: Double?, saved: Double?, look: String?) -> Double {
        if let level { return max(0, min(1, level)) }
        if let saved { return saved >= 0.5 ? 1 : 0 }
        return look == "glass" ? 1 : 0
    }

    static func wispGlass(level: Double?) -> Double { max(0, min(1, level ?? 0)) }

    /// KemoSabe's own colours, under Automatic: the look picked for it before palettes were shared.
    static func ownKemoSabe(look: String?) -> AgentPalette {
        if look == "glass" { return .pearl }
        return AgentPalette.palettes.first { $0.id == look } ?? .apricot
    }

    static func kemoSabe(_ palette: AgentPalette, custom: (body: String, face: String), look: String?, glass: Double) -> KemoSabeLook {
        switch palette.id {
        case AgentPalette.automatic.id: return KemoSabeLook(ownKemoSabe(look: look), glass: glass)
        case AgentPalette.custom.id: return KemoSabeLook(body: custom.body, face: custom.face, glass: glass)
        default: return KemoSabeLook(palette, glass: glass)
        }
    }

    static func wispEye(_ palette: AgentPalette, customFace: String) -> KemoSabeRGB? {
        switch palette.id {
        case AgentPalette.automatic.id: return nil
        case AgentPalette.custom.id: return KemoSabeRGB(hex: customFace)
        default: return KemoSabeRGB(hex: palette.eye ?? palette.accent)
        }
    }

    /// KemoSabe as the settings stand, for code outside a view.
    static func currentKemoSabe(_ defaults: UserDefaults = .standard) -> KemoSabeLook {
        let look = defaults.string(forKey: WidgetOptions.Keys.kemoSabeLook)
        let saved = defaults.object(forKey: WidgetOptions.Keys.agentGlass) as? Double
        let level = defaults.object(forKey: WidgetOptions.Keys.agentGlassLevel) as? Double
        let custom = (defaults.string(forKey: WidgetOptions.Keys.agentCustomBody) ?? AgentPalette.apricot.body,
                      defaults.string(forKey: WidgetOptions.Keys.agentCustomFace) ?? AgentPalette.apricot.accent)
        let palette = AgentPalette.resolve(defaults.string(forKey: WidgetOptions.Keys.agentPalette),
                                           themeColours: defaults.string(forKey: WidgetOptions.Keys.agentThemeColours))
        return kemoSabe(palette, custom: custom, look: look, glass: glass(level: level, saved: saved, look: look))
    }

    /// Sets the glass level for both characters.
    static func setGlass(_ level: Double, _ defaults: UserDefaults = .standard) {
        defaults.set(max(0, min(1, level)), forKey: WidgetOptions.Keys.agentGlassLevel)
    }

    /// Picks a palette for both characters. Picking one (not Automatic) retires KemoSabe's own saved
    /// look, so Automatic afterwards is Apricot; a saved glass look keeps its glass.
    static func choose(_ palette: AgentPalette, _ defaults: UserDefaults = .standard) {
        if palette.id != AgentPalette.automatic.id, let look = defaults.string(forKey: WidgetOptions.Keys.kemoSabeLook) {
            if look == "glass", defaults.object(forKey: WidgetOptions.Keys.agentGlass) == nil,
               defaults.object(forKey: WidgetOptions.Keys.agentGlassLevel) == nil {
                defaults.set(1.0, forKey: WidgetOptions.Keys.agentGlass)
            }
            defaults.removeObject(forKey: WidgetOptions.Keys.kemoSabeLook)
        }
        defaults.set(palette.id, forKey: WidgetOptions.Keys.agentPalette)
    }

    /// A colour as six hex digits, for Custom's colour pickers.
    static func hex(_ color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
}

/// Six hex digits as sRGB components, mixed to make a palette's shades.
struct KemoSabeRGB: Hashable {
    var r: Double, g: Double, b: Double

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        r = Double((value >> 16) & 0xFF) / 255; g = Double((value >> 8) & 0xFF) / 255; b = Double(value & 0xFF) / 255
    }

    static let white = KemoSabeRGB(r: 1, g: 1, b: 1)
    static let black = KemoSabeRGB(r: 0, g: 0, b: 0)

    func mixed(_ other: KemoSabeRGB, _ amount: Double) -> KemoSabeRGB {
        KemoSabeRGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }

    /// Relative luminance, 0 black to 1 white.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Lightened (on a dark Nook) or darkened (on a light one) just enough to read, keeping its hue.
    func legible(onLight light: Bool) -> KemoSabeRGB {
        var colour = self
        for _ in 0..<8 {
            if light ? colour.luminance <= 0.3 : colour.luminance >= 0.22 { break }
            colour = colour.mixed(light ? .black : .white, 0.22)
        }
        return colour
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}


extension Color {
    /// A colour from six hex digits, for the agent's palettes.
    init(kemoHex hex: String) {
        self = KemoSabeRGB(hex: hex).color
    }
}
