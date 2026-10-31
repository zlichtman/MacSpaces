import AppKit
import SwiftUI

/// The Music page's cover as live ASCII art (Settings → Appearance → Album art): the scene
/// is drawn small in grey, sampled 2×4 pixels per character, and drawn in three of the
/// theme's colours, or each character in the cover's colour under it (`AsciiColouring`). It animates at 30 fps only while the song plays and motion is allowed.
struct AsciiCover: View {
    let artwork: NSImage?
    let size: CGFloat
    var style: AsciiStyle
    var scene: AsciiScene
    var detail: AsciiDetail
    /// The song's position now, for the beat and the spin.
    var position: () -> Double
    var playing: Bool
    var colouring: AsciiColouring = .theme
    /// The song (title, artist, album), so a new song always prepares its cover.
    var song = ""
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var prepared = AsciiCoverCache.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = !playing || reduceMotion || theme.reduceMotion
        Group {
            if still {
                canvas(time: position())
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in canvas(time: position()) }
            }
        }
        .frame(width: size, height: size)
        // Runs again for every new cover, including one that arrives after its song.
        .task(id: "\(song)|\(artwork.map { "\(ObjectIdentifier($0))\($0.size)" } ?? "none")") { prepared.prepare(artwork) }
        .accessibilityLabel("Album art as ASCII")
    }

    private func canvas(time: Double) -> some View {
        let colors = AsciiColors(theme: theme)
        let cover = prepared.cover(for: artwork)
        return Canvas(rendersAsynchronously: false) { context, canvasSize in
            let font = detail.fontSize
            let cellWidth = font * 0.6, cellHeight = (font * 1.12 * 100).rounded() / 100
            let columns = max(4, Int(canvasSize.width / cellWidth)), rows = max(3, Int(canvasSize.height / cellHeight))
            let envelope = AsciiArt.beat(position: time, tempo: 112)
            let luminance = AsciiSampler.shared.sample(scene: scene, cover: cover, columns: columns, rows: rows,
                                                       cellWidth: cellWidth, cellHeight: cellHeight, time: time, beat: envelope)
            let cells = AsciiArt.convert(luminance, style: style, columns: columns, rows: rows, tick: Int(time * 6))
            let left = (canvasSize.width - CGFloat(columns) * cellWidth) / 2
            let top = (canvasSize.height - CGFloat(rows) * cellHeight) / 2
            let shading = [colors.dim, colors.mid, colors.bright]
            // Cover colours: one palette index per cell (`AsciiColors.coverInk`), or the
            // theme's bucket where the scene there isn't the cover.
            let tones: [Int]? = colouring == .cover
                ? AsciiSampler.shared.colours(scene: scene, cover: cover, columns: columns, rows: rows, cellWidth: cellWidth,
                                              cellHeight: cellHeight, time: time, beat: envelope)
                : nil
            func ink(_ index: Int, _ cell: AsciiCell) -> Int {
                if let tones, index < tones.count, tones[index] >= 0 { return 3 + AsciiColors.coverIndex(tones[index], level: cell.level) }
                return cell.bucket
            }
            func colour(_ key: Int) -> Color { key < 3 ? shading[key] : AsciiColors.coverInk(key - 3, light: colors.light) }
            if style == .braille {
                // Dots drawn as circles: exact on any font, one fill per colour.
                var paths: [Int: Path] = [:]
                let radius = min(cellWidth / 2, cellHeight / 4) * 0.36
                for (index, cell) in cells.enumerated() where cell.dots != 0 {
                    let key = ink(index, cell)
                    var path = paths[key] ?? Path()
                    defer { paths[key] = path }
                    let x = left + CGFloat(index % columns) * cellWidth, y = top + CGFloat(index / columns) * cellHeight
                    for row in 0..<4 {
                        for column in 0..<2 where cell.dots & AsciiArt.brailleBits[row][column] != 0 {
                            let center = CGPoint(x: x + (CGFloat(column) + 0.5) * cellWidth / 2, y: y + (CGFloat(row) + 0.5) * cellHeight / 4)
                            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                        }
                    }
                }
                for (key, path) in paths { context.fill(path, with: .color(colour(key))) }
            } else {
                var resolved: [String: GraphicsContext.ResolvedText] = [:]
                for (index, cell) in cells.enumerated() where !cell.isBlank {
                    let tone = ink(index, cell)
                    let key = "\(tone)\(cell.character)"
                    let text = resolved[key] ?? {
                        let made = context.resolve(Text(String(cell.character)).font(.custom("Menlo", size: font)).foregroundColor(colour(tone)))
                        resolved[key] = made
                        return made
                    }()
                    context.draw(text, at: CGPoint(x: left + CGFloat(index % columns) * cellWidth,
                                                   y: top + CGFloat(index / columns) * cellHeight), anchor: .topLeading)
                }
            }
        }
    }
}

