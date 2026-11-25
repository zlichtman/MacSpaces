import AppKit
import ImageIO
import SwiftUI

/// The Music page's cover as live ASCII art (Settings → Heartable → Album art): the scene
/// is drawn small in grey (over the Around effect, if any), sampled 2×4 pixels per character, and
/// drawn in three of the theme's colours, or each character in the cover's colour under it
/// (`AsciiColouring`); the 8-bit and 16-bit styles draw square pixel blocks instead of
/// characters. It animates at 30 fps only while the song plays and motion is allowed.
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
    /// The song's length, for the Clock scene's hand; 0 (unknown) turns it once a minute.
    var duration: Double = 0
    /// What moves around and behind the scene; off draws only the scene.
    var around: AsciiAround = .off
    /// Draws the Vinyl scene's tonearm.
    var tonearm = true
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var prepared = AsciiCoverCache.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = !playing || reduceMotion
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
            // Pixel styles use square cells (a 16-bit cell holds 2×2 square blocks).
            let pixelSide = style.pixelsPerSide
            let cellWidth = pixelSide > 0 ? font * (pixelSide == 1 ? 0.8 : 1) : font * 0.6
            let cellHeight = pixelSide > 0 ? cellWidth : (font * 1.12 * 100).rounded() / 100
            let columns = max(4, Int(canvasSize.width / cellWidth)), rows = max(3, Int(canvasSize.height / cellHeight))
            let envelope = AsciiArt.beat(position: time, tempo: AsciiSampler.tempo)
            let progress = duration > 0 ? min(1, max(0, time / duration)) : max(0, time).truncatingRemainder(dividingBy: 60) / 60
            let luminance = AsciiSampler.shared.sample(scene: scene, around: around, cover: cover, columns: columns, rows: rows,
                                                       cellWidth: cellWidth, cellHeight: cellHeight, time: time, beat: envelope,
                                                       progress: progress, tonearm: tonearm)
            let cells = AsciiArt.convert(luminance, style: style, columns: columns, rows: rows, tick: Int(time * 6))
            let left = (canvasSize.width - CGFloat(columns) * cellWidth) / 2
            let top = (canvasSize.height - CGFloat(rows) * cellHeight) / 2
            let shading = [colors.dim, colors.mid, colors.bright]
            // Cover colours: one palette index per cell (`AsciiColors.coverInk`), or the
            // theme's bucket where the scene there isn't the cover.
            let tones: [Int]? = colouring == .cover
                ? AsciiSampler.shared.colours(scene: scene, cover: cover, columns: columns, rows: rows, cellWidth: cellWidth,
                                              cellHeight: cellHeight, time: time, beat: envelope, progress: progress, tonearm: tonearm)
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
            } else if pixelSide > 0 {
                // Pixel blocks as rects, one fill per colour: the theme's ramp by shade, or the
                // cover's colour with the shade as its brightness.
                let brightest = style.shades - 1, ramp = colors.ramp(brightest)
                let blockWidth = cellWidth / CGFloat(pixelSide), blockHeight = cellHeight / CGFloat(pixelSide)
                var paths: [Int: Path] = [:]
                for (index, cell) in cells.enumerated() where cell.pixels != 0 {
                    let x = left + CGFloat(index % columns) * cellWidth, y = top + CGFloat(index / columns) * cellHeight
                    for block in 0..<(pixelSide * pixelSide) {
                        let shade = cell.shade(block)
                        guard shade > 0 else { continue }
                        let key: Int
                        if let tones, index < tones.count, tones[index] >= 0 {
                            key = 16 + AsciiColors.coverIndex(tones[index], level: Float(shade) / Float(brightest))
                        } else {
                            key = shade
                        }
                        paths[key, default: Path()].addRect(CGRect(x: x + CGFloat(block % pixelSide) * blockWidth,
                                                                   y: y + CGFloat(block / pixelSide) * blockHeight,
                                                                   width: blockWidth, height: blockHeight))
                    }
                }
                for (key, path) in paths {
                    context.fill(path, with: .color(key < 16 ? ramp[key - 1] : AsciiColors.coverInk(key - 16, light: colors.light)))
                }
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

/// The three ink colours from the theme: dim (background toward its blue), middle (its magenta
/// toward the accent) and the accent itself, so the record and its arm carry the theme's own colours.
struct AsciiColors {
    let dim: Color, mid: Color, bright: Color
    let light: Bool
    private let inks: [NSColor]

    @MainActor init(theme: ThemeStore) {
        let light = theme.nookScheme == .light
        self.light = light
        let background = NSColor(theme.notch.surface), accent = NSColor(theme.notch.accent)
        let palette = ThemeInks.current(theme)
        // A linked record takes one colour in three strengths; otherwise the theme's three.
        let linked = WidgetOptions.shared.vinylLinks[VinylPart.record.rawValue].flatMap(VinylInk.init).map { NSColor(palette.colour($0)) }
        let inks = linked.map { [Self.mix(background, $0, 0.55), Self.mix(background, $0, 0.8), $0] }
            ?? [Self.mix(background, NSColor(palette.blue), 0.6), Self.mix(NSColor(palette.magenta), accent, 0.35), accent]
        self.inks = inks
        dim = Color(nsColor: inks[0])
        mid = Color(nsColor: inks[1])
        bright = Color(nsColor: inks[2])
    }

    /// `count` colours from dim through middle to the accent: the three themselves for 8-bit,
    /// with shades between them for 16-bit.
    func ramp(_ count: Int) -> [Color] {
        guard count > 3 else { return [dim, mid, bright] }
        return (0..<count).map { index in
            let t = CGFloat(index) / CGFloat(count - 1) * 2
            return Color(nsColor: t < 1 ? Self.mix(inks[0], inks[1], t) : Self.mix(inks[1], inks[2], t - 1))
        }
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
final class AsciiPreparedCover: @unchecked Sendable {
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
    /// The beat the scenes move to, in beats a minute.
    static let tempo: Double = 112
    private var context: CGContext?
    private var colourContext: CGContext?

    /// The scene drawn once more, one pixel per character and with the cover in colour:
    /// each cell's palette tone (`AsciiColors.tone`), −1 where it's grey (the Around effects
    /// are grey, so they're left out).
    func colours(scene: AsciiScene, cover: AsciiPreparedCover?, columns: Int, rows: Int, cellWidth: CGFloat,
                 cellHeight: CGFloat, time: Double, beat: Double, progress: Double = 0, tonearm: Bool = true) -> [Int] {
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
            Self.draw(scene, in: g, width: width, height: height, time: time, beat: beat, progress: progress, cover: image, colour: true,
                      tonearm: tonearm)
        }
        g.restoreGState()
        let bytes = data.bindMemory(to: UInt8.self, capacity: columns * rows * 4)
        return (0..<(columns * rows)).map { index in
            AsciiColors.tone(red: CGFloat(bytes[index * 4]) / 255, green: CGFloat(bytes[index * 4 + 1]) / 255,
                             blue: CGFloat(bytes[index * 4 + 2]) / 255)
        }
    }

    func sample(scene: AsciiScene, around: AsciiAround = .off, cover: AsciiPreparedCover?, columns: Int, rows: Int,
                cellWidth: CGFloat, cellHeight: CGFloat, time: Double, beat: Double, progress: Double = 0,
                tonearm: Bool = true) -> [Float] {
        let sampleWidth = columns * 2, sampleHeight = rows * 4
        let width = CGFloat(columns) * cellWidth, height = CGFloat(rows) * cellHeight
        if scene == .spiral && around == .off {
            return Self.spiralValues(width: width, height: height, sampleWidth: sampleWidth, sampleHeight: sampleHeight,
                                     time: time, beat: beat, cover: cover, behind: nil)
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
        if scene == .spiral {
            // The spiral is worked out per pixel: only the effect is drawn, and the brighter wins.
            context.setFillColor(Self.gray(0)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            Self.drawAround(around, in: context, width: width, height: height, time: time, beat: beat)
        } else {
            Self.draw(scene, around: around, in: context, width: width, height: height, time: time, beat: beat,
                      progress: progress, cover: cover?.image, tonearm: tonearm)
        }
        context.restoreGState()
        let bytes = data.bindMemory(to: UInt8.self, capacity: sampleWidth * sampleHeight)
        if scene == .spiral {
            return Self.spiralValues(width: width, height: height, sampleWidth: sampleWidth, sampleHeight: sampleHeight,
                                     time: time, beat: beat, cover: cover, behind: bytes)
        }
        return (0..<(sampleWidth * sampleHeight)).map { AsciiArt.contrast(Float(bytes[$0]) / 255) }
    }

    /// The spiral at every sample, or the brighter of it and the effect already drawn behind it.
    private static func spiralValues(width: CGFloat, height: CGFloat, sampleWidth: Int, sampleHeight: Int, time: Double,
                                     beat: Double, cover: AsciiPreparedCover?, behind: UnsafeMutablePointer<UInt8>?) -> [Float] {
        var values = [Float](repeating: 0, count: sampleWidth * sampleHeight)
        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                var value = spiral(x: (CGFloat(x) + 0.5) * width / CGFloat(sampleWidth), y: (CGFloat(y) + 0.5) * height / CGFloat(sampleHeight),
                                   width: width, height: height, time: time, beat: beat, cover: cover)
                if let behind { value = max(value, Float(behind[y * sampleWidth + x]) / 255) }
                values[y * sampleWidth + x] = AsciiArt.contrast(value)
            }
        }
        return values
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

    /// A steady pseudo-random 0…1 for `index` and `salt`, so effects are the same every frame.
    private static func hash(_ index: Int, _ salt: Int) -> CGFloat {
        let value = sin(Double(index) * 12.9898 + Double(salt) * 78.233) * 43_758.5453
        return CGFloat(value - value.rounded(.down))
    }

    /// Strokes a line dark and wide, then bright on top, so it reads over the cover.
    private static func outlined(_ g: CGContext, from a: CGPoint, to b: CGPoint, width: CGFloat, brightness: CGFloat = 1) {
        g.setLineCap(.round)
        for (shade, lineWidth) in [(CGFloat(0), width * 2.4), (brightness, width)] {
            g.setStrokeColor(gray(shade)); g.setLineWidth(lineWidth)
            g.move(to: a); g.addLine(to: b); g.strokePath()
        }
    }

    /// The Around effect, in greys no brighter than about 0.6 so the scene stays on top.
    private static func drawAround(_ around: AsciiAround, in g: CGContext, width W: CGFloat, height H: CGFloat, time: Double, beat env: Double) {
        let cx = W / 2, cy = H / 2, m = min(W, H), t = CGFloat(time)
        let reach = (W * W + H * H).squareRoot() / 2
        // Beats so far, surging on each beat: the whole part plus how far its envelope has fallen.
        let beats = AsciiArt.beats(position: time, tempo: tempo)
        let surge = CGFloat(beats.rounded(.down) + (1 - env))
        switch around {
        case .off:
            break
        case .rain:
            let spacing = m * 0.045, columns = Int(W / spacing) + 1, width = m * 0.022
            for column in 0..<columns {
                let speed = 0.35 + hash(column, 1) * 0.9, length = H * (0.12 + hash(column, 2) * 0.22)
                let travel = H + length
                let head = (t * speed * H + hash(column, 3) * travel * 3).truncatingRemainder(dividingBy: travel) - length * 0.2
                let x = (CGFloat(column) + 0.5) * spacing
                // A fading tail of four pieces and a bright head.
                for piece in 0..<4 {
                    let y = head - length * CGFloat(4 - piece) / 4
                    g.setFillColor(gray(0.1 + 0.1 * CGFloat(piece)))
                    g.fill(CGRect(x: x - width / 2, y: y, width: width, height: length / 4))
                }
                g.setFillColor(gray(0.6)); g.fill(CGRect(x: x - width / 2, y: head, width: width, height: width * 2))
            }
        case .warp:
            g.setLineCap(.round)
            for star in 0..<56 {
                let angle = hash(star, 4) * .pi * 2
                var z = hash(star, 5) + t * 0.12 + surge * 0.06
                z -= z.rounded(.down)
                let outer = reach * z * z, inner = outer * (0.78 - 0.1 * CGFloat(env))
                g.setStrokeColor(gray(0.12 + 0.48 * z)); g.setLineWidth(m * (0.01 + 0.02 * z))
                g.move(to: CGPoint(x: cx + cos(angle) * inner, y: cy + sin(angle) * inner))
                g.addLine(to: CGPoint(x: cx + cos(angle) * outer, y: cy + sin(angle) * outer)); g.strokePath()
            }
        case .tunnel:
            let rings = 9
            for ring in 0..<rings {
                var z = CGFloat(ring) / CGFloat(rings) - t * 0.18 - surge * 0.03
                z -= z.rounded(.down)
                let radius = reach * z * z
                g.setStrokeColor(gray(0.1 + 0.5 * z)); g.setLineWidth(m * (0.008 + 0.03 * z))
                g.strokeEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
            }
        }
    }

    /// Draws `scene` over `around` on black. `colour` is the cover-colour pass: a faint cover
    /// is drawn at full strength there, so its colours count.
    private static func draw(_ scene: AsciiScene, around: AsciiAround = .off, in g: CGContext, width W: CGFloat, height H: CGFloat,
                             time: Double, beat: Double, progress: Double = 0, cover: CGImage?, colour: Bool = false,
                             tonearm: Bool = true) {
        g.setFillColor(gray(0)); g.fill(CGRect(x: 0, y: 0, width: W, height: H))
        drawAround(around, in: g, width: W, height: H, time: time, beat: beat)
        let cx = W / 2, cy = H / 2, m = min(W, H), env = CGFloat(beat), t = CGFloat(time)
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
            var r = R * 0.58
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
                    g.drawRadialGradient(sheen, startCenter: .zero, startRadius: R * 0.56, endCenter: .zero, endRadius: R, options: [])
                    g.restoreGState()
                }
            }
            g.rotate(by: angle)
            if let cover {
                g.saveGState()
                g.addEllipse(in: CGRect(x: -R * 0.55, y: -R * 0.55, width: R * 1.1, height: R * 1.1)); g.clip()
                drawImage(cover, in: CGRect(x: -R * 0.55, y: -R * 0.55, width: R * 1.1, height: R * 1.1), context: g)
                g.restoreGState()
            }
            g.setFillColor(gray(0)); g.fillEllipse(in: CGRect(x: -R * 0.03, y: -R * 0.03, width: R * 0.06, height: R * 0.06))
            g.restoreGState()
            guard tonearm else { break }
            g.setStrokeColor(gray(0xcf / 255)); g.setLineWidth(m * 0.022); g.setLineCap(.round); g.setLineJoin(.round)
            g.move(to: CGPoint(x: cx + R * 0.95, y: cy - R)); g.addLine(to: CGPoint(x: cx + R * 0.88, y: cy - R * 0.1))
            g.addLine(to: CGPoint(x: cx + R * 0.55, y: cy + R * 0.42)); g.strokePath()
            g.setFillColor(gray(0xe8 / 255)); g.fillEllipse(in: CGRect(x: cx + R * 0.95 - m * 0.05, y: cy - R - m * 0.05, width: m * 0.1, height: m * 0.1))
        case .clock:
            // The cover as a clock face: an hour hand at the song's progress, and a second hand
            // stepping round on the beat (once every 60 beats).
            let R = m * 0.45, disc = CGRect(x: cx - R, y: cy - R, width: R * 2, height: R * 2)
            g.saveGState(); g.addEllipse(in: disc); g.clip()
            if let cover { drawImage(cover, in: disc, context: g) } else { g.setFillColor(gray(0.35)); g.fill(disc) }
            g.restoreGState()
            g.setStrokeColor(gray(0.85)); g.setLineWidth(m * 0.025); g.strokeEllipse(in: disc)
            func point(_ angle: CGFloat, _ length: CGFloat) -> CGPoint { CGPoint(x: cx + sin(angle) * length, y: cy - cos(angle) * length) }
            for tick in 0..<12 {
                let angle = CGFloat(tick) * .pi / 6, major = tick % 3 == 0
                outlined(g, from: point(angle, R * (major ? 0.74 : 0.82)), to: point(angle, R * 0.92), width: m * (major ? 0.03 : 0.018))
            }
            outlined(g, from: CGPoint(x: cx, y: cy), to: point(CGFloat(progress) * .pi * 2, R * 0.55), width: m * 0.04)
            let beats = CGFloat(AsciiArt.beats(position: time, tempo: tempo))
            let second = (beats.rounded(.down) + 1 - env) * .pi * 2 / 60
            outlined(g, from: point(second + .pi, R * 0.14), to: point(second, R * 0.84), width: m * 0.014, brightness: 0.8)
            g.setFillColor(gray(1)); g.fillEllipse(in: CGRect(x: cx - m * 0.035, y: cy - m * 0.035, width: m * 0.07, height: m * 0.07))
        case .orb:
            // A soft lit sphere breathing with the beat, the cover faint inside it.
            let r = m * (0.36 + env * 0.05), disc = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            let space = CGColorSpaceCreateDeviceGray()
            if let halo = CGGradient(colorSpace: space, colorComponents: [1, 0.28, 1, 0], locations: [0, 1], count: 2) {
                g.drawRadialGradient(halo, startCenter: CGPoint(x: cx, y: cy), startRadius: r, endCenter: CGPoint(x: cx, y: cy),
                                     endRadius: r * (1.3 + env * 0.12), options: [])
            }
            g.saveGState(); g.addEllipse(in: disc); g.clip()
            let light = CGPoint(x: cx - r * 0.35, y: cy - r * 0.4)
            if let body = CGGradient(colorSpace: space, colorComponents: [1, 1, 0.55, 1, 0.12, 1], locations: [0, 0.45, 1], count: 3) {
                g.drawRadialGradient(body, startCenter: light, startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [.drawsAfterEndLocation])
            }
            if let cover {
                g.setAlpha(colour ? 1 : 0.38)
                drawImage(cover, in: disc.insetBy(dx: r * 0.12, dy: r * 0.12), context: g)
            }
            g.restoreGState()
        case .cuts:
            // The cover in eight strips, each kicked left or right on the beat.
            let s = m * 0.86, strips = 8, h = s / CGFloat(strips), top = cy - s / 2
            let kick = Int(AsciiArt.beats(position: time, tempo: tempo).rounded(.down))
            for strip in 0..<strips {
                let offset = (hash(strip, kick) * 2 - 1) * m * 0.09 * env + sin(t * 0.8 + CGFloat(strip)) * m * 0.008
                let x = cx - s / 2 + offset, y = top + CGFloat(strip) * h
                g.saveGState(); g.clip(to: CGRect(x: x, y: y, width: s, height: h + 0.5))
                if let cover { drawImage(cover, in: CGRect(x: x, y: top, width: s, height: s), context: g) } else {
                    g.setFillColor(gray(0.2 + 0.08 * CGFloat(strip % 3))); g.fill(CGRect(x: x, y: y, width: s, height: h))
                }
                g.restoreGState()
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
