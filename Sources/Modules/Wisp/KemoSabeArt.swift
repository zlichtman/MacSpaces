import AppKit
import os

/// KemoSabe's original 3D felt art (`KemoSabe`) repainted in a look's colours, made off the main
/// thread and kept once made. Each pixel keeps its light and shade and takes the look's body
/// colour, or its face colour where the paint is saturated coral (ported from Tsukumo's
/// `CompanionArt`); Apricot keeps the art's own colours. The glass layer is the same picture as 3D
/// glass (`GlassField`): the felt's outline and smoothed shading become a surface, lit for glossy
/// highlights on each lobe and paw, a warm rim and a glow inside in the look's own colours, the body pearly
/// and a little see-through, and the face (eyes, smile, blush) still solid. `KemoSabeFace` lays
/// the felt over it to show any level between, so the two never disagree on the pose.
///
/// The eyes and mouth come apart from the rest (`Layers`), so they can blink, droop, smile and frown:
/// the body under them is filled in from the shading around them, and each is its own small picture.
enum KemoSabeArt {
    enum Kind: String { case felt, glass }

    /// The art's eyes in fractions of the picture, from the top left, with a little room round each.
    static let eyes: [CGRect] = [CGRect(x: 145.0 / 480, y: 210.0 / 480, width: 57.0 / 480, height: 78.0 / 480),
                                 CGRect(x: 278.0 / 480, y: 210.0 / 480, width: 56.0 / 480, height: 78.0 / 480)]
    /// The smile, the same way, so it can open, widen and turn over into a frown.
    static let mouth = CGRect(x: 211.0 / 480, y: 263.0 / 480, width: 58.0 / 480, height: 34.0 / 480)
    /// Everything that comes apart from the body: the eyes, then the mouth.
    private static let parts: [CGRect] = eyes + [mouth]

    /// A repaint: the picture without its eyes and mouth, each eye (in `eyes`' order and
    /// rectangles) and the mouth (in `mouth`).
    struct Layers: @unchecked Sendable {
        let base: CGImage
        let eyes: [CGImage]
        var mouth: CGImage? = nil
    }

    private static let made = OSAllocatedUnfairLock(initialState: [String: Layers]())