/// The three ink colours from the theme: dim (background toward ink), middle (ink toward the
/// accent) and the accent itself, so every Terminal and nature theme gets its own.
struct AsciiColors {
    let dim: Color, mid: Color, bright: Color
    let light: Bool

    @MainActor init(theme: ThemeStore) {
        let light = theme.nookScheme == .light
        self.light = light
        let background = NSColor(theme.notch.surface), ink = NSColor(theme.nookForeground), accent = NSColor(theme.notch.accent)
        dim = Color(nsColor: Self.mix(background, ink, light ? 0.45 : 0.38))
        mid = Color(nsColor: Self.mix(ink, accent, 0.35))
        bright = Color(nsColor: accent)
    }

    /// Cover colours in 18 hues, 3 saturations and 3 brightnesses (a palette index, so a frame
    /// resolves a few dozen inks, not one per character); brightness follows the cell.
    static let hues = 18, saturations = 3, values = 3

    /// A cell's ink: its cover colour's hue and saturation with three brightness steps by level.
    static func coverIndex(_ tone: Int, level: Float) -> Int { tone * values + min(values - 1, Int(level * Float(values))) }

    /// Dark Nooks get bright, readable colours; light ones deeper versions of the same.
    static func coverInk(_ index: Int, light: Bool) -> Color {
        let value = index % values, tone = index / values
        let hue = Double(tone / saturations) / Double(hues), saturation = 0.35 + 0.3 * Double(tone % saturations)
        let brightness = light ? 0.62 - 0.12 * Double(value) : 0.6 + 0.2 * Double(value)
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    /// A pixel's palette tone, or −1 when it's grey (the record, the arm, the sky), which
    /// keeps the theme's colours.
    static func tone(red r: CGFloat, green g: CGFloat, blue b: CGFloat) -> Int {
        let high = max(r, g, b), low = min(r, g, b)
        guard high > 0.08, (high - low) / high > 0.18 else { return -1 }
        var hue = NSColor(srgbRed: r, green: g, blue: b, alpha: 1).hueComponent
        if hue >= 1 { hue = 0 }
        let step = min(hues - 1, Int((hue * CGFloat(hues)).rounded()) % hues)
        let saturation = min(saturations - 1, Int((high - low) / high * CGFloat(saturations)))
        return step * saturations + saturation
    }

    static func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return b }
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
    }
}

/// A cover ready for the ASCII scenes: a 256×256 grey image and its luminance, and a
/// 64×64 colour copy for cover colours.
final class AsciiPreparedCover {
    let image: CGImage
    let luminance: [Float]
    let colour: CGImage?
    init(image: CGImage, luminance: [Float], colour: CGImage?) { self.image = image; self.luminance = luminance; self.colour = colour }
}

/// Prepares each new cover once, off the main thread on one serial worker; a newer cover
/// replaces an older one still in progress.
@MainActor
final class AsciiCoverCache: ObservableObject {
    static let shared = AsciiCoverCache()
    /// The artwork itself is held, not just its address: a new cover can be allocated where
    /// the last one was, and must never be taken for it.
    @Published private(set) var current: (artwork: NSImage, cover: AsciiPreparedCover)?
    private var requested: NSImage?
    private let worker = DispatchQueue(label: "ascii-cover", qos: .utility)

