import SwiftUI

/// A theme's effect behind the open Nook: petals drifting down for Blossom, rain for
/// Monsoon, a flowing rainbow keyboard for Rainbow, and so on. Every effect is original
/// geometry drawn here. Effects move only while the Nook is open and Reduce Motion is
/// off; otherwise they hold a still frame. They stay faint and frame the content.
enum ThemeMotif: String, CaseIterable {
    // Nature
    case petals, sprigs, aurora, snow, leaves, sunbursts, bubbles, ripples, waves, embers
    case rain, storm, fireflies, stars, autumn
    // Live
    case rainbowKeys, synthGrid, lava, plasma, codeRain, warp, fireworks, circuit, prism, nebula
}

extension ThemeFamily {
    var motif: ThemeMotif? {
        switch self {
        case .blossom: return .petals
        case .lavender: return .sprigs
        case .aurora: return .aurora
        case .alpine: return .snow
        case .moss: return .leaves
        case .sunflower: return .sunbursts
        case .coral: return .bubbles
        case .dune: return .ripples
        case .tidal: return .waves
        case .ember: return .embers
        case .monsoon: return .rain
        case .thunderstorm: return .storm
        case .firefly: return .fireflies
        case .starlight: return .stars
        case .autumn: return .autumn
        case .rainbow: return .rainbowKeys
        case .synthwave: return .synthGrid
        case .lava: return .lava
        case .plasma: return .plasma
        case .codeRain: return .codeRain
        case .warp: return .warp
        case .fireworks: return .fireworks
        case .circuit: return .circuit
        case .prism: return .prism
        case .nebula: return .nebula
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
    /// Fades the effect toward the middle, where text and tiles sit.
    var softensCenter = true
    /// Moves at up to 30 frames a second; false holds a still frame.
    var animated = false

    /// The moment a still frame shows, chosen so every effect looks settled.
    static let stillTime = 7.3

    var body: some View {
        // A timer schedule rather than the display-linked `.animation` one: the Nook's panel
        // sits over the menu bar, where macOS can report it as hidden and pause display links.
        TimelineView(.periodic(from: .now, by: animated ? 1.0 / 30 : 3600)) { timeline in
            // Demo captures run in slow motion; effects slow with them.
            let t = animated ? (timeline.date.timeIntervalSinceReferenceDate / Design.demoTimeScale)
                .truncatingRemainder(dividingBy: 3600) : Self.stillTime
            Canvas(rendersAsynchronously: false) { context, size in
                MotifPainter(motif: motif, accent: accent, ink: ink, scale: scale, strength: strength, t: t)
                    .paint(&context, size)
            }
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
    let t: Double

    private func alpha(_ base: Double) -> Double { min(1, max(0, base * strength)) }

    /// Stable pseudo-random numbers, so nothing shimmers as the panel resizes.
    private func random(_ index: Int, _ salt: Int) -> CGFloat {
        var x = UInt64(bitPattern: Int64(index &* 73_856_093 ^ salt &* 19_349_663))
        x ^= x >> 33; x &*= 0xff51_afd7_ed55_8ccd; x ^= x >> 33
        return CGFloat(x % 10_000) / 10_000
    }

    /// How many particles cover this area at a given spacing.
    private func count(_ size: CGSize, spacing: CGFloat) -> Int {
        max(6, Int((size.width * size.height) / (spacing * spacing * scale * scale)))
    }

    /// A position that travels from one edge to the other and wraps.
    private func travel(_ start: CGFloat, speed: CGFloat, span: CGFloat) -> CGFloat {
        let value = (start * span + CGFloat(t) * speed * scale).truncatingRemainder(dividingBy: span)
        return value < 0 ? value + span : value
    }

    func paint(_ context: inout GraphicsContext, _ size: CGSize) {
        switch motif {
        case .petals: falling(&context, size, spacing: 64, speed: 16, sway: 14, spin: 0.5) { c, r, _ in petal(&c, r) }
        case .autumn: falling(&context, size, spacing: 58, speed: 22, sway: 22, spin: 0.9) { c, r, i in leaf(&c, r, warm: i % 3) }
        case .sprigs: scatter(&context, size, spacing: 60, sway: 7) { c, r, _ in sprig(&c, r) }
        case .leaves: scatter(&context, size, spacing: 60, sway: 5) { c, r, i in leaf(&c, r, warm: i % 2) }
        case .sunbursts: scatter(&context, size, spacing: 66, sway: 0) { c, r, i in sunburst(&c, r, i) }
        case .bubbles: rising(&context, size)
        case .embers: embers(&context, size)
        case .waves: lines(&context, size, spacing: 26, amplitude: 4, wavelength: 46, width: 1.4, opacity: 0.16, drift: 0.9)
        case .ripples: lines(&context, size, spacing: 22, amplitude: 6, wavelength: 140, width: 1.2, opacity: 0.15, drift: 0.25)
        case .aurora: aurora(&context, size)
        case .snow: peaks(&context, size); snowfall(&context, size)
        case .rain: rain(&context, size, heavy: false)
        case .storm: lightning(&context, size); rain(&context, size, heavy: true)
        case .fireflies: fireflies(&context, size)
        case .stars: starfield(&context, size)
        case .rainbowKeys: rainbowKeys(&context, size)
        case .synthGrid: synthGrid(&context, size)
        case .lava: lava(&context, size)
        case .plasma: plasma(&context, size)
        case .codeRain: codeRain(&context, size)
        case .warp: warp(&context, size)
        case .fireworks: fireworks(&context, size)
        case .circuit: circuit(&context, size)
        case .prism: prism(&context, size)
        case .nebula: nebula(&context, size)
        }
    }

    // MARK: Particles

    private func falling(_ context: inout GraphicsContext, _ size: CGSize, spacing: CGFloat, speed: CGFloat,
                         sway: CGFloat, spin: Double, draw: (inout GraphicsContext, CGFloat, Int) -> Void) {
        let margin = 30 * scale
        for i in 0..<count(size, spacing: spacing) {
            let y = travel(random(i, 3), speed: speed * (0.7 + 0.6 * random(i, 4)), span: size.height + margin * 2) - margin
            let x = random(i, 1) * size.width + CGFloat(sin(t * 0.7 + Double(i))) * sway * scale
            var c = context
            c.translateBy(x: x, y: y)
            c.rotate(by: .radians(Double(random(i, 5)) * 6.28 + t * spin * (i % 2 == 0 ? 1 : -1)))
            draw(&c, (7 + 5 * random(i, 6)) * scale, i)
        }
    }

    private func scatter(_ context: inout GraphicsContext, _ size: CGSize, spacing: CGFloat, sway: Double,
                         draw: (inout GraphicsContext, CGFloat, Int) -> Void) {
        let step = spacing * scale
        var index = 0
        var y: CGFloat = 0
        while y < size.height + step {
            var x: CGFloat = 0
            while x < size.width + step {
                defer { x += step; index += 1 }
                guard random(index, 1) > 0.3 else { continue }
                var c = context
                c.translateBy(x: x + step * (0.2 + 0.6 * random(index, 2)), y: y + step * (0.2 + 0.6 * random(index, 3)))
                c.rotate(by: .degrees(Double(random(index, 5)) * 360 + sway * sin(t * 0.8 + Double(index))))
                draw(&c, (7 + 6 * random(index, 4)) * scale, index)
            }
            y += step
        }
    }

    private func rising(_ context: inout GraphicsContext, _ size: CGSize) {
        let span = size.height + 40 * scale
        for i in 0..<count(size, spacing: 70) {
            let y = size.height + 20 * scale - travel(random(i, 3), speed: 14 + 16 * random(i, 4), span: span)
            let x = random(i, 1) * size.width + CGFloat(sin(t * 1.3 + Double(i) * 2)) * 6 * scale
            let r = (3 + 7 * random(i, 5)) * scale
            context.stroke(circle(CGPoint(x: x, y: y), r), with: .color(accent.opacity(alpha(0.18))), lineWidth: 1.1)
        }
    }

    private func embers(_ context: inout GraphicsContext, _ size: CGSize) {
        let span = size.height + 20 * scale
        for i in 0..<count(size, spacing: 46) {
            let y = size.height + 10 * scale - travel(random(i, 3), speed: 18 + 26 * random(i, 4), span: span)
            let x = random(i, 1) * size.width + CGFloat(sin(t * 2 + Double(i))) * 8 * scale
            let flicker = 0.55 + 0.45 * sin(t * 6 + Double(i) * 1.7)
            let fade = Double(max(0, y / max(size.height, 1)))
            context.fill(circle(CGPoint(x: x, y: y), (1 + 1.6 * random(i, 5)) * scale),
                         with: .color(accent.opacity(alpha(0.45 * flicker * fade))))
        }
    }

    private func snowfall(_ context: inout GraphicsContext, _ size: CGSize) {
        let span = size.height + 20 * scale
        for i in 0..<count(size, spacing: 34) {
            let y = travel(random(i, 3), speed: 10 + 18 * random(i, 4), span: span) - 10 * scale
            let x = random(i, 1) * size.width + CGFloat(sin(t * 0.9 + Double(i))) * 10 * scale
            context.fill(circle(CGPoint(x: x, y: y), (0.8 + 1.8 * random(i, 5)) * scale), with: .color(ink.opacity(alpha(0.28))))
        }
    }

    private func rain(_ context: inout GraphicsContext, _ size: CGSize, heavy: Bool) {
        let span = size.height + 40 * scale
        let slant: CGFloat = heavy ? 0.22 : 0.12
        for i in 0..<count(size, spacing: heavy ? 22 : 30) {
            let length = (10 + 10 * random(i, 5)) * scale
            let y = travel(random(i, 3), speed: (heavy ? 420 : 300) + 160 * random(i, 4), span: span) - 20 * scale
            let x = random(i, 1) * (size.width + 60) - 30 + y * slant
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x - length * slant, y: y - length))
            context.stroke(drop, with: .color(ink.opacity(alpha(heavy ? 0.20 : 0.16))), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
    }

    private func lightning(_ context: inout GraphicsContext, _ size: CGSize) {
        let period = 6.5
        let strike = Int(t / period)
        let phase = t.truncatingRemainder(dividingBy: period)
        guard phase < 0.45 else { return }
        // Two quick flashes, then fading.
        let flash = phase < 0.08 ? 1 : (phase > 0.14 && phase < 0.2 ? 0.8 : max(0, 1 - phase / 0.45) * 0.4)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ink.opacity(alpha(0.07 * flash))))
        var bolt = Path()
        var point = CGPoint(x: size.width * (0.2 + 0.6 * random(strike, 20)), y: 0)
        bolt.move(to: point)
        var step = 0
        while point.y < size.height * 0.7 {
            point = CGPoint(x: point.x + (random(strike * 31 + step, 21) - 0.5) * 36 * scale, y: point.y + (14 + 16 * random(strike + step, 22)) * scale)
            bolt.addLine(to: point); step += 1
        }
        var glow = context
        glow.addFilter(.blur(radius: 4))
        glow.stroke(bolt, with: .color(accent.opacity(alpha(0.5 * flash))), lineWidth: 3)
        context.stroke(bolt, with: .color(ink.opacity(alpha(0.6 * flash))), lineWidth: 1.2)
    }

    private func fireflies(_ context: inout GraphicsContext, _ size: CGSize) {
        for i in 0..<max(10, count(size, spacing: 90)) {
            let base = CGPoint(x: random(i, 1) * size.width, y: random(i, 2) * size.height)
            let p = CGPoint(x: base.x + CGFloat(sin(t * (0.2 + 0.2 * Double(random(i, 3))) + Double(i))) * 34 * scale,
                            y: base.y + CGFloat(cos(t * (0.18 + 0.2 * Double(random(i, 4))) + Double(i) * 1.3)) * 22 * scale)
            let glow = 0.3 + 0.7 * max(0, sin(t * (0.9 + Double(random(i, 5))) + Double(i) * 2.1))
            let r = 14 * scale
            context.fill(circle(p, r), with: .radialGradient(Gradient(colors: [accent.opacity(alpha(0.7 * glow)), .clear]),
                                                               center: p, startRadius: 0, endRadius: r))
            context.fill(circle(p, 1.8 * scale), with: .color(accent.opacity(alpha(glow))))
        }
    }

    private func starfield(_ context: inout GraphicsContext, _ size: CGSize) {
        for i in 0..<count(size, spacing: 30) {
            let p = CGPoint(x: random(i, 1) * size.width, y: random(i, 2) * size.height)
            let twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * (1 + 2 * Double(random(i, 3))) + Double(i)))
            if i % 11 == 0 {
                var c = context; c.translateBy(x: p.x, y: p.y)
                sparkle(&c, 3.5 * scale, .color(accent.opacity(alpha(0.4 * twinkle))))
            } else {
                context.fill(circle(p, (0.6 + 1.1 * random(i, 4)) * scale), with: .color(ink.opacity(alpha(0.3 * twinkle))))
            }
        }
        // A shooting star every few seconds.
        let period = 5.0
        let phase = t.truncatingRemainder(dividingBy: period) / 1.1
        guard phase < 1 else { return }
        let n = Int(t / period)
        let start = CGPoint(x: size.width * (0.1 + 0.6 * random(n, 30)), y: size.height * 0.25 * random(n, 31))
        let head = CGPoint(x: start.x + 180 * scale * phase, y: start.y + 70 * scale * phase)
        var trail = Path(); trail.move(to: CGPoint(x: head.x - 50 * scale, y: head.y - 19 * scale)); trail.addLine(to: head)
        context.stroke(trail, with: .linearGradient(Gradient(colors: [.clear, ink.opacity(alpha(0.6 * (1 - phase)))]),
                                                    startPoint: trail.boundingRect.origin, endPoint: head), lineWidth: 1.4)
    }