    static func original() -> CGImage? {
        NSImage(named: "KemoSabe")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func key(_ kind: Kind, _ look: KemoSabeLook, small: Bool) -> String {
        "\(kind.rawValue)|\(look.body)|\(look.face)|\(small ? "s" : "l")"
    }

    /// The layers to draw, once made.
    static func cached(_ kind: Kind, look: KemoSabeLook, small: Bool) -> Layers? {
        let key = key(kind, look, small: small)
        return made.withLock { $0[key] }
    }

    /// Makes the repaint on a worker; true once it's ready to draw.
    @MainActor static func make(_ kind: Kind, look: KemoSabeLook, small: Bool) async -> Bool {
        if cached(kind, look: look, small: small) != nil { return true }
        guard let source = original() else { return false }
        let key = key(kind, look, small: small)
        let picture = Layers(base: source, eyes: [])
        let body = Tint(hex: look.body), face = Tint(hex: look.face)
        let frosted: Bool = kind == .glass
        let asDrawn: Bool = look.body == AgentPalette.apricot.body && look.face == AgentPalette.apricot.accent
        let painted = await Task.detached(priority: .userInitiated) { [picture, body, face, small, frosted, asDrawn] in
            recolored(picture.base, body: body, accent: face, maxSide: small ? 180 : nil, frosted: frosted, asDrawn: asDrawn)
        }.value
        guard let painted else { return false }
        made.withLock { $0[key] = painted }
        return true
    }

    /// The felt laid over the glass at a level between (in steps of 5%), as one picture, so a
    /// half-glass KemoSabe draws as cheaply as a felt one. Nil until made.
    static func blended(look: KemoSabeLook, small: Bool) -> CGImage? {
        let key = blendKey(look, small: small)
        return made.withLock { $0[key]?.base }
    }

    private static func blendKey(_ look: KemoSabeLook, small: Bool) -> String {
        "mix\(Int((look.glass * 20).rounded()))|\(look.body)|\(look.face)|\(small ? "s" : "l")"
    }

    /// Makes the blend on a worker from the two repaints, once both are made.
    @MainActor static func makeBlend(look: KemoSabeLook, small: Bool) async -> Bool {
        if blended(look: look, small: small) != nil { return true }
        guard let felt = cached(.felt, look: look, small: small), let glass = cached(.glass, look: look, small: small) else { return false }
        let key = blendKey(look, small: small)
        let level = CGFloat((look.glass * 20).rounded() / 20)
        let mixed = await Task.detached(priority: .userInitiated) { [felt, glass, level] () -> Layers? in
            let width = felt.base.width, height = felt.base.height
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            let all = CGRect(x: 0, y: 0, width: width, height: height)
            context.draw(glass.base, in: all)
            context.setAlpha(1 - level)
            context.draw(felt.base, in: all)
            return context.makeImage().map { Layers(base: $0, eyes: felt.eyes, mouth: felt.mouth) }
        }.value
        guard let mixed else { return false }
        made.withLock { $0[key] = mixed }
        return true
    }

    struct Tint: Sendable {
        var r: Float, g: Float, b: Float
        init(hex: String) {
            let value = UInt32(hex, radix: 16) ?? 0
            r = Float((value >> 16) & 0xFF) / 255; g = Float((value >> 8) & 0xFF) / 255; b = Float(value & 0xFF) / 255
        }
    }

    private static func recolored(_ image: CGImage, body: Tint, accent: Tint, maxSide: Int?, frosted: Bool, asDrawn: Bool) -> Layers? {
        let scale = maxSide.map { min(1, Double($0) / Double(max(image.width, image.height))) } ?? 1
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let eyeContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data, let eyeData = eyeContext.data else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let rowBytes = context.bytesPerRow
        let count = rowBytes * height
        let pixels = UnsafeMutableBufferPointer<UInt8>(start: data.assumingMemoryBound(to: UInt8.self), count: count)
        let eyePixels = UnsafeMutableBufferPointer<UInt8>(start: eyeData.assumingMemoryBound(to: UInt8.self), count: eyeContext.bytesPerRow * height)
        // A bitmap context's first row in memory is the picture's top, as `eyes` measures.
        let eyeBoxes: [(x0: Int, x1: Int, y0: Int, y1: Int)] = parts.map { box in
            (Int(box.minX * CGFloat(width)), Int(box.maxX * CGFloat(width)), Int(box.minY * CGFloat(height)), Int(box.maxY * CGFloat(height)))
        }
        func inEye(_ column: Int, _ row: Int) -> Bool {
            eyeBoxes.contains { column >= $0.x0 && column < $0.x1 && row >= $0.y0 && row < $0.y1 }
        }
        // The art's outline, shading and paint, read once.
        var alphas = [Float](repeating: 0, count: width * height)
        var lights = [Float](repeating: 0, count: width * height)
        var plain = [Float](repeating: 0, count: width * height)
        var plainG = [Float](repeating: 0, count: width * height)
        var plainB = [Float](repeating: 0, count: width * height)
        var plainWeight = [Float](repeating: 0, count: width * height)
        var eyeWeight = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let i = row * rowBytes + column * 4, p = row * width + column
                let alpha = Float(pixels[i + 3]) / 255
                guard alpha > 0 else { continue }
                let r = min(1, Float(pixels[i]) / (255 * alpha)), g = min(1, Float(pixels[i + 1]) / (255 * alpha))
                let b = min(1, Float(pixels[i + 2]) / (255 * alpha))
                let unpainted = alpha * (1 - smoothstep(0.06, 0.2, r - g))
                alphas[p] = alpha
                lights[p] = r / 0.97 * alpha
                plain[p] = r * unpainted
                plainG[p] = g * unpainted
                plainB[p] = b * unpainted
                if inEye(column, row) { eyeWeight[p] = smoothstep(0.25, 0.43, r - g) }
                plainWeight[p] = unpainted
            }
        }
        // Each eye, its highlight and soft edge included: the paint, spread a little and firmed up.
        let spread = blurred(eyeWeight, width, height, max(1, width / 160))
        for p in 0..<(width * height) where spread[p] > 0 { eyeWeight[p] = smoothstep(0.08, 0.45, spread[p]) }
        // The shading of the unpainted felt around each pixel fills in under the eyes.
        let fill = max(3, width * 4 / 100)
        let plainNear = blurred(blurred(plain, width, height, fill), width, height, fill)
        let plainNearG = blurred(blurred(plainG, width, height, fill), width, height, fill)
        let plainNearB = blurred(blurred(plainB, width, height, fill), width, height, fill)
        let plainNearWeight = blurred(blurred(plainWeight, width, height, fill), width, height, fill)
        var glassField = GlassField()
        if frosted {
            // Glass traces the shading as if the eyes weren't there, so they leave no ring.
            for p in 0..<(width * height) where eyeWeight[p] > 0 {
                let filled = plainNear[p] / max(plainNearWeight[p], 0.001) / 0.97 * alphas[p]
                lights[p] += (filled - lights[p]) * eyeWeight[p]
            }
            glassField = GlassField(alphas: alphas, lights: lights, width: width, height: height)
        }
        // The art's own cream, so Apricot maps to itself.
        let bodyR = body.r / 0.965, bodyG = body.g / 0.91, bodyB = body.b / 0.82

