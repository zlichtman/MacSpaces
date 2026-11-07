import SwiftUI
import AppKit
import os

/// How KemoSabe looks (Settings → Tsukumo → Agent): its cloud in one of Tsukumo's companion
/// palettes, or its glass figure. Apricot is the painted art as it is; the other palettes repaint
/// it (`KemoSabeArt`), as Tsukumo's app did.
struct KemoSabeLook: Identifiable, Hashable {
    let id: String
    let name: String
    /// The body and the coral paint as hex; nil for glass, which is a picture of its own.
    let body: String?
    let accent: String?
    /// The colour behind it in the picker.
    let background: String

    var isGlass: Bool { body == nil }

    static let apricot = KemoSabeLook(id: "apricot", name: "Apricot", body: "F5E7CF", accent: "EF705B", background: "211B2C")
    static let glass = KemoSabeLook(id: "glass", name: "Glass", body: nil, accent: nil, background: "1D2533")

    /// Apricot and glass, then Tsukumo's featured palettes, then the rest. Tsukumo's two-tone
    /// Classic went with its two-tone figure, and Blueberry was never offered.
    static let all: [KemoSabeLook] = [apricot, glass] + [
        ("matcha", "Matcha", "DCD89A", "6E7238", "282A1B"), ("lavender", "Lavender", "E2D9F5", "8563BD", "252039"),
        ("sky", "Sky", "D0E7F4", "397AA4", "192938"), ("rose", "Rose", "F5D7DD", "B74F76", "311E29"),
        ("aurora", "Aurora", "CBEAE1", "8276AE", "1D2533"), ("cocoa", "Cocoa", "E5CCAD", "815036", "2A211E"),
        ("graphite", "Graphite", "D5D3CF", "66656D", "202024"), ("butter", "Butter", "F5E5A6", "B47B35", "2A251C"),
        ("pistachio", "Pistachio", "CBECD2", "2E7355", "17372E"), ("peach", "Peach", "F3D0B8", "C96956", "302022"),
        ("porcelain", "Porcelain", "F0ECE5", "8091A2", "232930"), ("moss", "Moss", "91AD94", "344C3F", "182622"),
        ("midnight", "Midnight", "BFCBDC", "6D87AC", "141D2C"), ("cherry", "Cherry", "EDC8CC", "AE435C", "2B1923"),
        ("ember", "Ember", "F0A678", "913E49", "301D23"), ("lagoon", "Lagoon", "A7DCD8", "235D70", "112B34"),
        ("mulberry", "Mulberry", "CFA3CA", "663C6B", "2F1D33"), ("ink", "Ink", "7685B6", "FFF0CF", "121827"),
        ("paper", "Paper", "EEECE2", "353D4C", "1A202B"),
    ].map { KemoSabeLook(id: $0.0, name: $0.1, body: $0.2, accent: $0.3, background: $0.4) }

    static func named(_ id: String?) -> KemoSabeLook { all.first { $0.id == id } ?? apricot }
    static var current: KemoSabeLook { named(UserDefaults.standard.string(forKey: WidgetOptions.Keys.kemoSabeLook)) }
}

/// KemoSabe's art repainted in a palette, made off the main thread and kept once made. Each
/// pixel keeps its light and shade and takes the palette's body colour, or its accent where the
/// paint is saturated coral; in the reading picture the computer keeps its cream keys and dark
/// screen, and only its coral shell changes (ported from Tsukumo's `CompanionArt`).
enum KemoSabeArt {
    private struct Picture: @unchecked Sendable { let image: CGImage }
    private static let made = OSAllocatedUnfairLock(initialState: [String: Picture]())

    private static func key(searching: Bool, look: KemoSabeLook, small: Bool) -> String {
        "\(searching ? "searching" : "resting")|\(look.id)|\(small ? "s" : "l")"
    }

    /// The repainted picture, if it's been made.
    static func cached(searching: Bool, look: KemoSabeLook, small: Bool) -> CGImage? {
        let key = key(searching: searching, look: look, small: small)
        return made.withLock { $0[key]?.image }
    }

