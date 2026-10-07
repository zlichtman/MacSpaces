import SwiftUI

/// A theme's effect behind the open Nook: petals drifting down for Blossom, rain for
/// Monsoon, a flowing rainbow keyboard for Rainbow, and so on. Every effect is original
/// geometry drawn here. Effects move only while the Nook is open and Reduce Motion is
/// off; otherwise they hold a still frame. They stay faint and frame the content.
enum ThemeMotif: String, CaseIterable {
    // Bloom
    case petals, lavenderField, sunflowers, meadow, lotus
    // Forest
    case fronds, leaves, bamboo, fireflies, moonrise
    // Earth
    case embers, lava, ripples, autumn, canyon
    // Water
    case waves, rain, storm, snow, glacier
    // Sky
    case aurora, stars, nebula, prism, plasma
    // Tech
    case synthGrid, circuit, codeRain, warp, rainbowKeys
}

extension ThemeFamily {
    var motif: ThemeMotif? {
        switch self {
        case .blossom: return .petals
        case .lavender: return .lavenderField
        case .sunflower: return .sunflowers
        case .wildflower: return .meadow
        case .lotus: return .lotus
        case .fern: return .fronds
        case .moss: return .leaves
        case .bamboo: return .bamboo
        case .firefly: return .fireflies
        case .moonrise: return .moonrise
        case .ember: return .embers
        case .lava: return .lava
        case .dune: return .ripples
        case .autumn: return .autumn
        case .canyon: return .canyon
        case .tidal: return .waves
        case .monsoon: return .rain
        case .thunderstorm: return .storm
        case .alpine: return .snow
        case .glacier: return .glacier
        case .aurora: return .aurora
        case .starlight: return .stars
        case .nebula: return .nebula
        case .prism: return .prism
        case .plasma: return .plasma
        case .synthwave: return .synthGrid
        case .circuit: return .circuit
        case .codeRain: return .codeRain
        case .warp: return .warp
        case .rainbow: return .rainbowKeys
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
        case .petals: blossomBranch(&context, size); falling(&context, size, spacing: 70, speed: 13, sway: 18, spin: 0.35) { c, r, i in petal(&c, r, i) }
        case .lavenderField: lavenderField(&context, size)
        case .sunflowers: sunflowers(&context, size)
        case .meadow: meadow(&context, size)
        case .lotus: lotusPond(&context, size)
        case .fronds: fernFronds(&context, size)
        case .leaves: scatter(&context, size, spacing: 60, sway: 5) { c, r, i in leaf(&c, r, warm: i % 2) }
        case .bamboo: bamboo(&context, size)
        case .fireflies: fireflies(&context, size)
        case .moonrise: moonrise(&context, size)
        case .embers: embers(&context, size)
        case .lava: lava(&context, size)
        case .ripples: lines(&context, size, spacing: 22, amplitude: 6, wavelength: 140, width: 1.2, opacity: 0.15, drift: 0.25)
        case .autumn: falling(&context, size, spacing: 58, speed: 22, sway: 22, spin: 0.9) { c, r, i in leaf(&c, r, warm: i % 3) }
        case .canyon: canyon(&context, size)
        case .waves: lines(&context, size, spacing: 26, amplitude: 4, wavelength: 46, width: 1.4, opacity: 0.16, drift: 0.9)
        case .rain: rain(&context, size, heavy: false)
        case .storm: lightning(&context, size); rain(&context, size, heavy: true)
        case .snow: snowScene(&context, size)
        case .glacier: glacier(&context, size)
        case .aurora: aurora(&context, size)
        case .stars: starfield(&context, size)
        case .nebula: nebula(&context, size)
        case .prism: prism(&context, size)
        case .plasma: plasma(&context, size)
        case .synthGrid: synthGrid(&context, size)
        case .circuit: circuit(&context, size)
        case .codeRain: codeRain(&context, size)
        case .warp: warp(&context, size)
        case .rainbowKeys: rainbowKeys(&context, size)
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
                let hue = (Double(x / max(size.width, 1)) * 0.9 + Double(y / max(size.height, 1)) * 0.25 - t * 0.05)
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
        let offset = t * 0.3
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
            let x = size.width * (0.1 + 0.8 * random(i, 1)) + CGFloat(sin(t * 0.08 + Double(i))) * 30 * scale
            let y = size.height * (0.5 + 0.42 * CGFloat(sin(t * (0.06 + 0.04 * Double(random(i, 2))) + Double(i) * 1.9)))
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
                let v = sin(Double(x) / 70 + t * 0.3) + sin(Double(y) / 45 - t * 0.25) + sin(Double(x + y) / 90 + t * 0.18)
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
            let head = travel(random(i, 1), speed: 22 + 34 * random(i, 2), span: span)
            for k in 0..<trail {
                let y = head - CGFloat(k) * row
                guard y > -row, y < size.height + row else { continue }
                let glyph = glyphs[(i * 7 + k * 3 + Int(t * 2)) % glyphs.count]
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
        for i in 0..<64 {
            let angle = Double(random(i, 1)) * .pi * 2
            let progress = CGFloat((Double(random(i, 2)) + t * (0.06 + 0.08 * Double(random(i, 3)))).truncatingRemainder(dividingBy: 1))
            let far = reach * progress * progress
            let near = far * 0.82
            var streak = Path()
            streak.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * near, y: center.y + CGFloat(sin(angle)) * near))
            streak.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * far, y: center.y + CGFloat(sin(angle)) * far))
            context.stroke(streak, with: .color((i % 4 == 0 ? accent : ink).opacity(alpha(0.45 * Double(progress)))),
                           style: StrokeStyle(lineWidth: 0.6 + 1.6 * progress, lineCap: .round))
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
            let progress = CGFloat((t * 0.25 + Double(random(index, 9))).truncatingRemainder(dividingBy: 1))
            let dot = trace.trimmedPath(from: max(0, progress - 0.08), to: progress)
            context.stroke(dot, with: .color(accent.opacity(alpha(0.8))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private func prism(_ context: inout GraphicsContext, _ size: CGSize) {
        var beams = context
        beams.addFilter(.blur(radius: 10 * scale))
        let origin = CGPoint(x: -20, y: -20)
        let sweep = sin(t * 0.12) * 0.18
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

    // MARK: Gentle Nature geometry

    private func bamboo(_ context: inout GraphicsContext, _ size: CGSize) {
        let spacing = 62 * scale
        for i in 0..<max(1, Int(size.width / spacing) + 2) {
            let x = CGFloat(i) * spacing + random(i, 1) * spacing * 0.5
            let lean = CGFloat(sin(t * 0.35 + Double(i))) * 6 * scale
            var cane = Path()
            cane.move(to: CGPoint(x: x, y: size.height + 10 * scale))
            cane.addLine(to: CGPoint(x: x + lean, y: -10 * scale))
            context.stroke(cane, with: .color(accent.opacity(alpha(0.12))),
                           style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round))
            var y = random(i, 2) * spacing
            while y < size.height {
                let bend = lean * (1 - y / max(1, size.height))
                var joint = Path()
                joint.move(to: CGPoint(x: x + bend - 4 * scale, y: y))
                joint.addLine(to: CGPoint(x: x + bend + 4 * scale, y: y))
                context.stroke(joint, with: .color(accent.opacity(alpha(0.22))), lineWidth: scale)
                var leafContext = context
                leafContext.translateBy(x: x + bend, y: y)
                leafContext.rotate(by: .degrees(i % 2 == 0 ? 55 : -55))
                leaf(&leafContext, 6 * scale, warm: 1)
                y += spacing
            }
        }
    }





    // MARK: Scenes

    private var stemGreen: Color { Color(red: 0.42, green: 0.64, blue: 0.38) }

    /// A wind that moves across the scene as a slow wave, so plants lean in turn.
    private func wind(_ x: CGFloat, _ size: CGSize, strength: Double = 1) -> Double {
        (sin(t * 0.8 - Double(x / max(size.width, 1)) * 4) * 0.6 + sin(t * 0.33 + Double(x) / 90) * 0.4) * strength
    }

    /// A cherry branch reaching in from the top corner, in flower.
    private func blossomBranch(_ context: inout GraphicsContext, _ size: CGSize) {
        var branch = Path()
        let start = CGPoint(x: -10, y: size.height * 0.08)
        branch.move(to: start)
        branch.addQuadCurve(to: CGPoint(x: size.width * 0.42, y: size.height * 0.04), control: CGPoint(x: size.width * 0.2, y: size.height * 0.2))
        branch.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.13))
        branch.addQuadCurve(to: CGPoint(x: size.width * 0.3, y: size.height * 0.26), control: CGPoint(x: size.width * 0.27, y: size.height * 0.12))
        context.stroke(branch, with: .color(ink.opacity(alpha(0.12))), style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round))
        for i in 0..<16 {
            let along = CGFloat(i) / 15
            let p = CGPoint(x: size.width * 0.42 * along + (random(i, 40) - 0.5) * 18 * scale,
                            y: size.height * (0.05 + 0.12 * random(i, 41)) + CGFloat(sin(Double(along) * 3)) * 8 * scale)
            var c = context
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .degrees(Double(random(i, 42)) * 72 + sin(t * 0.6 + Double(i)) * 6))
            flower(&c, (5 + 3 * random(i, 43)) * scale, petals: 5, petal: accent.opacity(alpha(0.26)), heart: ink.opacity(alpha(0.18)))
        }
    }

    /// One petal that flutters as it falls: it turns, and tips edge-on and back.
    private func petal(_ c: inout GraphicsContext, _ r: CGFloat, _ i: Int) {
        let flip = CGFloat(cos(t * (1.4 + Double(random(i, 7))) + Double(i)))
        c.scaleBy(x: max(0.15, abs(flip)), y: 1)
        var shape = Path()
        shape.move(to: CGPoint(x: 0, y: -r))
        shape.addQuadCurve(to: CGPoint(x: 0, y: r * 0.9), control: CGPoint(x: r * 0.95, y: -r * 0.1))
        shape.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -r * 0.95, y: -r * 0.1))
        c.fill(shape, with: .color(accent.opacity(alpha(0.16 + 0.1 * Double(abs(flip))))))
    }

    /// A field of lavender along the bottom, leaning as the wind passes over it.
    private func lavenderField(_ context: inout GraphicsContext, _ size: CGSize) {
        var x: CGFloat = -4
        var i = 0
        while x < size.width + 8 {
            defer { x += (7 + 5 * random(i, 50)) * scale; i += 1 }
            let height = (40 + 60 * random(i, 51)) * scale
            let lean = CGFloat(wind(x, size)) * 0.18
            let base = CGPoint(x: x, y: size.height + 4)
            let tip = CGPoint(x: x + lean * height, y: size.height - height)
            var stem = Path()
            stem.move(to: base)
            stem.addQuadCurve(to: tip, control: CGPoint(x: x + lean * height * 0.3, y: size.height - height * 0.5))
            context.stroke(stem, with: .color(stemGreen.opacity(alpha(0.18))), lineWidth: 1.1 * scale)
            // Buds up the top of the stem, smaller toward the tip.
            for k in 0..<8 {
                let f = CGFloat(k) / 8
                let p = CGPoint(x: x + lean * height * (0.62 + 0.38 * f), y: size.height - height * (0.62 + 0.38 * f))
                let r = (2.6 - 1.4 * f) * scale
                for side: CGFloat in [-1, 1] {
                    context.fill(Path(ellipseIn: CGRect(x: p.x + side * r * 0.7 - r * 0.55, y: p.y - r, width: r * 1.1, height: r * 1.6)),
                                 with: .color(accent.opacity(alpha(0.22 + 0.08 * Double(random(i * 8 + k, 52))))))
                }
            }
        }
        // A bee or two drifting over the flowers.
        for b in 0..<2 {
            let bx = travel(random(b, 53), speed: 18, span: size.width + 40) - 20
            let by = size.height * (0.55 + 0.1 * CGFloat(b)) + CGFloat(sin(t * 2.3 + Double(b) * 3)) * 10 * scale
            context.fill(circle(CGPoint(x: bx, y: by), 1.8 * scale), with: .color(Color(red: 0.95, green: 0.78, blue: 0.3).opacity(alpha(0.45))))
            let flap = abs(sin(t * 30 + Double(b))) * 2.2 * scale
            context.fill(Path(ellipseIn: CGRect(x: bx - 1.5 * scale, y: by - 2 * scale - flap, width: 3 * scale, height: flap + 0.5)),
                         with: .color(ink.opacity(alpha(0.25))))
        }
    }

    /// Sunflowers along the bottom: tall stems with leaves, heavy heads nodding.
    private func sunflowers(_ context: inout GraphicsContext, _ size: CGSize) {
        let count = max(3, Int(size.width / (92 * scale)))
        for i in 0..<count {
            let x = (CGFloat(i) + 0.5) / CGFloat(count) * size.width + (random(i, 60) - 0.5) * 30 * scale
            let height = size.height * (0.32 + 0.3 * random(i, 61))
            let sway = CGFloat(wind(x, size, strength: 0.7)) * 10 * scale
            let head = CGPoint(x: x + sway, y: size.height - height)
            var stem = Path()
            stem.move(to: CGPoint(x: x, y: size.height + 4))
            stem.addQuadCurve(to: head, control: CGPoint(x: x + sway * 0.2, y: size.height - height * 0.5))
            context.stroke(stem, with: .color(stemGreen.opacity(alpha(0.22))), lineWidth: 2.2 * scale)
            for side: CGFloat in [-1, 1] {
                var leafContext = context
                leafContext.translateBy(x: x + sway * 0.3, y: size.height - height * (0.35 + 0.15 * (side + 1)))
                leafContext.rotate(by: .degrees(Double(side) * 60 + sin(t * 0.8 + Double(i)) * 5))
                leaf(&leafContext, 8 * scale, warm: 1, color: stemGreen)
            }
            var c = context
            c.translateBy(x: head.x, y: head.y)
            // Heads face a little to one side, turning slowly.
            c.scaleBy(x: 0.82 + 0.18 * CGFloat(cos(t * 0.15 + Double(i))), y: 1)
            c.rotate(by: .degrees(Double(sway / scale) * 1.5))
            let r = (13 + 6 * random(i, 62)) * scale
            for k in 0..<16 {
                var p = c
                p.rotate(by: .degrees(Double(k) * 22.5))
                p.fill(Path(ellipseIn: CGRect(x: -r * 0.17, y: -r * 1.15, width: r * 0.34, height: r * 0.62)),
                       with: .color(accent.opacity(alpha(0.3))))
            }
            c.fill(circle(.zero, r * 0.5), with: .color(Color(red: 0.36, green: 0.22, blue: 0.1).opacity(alpha(0.42))))
            for k in 0..<10 {
                let angle = Double(k) * 2.4
                let d = r * 0.4 * CGFloat(sqrt(Double(k) / 10))
                c.fill(circle(CGPoint(x: CGFloat(cos(angle)) * d, y: CGFloat(sin(angle)) * d), 0.9 * scale),
                       with: .color(accent.opacity(alpha(0.3))))
            }
        }
    }

    /// A meadow: grasses and mixed wildflowers moving in the wind, butterflies over them.
    private func meadow(_ context: inout GraphicsContext, _ size: CGSize) {
        var x: CGFloat = 0
        var i = 0
        while x < size.width {
            defer { x += 5 * scale; i += 1 }
            let height = (14 + 30 * random(i, 70)) * scale
            let lean = CGFloat(wind(x, size)) * 0.3
            var blade = Path()
            blade.move(to: CGPoint(x: x, y: size.height + 2))
            blade.addQuadCurve(to: CGPoint(x: x + lean * height, y: size.height - height), control: CGPoint(x: x, y: size.height - height * 0.6))
            context.stroke(blade, with: .color(stemGreen.opacity(alpha(0.16))), lineWidth: scale)
        }
        let palette = [accent, Color.white, Color(red: 1, green: 0.84, blue: 0.3), Color(red: 0.7, green: 0.55, blue: 1)]
        for f in 0..<max(8, Int(size.width / (26 * scale))) {
            let fx = random(f, 71) * size.width
            let height = (24 + 50 * random(f, 72)) * scale
            let lean = CGFloat(wind(fx, size)) * 0.22
            let head = CGPoint(x: fx + lean * height, y: size.height - height)
            var stem = Path()
            stem.move(to: CGPoint(x: fx, y: size.height + 2))
            stem.addQuadCurve(to: head, control: CGPoint(x: fx, y: size.height - height * 0.5))
            context.stroke(stem, with: .color(stemGreen.opacity(alpha(0.2))), lineWidth: 0.9 * scale)
            var c = context
            c.translateBy(x: head.x, y: head.y)
            c.rotate(by: .degrees(Double(random(f, 73)) * 60))
            let colour = palette[f % palette.count]
            flower(&c, (5.5 + 4 * random(f, 74)) * scale, petals: f % 3 == 0 ? 8 : 5,
                   petal: colour.opacity(alpha(0.3)), heart: Color(red: 1, green: 0.8, blue: 0.3).opacity(alpha(0.35)))
        }
        for b in 0..<3 {
            let bx = travel(random(b, 75), speed: 12 + 6 * random(b, 76), span: size.width + 60) - 30
            let by = size.height * (0.3 + 0.25 * random(b, 77)) + CGFloat(sin(t * 1.6 + Double(b) * 2)) * 16 * scale
            let flap = CGFloat(abs(sin(t * 9 + Double(b))))
            var c = context
            c.translateBy(x: bx, y: by)
            for side: CGFloat in [-1, 1] {
                c.fill(Path(ellipseIn: CGRect(x: side > 0 ? 0 : -5 * scale * flap, y: -4 * scale, width: 5 * scale * flap, height: 7 * scale)),
                       with: .color(palette[(b + 1) % palette.count].opacity(alpha(0.4))))
            }
        }
    }

    /// Still water with drifting lily pads, lotus flowers opening on them, and rings
    /// spreading where something touches the surface.
    private func lotusPond(_ context: inout GraphicsContext, _ size: CGSize) {
        lines(&context, size, spacing: 30, amplitude: 2, wavelength: 90, width: 0.9, opacity: 0.07, drift: 0.25)
        for i in 0..<max(5, Int(size.width / (80 * scale))) {
            let x = random(i, 80) * size.width + CGFloat(sin(t * 0.07 + Double(i))) * 16 * scale
            let y = size.height * (i % 2 == 0 ? 0.82 + 0.12 * random(i, 81) : 0.08 + 0.14 * random(i, 81))
            let r = (13 + 9 * random(i, 82)) * scale
            var pad = Path()
            let notch = Double(random(i, 83)) * 6.28 + sin(t * 0.1 + Double(i)) * 0.3
            pad.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: .radians(notch + 0.25), endAngle: .radians(notch - 0.25 + 6.28), clockwise: false)
            pad.addLine(to: CGPoint(x: x, y: y))
            pad.closeSubpath()
            context.fill(pad, with: .color(stemGreen.opacity(alpha(0.2))))
            guard i % 2 == 0 else { continue }
            // A lotus: layered petals that open and close slowly.
            var c = context
            c.translateBy(x: x + r * 0.15, y: y - r * 0.2)
            let open = 0.75 + 0.25 * sin(t * 0.25 + Double(i))
            for layer in 0..<2 {
                for k in 0..<6 {
                    var p = c
                    p.rotate(by: .degrees(Double(k) * 60 + Double(layer) * 30))
                    let length = r * (layer == 0 ? 0.95 : 0.65) * CGFloat(open)
                    p.fill(Path(ellipseIn: CGRect(x: -r * 0.17, y: -length, width: r * 0.34, height: length)),
                           with: .color(accent.opacity(alpha(layer == 0 ? 0.28 : 0.38))))
                }
            }
            c.fill(circle(.zero, r * 0.16), with: .color(Color(red: 1, green: 0.85, blue: 0.4).opacity(alpha(0.45))))
        }
        for k in 0..<3 {
            let period = 5.0 + Double(k)
            let phase = (t / period + Double(k) * 0.37).truncatingRemainder(dividingBy: 1)
            let cycle = Int(t / period + Double(k) * 0.37)
            let center = CGPoint(x: size.width * random(cycle * 3 + k, 84), y: size.height * (0.3 + 0.4 * random(cycle * 3 + k, 85)))
            for ring in 0..<2 {
                let r = (8 + 60 * phase - Double(ring) * 10) * Double(scale)
                guard r > 0 else { continue }
                context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r * 0.4, width: r * 2, height: r * 0.8)),
                               with: .color(ink.opacity(alpha(0.12 * (1 - phase)))), lineWidth: 0.8)
            }
        }
    }

    /// Big fern fronds reaching in from the bottom corners, swaying.
    private func fernFronds(_ context: inout GraphicsContext, _ size: CGSize) {
        let roots: [(CGPoint, Double, CGFloat)] = [
            (CGPoint(x: -8, y: size.height + 8), -55, 1), (CGPoint(x: size.width * 0.12, y: size.height + 10), -25, 0.8),
            (CGPoint(x: size.width + 8, y: size.height + 8), -125, 1), (CGPoint(x: size.width * 0.86, y: size.height + 10), -150, 0.85),
            (CGPoint(x: size.width * 0.5, y: size.height + 14), -95, 0.6),
        ]
        for (index, root) in roots.enumerated() {
            let length = min(size.height * 0.9, 190 * scale) * root.2
            let angle = root.1 + sin(t * 0.5 + Double(index) * 1.3) * 4
            var c = context
            c.translateBy(x: root.0.x, y: root.0.y)
            c.rotate(by: .degrees(angle))
            // The stem curls a little toward its tip.
            let curl = CGFloat(index % 2 == 0 ? 1 : -1) * length * 0.18
            var rachis = Path()
            rachis.move(to: .zero)
            rachis.addQuadCurve(to: CGPoint(x: length, y: curl), control: CGPoint(x: length * 0.6, y: 0))
            c.stroke(rachis, with: .color(stemGreen.opacity(alpha(0.22))), lineWidth: 1.4 * scale)
            for k in 1..<18 {
                let f = CGFloat(k) / 18
                let along = CGPoint(x: length * f, y: curl * f * f)
                let leafLength = length * 0.22 * (1 - f * 0.85)
                for side: CGFloat in [-1, 1] {
                    var leafContext = c
                    leafContext.translateBy(x: along.x, y: along.y)
                    leafContext.rotate(by: .degrees(Double(side) * (62 - Double(f) * 20)))
                    var leaflet = Path()
                    leaflet.move(to: .zero)
                    leaflet.addQuadCurve(to: CGPoint(x: leafLength, y: 0), control: CGPoint(x: leafLength * 0.5, y: -leafLength * 0.22))
                    leaflet.addQuadCurve(to: .zero, control: CGPoint(x: leafLength * 0.5, y: leafLength * 0.22))
                    leafContext.fill(leaflet, with: .color(accent.opacity(alpha(0.2))))
                }
            }
        }
    }

    /// A moon rising over a pine treeline, mist drifting between the trees.
    private func moonrise(_ context: inout GraphicsContext, _ size: CGSize) {
        for i in 0..<26 {
            let p = CGPoint(x: random(i, 90) * size.width, y: random(i, 91) * size.height * 0.6)
            let twinkle = 0.4 + 0.6 * (0.5 + 0.5 * sin(t * (0.8 + Double(random(i, 92))) + Double(i)))
            context.fill(circle(p, (0.6 + random(i, 93)) * scale), with: .color(ink.opacity(alpha(0.28 * twinkle))))
        }
        let rise = CGFloat(sin(t * 0.05)) * 6 * scale
        let moon = CGPoint(x: size.width * 0.78, y: size.height * 0.3 + rise)
        let r = 22 * scale
        context.fill(circle(moon, r * 3), with: .radialGradient(Gradient(colors: [accent.opacity(alpha(0.16)), .clear]),
                                                                center: moon, startRadius: r, endRadius: r * 3))
        context.fill(circle(moon, r), with: .color(accent.opacity(alpha(0.32))))
        context.fill(circle(CGPoint(x: moon.x + r * 0.42, y: moon.y - r * 0.18), r * 0.92), with: .color(.black.opacity(0.0)))
        var crater = context
        crater.opacity = 0.5
        for k in 0..<3 {
            crater.fill(circle(CGPoint(x: moon.x - r * (0.3 - 0.25 * CGFloat(k)), y: moon.y + r * (0.2 - 0.2 * CGFloat(k))), r * 0.14),
                        with: .color(ink.opacity(alpha(0.08))))
        }
        // Two rows of pines: each a trunk under three stacked tiers.
        for layer in 0..<2 {
            let base = size.height * (layer == 0 ? 0.9 : 1.0)
            var x: CGFloat = -10, i = layer * 100
            var trees = Path()
            while x < size.width + 20 {
                let w = (16 + 12 * random(i, 94)) * scale * (layer == 0 ? 0.8 : 1)
                let h = (34 + 40 * random(i, 95)) * scale * (layer == 0 ? 0.75 : 1)
                let cx = x + w / 2
                trees.addRect(CGRect(x: cx - w * 0.06, y: base - h * 0.2, width: w * 0.12, height: h * 0.2 + 4))
                for tier in 0..<3 {
                    let f = CGFloat(tier)
                    let tierBase = base - h * (0.12 + 0.26 * f)
                    let half = w * (0.5 - 0.12 * f)
                    trees.move(to: CGPoint(x: cx - half, y: tierBase))
                    trees.addLine(to: CGPoint(x: cx, y: tierBase - h * 0.42))
                    trees.addLine(to: CGPoint(x: cx + half, y: tierBase))
                    trees.closeSubpath()
                }
                x += w * (0.75 + 0.5 * random(i, 96)); i += 1
            }
            trees.addRect(CGRect(x: 0, y: base, width: size.width, height: size.height - base + 4))
            context.fill(trees, with: .color(ink.opacity(alpha(layer == 0 ? 0.06 : 0.11))))
        }
        var mist = context
        mist.addFilter(.blur(radius: 12 * scale))
        let drift = CGFloat(t * 6).truncatingRemainder(dividingBy: size.width + 200) - 100
        mist.fill(Path(ellipseIn: CGRect(x: drift, y: size.height * 0.8, width: 220 * scale, height: 18 * scale)), with: .color(ink.opacity(alpha(0.06))))
    }

    /// Red rock: layered mesas and strata, heat shimmer and drifting dust.
    private func canyon(_ context: inout GraphicsContext, _ size: CGSize) {
        for layer in 0..<4 {
            let base = size.height * (0.58 + 0.12 * CGFloat(layer))
            var rock = Path()
            rock.move(to: CGPoint(x: 0, y: size.height))
            var x: CGFloat = -20, i = layer * 40
            rock.addLine(to: CGPoint(x: x, y: base))
            while x < size.width + 20 {
                let w = (60 + 110 * random(i, 100)) * scale
                let lift = (random(i, 101) > 0.55 ? (18 + 30 * random(i, 102)) : 4 * random(i, 102)) * scale
                // Flat-topped mesas with steep sides.
                rock.addLine(to: CGPoint(x: x + w * 0.12, y: base - lift))
                rock.addLine(to: CGPoint(x: x + w * 0.88, y: base - lift))
                rock.addLine(to: CGPoint(x: x + w, y: base))
                x += w; i += 1
            }
            rock.addLine(to: CGPoint(x: size.width, y: size.height))
            rock.closeSubpath()
            context.fill(rock, with: .color(accent.opacity(alpha(0.06 + 0.035 * Double(layer)))))
            // Strata lines across each layer.
            for k in 0..<3 {
                var line = Path()
                let y = base + CGFloat(k + 1) * 7 * scale
                line.move(to: CGPoint(x: 0, y: y))
                var lx: CGFloat = 0
                while lx < size.width { lx += 8; line.addLine(to: CGPoint(x: lx, y: y + CGFloat(sin(Double(lx) / 50 + Double(layer + k))) * 2)) }
                context.stroke(line, with: .color(ink.opacity(alpha(0.05))), lineWidth: 0.8)
            }
        }
        for k in 0..<5 {
            var shimmer = Path()
            let y = size.height * (0.5 - 0.05 * CGFloat(k)) - CGFloat((t * 4 + Double(k) * 9).truncatingRemainder(dividingBy: 30)) * scale
            shimmer.move(to: CGPoint(x: 0, y: y))
            var sx: CGFloat = 0
            while sx < size.width { sx += 6; shimmer.addLine(to: CGPoint(x: sx, y: y + CGFloat(sin(Double(sx) / 14 + t * 2 + Double(k))) * 1.5)) }
            context.stroke(shimmer, with: .color(ink.opacity(alpha(0.035))), lineWidth: 1)
        }
        for i in 0..<20 {
            let x = travel(random(i, 103), speed: 10 + 8 * random(i, 104), span: size.width + 20) - 10
            let y = size.height * (0.4 + 0.5 * random(i, 105)) + CGFloat(sin(t + Double(i))) * 4 * scale
            context.fill(circle(CGPoint(x: x, y: y), (0.6 + random(i, 106)) * scale), with: .color(accent.opacity(alpha(0.25))))
        }
    }

    /// Snow in depth: far flakes small and slow, near ones large, soft and quicker,
    /// all carried by the same wind, settling into drifts.
    private func snowScene(_ context: inout GraphicsContext, _ size: CGSize) {
        for layer in 0..<2 {
            var hills = Path()
            hills.move(to: CGPoint(x: 0, y: size.height))
            let base = size.height * (layer == 0 ? 0.8 : 0.9)
            var x: CGFloat = 0
            while x <= size.width + 10 {
                hills.addLine(to: CGPoint(x: x, y: base - CGFloat(sin(Double(x) / (layer == 0 ? 120 : 70) + Double(layer))) * 10 * scale))
                x += 8
            }
            hills.addLine(to: CGPoint(x: size.width, y: size.height))
            hills.closeSubpath()
            context.fill(hills, with: .color(ink.opacity(alpha(layer == 0 ? 0.05 : 0.09))))
        }
        let gust = CGFloat(sin(t * 0.3)) * 22 * scale
        for depth in 0..<3 {
            var layer = context
            if depth == 2 { layer.addFilter(.blur(radius: 1.6 * scale)) }
            let spacing: CGFloat = [26, 40, 70][depth]
            let speed: CGFloat = [8, 16, 28][depth]
            let radius: CGFloat = [0.8, 1.6, 3][depth]
            let span = size.height + 20 * scale
            for i in 0..<count(size, spacing: spacing) {
                let seed = i + depth * 1000
                let y = travel(random(seed, 3), speed: speed * (0.8 + 0.4 * random(seed, 4)), span: span) - 10 * scale
                let x = random(seed, 1) * (size.width + 40) - 20 + gust * CGFloat(depth + 1) / 3
                    + CGFloat(sin(t * 0.9 + Double(seed))) * 8 * scale
                layer.fill(circle(CGPoint(x: x, y: y), radius * (0.7 + 0.6 * random(seed, 5)) * scale),
                           with: .color(ink.opacity(alpha([0.22, 0.3, 0.26][depth]))))
            }
        }
    }

    /// An ice shelf of faceted blue blocks; light sweeps across it, and crystals glint in the air.
    private func glacier(_ context: inout GraphicsContext, _ size: CGSize) {
        var shelf = Path()
        var facets: [Path] = []
        var x: CGFloat = -20, i = 0
        let base = size.height * 0.68
        shelf.move(to: CGPoint(x: -20, y: size.height))
        while x < size.width + 20 {
            let w = (40 + 60 * random(i, 110)) * scale
            let top = base - (10 + 40 * random(i, 111)) * scale
            let peak = CGPoint(x: x + w * (0.3 + 0.4 * random(i, 112)), y: top)
            shelf.addLine(to: CGPoint(x: x, y: base + 6 * scale))
            shelf.addLine(to: peak)
            var facet = Path()
            facet.move(to: peak)
            facet.addLine(to: CGPoint(x: x + w, y: base + 6 * scale))
            facet.addLine(to: CGPoint(x: peak.x + w * 0.1, y: size.height))
            facet.addLine(to: CGPoint(x: peak.x - w * 0.05, y: size.height))
            facet.closeSubpath()
            facets.append(facet)
            x += w; i += 1
        }
        shelf.addLine(to: CGPoint(x: size.width + 20, y: size.height))
        shelf.closeSubpath()
        context.fill(shelf, with: .linearGradient(Gradient(colors: [accent.opacity(alpha(0.16)), accent.opacity(alpha(0.06))]),
                                                  startPoint: CGPoint(x: 0, y: base - 40 * scale), endPoint: CGPoint(x: 0, y: size.height)))
        for facet in facets { context.fill(facet, with: .color(ink.opacity(alpha(0.05)))) }
        context.stroke(shelf, with: .color(ink.opacity(alpha(0.16))), lineWidth: 0.8 * scale)
        // A band of light moving slowly across the ice.
        var shine = context
        shine.clip(to: shelf)
        let sweep = CGFloat((t * 0.05).truncatingRemainder(dividingBy: 1)) * (size.width + 300) - 150
        var band = Path()
        band.move(to: CGPoint(x: sweep, y: size.height))
        band.addLine(to: CGPoint(x: sweep + 60 * scale, y: base - 60 * scale))
        band.addLine(to: CGPoint(x: sweep + 100 * scale, y: base - 60 * scale))
        band.addLine(to: CGPoint(x: sweep + 40 * scale, y: size.height))
        band.closeSubpath()
        shine.addFilter(.blur(radius: 8 * scale))
        shine.fill(band, with: .color(ink.opacity(alpha(0.16))))
        for k in 0..<18 {
            let p = CGPoint(x: random(k, 113) * size.width,
                            y: size.height * 0.7 - travel(random(k, 114), speed: 4 + 4 * random(k, 115), span: size.height * 0.7))
            let glint = max(0, sin(t * (1 + Double(random(k, 116))) + Double(k) * 2))
            var c = context
            c.translateBy(x: p.x, y: p.y)
            sparkle(&c, (2 + 2 * random(k, 117)) * scale * CGFloat(0.5 + 0.5 * glint), .color(ink.opacity(alpha(0.35 * glint))))
        }
    }

    // MARK: Shapes


    private func leaf(_ c: inout GraphicsContext, _ r: CGFloat, warm: Int, color: Color? = nil) {
        let tint = color ?? accent
        var leaf = Path()
        leaf.move(to: CGPoint(x: 0, y: -r * 1.2))
        leaf.addQuadCurve(to: CGPoint(x: 0, y: r * 1.2), control: CGPoint(x: r * 1.1, y: 0))
        leaf.addQuadCurve(to: CGPoint(x: 0, y: -r * 1.2), control: CGPoint(x: -r * 1.1, y: 0))
        c.fill(leaf, with: .color(tint.opacity(alpha([0.16, 0.11, 0.2][warm % 3]))))
        var rib = Path(); rib.move(to: CGPoint(x: 0, y: -r * 1.1)); rib.addLine(to: CGPoint(x: 0, y: r * 1.4))
        c.stroke(rib, with: .color(tint.opacity(alpha(0.18))), lineWidth: 0.8)
    }

    /// A small open flower: rounded petals around a centre.
    private func flower(_ c: inout GraphicsContext, _ r: CGFloat, petals: Int, petal: Color, heart: Color) {
        for k in 0..<petals {
            var p = c
            p.rotate(by: .degrees(Double(k) * 360 / Double(petals)))
            p.fill(Path(ellipseIn: CGRect(x: -r * 0.36, y: -r * 1.05, width: r * 0.72, height: r * 0.95)), with: .color(petal))
        }
        c.fill(circle(.zero, r * 0.28), with: .color(heart))
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
