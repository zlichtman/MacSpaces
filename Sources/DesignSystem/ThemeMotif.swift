import SwiftUI

/// A theme's effect behind the open Nook: petals drifting down for Blossom, rain for
/// Monsoon, a flowing rainbow keyboard for Rainbow, and so on. Flower scenes use
/// generated botanical photographs with a gentle breeze. Earth and Water scenes
/// use detailed photographs with their own weather and atmosphere; other effects
/// use original geometry. Effects move only while the Nook is open and Reduce Motion is off;
/// otherwise they hold a still frame. They stay faint and frame the content.
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

    /// Photographic scenes keep their existing motif and saved theme IDs.
    var natureAsset: String? {
        switch self {
        case .lava: return "ThemeLava"
        case .canyon: return "ThemeCanyon"
        case .embers: return "ThemeEmber"
        case .ripples: return "ThemeDune"
        case .autumn: return "ThemeAutumn"
        case .waves: return "ThemeTidal"
        case .glacier: return "ThemeGlacier"
        case .rain: return "ThemeMonsoon"
        case .snow: return "ThemeSnow"
        case .storm: return "ThemeThunderstorm"
        case .fireflies: return "ThemeFirefly"
        case .bamboo: return "ThemeBamboo"
        case .leaves: return "ThemeMoss"
        case .fronds: return "ThemeFern"
        case .moonrise: return "ThemeMoonrise"
        case .stars: return "ThemeStarlight"
        case .aurora: return "ThemeAurora"
        case .prism: return "ThemePrism"
        case .plasma: return "ThemePlasma"
        case .nebula: return "ThemeNebula"
        default: return nil
        }
    }

    /// Asset names are shared by the live Nook and still Settings cards.
    var floralAsset: String? {
        switch self {
        case .petals: return "ThemeBlossom"
        case .lavenderField: return "ThemeLavender"
        case .sunflowers: return "ThemeSunflower"
        case .meadow: return "ThemeWildflower"
        case .lotus: return "ThemeLotus"
        default: return nil
        }
    }
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
    /// Theme cards: draw a small copy of the photo, made once off the main thread,
    /// instead of decoding the full-size HEIC for every card (the theme picker lagged).
    var thumbnail = false
    @ObservedObject private var photos = MotifImages.shared

    /// The moment a still frame shows, chosen so every effect looks settled.
    static let stillTime = 7.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var moves: Bool { animated && !reduceMotion }

    var body: some View {
        Group {
            if moves {
                // Menu-bar panels can pause display-linked animation schedules.
                TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
                    let t = (timeline.date.timeIntervalSinceReferenceDate / Design.demoTimeScale)
                        .truncatingRemainder(dividingBy: 3600)
                    scene(at: t)
                }
            } else {
                // No timer at all for previews, disabled animation or Reduce Motion.
                scene(at: Self.stillTime)
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
        .task(id: motif) { if !thumbnail { photos.prepare(motif) } }
    }

    @ViewBuilder private func scene(at t: Double) -> some View {
        if let asset = motif.floralAsset {
            if thumbnail {
                MotifThumbnailPhoto(asset: asset) { photo in
                    FloralMotifView(photo: photo, motif: motif, strength: strength, t: t, animated: moves)
                }
            } else if let image = photos.image(for: asset) {
                FloralMotifView(photo: Image(decorative: image, scale: 1), motif: motif,
                                strength: strength, t: t, animated: moves)
            }
        } else if let asset = motif.natureAsset {
            if thumbnail {
                MotifThumbnailPhoto(asset: asset) { photo in
                    NatureMotifView(photo: photo, motif: motif, accent: accent, ink: ink,
                                    scale: scale, strength: strength, t: t, animated: moves)
                }
            } else if let image = photos.image(for: asset) {
                NatureMotifView(photo: Image(decorative: image, scale: 1), motif: motif, accent: accent, ink: ink,
                                scale: scale, strength: strength, t: t, animated: moves)
            }
        } else {
            Canvas(rendersAsynchronously: false) { context, size in
                MotifPainter(motif: motif, accent: accent, ink: ink, scale: scale, strength: strength, t: t)
                    .paint(&context, size)
            }
        }
    }
}

