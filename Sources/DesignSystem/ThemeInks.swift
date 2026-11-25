import AppKit
import SwiftUI

/// A theme's full set of colours beyond its background, text and accent. Terminal themes bring
/// their own sixteen; one with none, like a scene, gets a set worked out from its accent, so
/// its colours sit together. Every ink stays readable on the Nook, so a theme's dark blue never
/// vanishes into a dark panel.
struct ThemeInks {
    let red: Color, green: Color, yellow: Color, blue: Color, magenta: Color, cyan: Color
    /// The theme's text and accent, held to the same contrast as the rest.
    let text: Color, accent: Color

    /// The contrast an ink needs on the Nook: small type, but never body text.
    static let leastContrast = 3.0
    private static var cache: (key: String, inks: ThemeInks)?

    @MainActor static func current(_ theme: ThemeStore) -> ThemeInks {
        let ansi = ansi(theme)
        let surface = hex(theme.notch.surface), raised = hex(theme.notch.surfaceSecondary)
        let ink = hex(theme.nookForeground), accent = hex(theme.notch.accent)
        // A see-through Nook shows whatever is behind it, so its colours need more to stand on.
        let least = (theme.activeLook?.seeThrough ?? 0) > 0.01 ? 4.5 : leastContrast
        let key = [surface, raised, ink, accent, "\(least)", ansi?.joined() ?? ""].joined(separator: "|")
        if let cache, cache.key == key { return cache.inks }
        let picks = hexes(ansi: ansi, accent: accent, surface: surface, foreground: ink, raised: raised, least: least)
        func colour(_ index: Int) -> Color { Color(themeHex: picks[index]) ?? theme.notch.accent }
        let readableAccent = readable(accent, surface: surface, raised: raised, foreground: ink, least: least)
        let inks = ThemeInks(red: colour(0), green: colour(1), yellow: colour(2), blue: colour(3), magenta: colour(4), cyan: colour(5),
                             text: theme.nookForeground, accent: Color(themeHex: readableAccent) ?? theme.notch.accent)
        cache = (key, inks)
        return inks
    }

    /// The colour a part of the Vinyl look uses: its link, else what it has always used.
    func colour(_ part: VinylPart, links: [String: String]) -> Color { colour(links[part.rawValue].flatMap(VinylInk.init) ?? part.standard) }

    func colour(_ ink: VinylInk) -> Color {
        switch ink {
        case .text: return text
        case .accent: return accent
        case .red: return red
        case .green: return green
        case .yellow: return yellow
        case .blue: return blue
        case .magenta: return magenta
        case .cyan: return cyan
        }
    }

    /// The colour as it is if it reads on both the Nook's colours, else moved toward the text until it does.
    static func readable(_ colour: String, surface: String, raised: String? = nil, foreground: String, least: Double = leastContrast) -> String {
        func reads(_ candidate: String) -> Bool {
            CustomThemeColors.contrast(candidate, surface) >= least
                && raised.map { CustomThemeColors.contrast(candidate, $0) >= least } ?? true
        }
        var mixed = colour, step = 0.0
        while !reads(mixed), step < 1 {
            step += 0.1
            mixed = mix(colour, foreground, step)
        }
        return mixed
    }

    /// The theme in use's ANSI colours: a library theme's own, or the original of one of our palettes.
    @MainActor private static func ansi(_ theme: ThemeStore) -> [String]? {
        if theme.family == .ghostty { return GhosttyThemes.selected?.ansi }
        GhosttyLibrary.shared.load()
        return GhosttyThemes.originals[theme.family].flatMap { GhosttyLibrary.shared.theme(named: $0)?.ansi }
    }

    /// Red, green, yellow, blue, magenta and cyan as hex: the normal colour, else its bright one,
    /// else the normal one moved toward the text until it reads.
    static func hexes(ansi: [String]?, accent: String, surface: String, foreground: String, raised: String? = nil,
                      least: Double = leastContrast) -> [String] {
        let wanted = ansi?.count == 16 ? nil : derived(accent: accent)
        func reads(_ colour: String) -> Bool {
            CustomThemeColors.contrast(colour, surface) >= least && raised.map { CustomThemeColors.contrast(colour, $0) >= least } ?? true
        }
        return (0..<6).map { index in
            let normal = wanted?[index] ?? ansi![index + 1]
            if reads(normal) { return normal }
            if let ansi, ansi.count == 16, reads(ansi[index + 9]) { return ansi[index + 9] }
            return readable(normal, surface: surface, raised: raised, foreground: foreground, least: least)
        }
    }

    /// The six hues at the accent's own strength and brightness.
    private static func derived(accent: String) -> [String] {
        let base = NSColor(cgColor: TerminalPillColours.colour(accent) ?? .white)?.usingColorSpace(.sRGB) ?? .white
        let saturation = max(0.35, base.saturationComponent), brightness = max(0.6, base.brightnessComponent)
        return [0.0, 0.33, 0.13, 0.6, 0.85, 0.5].map { hue in
            hex(NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1))
        }
    }

    private static func mix(_ a: String, _ b: String, _ t: Double) -> String {
        guard let from = TerminalPillColours.colour(a).flatMap({ NSColor(cgColor: $0) }),
              let to = TerminalPillColours.colour(b).flatMap({ NSColor(cgColor: $0) }),
              let mixed = from.blended(withFraction: t, of: to) else { return a }
        return hex(mixed)
    }

    /// The theme's accent for a bubble beside the closed notch, lifted when it wouldn't show on the bubble's black.
    @MainActor static func bubbleAccent(_ theme: ThemeStore) -> Color {
        let lifted = readable(hex(theme.notch.accent), surface: "000000", foreground: "FFFFFF", least: 3)
        return Color(themeHex: lifted) ?? theme.notch.accent
    }

    private static func hex(_ colour: Color) -> String { hex(NSColor(colour)) }

    private static func hex(_ colour: NSColor) -> String {
        let rgb = colour.usingColorSpace(.sRGB) ?? colour
        return String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
}

/// The colours a theme offers the Vinyl look's parts.
enum VinylInk: String, CaseIterable, Identifiable {
    case text, accent, red, green, yellow, blue, magenta, cyan
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// The parts of the Vinyl look that can be linked to another of the theme's colours.
enum VinylPart: String, CaseIterable, Identifiable {
    case title, artist, lyrics, times, bar, play, skip, status, record
    var id: String { rawValue }
    var label: String { self == .skip ? "Buttons" : rawValue.capitalized }
    /// What it uses until it's linked to something else.
    var standard: VinylInk {
        switch self {
        case .title, .skip: return .text
        case .artist, .record: return .blue
        case .lyrics, .play: return .accent
        case .times: return .cyan
        case .bar: return .green
        case .status: return .yellow
        }
    }
}