    func cover(for artwork: NSImage?) -> AsciiPreparedCover? {
        guard let artwork, let current, current.artwork === artwork else { return nil }
        return current.cover
    }

    func prepare(_ artwork: NSImage?) {
        guard let artwork else { requested = nil; return }
        guard requested !== artwork else { return }
        // Set first, so a cover still being made for a song skipped past can't land.
        requested = artwork
        guard current?.artwork !== artwork else { return }
        guard let source = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        worker.async {
            let prepared = Self.make(source)
            DispatchQueue.main.async {
                guard self.requested === artwork, let prepared else { return }
                self.current = (artwork, prepared)
            }
        }
    }

    #if DEBUG
    /// Captures: prepare on the spot (their recording loop holds the main queue).
    func prepareNow(_ artwork: NSImage?) {
        guard let artwork, let source = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let prepared = Self.make(source) else { return }
        requested = artwork
        current = (artwork, prepared)
    }
    #endif

    nonisolated static func make(_ source: CGImage) -> AsciiPreparedCover? {
        let side = 256
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context.makeImage(), let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side)
        // Row 0 of the buffer is the image's top row.
        let luminance = (0..<(side * side)).map { Float(bytes[$0]) / 255 }
        let small = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        small?.interpolationQuality = .medium
        small?.draw(source, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        return AsciiPreparedCover(image: image, luminance: luminance, colour: small?.makeImage())
    }
}

/// Draws a scene into a small grey bitmap (2 pixels per character across, 4 down), scaled
/// to the real cell shape so circles stay round, and returns its luminance after the
/// contrast curve.
@MainActor
final class AsciiSampler {
    static let shared = AsciiSampler()
    private var context: CGContext?
    private var colourContext: CGContext?

    /// The scene drawn once more, one pixel per character and with the cover in colour:
    /// each cell's palette tone (`AsciiColors.tone`), −1 where it's grey.
    func colours(scene: AsciiScene, cover: AsciiPreparedCover?, columns: Int, rows: Int, cellWidth: CGFloat,
                 cellHeight: CGFloat, time: Double, beat: Double) -> [Int] {
        guard let image = cover?.colour else { return [] }
        if colourContext?.width != columns || colourContext?.height != rows {
            colourContext = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        }
        guard let g = colourContext, let data = g.data else { return [] }
        let width = CGFloat(columns) * cellWidth, height = CGFloat(rows) * cellHeight
        g.saveGState()
        g.translateBy(x: 0, y: CGFloat(rows))
        g.scaleBy(x: CGFloat(columns) / width, y: -CGFloat(rows) / height)
        if scene == .spiral {
            // Only the cover in the middle has colour; the arms stay the theme's.
            let m = min(width, height), R = m * 0.24
            g.setFillColor(Self.gray(0)); g.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let disc = CGRect(x: width / 2 - R, y: height / 2 - R, width: R * 2, height: R * 2)
            g.saveGState(); g.addEllipse(in: disc); g.clip(); Self.drawImage(image, in: disc, context: g); g.restoreGState()
        } else {
            Self.draw(scene, in: g, width: width, height: height, time: time, beat: beat, cover: image)
        }
        g.restoreGState()
        let bytes = data.bindMemory(to: UInt8.self, capacity: columns * rows * 4)
        return (0..<(columns * rows)).map { index in
            AsciiColors.tone(red: CGFloat(bytes[index * 4]) / 255, green: CGFloat(bytes[index * 4 + 1]) / 255,
                             blue: CGFloat(bytes[index * 4 + 2]) / 255)
        }
    }