        /// The felt body at a light, as drawn or in the look.
        func feltBody(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
            if asDrawn { return (r, g, b) }
            return (r * bodyR, g * bodyG, b * bodyB)
        }

        for row in 0..<height {
            for column in 0..<width {
                let i = row * rowBytes + column * 4, p = row * width + column
                let alpha = Float(pixels[i + 3]) / 255
                guard alpha > 0 else { continue }
                let unpremultiply = 1 / (255 * alpha)
                let r = min(1, Float(pixels[i]) * unpremultiply), g = min(1, Float(pixels[i + 1]) * unpremultiply)
                let b = min(1, Float(pixels[i + 2]) * unpremultiply)
                let light = r / 0.97
                let coral = smoothstep(0.25, 0.43, r - g)
                let painted: (Float, Float, Float) = asDrawn ? (r, g, b) : (accent.r * light, accent.g * light, accent.b * light)
                let felt = feltBody(r, g, b)
                var out = (felt.0 + (painted.0 - felt.0) * coral, felt.1 + (painted.1 - felt.1) * coral, felt.2 + (painted.2 - felt.2) * coral)
                // An eye: kept for its own picture, and the body filled in under it.
                // The eye's soft edge comes away with it, so no ring is left behind.
                let eye = eyeWeight[p]
                let weight = max(plainNearWeight[p], 0.001)
                var bodyHere = (plainNear[p] / weight, plainNearG[p] / weight, plainNearB[p] / weight)
                if !asDrawn { bodyHere = (bodyHere.0 * bodyR, bodyHere.1 * bodyG, bodyHere.2 * bodyB) }
                if eye > 0 {
                    eyePixels[i] = channel(out.0, alpha * eye); eyePixels[i + 1] = channel(out.1, alpha * eye)
                    eyePixels[i + 2] = channel(out.2, alpha * eye); eyePixels[i + 3] = UInt8((alpha * eye * 255).rounded())
                    out = (out.0 + (bodyHere.0 - out.0) * eye, out.1 + (bodyHere.1 - out.1) * eye, out.2 + (bodyHere.2 - out.2) * eye)
                }
                var shown = alpha
                if frosted {
                    let face = coral * (1 - eye)
                    let blush = smoothstep(0.08, 0.3, r - g) * (1 - coral) * (1 - eye)
                    let lit = glassField.shade(column, row, body: body, accent: accent)
                    let keep = min(1, face + 0.6 * blush)
                    out = (lit.r + (out.0 - lit.r) * keep, lit.g + (out.1 - lit.g) * keep, lit.b + (out.2 - lit.b) * keep)
                    shown = alpha * (lit.a + (1 - lit.a) * keep)
                }
                pixels[i] = channel(out.0, shown); pixels[i + 1] = channel(out.1, shown); pixels[i + 2] = channel(out.2, shown)
                pixels[i + 3] = UInt8((shown * 255).rounded())
            }
        }
        guard let base = context.makeImage(), let allEyes = eyeContext.makeImage() else { return nil }
        // CGImage cropping counts from the top left too.
        let crops: [CGImage] = eyeBoxes.compactMap { box in
            allEyes.cropping(to: CGRect(x: box.x0, y: box.y0, width: box.x1 - box.x0, height: box.y1 - box.y0))
        }
        guard crops.count == parts.count else { return nil }
        return Layers(base: base, eyes: Array(crops.prefix(eyes.count)), mouth: crops.last)
    }

    /// Glass from the felt's own shape: a height field from its outline (a soft dome) and its smoothed
    /// shading (the lobes and paws), whose slopes give each pixel a surface normal. Lit from the upper
    /// left, that gives specular highlights on every lobe and paw, a Fresnel rim tinted warm, a pearly
    /// body and a glow deep inside, as the original glass art has, tinted from the look (its face
    /// colour in the body's glass) rather than the art's violet.
    struct GlassField {
        private var width = 0, height = 0
        private var heightMap: [Float] = []
        private var smooth: [Float] = []
        private var alphaNear: [Float] = []
        private var depth: [Float] = []
        private var slope: Float = 0

        init() {}

        init(alphas: [Float], lights: [Float], width: Int, height: Int) {
            self.width = width; self.height = height
            let fine = max(1, width / 90), dome = max(2, width * 4 / 100), deep = max(3, width * 9 / 100)
            // The felt's fibres smoothed away, keeping its lobes, creases and paws.
            let lit = KemoSabeArt.blurred(KemoSabeArt.blurred(lights, width, height, fine), width, height, fine)
            let alpha = KemoSabeArt.blurred(KemoSabeArt.blurred(alphas, width, height, fine), width, height, fine)
            let rounded = KemoSabeArt.blurred(KemoSabeArt.blurred(alphas, width, height, dome), width, height, dome)
            let inner = KemoSabeArt.blurred(KemoSabeArt.blurred(alphas, width, height, deep), width, height, deep)
            depth = inner
            smooth = lit
            alphaNear = alpha
            let edge = KemoSabeArt.blurred(KemoSabeArt.blurred(alphas, width, height, max(1, width / 60)), width, height, max(1, width / 60))
            heightMap = (0..<(width * height)).map { p in 1.3 * lit[p] + 0.5 * edge[p] + 0.6 * rounded[p] + 0.4 * inner[p] }
            slope = Float(width) * 0.2
        }

        /// The glass colour and coverage at a pixel, unpremultiplied.
        func shade(_ x: Int, _ y: Int, body: Tint, accent: Tint) -> (r: Float, g: Float, b: Float, a: Float) {
            let step = max(1, width / 240)
            let x0 = max(0, x - step), x1 = min(width - 1, x + step), y0 = max(0, y - step), y1 = min(height - 1, y + step)
            let dx = (heightMap[y * width + x1] - heightMap[y * width + x0]) / Float(max(1, x1 - x0))
            let dy = (heightMap[y1 * width + x] - heightMap[y0 * width + x]) / Float(max(1, y1 - y0))
            var nx: Float = -dx * slope, ny: Float = -dy * slope, nz: Float = 1
            let length = (nx * nx + ny * ny + nz * nz).squareRoot()
            nx /= length; ny /= length; nz /= length
            // Light from the upper left and in front (y runs down the picture), the eye straight on.
            let lx: Float = -0.42, ly: Float = -0.62, lz: Float = 0.66
            let hz: Float = lz + 1
            let hl: Float = (lx * lx + ly * ly + hz * hz).squareRoot()
            let facing: Float = max(0, (nx * lx + ny * ly + nz * hz) / hl)
            let diffuse: Float = max(0, nx * lx + ny * ly + nz * lz)
            let p = y * width + x
            let shadeHere: Float = min(1, smooth[p] / max(alphaNear[p], 0.05))
            let rim: Float = pow(max(0, 1 - nz), 1.6)
            let spec: Float = 1.3 * pow(facing, 110) + 0.45 * pow(facing, 30)
            let sheen: Float = 0.16 * pow(facing, 7)
            // Deep inside, a glow strongest just below the middle, in the palette's own colours.
            let u = Float(x) / Float(width) - 0.5, v = Float(y) / Float(height) - 0.56
            let core: Float = exp(-(u * u / 0.022 + v * v / 0.028)) * Self.ease(0.5, 0.92, depth[p])
            func channel(_ tint: Float, _ warm: Float, _ inner: Float) -> Float {
                // A pearly body, lit softly; the light passes through, so the shade never goes dark.
                var c: Float = tint * (0.84 + 0.12 * shadeHere + 0.12 * diffuse)
                // Light scattered inside warms the seams and the shaded side, as in thick glass.
                let deep: Float = tint * (0.5 + 0.5 * warm)
                c += (deep - c) * min(1, 0.55 * (1 - shadeHere) + 0.25 * (1 - diffuse))
                c += (inner - c) * 0.72 * core
                // The rim catches warm light, as thick glass does at its edge.
                let edge: Float = min(1, (tint * 0.4 + warm * 0.6) * 1.08)
                c += (edge - c) * 0.75 * rim
                c += (1 - c) * min(1, spec + sheen)
                return min(1, max(0, c))
            }
            // Glass carries its colour richer than felt: the body a little more saturated, and
            // the warm light at its rim and seams the body's own hue, deepened, with some face colour.
            let grey: Float = (body.r + body.g + body.b) / 3
            func rich(_ c: Float, _ k: Float) -> Float { min(1, max(0, grey + (c - grey) * k)) }
            let tint = (r: rich(body.r, 1.4), g: rich(body.g, 1.4), b: rich(body.b, 1.4))
            let warm = (r: rich(body.r, 2.6) * 0.8 + accent.r * 0.2, g: rich(body.g, 2.6) * 0.8 + accent.g * 0.2,
                        b: rich(body.b, 2.6) * 0.8 + accent.b * 0.2)
            // The glow: the face colour, a little richer, carried in the body's glass and lifted
            // toward white so it shines from inside; a grey palette glows grey, never violet.
            let accentGrey: Float = (accent.r + accent.g + accent.b) / 3
            func inner(_ face: Float, _ glass: Float) -> Float {
                let vivid: Float = min(1, max(0, accentGrey + (face - accentGrey) * 1.25))
                let mixed: Float = vivid * 0.6 + glass * 0.4
                return mixed + (1 - mixed) * 0.22
            }
            let glow = (r: inner(accent.r, tint.r), g: inner(accent.g, tint.g), b: inner(accent.b, tint.b))
            let r = channel(tint.r, warm.r, glow.r), g = channel(tint.g, warm.g, glow.g)
            let b = channel(tint.b, warm.b, glow.b)
            let a: Float = min(1, 0.88 + 0.2 * rim + 0.4 * spec)
            return (r, g, b, a)
        }

        private static func ease(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
            let t = min(1, max(0, (x - e0) / (e1 - e0)))
            return t * t * (3 - 2 * t)
        }
    }

    /// A box blur of `radius` across and down, edges held.
    private static func blurred(_ values: [Float], _ width: Int, _ height: Int, _ radius: Int) -> [Float] {
        var across = [Float](repeating: 0, count: values.count)
        let span = Float(2 * radius + 1)
        for row in 0..<height {
            let base = row * width
            var sum: Float = 0
            for k in -radius...radius { sum += values[base + min(width - 1, max(0, k))] }
            for column in 0..<width {
                across[base + column] = sum / span
                sum += values[base + min(width - 1, column + radius + 1)] - values[base + max(0, column - radius)]
            }
        }
        var down = [Float](repeating: 0, count: values.count)
        for column in 0..<width {
            var sum: Float = 0
            for k in -radius...radius { sum += across[min(height - 1, max(0, k)) * width + column] }
            for row in 0..<height {
                down[row * width + column] = sum / span
                sum += across[min(height - 1, row + radius + 1) * width + column] - across[max(0, row - radius) * width + column]
            }
        }
        return down
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private static func channel(_ value: Float, _ alpha: Float) -> UInt8 {
        UInt8((min(1, max(0, value)) * alpha * 255).rounded())
    }
}
