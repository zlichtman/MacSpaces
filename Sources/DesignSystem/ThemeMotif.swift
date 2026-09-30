import SwiftUI

/// A decorative pattern drawn behind a theme's panels: flowers for Blossom,
/// ridges for Alpine, and so on. Every motif is simple original geometry drawn
/// here, kept faint so text and tiles stay the focus.
enum ThemeMotif: String, CaseIterable {
    case petals, sprigs, aurora, peaks, leaves, sunbursts, bubbles, ripples
    case waves, sparks, polka, seeds, citrus, clouds, pixels, halftone
}

extension ThemeFamily {
    var motif: ThemeMotif? {
        switch self {
        case .blossom: return .petals
        case .lavender: return .sprigs
        case .aurora: return .aurora
        case .alpine: return .peaks
        case .moss: return .leaves
        case .sunflower: return .sunbursts
        case .coral: return .bubbles
        case .dune: return .ripples
        case .tidal: return .waves
        case .ember: return .sparks
        case .bubblegum: return .polka
        case .matcha: return .leaves
        case .strawberryMilk: return .seeds
        case .lemonDrop: return .citrus
        case .cottonCandy: return .clouds
        case .arcade: return .pixels
        case .newsprint: return .halftone
        default: return nil
        }
    }
}

struct ThemeMotifView: View {
    let motif: ThemeMotif
    let accent: Color
    let ink: Color
    /// Scales the whole pattern: 1 in the Nook, smaller on theme previews.
    var scale: CGFloat = 1
    /// Multiplies the faint default opacity; previews use more.
    var strength: Double = 1
    /// Fades the pattern toward the middle, where text and tiles sit, so it
    /// frames the content instead of running behind it.
    var softensCenter = true

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            MotifPainter(motif: motif, accent: accent, ink: ink, scale: scale, strength: strength)
                .paint(&context, size)
        }
        .mask {
            if softensCenter {
                EllipticalGradient(colors: [.black.opacity(0.3), .black], center: .center,
                                   startRadiusFraction: 0.05, endRadiusFraction: 0.72)
            } else {
                Color.black
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MotifPainter {
    let motif: ThemeMotif
    let accent: Color
    let ink: Color
    let scale: CGFloat
    let strength: Double

    private func alpha(_ base: Double) -> Double { min(1, base * strength) }

    /// Stable pseudo-random numbers, so the pattern never shimmers as the panel resizes.
    private func random(_ index: Int, _ salt: Int) -> CGFloat {
        var x = UInt64(bitPattern: Int64(index &* 73_856_093 ^ salt &* 19_349_663))
        x ^= x >> 33; x &*= 0xff51_afd7_ed55_8ccd; x ^= x >> 33
        return CGFloat(x % 10_000) / 10_000
    }

    func paint(_ context: inout GraphicsContext, _ size: CGSize) {
        switch motif {
        case .aurora: aurora(&context, size)
        case .peaks: peaks(&context, size)
        case .waves: lines(&context, size, spacing: 26, amplitude: 4, wavelength: 46, width: 1.4, opacity: 0.16)
        case .ripples: lines(&context, size, spacing: 22, amplitude: 6, wavelength: 140, width: 1.2, opacity: 0.15)
        case .polka: grid(&context, size, cell: 36, staggered: true) { c, p, _ in
            c.fill(circle(p, 3 * scale), with: .color(accent.opacity(alpha(0.13))))
        }
        case .halftone: grid(&context, size, cell: 14, staggered: false) { c, p, _ in
            let t = (p.x / max(size.width, 1) + p.y / max(size.height, 1)) / 2
            c.fill(circle(p, 0.6 + 2.4 * t), with: .color(ink.opacity(alpha(0.10))))
        }
        case .pixels: grid(&context, size, cell: 12, staggered: false) { c, p, i in
            guard random(i, 3) > 0.82 else { return }
            let s = 6 * scale
            c.fill(Path(CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)),
                   with: .color(accent.opacity(alpha(0.08 + 0.12 * random(i, 4)))))
        }
        default: scatter(&context, size)
        }
    }

    // MARK: Layouts

    private func grid(_ context: inout GraphicsContext, _ size: CGSize, cell: CGFloat, staggered: Bool,
                      draw: (inout GraphicsContext, CGPoint, Int) -> Void) {
        let step = cell * scale
        var row = 0, index = 0
        var y = step / 2
        while y < size.height + step {
            var x = step / 2 + (staggered && row % 2 == 1 ? step / 2 : 0)
            while x < size.width + step {
                draw(&context, CGPoint(x: x, y: y), index)
                x += step; index += 1
            }
            y += step; row += 1
        }
    }

    /// Motifs placed one per cell with jitter, size and rotation variety.
    private func scatter(_ context: inout GraphicsContext, _ size: CGSize) {
        let step = 58 * scale
        var index = 0
        var y: CGFloat = 0
        while y < size.height + step {
            var x: CGFloat = 0
            while x < size.width + step {
                defer { x += step; index += 1 }
                guard random(index, 1) > 0.28 else { continue }
                let point = CGPoint(x: x + step * (0.2 + 0.6 * random(index, 2)),
                                    y: y + step * (0.2 + 0.6 * random(index, 3)))
                let r = (7 + 6 * random(index, 4)) * scale
                let angle = Angle.degrees(Double(random(index, 5)) * 360)
                var c = context
                c.translateBy(x: point.x, y: point.y)
                c.rotate(by: angle)
                motifShape(&c, r, index)
            }
            y += step
        }
    }

    private func motifShape(_ c: inout GraphicsContext, _ r: CGFloat, _ i: Int) {
        let fill = GraphicsContext.Shading.color(accent.opacity(alpha(0.15)))
        let line = GraphicsContext.Shading.color(accent.opacity(alpha(0.15)))
        switch motif {
        case .petals:
            for k in 0..<5 {
                var petal = c
                petal.rotate(by: .degrees(Double(k) * 72))
                petal.fill(Path(ellipseIn: CGRect(x: -r * 0.32, y: -r * 1.05, width: r * 0.64, height: r * 0.9)), with: fill)
            }
            c.fill(circle(.zero, r * 0.22), with: .color(ink.opacity(alpha(0.14))))
        case .sprigs:
            var stem = Path(); stem.move(to: CGPoint(x: 0, y: r * 1.3)); stem.addQuadCurve(to: CGPoint(x: 0, y: -r * 1.3), control: CGPoint(x: r * 0.5, y: 0))
            c.stroke(stem, with: line, lineWidth: 1)
            for k in 0..<4 {
                let t = CGFloat(k) / 3 - 0.5
                c.fill(Path(ellipseIn: CGRect(x: (k % 2 == 0 ? -r * 0.35 : r * 0.1) + r * 0.2, y: t * r * 2.2 - r * 0.2, width: r * 0.4, height: r * 0.55)), with: fill)
            }
        case .leaves:
            var leaf = Path()
            leaf.move(to: CGPoint(x: 0, y: -r * 1.2))
            leaf.addQuadCurve(to: CGPoint(x: 0, y: r * 1.2), control: CGPoint(x: r * 1.1, y: 0))
            leaf.addQuadCurve(to: CGPoint(x: 0, y: -r * 1.2), control: CGPoint(x: -r * 1.1, y: 0))
            c.fill(leaf, with: fill)
            var rib = Path(); rib.move(to: CGPoint(x: 0, y: -r * 1.1)); rib.addLine(to: CGPoint(x: 0, y: r * 1.4))
            c.stroke(rib, with: line, lineWidth: 0.8)
        case .sunbursts:
            c.fill(circle(.zero, r * 0.45), with: fill)
            for k in 0..<8 {
                var ray = c; ray.rotate(by: .degrees(Double(k) * 45))
                var p = Path(); p.move(to: CGPoint(x: 0, y: r * 0.7)); p.addLine(to: CGPoint(x: 0, y: r * 1.15))
                ray.stroke(p, with: line, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        case .bubbles:
            c.stroke(circle(.zero, r * 0.9), with: line, lineWidth: 1.2)
            c.stroke(circle(CGPoint(x: r * 1.1, y: -r * 0.9), r * 0.35), with: line, lineWidth: 1)
        case .sparks:
            sparkle(&c, r * 0.8, .color(accent.opacity(alpha(0.18))))
        case .seeds:
            for k in 0..<3 {
                var seed = c
                seed.translateBy(x: CGFloat(k - 1) * r * 0.9, y: CGFloat(k % 2) * r * 0.7)
                seed.rotate(by: .degrees(Double(k) * 25))
                var drop = Path()
                drop.move(to: CGPoint(x: 0, y: -r * 0.45))
                drop.addQuadCurve(to: CGPoint(x: 0, y: r * 0.35), control: CGPoint(x: r * 0.4, y: r * 0.1))
                drop.addQuadCurve(to: CGPoint(x: 0, y: -r * 0.45), control: CGPoint(x: -r * 0.4, y: r * 0.1))
                seed.fill(drop, with: fill)
            }
        case .citrus:
            c.stroke(circle(.zero, r), with: line, lineWidth: 1.1)
            for k in 0..<6 {
                var seg = c; seg.rotate(by: .degrees(Double(k) * 60))
                var p = Path(); p.move(to: .zero); p.addLine(to: CGPoint(x: 0, y: r * 0.8))
                seg.stroke(p, with: line, lineWidth: 0.9)
            }
        case .clouds:
            var cloud = Path()
            cloud.addEllipse(in: CGRect(x: -r * 1.2, y: -r * 0.2, width: r * 1.3, height: r * 0.8))
            cloud.addEllipse(in: CGRect(x: -r * 0.55, y: -r * 0.65, width: r * 1.2, height: r * 1.1))
            cloud.addEllipse(in: CGRect(x: r * 0.2, y: -r * 0.25, width: r * 1.1, height: r * 0.8))
            c.fill(cloud, with: fill)
        default:
            break
        }
    }

    // MARK: Line motifs

    private func lines(_ context: inout GraphicsContext, _ size: CGSize, spacing: CGFloat, amplitude: CGFloat,
                       wavelength: CGFloat, width: CGFloat, opacity: Double) {
        let step = spacing * scale
        var y = step * 0.6, row = 0
        while y < size.height + step {
            var path = Path()
            let phase = random(row, 7) * .pi * 2
            path.move(to: CGPoint(x: 0, y: y + sin(phase) * amplitude))
            var x: CGFloat = 0
            while x <= size.width {
                x += 4
                path.addLine(to: CGPoint(x: x, y: y + sin(x / (wavelength * scale) * .pi * 2 + phase) * amplitude * scale))
            }
            context.stroke(path, with: .color(accent.opacity(alpha(opacity))), lineWidth: width)
            y += step; row += 1
        }
    }

    private func peaks(_ context: inout GraphicsContext, _ size: CGSize) {
        for layer in 0..<2 {
            let base = size.height * (layer == 0 ? 0.62 : 0.78)
            let height = size.height * (layer == 0 ? 0.30 : 0.20)
            var ridge = Path()
            ridge.move(to: CGPoint(x: 0, y: size.height))
            var x: CGFloat = 0, index = layer * 50
            ridge.addLine(to: CGPoint(x: 0, y: base))
            while x < size.width {
                let span = (70 + 90 * random(index, 8)) * scale
                ridge.addLine(to: CGPoint(x: x + span / 2, y: base - height * (0.4 + 0.6 * random(index, 9))))
                ridge.addLine(to: CGPoint(x: x + span, y: base - height * 0.1 * random(index, 10)))
                x += span; index += 1
            }
            ridge.addLine(to: CGPoint(x: size.width, y: size.height))
            ridge.closeSubpath()
            context.fill(ridge, with: .color(accent.opacity(alpha(layer == 0 ? 0.07 : 0.10))))
        }
        // A few stars above the ridges.
        for i in 0..<24 {
            let p = CGPoint(x: random(i, 11) * size.width, y: random(i, 12) * size.height * 0.45)
            context.fill(circle(p, (0.8 + random(i, 13)) * scale), with: .color(ink.opacity(alpha(0.16))))
        }
    }

    private func aurora(_ context: inout GraphicsContext, _ size: CGSize) {
        var glow = context
        glow.addFilter(.blur(radius: 14 * scale))
        for band in 0..<3 {
            var path = Path()
            let y0 = size.height * (0.22 + 0.16 * CGFloat(band))
            let phase = CGFloat(band) * 1.7
            path.move(to: CGPoint(x: -20, y: y0))
            var x: CGFloat = -20
            while x <= size.width + 20 {
                x += 6
                path.addLine(to: CGPoint(x: x, y: y0 + sin(x / (180 * scale) + phase) * 18 * scale))
            }
            let color = band == 1 ? ink : accent
            glow.stroke(path, with: .color(color.opacity(alpha(band == 1 ? 0.07 : 0.18))), lineWidth: 18 * scale)
        }
        for i in 0..<30 {
            let p = CGPoint(x: random(i, 14) * size.width, y: random(i, 15) * size.height)
            if i % 5 == 0 {
                var c = context; c.translateBy(x: p.x, y: p.y)
                sparkle(&c, 4 * scale, .color(ink.opacity(alpha(0.22))))
            } else {
                context.fill(circle(p, (0.7 + random(i, 16)) * scale), with: .color(ink.opacity(alpha(0.18))))
            }
        }
    }

    // MARK: Shapes

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func sparkle(_ c: inout GraphicsContext, _ r: CGFloat, _ shading: GraphicsContext.Shading) {
        var star = Path()
        star.move(to: CGPoint(x: 0, y: -r))
        star.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        star.addQuadCurve(to: CGPoint(x: 0, y: r), control: .zero)
        star.addQuadCurve(to: CGPoint(x: -r, y: 0), control: .zero)
        star.addQuadCurve(to: CGPoint(x: 0, y: -r), control: .zero)
        c.fill(star, with: shading)
    }
}