    /// Makes the picture on a worker; true once it's ready to draw.
    @MainActor static func make(searching: Bool, look: KemoSabeLook, small: Bool) async -> Bool {
        if cached(searching: searching, look: look, small: small) != nil { return true }
        guard let body = look.body, let accent = look.accent,
              let source = NSImage(named: searching ? "KemoSabeSearching" : "KemoSabe")?
                .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let key = key(searching: searching, look: look, small: small)
        let picture = Picture(image: source)
        let painted = await Task.detached(priority: .userInitiated) { [picture, body, accent, searching, small] in
            recolored(picture.image, body: Tint(hex: body), accent: Tint(hex: accent), props: searching, maxSide: small ? 160 : nil)
                .map(Picture.init)
        }.value
        guard let painted else { return false }
        made.withLock { $0[key] = painted }
        return true
    }

    struct Tint {
        var r: Float, g: Float, b: Float
        init(hex: String) {
            let value = UInt32(hex, radix: 16) ?? 0
            r = Float((value >> 16) & 0xFF) / 255; g = Float((value >> 8) & 0xFF) / 255; b = Float(value & 0xFF) / 255
        }
    }

    /// Where the computer is drawn in the reading picture, in unit coordinates: its monitor and
    /// keyboard, minus the paws resting on the keys.
    private static func isProp(x: Float, y: Float) -> Bool {
        func ellipse(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float) -> Bool {
            let dx = (x - cx) / rx, dy = (y - cy) / ry
            return dx * dx + dy * dy <= 1
        }
        if ellipse(0.318, 0.765, 0.085, 0.072) || ellipse(0.485, 0.765, 0.082, 0.072) { return false }
        if y >= 0.775 { return true }
        let (x0, y0, x1, y1, r): (Float, Float, Float, Float, Float) = (0.521, 0.524, 0.925, 0.87, 0.06)
        guard x >= x0, x <= x1, y >= y0, y <= y1 else { return false }
        let cx = min(max(x, x0 + r), x1 - r), cy = min(max(y, y0 + r), y1 - r)
        return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r
    }

    private static func recolored(_ image: CGImage, body: Tint, accent: Tint, props: Bool, maxSide: Int?) -> CGImage? {
        let scale = maxSide.map { min(1, Double($0) / Double(max(image.width, image.height))) } ?? 1
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let rowBytes = context.bytesPerRow
        let pixels = UnsafeMutableBufferPointer<UInt8>(start: data.assumingMemoryBound(to: UInt8.self), count: rowBytes * height)
        // The art's own cream, so Apricot would map to itself.
        let bodyR = body.r / 0.965, bodyG = body.g / 0.91, bodyB = body.b / 0.82
        for row in 0..<height {
            let y = (Float(row) + 0.5) / Float(height)
            for column in 0..<width {
                let i = row * rowBytes + column * 4
                let alpha = Float(pixels[i + 3]) / 255
                guard alpha > 0 else { continue }
                let unpremultiply = 1 / (255 * alpha)
                let r = min(1, Float(pixels[i]) * unpremultiply), g = min(1, Float(pixels[i + 1]) * unpremultiply)
                let b = min(1, Float(pixels[i + 2]) * unpremultiply)
                let light = r / 0.97
                let out: (Float, Float, Float)
                if props, isProp(x: (Float(column) + 0.5) / Float(width), y: y) {
                    let coral = smoothstep(0.12, 0.30, r - g)
                    out = (r + (accent.r * light - r) * coral, g + (accent.g * light - g) * coral, b + (accent.b * light - b) * coral)
                } else {
                    let coral = smoothstep(0.25, 0.43, r - g)
                    out = (r * bodyR + (accent.r * light - r * bodyR) * coral,
                           g * bodyG + (accent.g * light - g * bodyG) * coral,
                           b * bodyB + (accent.b * light - b * bodyB) * coral)
                }
                pixels[i] = channel(out.0, alpha); pixels[i + 1] = channel(out.1, alpha); pixels[i + 2] = channel(out.2, alpha)
            }
        }
        return context.makeImage()
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private static func channel(_ value: Float, _ alpha: Float) -> UInt8 {
        UInt8((min(1, max(0, value)) * alpha * 255).rounded())
    }
}

extension Color {
    /// A colour from six hex digits, for KemoSabe's palettes.
    init(kemoHex hex: String) {
        let tint = KemoSabeArt.Tint(hex: hex)
        self.init(.sRGB, red: Double(tint.r), green: Double(tint.g), blue: Double(tint.b))
    }
}