    // MARK: Lines and fields

    private func lines(_ context: inout GraphicsContext, _ size: CGSize, spacing: CGFloat, amplitude: CGFloat,
                       wavelength: CGFloat, width: CGFloat, opacity: Double, drift: Double) {
        let step = spacing * scale
        var y = step * 0.6, row = 0
        while y < size.height + step {
            var path = Path()
            let phase = Double(random(row, 7)) * .pi * 2 + t * drift
            var x: CGFloat = 0
            path.move(to: CGPoint(x: 0, y: y + CGFloat(sin(phase)) * amplitude * scale))
            while x <= size.width {
                x += 4
                path.addLine(to: CGPoint(x: x, y: y + CGFloat(sin(Double(x / (wavelength * scale)) * .pi * 2 + phase)) * amplitude * scale))
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
            ridge.addLine(to: CGPoint(x: 0, y: base))
            var x: CGFloat = 0, index = layer * 50
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
    }

    private func aurora(_ context: inout GraphicsContext, _ size: CGSize) {
        var glow = context
        glow.addFilter(.blur(radius: 14 * scale))
        for band in 0..<3 {
            var path = Path()
            let y0 = size.height * (0.22 + 0.16 * CGFloat(band))
            let phase = Double(band) * 1.7 + t * (0.25 + 0.08 * Double(band))
            path.move(to: CGPoint(x: -20, y: y0))
            var x: CGFloat = -20
            while x <= size.width + 20 {
                x += 6
                path.addLine(to: CGPoint(x: x, y: y0 + CGFloat(sin(Double(x / (180 * scale)) + phase)) * 18 * scale))
            }
            let shimmer = 0.75 + 0.25 * sin(t * 0.7 + Double(band) * 2)
            glow.stroke(path, with: .color((band == 1 ? ink : accent).opacity(alpha((band == 1 ? 0.07 : 0.18) * shimmer))), lineWidth: 18 * scale)
        }
        for i in 0..<30 {
            let p = CGPoint(x: random(i, 14) * size.width, y: random(i, 15) * size.height)
            let twinkle = 0.5 + 0.5 * sin(t * 2 + Double(i))
            context.fill(circle(p, (0.7 + random(i, 16)) * scale), with: .color(ink.opacity(alpha(0.2 * twinkle))))
        }
    }

    // MARK: Live effects

    /// A backlit keyboard with a rainbow flowing across the keys.
    private func rainbowKeys(_ context: inout GraphicsContext, _ size: CGSize) {
        let key = 22 * scale, gap = 4 * scale
        var row = 0
        var y = gap
        while y < size.height {
            var x = gap + (row % 2 == 1 ? key / 2 : 0)
            while x < size.width {
                let hue = (Double(x / max(size.width, 1)) * 0.9 + Double(y / max(size.height, 1)) * 0.25 - t * 0.12)
                    .truncatingRemainder(dividingBy: 1)
                let rect = CGRect(x: x, y: y, width: key - gap, height: key - gap)
                context.fill(Path(roundedRect: rect, cornerRadius: 4 * scale),
                             with: .color(Color(hue: hue < 0 ? hue + 1 : hue, saturation: 0.9, brightness: 1).opacity(alpha(0.28))))
                x += key
            }
            y += key; row += 1
        }
    }

    /// A neon grid scrolling toward you under a striped sun.
    private func synthGrid(_ context: inout GraphicsContext, _ size: CGSize) {
        let horizon = size.height * 0.52
        let cyan = Color(red: 0.2, green: 0.85, blue: 1)
        // Sun with bands cut out of its lower half.
        let sunRadius = min(size.width, size.height) * 0.28
        let center = CGPoint(x: size.width / 2, y: horizon)
        var sun = context
        sun.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)))
        sun.fill(circle(center, sunRadius), with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.8, blue: 0.3).opacity(alpha(0.28)), accent.opacity(alpha(0.28))]),
                                                                   startPoint: CGPoint(x: 0, y: center.y - sunRadius), endPoint: CGPoint(x: 0, y: horizon)))
        for k in 1...4 {
            let bandY = horizon - CGFloat(k) * sunRadius * 0.14
            sun.blendMode = .destinationOut
            sun.fill(Path(CGRect(x: 0, y: bandY, width: size.width, height: CGFloat(k) * 1.4 * scale)), with: .color(.black))
        }
        // Floor: lines converging on the sun, and rows sliding toward the viewer.
        let floor = Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon))
        var grid = context
        grid.clip(to: floor)
        for k in -12...12 {
            var line = Path()
            line.move(to: center)
            line.addLine(to: CGPoint(x: center.x + CGFloat(k) * size.width * 0.12, y: size.height))
            grid.stroke(line, with: .color(accent.opacity(alpha(0.22))), lineWidth: 1)
        }
        let offset = t * 0.6
        for k in 0..<10 {
            let depth = (Double(k) + offset.truncatingRemainder(dividingBy: 1)) / 10
            let y = horizon + (size.height - horizon) * CGFloat(depth * depth)
            var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
            grid.stroke(line, with: .color(cyan.opacity(alpha(0.10 + 0.18 * depth))), lineWidth: 1)
        }
    }

    private func lava(_ context: inout GraphicsContext, _ size: CGSize) {
        var blobs = context
        blobs.addFilter(.blur(radius: 22 * scale))
        let warm = Color(red: 1, green: 0.62, blue: 0.2)
        for i in 0..<7 {
            let x = size.width * (0.1 + 0.8 * random(i, 1)) + CGFloat(sin(t * 0.15 + Double(i))) * 30 * scale
            let y = size.height * (0.5 + 0.42 * CGFloat(sin(t * (0.12 + 0.08 * Double(random(i, 2))) + Double(i) * 1.9)))
            let r = (34 + 34 * random(i, 3)) * scale
            blobs.fill(circle(CGPoint(x: x, y: y), r), with: .color((i % 2 == 0 ? accent : warm).opacity(alpha(0.30))))
        }
    }

    private func plasma(_ context: inout GraphicsContext, _ size: CGSize) {
        var field = context
        field.addFilter(.blur(radius: 14 * scale))
        let cell = 26 * scale
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
                let v = sin(Double(x) / 70 + t * 0.6) + sin(Double(y) / 45 - t * 0.5) + sin(Double(x + y) / 90 + t * 0.35)
                let hue = (0.62 + v / 12 + t * 0.01).truncatingRemainder(dividingBy: 1)
                field.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)),
                           with: .color(Color(hue: hue, saturation: 0.75, brightness: 1).opacity(alpha(0.10 + 0.05 * (v + 3) / 6))))
                x += cell
            }
            y += cell
        }
    }

    private func codeRain(_ context: inout GraphicsContext, _ size: CGSize) {
        let glyphs = ["0", "1", "7", "A", "F", "3", "9", "E", "4", "C"]
            .map { context.resolve(Text($0).font(.system(size: 11 * scale, weight: .medium, design: .monospaced))) }
        let column = 16 * scale, row = 14 * scale
        let trail = 9
        var i = 0
        var x = column / 2
        while x < size.width {
            let span = size.height + CGFloat(trail) * row
            let head = travel(random(i, 1), speed: 40 + 70 * random(i, 2), span: span)
            for k in 0..<trail {
                let y = head - CGFloat(k) * row
                guard y > -row, y < size.height + row else { continue }
                let glyph = glyphs[(i * 7 + k * 3 + Int(t * 5)) % glyphs.count]
                var c = context
                c.opacity = alpha((k == 0 ? 0.5 : 0.28) * (1 - Double(k) / Double(trail)))
                c.draw(glyph, at: CGPoint(x: x, y: y))
            }
            x += column; i += 1
        }
    }

    private func warp(_ context: inout GraphicsContext, _ size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let reach = hypot(size.width, size.height) / 2
        for i in 0..<110 {
            let angle = Double(random(i, 1)) * .pi * 2
            let progress = CGFloat((Double(random(i, 2)) + t * (0.15 + 0.2 * Double(random(i, 3)))).truncatingRemainder(dividingBy: 1))
            let far = reach * progress * progress
            let near = far * 0.82
            var streak = Path()
            streak.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * near, y: center.y + CGFloat(sin(angle)) * near))
            streak.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * far, y: center.y + CGFloat(sin(angle)) * far))
            context.stroke(streak, with: .color((i % 4 == 0 ? accent : ink).opacity(alpha(0.45 * Double(progress)))),
                           style: StrokeStyle(lineWidth: 0.6 + 1.6 * progress, lineCap: .round))
        }
    }

    /// Rockets climb, burst into sparks that arc out, sag and fade, then twinkle
    /// out. Each burst repeats on its own period at a new place and colour.
    private func fireworks(_ context: inout GraphicsContext, _ size: CGSize) {
        let colours = [accent, ink, accent.mix(with: ink, by: 0.45)]
        for burst in 0..<5 {
            let period = 3.4 + 1.8 * Double(random(burst, 1))
            let phase = t / period + Double(random(burst, 2)) * 4
            let cycle = Int(phase.rounded(.down))
            let life = phase - Double(cycle)
            let seed = burst * 131 + cycle
            let centre = CGPoint(x: size.width * (0.08 + 0.84 * random(seed, 3)),
                                 y: size.height * (0.14 + 0.42 * random(seed, 4)))
            let colour = colours[seed % colours.count]
            let launch = 0.16
            if life < launch {
                // The rocket's trail, rising from below the bottom edge.
                let progress = CGFloat(life / launch)
                let y = size.height + 8 * scale - (size.height + 8 * scale - centre.y) * progress
                var trail = Path()
                trail.move(to: CGPoint(x: centre.x, y: y + 14 * scale))
                trail.addLine(to: CGPoint(x: centre.x, y: y))
                context.stroke(trail, with: .color(colour.opacity(alpha(0.35))),
                               style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round))
                context.fill(circle(CGPoint(x: centre.x, y: y), 1.6 * scale), with: .color(colour.opacity(alpha(0.6))))
                continue
            }
            let progress = (life - launch) / (1 - launch)
            let spread = (52 + 46 * random(seed, 5)) * scale * CGFloat(1 - pow(1 - progress, 3))
            let sag = 30 * scale * CGFloat(progress * progress)
            let fade = 1 - progress
            let sparks = 26 + Int(random(seed, 6) * 12)
            // An outer ring and a smaller inner ring in a second colour.
            let inner = colours[(seed + 1) % colours.count]
            for spark in 0..<(sparks + sparks / 2) {
                let outer = spark < sparks
                let count = outer ? sparks : sparks / 2
                let index = outer ? spark : spark - sparks
                let angle = Double(index) / Double(count) * .pi * 2 + Double(random(seed, 7)) * .pi + (outer ? 0 : 0.3)
                let reach = spread * (outer ? 0.85 + 0.15 * random(seed + spark, 8) : 0.5)
                let sparkColour = outer ? colour : inner
                let tip = CGPoint(x: centre.x + CGFloat(cos(angle)) * reach,
                                  y: centre.y + CGFloat(sin(angle)) * reach + sag)
                let tail = CGPoint(x: centre.x + CGFloat(cos(angle)) * reach * 0.55,
                                   y: centre.y + CGFloat(sin(angle)) * reach * 0.55 + sag * 0.5)
                var streak = Path()
                streak.move(to: tail)
                streak.addLine(to: tip)
                context.stroke(streak, with: .linearGradient(Gradient(colors: [sparkColour.opacity(0), sparkColour.opacity(alpha(0.5 * fade))]),
                                                             startPoint: tail, endPoint: tip),
                               style: StrokeStyle(lineWidth: 1.3 * scale, lineCap: .round))
                // Late sparks twinkle as they die.
                let twinkle = progress > 0.55 ? 0.5 + 0.5 * sin(t * 18 + Double(spark)) : 1
                context.fill(circle(tip, 1.6 * scale), with: .color(sparkColour.opacity(alpha(0.75 * fade * twinkle))))
            }
            // A brief flash at the moment of the burst.
            if progress < 0.12 {
                context.fill(circle(centre, 16 * scale * CGFloat(1 - progress / 0.12)),
                             with: .color(colour.opacity(alpha(0.25 * (1 - progress / 0.12)))))
            }
        }
    }

    private func circuit(_ context: inout GraphicsContext, _ size: CGSize) {
        let step = 34 * scale
        var traces: [Path] = []
        var i = 0
        var y = step / 2
        while y < size.height {
            var x = step / 2
            while x < size.width {
                defer { x += step; i += 1 }
                guard random(i, 1) > 0.45 else { continue }
                var trace = Path()
                trace.move(to: CGPoint(x: x, y: y))
                let horizontal = random(i, 2) > 0.5
                let length = step * (1 + CGFloat(Int(random(i, 3) * 3)))
                let bend = CGPoint(x: horizontal ? x + length : x, y: horizontal ? y : y + length)
                trace.addLine(to: bend)
                trace.addLine(to: CGPoint(x: bend.x + (horizontal ? 0 : step * 0.6), y: bend.y + (horizontal ? step * 0.6 : 0)))
                context.stroke(trace, with: .color(accent.opacity(alpha(0.14))), lineWidth: 1)
                context.fill(circle(CGPoint(x: x, y: y), 2.2 * scale), with: .color(accent.opacity(alpha(0.2))))
                traces.append(trace)
            }
            y += step
        }
        // Light pulses running along some traces.
        for (index, trace) in traces.enumerated() where index % 3 == 0 {
            let progress = CGFloat((t * 0.5 + Double(random(index, 9))).truncatingRemainder(dividingBy: 1))
            let dot = trace.trimmedPath(from: max(0, progress - 0.08), to: progress)
            context.stroke(dot, with: .color(accent.opacity(alpha(0.8))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private func prism(_ context: inout GraphicsContext, _ size: CGSize) {
        var beams = context
        beams.addFilter(.blur(radius: 10 * scale))
        let origin = CGPoint(x: -20, y: -20)
        let sweep = sin(t * 0.25) * 0.18
        for k in 0..<7 {
            let angle = 0.25 + Double(k) * 0.11 + sweep
            let length = hypot(size.width, size.height) * 1.2
            var beam = Path()
            beam.move(to: origin)
            beam.addLine(to: CGPoint(x: origin.x + CGFloat(cos(angle - 0.03)) * length, y: origin.y + CGFloat(sin(angle - 0.03)) * length))
            beam.addLine(to: CGPoint(x: origin.x + CGFloat(cos(angle + 0.03)) * length, y: origin.y + CGFloat(sin(angle + 0.03)) * length))
            beam.closeSubpath()
            beams.fill(beam, with: .color(Color(hue: Double(k) / 7, saturation: 0.8, brightness: 1).opacity(alpha(0.10))))
        }
    }

    private func nebula(_ context: inout GraphicsContext, _ size: CGSize) {
        var clouds = context
        clouds.addFilter(.blur(radius: 30 * scale))
        let colors = [accent, Color(red: 0.35, green: 0.55, blue: 1), Color(red: 1, green: 0.45, blue: 0.7)]
        for i in 0..<6 {
            let x = size.width * (0.1 + 0.8 * random(i, 1)) + CGFloat(sin(t * 0.05 + Double(i))) * 40 * scale
            let y = size.height * (0.1 + 0.8 * random(i, 2)) + CGFloat(cos(t * 0.04 + Double(i))) * 20 * scale
            clouds.fill(Path(ellipseIn: CGRect(x: x - 70 * scale, y: y - 40 * scale, width: 140 * scale, height: 80 * scale)),
                        with: .color(colors[i % colors.count].opacity(alpha(0.18))))
        }
        for i in 0..<40 {
            let p = CGPoint(x: random(i, 5) * size.width, y: random(i, 6) * size.height)
            let twinkle = 0.5 + 0.5 * sin(t * 1.6 + Double(i))
            context.fill(circle(p, (0.6 + random(i, 7)) * scale), with: .color(ink.opacity(alpha(0.3 * twinkle))))
        }
    }

    // MARK: Shapes

    private func petal(_ c: inout GraphicsContext, _ r: CGFloat) {
        for k in 0..<5 {
            var p = c
            p.rotate(by: .degrees(Double(k) * 72))
            p.fill(Path(ellipseIn: CGRect(x: -r * 0.32, y: -r * 1.05, width: r * 0.64, height: r * 0.9)), with: .color(accent.opacity(alpha(0.16))))
        }
        c.fill(circle(.zero, r * 0.22), with: .color(ink.opacity(alpha(0.14))))
    }

    private func leaf(_ c: inout GraphicsContext, _ r: CGFloat, warm: Int) {
        var leaf = Path()
        leaf.move(to: CGPoint(x: 0, y: -r * 1.2))
        leaf.addQuadCurve(to: CGPoint(x: 0, y: r * 1.2), control: CGPoint(x: r * 1.1, y: 0))
        leaf.addQuadCurve(to: CGPoint(x: 0, y: -r * 1.2), control: CGPoint(x: -r * 1.1, y: 0))
        c.fill(leaf, with: .color(accent.opacity(alpha([0.16, 0.11, 0.2][warm % 3]))))
        var rib = Path(); rib.move(to: CGPoint(x: 0, y: -r * 1.1)); rib.addLine(to: CGPoint(x: 0, y: r * 1.4))
        c.stroke(rib, with: .color(accent.opacity(alpha(0.18))), lineWidth: 0.8)
    }

    private func sprig(_ c: inout GraphicsContext, _ r: CGFloat) {
        var stem = Path(); stem.move(to: CGPoint(x: 0, y: r * 1.3)); stem.addQuadCurve(to: CGPoint(x: 0, y: -r * 1.3), control: CGPoint(x: r * 0.5, y: 0))
        c.stroke(stem, with: .color(accent.opacity(alpha(0.16))), lineWidth: 1)
        for k in 0..<4 {
            let offset = CGFloat(k) / 3 - 0.5
            c.fill(Path(ellipseIn: CGRect(x: (k % 2 == 0 ? -r * 0.35 : r * 0.1) + r * 0.2, y: offset * r * 2.2 - r * 0.2, width: r * 0.4, height: r * 0.55)),
                   with: .color(accent.opacity(alpha(0.16))))
        }
    }

    private func sunburst(_ c: inout GraphicsContext, _ r: CGFloat, _ i: Int) {
        c.rotate(by: .radians(t * 0.2 * (i % 2 == 0 ? 1 : -1)))
        c.fill(circle(.zero, r * 0.45), with: .color(accent.opacity(alpha(0.15))))
        for k in 0..<8 {
            var ray = c; ray.rotate(by: .degrees(Double(k) * 45))
            var p = Path(); p.move(to: CGPoint(x: 0, y: r * 0.7)); p.addLine(to: CGPoint(x: 0, y: r * 1.15))
            ray.stroke(p, with: .color(accent.opacity(alpha(0.16))), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }

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