/// Only Settings cards observe thumbnail arrivals; decoding a card must not
/// invalidate the live scene behind an opening Nook.
private struct MotifThumbnailPhoto<Content: View>: View {
    let asset: String
    let content: (Image) -> Content
    @ObservedObject private var thumbnails = MotifThumbnails.shared

    var body: some View {
        if let image = thumbnails.image(asset) {
            content(Image(decorative: image, scale: 1))
        }
    }
}

/// The photo remains sharp; a small GPU displacement moves the side flowers while
/// keeping their roots and the quiet center steady. macOS 13 uses a gentle pan.
private struct FloralMotifView: View {
    let photo: Image
    let motif: ThemeMotif
    let strength: Double
    let t: Double
    let animated: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = CGSize(width: geometry.size.width + 12, height: geometry.size.height + 12)
            // One Canvas keeps the photo, parallax and particles on the same frame clock.
            let scene = Canvas { context, canvasSize in
                let photo = context.resolve(photo)
                let fit = max(canvasSize.width / max(1, photo.size.width),
                              canvasSize.height / max(1, photo.size.height))
                let width = photo.size.width * fit + 12
                let height = photo.size.height * fit + 12
                let panX = animated ? CGFloat(sin(t * 0.22)) * 1.5 : 0
                let panY = animated ? CGFloat(cos(t * 0.17)) * 0.6 : 0
                var imageContext = context
                imageContext.opacity = min(1, max(0, 0.52 * strength))
                imageContext.draw(photo, in: CGRect(x: (canvasSize.width - width) / 2 + panX,
                    y: -6 + panY, width: width, height: height))
                if animated {
                    // A few soft pollen motes (petals for Blossom), concentrated at the edges.
                    for i in 0..<12 {
                        let phase = Double(i) * 2.39996
                        let progress = (t * 0.012 + Double(i) / 12).truncatingRemainder(dividingBy: 1)
                        let edge = CGFloat(i % 6) / 6 * 0.26
                        let x = canvasSize.width * (i % 2 == 0 ? edge : 1 - edge)
                            + CGFloat(sin(t * 0.28 + phase)) * 7
                        let y = canvasSize.height * CGFloat(1 - progress)
                        let radius: CGFloat = motif == .petals ? 2.2 : 0.9
                        let fade = sin(progress * .pi) * min(1, max(0, strength)) * 0.24
                        var particle = context
                        particle.translateBy(x: x, y: y)
                        particle.rotate(by: .radians(t * 0.35 + phase))
                        particle.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius,
                            width: radius * 2, height: radius * (motif == .petals ? 3 : 2))),
                            with: .color((motif == .petals ? Color(red: 1, green: 0.8, blue: 0.86)
                                                          : Color(red: 1, green: 0.91, blue: 0.7)).opacity(fade)))
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            Group {
                if #available(macOS 14.0, *), animated {
                    scene.distortionEffect(ShaderLibrary.floralBreeze(
                        .float2(Float(size.width), Float(size.height)), .float(Float(t)),
                        .float(motif == .lotus ? 1 : 0)),
                        maxSampleOffset: CGSize(width: 3, height: 2))
                } else {
                    scene
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}

/// The scene image and its weather share the same Canvas and 30 fps clock.
private struct NatureMotifView: View {
    let photo: Image
    let motif: ThemeMotif
    let accent: Color
    let ink: Color
    let scale: CGFloat
    let strength: Double
    let t: Double
    let animated: Bool