    func sample(scene: AsciiScene, cover: AsciiPreparedCover?, columns: Int, rows: Int, cellWidth: CGFloat,
                cellHeight: CGFloat, time: Double, beat: Double) -> [Float] {
        let sampleWidth = columns * 2, sampleHeight = rows * 4
        let width = CGFloat(columns) * cellWidth, height = CGFloat(rows) * cellHeight
        if scene == .spiral {
            var values = [Float](repeating: 0, count: sampleWidth * sampleHeight)
            for y in 0..<sampleHeight {
                for x in 0..<sampleWidth {
                    let value = Self.spiral(x: (CGFloat(x) + 0.5) * width / CGFloat(sampleWidth), y: (CGFloat(y) + 0.5) * height / CGFloat(sampleHeight),
                                            width: width, height: height, time: time, beat: beat, cover: cover)
                    values[y * sampleWidth + x] = AsciiArt.contrast(value)
                }
            }
            return values
        }
        if context?.width != sampleWidth || context?.height != sampleHeight {
            context = CGContext(data: nil, width: sampleWidth, height: sampleHeight, bitsPerComponent: 8, bytesPerRow: sampleWidth,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        }
        guard let context, let data = context.data else { return [] }
        context.saveGState()
        // Top-left origin, in the scene's own units (as the reference's canvas).
        context.translateBy(x: 0, y: CGFloat(sampleHeight))
        context.scaleBy(x: CGFloat(sampleWidth) / width, y: -CGFloat(sampleHeight) / height)
        Self.draw(scene, in: context, width: width, height: height, time: time, beat: beat, cover: cover?.image)
        context.restoreGState()
        let bytes = data.bindMemory(to: UInt8.self, capacity: sampleWidth * sampleHeight)
        return (0..<(sampleWidth * sampleHeight)).map { AsciiArt.contrast(Float(bytes[$0]) / 255) }
    }

    private static func gray(_ value: CGFloat, _ alpha: CGFloat = 1) -> CGColor { CGColor(gray: value, alpha: alpha) }

    /// Draws an image right way up in a top-left-origin context.
    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private static func draw(_ scene: AsciiScene, in g: CGContext, width W: CGFloat, height H: CGFloat, time t: Double, beat env: Double, cover: CGImage?) {
        g.setFillColor(gray(0)); g.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let cx = W / 2, cy = H / 2, m = min(W, H), env = CGFloat(env), t = CGFloat(t)
        switch scene {
        case .cover:
            let s = m * 0.94
            if let cover { drawImage(cover, in: CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s), context: g) }
        case .pulse:
            let s = m * (0.78 + env * 0.07)
            g.setStrokeColor(gray(1, 0.5 * env)); g.setLineWidth(m * 0.02)
            g.addArc(center: CGPoint(x: cx, y: cy), radius: s * 0.5 + (1 - env) * m * 0.35, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            g.strokePath()
            g.saveGState(); g.translateBy(x: cx, y: cy); g.rotate(by: sin(t * 0.6) * 0.04)
            if let cover { drawImage(cover, in: CGRect(x: -s / 2, y: -s / 2, width: s, height: s), context: g) }
            g.restoreGState()
        case .vinyl:
            let R = m * 0.47, angle = t * .pi * 2 * (33.333 / 60)
            g.saveGState(); g.translateBy(x: cx, y: cy)
            g.setFillColor(gray(0x26 / 255)); g.fillEllipse(in: CGRect(x: -R, y: -R, width: R * 2, height: R * 2))
            g.setLineWidth(R * 0.012)
            var r = R * 0.4
            while r < R * 0.98 {
                g.setStrokeColor(gray(Int(r.rounded()) % 3 != 0 ? 0x4a / 255 : 0x6a / 255))
                g.strokeEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
                r += R * 0.028
            }
            // The sheen: two fixed wedges, brighter mid-way out.
            if let sheen = CGGradient(colorSpace: CGColorSpaceCreateDeviceGray(), colorComponents: [1, 0, 1, 0.28, 1, 0.05], locations: [0, 0.6, 1], count: 3) {
                for start in [-0.9, 2.24] as [CGFloat] {
                    g.saveGState()
                    g.move(to: .zero); g.addArc(center: .zero, radius: R * 0.98, startAngle: start, endAngle: start + 0.42, clockwise: false); g.closePath(); g.clip()
                    g.drawRadialGradient(sheen, startCenter: .zero, startRadius: R * 0.38, endCenter: .zero, endRadius: R, options: [])
                    g.restoreGState()
                }
            }
            g.rotate(by: angle)
            if let cover {
                g.saveGState()
                g.addEllipse(in: CGRect(x: -R * 0.37, y: -R * 0.37, width: R * 0.74, height: R * 0.74)); g.clip()
                drawImage(cover, in: CGRect(x: -R * 0.37, y: -R * 0.37, width: R * 0.74, height: R * 0.74), context: g)
                g.restoreGState()
            }
            g.setFillColor(gray(0)); g.fillEllipse(in: CGRect(x: -R * 0.03, y: -R * 0.03, width: R * 0.06, height: R * 0.06))
            g.restoreGState()
            g.setStrokeColor(gray(0xcf / 255)); g.setLineWidth(m * 0.022); g.setLineCap(.round); g.setLineJoin(.round)
            g.move(to: CGPoint(x: cx + R * 0.95, y: cy - R)); g.addLine(to: CGPoint(x: cx + R * 0.88, y: cy - R * 0.1))
            g.addLine(to: CGPoint(x: cx + R * 0.55, y: cy + R * 0.42)); g.strokePath()
            g.setFillColor(gray(0xe8 / 255)); g.fillEllipse(in: CGRect(x: cx + R * 0.95 - m * 0.05, y: cy - R - m * 0.05, width: m * 0.1, height: m * 0.1))
        case .horizon:
            let horizon = H * 0.6, r = m * 0.36, sunY = horizon - r * 0.35
            if let sun = CGGradient(colorSpace: CGColorSpaceCreateDeviceGray(), colorComponents: [1, 1, 0x77 / 255, 1], locations: [0, 1], count: 2) {
                g.saveGState(); g.addEllipse(in: CGRect(x: cx - r, y: sunY - r, width: r * 2, height: r * 2)); g.clip()
                g.drawLinearGradient(sun, start: CGPoint(x: 0, y: sunY - r), end: CGPoint(x: 0, y: sunY + r), options: [])
                g.restoreGState()
            }
            let offset = (t * 14).truncatingRemainder(dividingBy: 22)
            var y = sunY - r * 0.1 + offset - 22
            g.setFillColor(gray(0))
            while y < horizon {
                if y >= sunY - r * 0.1 { g.fill(CGRect(x: 0, y: y, width: W, height: 2 + max(0, (y - sunY) / r) * 9)) }
                y += 22
            }
            g.fill(CGRect(x: 0, y: horizon, width: W, height: H - horizon))
            g.setStrokeColor(gray(0xb0 / 255)); g.setLineWidth(3)
            for i in -12...12 {
                g.move(to: CGPoint(x: cx + CGFloat(i) * 8, y: horizon)); g.addLine(to: CGPoint(x: cx + CGFloat(i) * W * 0.22, y: H)); g.strokePath()
            }
            let speed = (t * 0.6).truncatingRemainder(dividingBy: 1)
            for j in 0..<10 {
                let z = (CGFloat(j) + speed) / 10, line = horizon + (H - horizon) * z * z
                g.setStrokeColor(gray(0xb0 / 255, 0.3 + z * 0.7))
                g.move(to: CGPoint(x: 0, y: line)); g.addLine(to: CGPoint(x: W, y: line)); g.strokePath()
            }
        case .spiral:
            break
        }
    }

    /// Four arms turning around the cover in the middle.
    private static func spiral(x: CGFloat, y: CGFloat, width W: CGFloat, height H: CGFloat, time t: Double, beat env: Double, cover: AsciiPreparedCover?) -> Float {
        let cx = W / 2, cy = H / 2, m = min(W, H), dx = x - cx, dy = y - cy
        let r = (dx * dx + dy * dy).squareRoot(), a = atan2(dy, dx), R = m * 0.24
        if r < R {
            guard let cover else { return 0.4 }
            let u = min(255, max(0, Int(((dx / R) * 0.5 + 0.5) * 255))), v = min(255, max(0, Int(((dy / R) * 0.5 + 0.5) * 255)))
            return cover.luminance[v * 256 + u]
        }
        var value = 0.5 + 0.5 * sin(4 * a + r * 0.11 - CGFloat(t) * 3.2)
        value = value > 0.55 ? 1 : value * 0.5
        return Float(value * max(0, 1 - (r - R) / (m * 0.75)) * (0.75 + CGFloat(env) * 0.25))
    }
}