    private var motionKind: Float {
        switch motif {
        case .ripples: return 0 // Wind ripples only in the foreground sand.
        case .lava: return 1
        case .waves: return 2
        case .canyon: return 3
        case .autumn, .fronds, .bamboo: return 4
        case .aurora: return 6
        case .plasma, .nebula: return 7
        default: return 5 // Weather overlays move; solid ice and trees stay still.
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let margin: CGFloat = motif == .aurora ? 32 : 12
            let size = CGSize(width: geometry.size.width + margin, height: geometry.size.height + margin)
            let scene = Canvas { context, canvasSize in
                let photo = context.resolve(photo)
                let fit = max(canvasSize.width / max(1, photo.size.width),
                              canvasSize.height / max(1, photo.size.height))
                let width = photo.size.width * fit + 12
                let height = photo.size.height * fit + 12
                // Keep the camera fixed on dunes and ice; their atmosphere supplies movement.
                let pans = animated && ![ThemeMotif.ripples, .glacier, .moonrise].contains(motif)
                let panX = pans ? CGFloat(sin(t * 0.18)) * 0.6 : 0
                let panY = pans ? CGFloat(cos(t * 0.15)) * 0.3 : 0
                let fire = animated && (motif == .lava || motif == .embers || motif == .plasma)
                let glow = fire ? 0.97 + 0.03 * sin(t * 1.1) : 1
                var imageContext = context
                imageContext.opacity = min(1, max(0, 0.52 * strength * glow))
                // Prism's light slowly turns through the spectrum; nothing is drawn on top
                // of it, or of Aurora, whose photo flows on its own (owner).
                if animated && motif == .prism {
                    imageContext.addFilter(.hueRotation(.radians(t * 0.22)))
                }
                imageContext.draw(photo, in: CGRect(x: (canvasSize.width - width) / 2 + panX,
                    y: -6 + panY, width: width, height: height))
                if animated {
                    MotifPainter(motif: motif, accent: accent, ink: ink, scale: scale, strength: strength, t: t)
                        .paintPhotographicAtmosphere(&context, canvasSize)
                }
            }
            .frame(width: size.width, height: size.height)
            Group {
                if #available(macOS 14.0, *), animated, motionKind != 5 {
                    scene.distortionEffect(ShaderLibrary.natureMotion(
                        .float2(Float(size.width), Float(size.height)), .float(Float(t)), .float(motionKind)),
                        maxSampleOffset: motif == .aurora ? CGSize(width: 8, height: 14) : CGSize(width: 3, height: 2))
                } else {
                    scene
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
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
        case .petals, .lavenderField, .sunflowers, .meadow, .lotus: break // Photo scenes above.
        case .embers, .lava, .ripples, .autumn, .canyon, .waves, .rain, .storm, .snow, .glacier: break // Photo scenes above.
        case .fronds, .leaves, .bamboo, .fireflies, .moonrise, .aurora, .stars, .nebula, .prism, .plasma: break // Photo scenes above.
        // Rainbow is a drawn theme, not a photo (owner): a current of moving light.
        case .rainbowKeys: rainbowFlow(&context, size)
        case .synthGrid: synthGrid(&context, size)
        case .circuit: circuit(&context, size)
        case .codeRain: codeRain(&context, size)
        case .warp: warp(&context, size)
        }
    }

    /// Only weather and atmosphere; the photograph already supplies the terrain.
    func paintPhotographicAtmosphere(_ context: inout GraphicsContext, _ size: CGSize) {
        switch motif {
        case .lava, .embers: embers(&context, size)
        case .ripples, .canyon: windblownSand(&context, size)
        case .autumn:
            falling(&context, size, spacing: 80, speed: 16, sway: 18, spin: 0.5) { c, r, i in
                leaf(&c, r * 0.65, warm: i % 3)
            }
        case .rain: rain(&context, size, heavy: false)
        case .storm: lightning(&context, size); rain(&context, size, heavy: true)
        case .snow: snowParticles(&context, size)
        case .glacier, .leaves: iceGlints(&context, size)
        case .fireflies: fireflies(&context, size)
        case .stars: starfield(&context, size)
        case .nebula: skyGlints(&context, size)
        case .moonrise: skyGlints(&context, size); forestMist(&context, size)
        case .bamboo, .fronds: forestMist(&context, size)
        default: break
        }
    }

    private func skyGlints(_ context: inout GraphicsContext, _ size: CGSize) {
        for i in 0..<24 {
            let p=CGPoint(x: random(i, 170)*size.width, y: random(i, 171)*size.height*0.62)
            let glow=0.4+0.6*max(0, sin(t*0.7+Double(i)*1.9))
            context.fill(circle(p, (0.45+0.45*random(i, 172))*scale),
                         with: .color(Color.white.opacity(alpha(0.16*glow))))
        }
    }

    private func forestMist(_ context: inout GraphicsContext, _ size: CGSize) {
        var mist=context
        mist.addFilter(.blur(radius: 12*scale))
        for i in 0..<3 {
            let x=travel(random(i, 180), speed: 5+3*random(i, 181), span: size.width+240)-120
            let y=size.height*(0.72+0.08*CGFloat(i))
            mist.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 160*scale, height: 9*scale)),
                      with: .color(Color.white.opacity(alpha(0.035))))
        }
    }

    /// Wind carries tiny sand grains and a low veil along the dune ridges.
    private func windblownSand(_ context: inout GraphicsContext, _ size: CGSize) {
        for i in 0..<48 {
            let x = travel(random(i, 150), speed: 16 + 20 * random(i, 151), span: size.width + 20) - 10
            let y = size.height * (0.52 + 0.45 * random(i, 152))
                + CGFloat(sin(t * 0.7 + Double(i))) * 2 * scale
            let radius = (0.3 + 0.65 * random(i, 153)) * scale
            let glint = 0.45 + 0.55 * abs(sin(t * 0.9 + Double(i)))
            context.fill(circle(CGPoint(x: x, y: y), radius),
                with: .color(Color(red: 1, green: 0.87, blue: 0.61).opacity(alpha(0.30 * glint))))
        }
        // Long, diffuse wisps hug the sand; they never redraw or reshape the dunes.
        var haze = context
        haze.addFilter(.blur(radius: 5 * scale))
        for i in 0..<4 {
            let x = travel(random(i, 154), speed: 12 + 6 * random(i, 155), span: size.width + 180) - 90
            let y = size.height * (0.65 + 0.08 * CGFloat(i)) + CGFloat(sin(t * 0.35 + Double(i))) * 3
            haze.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 85 * scale, height: 3 * scale)),
                with: .color(Color(red: 1, green: 0.86, blue: 0.58).opacity(alpha(0.06))))
        }
    }

    private func iceGlints(_ context: inout GraphicsContext, _ size: CGSize) {
        for i in 0..<16 {
            let point = CGPoint(x: random(i, 113) * size.width,
                                y: size.height * (0.30 + 0.66 * random(i, 114)))
            let glint = pow(max(0, sin(t * 0.65 + Double(i) * 2.1)), 5)
            var c = context
            c.translateBy(x: point.x, y: point.y)
            sparkle(&c, (0.8 + random(i, 117)) * scale,
                    .color(Color.white.opacity(alpha(0.20 * glint))))
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
        // Three staggered paths keep shooting stars visible around the widget edges.
        for lane in 0..<3 {
            let period = 4.2 + Double(lane) * 0.9
            let clock = t + Double(lane) * 1.5
            let phase = clock.truncatingRemainder(dividingBy: period) / 1.8
            guard phase < 1 else { continue }
            let cycle = Int(clock / period)
            let seed = cycle * 3 + lane
            let baseY: CGFloat = lane == 2 ? 0.74 : 0.04 + 0.09 * CGFloat(lane)
            let start = CGPoint(x: size.width * (-0.08 + 0.30 * random(seed, 30)), y: size.height * baseY)
            let dx = size.width * (0.58 + 0.20 * random(seed, 31))
            let dy = size.height * (lane == 2 ? 0.17 : 0.23)
            let head = CGPoint(x: start.x + dx * phase, y: start.y + dy * phase)
            let tail = CGPoint(x: head.x - dx * 0.27, y: head.y - dy * 0.27)
            let fade = sin(phase * .pi)
            var trail = Path(); trail.move(to: tail); trail.addLine(to: head)
            var halo = context
            halo.addFilter(.blur(radius: 2.5 * scale))
            halo.stroke(trail, with: .color(Color(red: 0.62, green: 0.77, blue: 1).opacity(alpha(0.42 * fade))),
                        style: StrokeStyle(lineWidth: 5 * scale, lineCap: .round))
            context.stroke(trail, with: .linearGradient(Gradient(colors: [.clear, .white.opacity(alpha(0.95 * fade))]),
                startPoint: tail, endPoint: head), style: StrokeStyle(lineWidth: 1.7 * scale, lineCap: .round))
            context.fill(circle(head, 1.8 * scale), with: .color(.white.opacity(alpha(0.95 * fade))))
        }
    }

    // MARK: Lines and fields

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

    // MARK: Live effects

    /// Rainbow: a soft field of colour flowing across the panel, like light through
    /// silk. Thin rows each carry the whole spectrum, offset by a slow wave, then blur
    /// into one smooth surface; the colours travel quickly enough to notice (owner).
    private func rainbowFlow(_ context: inout GraphicsContext, _ size: CGSize) {
        var field = context
        field.addFilter(.blur(radius: 10 * scale))
        let row = max(3, 5 * scale)
        let spectrum = (0...6).map { Color(hue: Double($0) / 6, saturation: 0.85, brightness: 1) }
        var y: CGFloat = -row
        while y < size.height + row {
            // Each row's spectrum is pushed sideways by two waves, so the bands bend and flow.
            let wave = sin(Double(y) / 46 + t * 1.1) * 0.18 + sin(Double(y) / 19 - t * 0.7) * 0.06
            let shift = CGFloat((t * 0.22 + wave).truncatingRemainder(dividingBy: 1)) * size.width
            let span = size.width * 1.4
            for tile in -1...1 {
                let start = CGPoint(x: shift + CGFloat(tile) * span - span * 0.2, y: y)
                field.fill(Path(CGRect(x: start.x, y: y, width: span, height: row + 1)),
                           with: .linearGradient(Gradient(colors: spectrum.map { $0.opacity(alpha(0.42)) }),
                                                 startPoint: start, endPoint: CGPoint(x: start.x + span, y: y)))
            }
            y += row
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

    /// Snow in depth: far flakes small and slow, near ones large, soft and quicker,
    /// all carried by the same wind, settling into drifts.
    private func snowParticles(_ context: inout GraphicsContext, _ size: CGSize) {
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

/// Small copies of the theme photos for the theme cards, each made once in the
/// background (decoding a 1586-pixel HEIC per card on the main thread stalled
/// Settings → Appearance).
@MainActor
final class MotifThumbnails: ObservableObject {
    static let shared = MotifThumbnails()
    @Published private(set) var images: [String: CGImage] = [:]
    private var requested: Set<String> = []
    private let queue = DispatchQueue(label: "dev.opensource.MacSpaces.theme-thumbnails", qos: .utility)
    /// Wide enough for a card at 2x.
    nonisolated static let width = 360

    func image(_ asset: String) -> CGImage? {
        if let image = images[asset] { return image }
        if requested.insert(asset).inserted {
            queue.async { [weak self] in
                let image = autoreleasepool { Self.make(asset) }
                DispatchQueue.main.async { [weak self] in
                    if let image { self?.images[asset] = image }
                }
            }
        }
        return nil
    }

    nonisolated private static func make(_ asset: String) -> CGImage? {
        guard let full = Bundle.main.image(forResource: asset)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              full.width > 0 else { return nil }
        let height = max(1, Int((Double(width) * Double(full.height) / Double(full.width)).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// One retained, decoded scene, prepared before pointer interaction. No image decode in body.
@MainActor
final class MotifImages: ObservableObject {
    static let shared = MotifImages()
    @Published private(set) var image: CGImage?
    private var asset: String?
    private let queue = DispatchQueue(label: "dev.opensource.MacSpaces.theme-image", qos: .userInitiated)

    func image(for name: String) -> CGImage? { asset == name ? image : nil }

    func prepare(_ motif: ThemeMotif?) {
        let name = motif?.floralAsset ?? motif?.natureAsset
        guard name != asset else { return }
        asset = name
        image = nil
        guard let name else { return }
        queue.async { [weak self] in
            let decoded = Self.decode(name)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.asset == name else { return }
                self.image = decoded
            }
        }
    }

    nonisolated static func decode(_ asset: String) -> CGImage? {
        guard let full = Bundle.main.image(forResource: asset)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              full.width > 0, full.height > 0 else { return nil }
        let width = min(1800, full.width)
        let height = max(1, Int((Double(width) * Double(full.height) / Double(full.width)).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
