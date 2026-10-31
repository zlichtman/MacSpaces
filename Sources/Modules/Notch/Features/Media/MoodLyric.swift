import AppKit
import Combine
import NaturalLanguage
import QuartzCore
import SwiftUI
import os

// MARK: - Mood

/// Poster's type over abstract motion that suits the line (`MoodTreatment`), like a
/// lyric video: a slow field of the cover's colours at the back, the treatment's
/// motif (motes, rings, a bloom, rain, light, aurora, embers or fog) in the middle,
/// a few near sparks and a light film grain in front. Each word gets a small accent
/// as it's sung (the headline the biggest) and each line lands with a soft hit.
/// Colours come from the album cover blended with the theme's accent and ink.
/// Live motion runs in Core Animation, so the app does nothing per frame; previews,
/// Reduce Motion and captures draw the same scene as a still frame.
struct MoodLyric: View {
    let line: String
    let accent: Color
    let ink: Color
    let size: CGSize
    let animated: Bool
    /// The motion holds while the song is paused.
    var playing = true
    /// The line's sung span in song time, for its pace and word timing; untimed
    /// lyrics count as medium pace and get no word accents.
    var span: ClosedRange<TimeInterval>?
    /// The song's time as this line renders, against which the words are timed.
    var songTime: TimeInterval?
    let composition: PosterLyric.Composition
    var identity = 0
    @ObservedObject private var capture = MoodCapture.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var cover = MoodCoverPalette.shared

    var body: some View {
        let plan = self.plan()
        let palette = MoodPalette(accent: accent, ink: ink, cover: cover.colors)
        // Behind the headline: left for most compositions, right when flush right.
        let focus: CGFloat = composition == .flushRight ? 0.74 : 0.27
        let scene = MoodScene(treatment: plan.treatment, tempo: MoodTreatment.tempo(wordsPerSecond: plan.pace),
                              focus: focus, palette: palette, size: size)
        let beats = MoodScene.beats(treatment: plan.treatment, words: plan.words, delays: plan.delays, hero: plan.hero,
                                    hit: MoodTreatment.hitStrength(wordsPerSecond: plan.pace), focus: focus,
                                    palette: palette, size: size)
        let contrast: Color = palette.dark ? .black : .white
        ZStack {
            MoodBackdrop(scene: scene, beats: beats,
                         key: MoodScene.Key(treatment: plan.treatment, focus: Double(focus), width: Double(size.width),
                                            height: Double(size.height), palette: palette.key),
                         animated: animated && !theme.reduceMotion, playing: playing, identity: identity)
            // Contrast follows the glyphs, never the lyric frame. Leave the shadows
            // unclipped so even a headline near the edge cannot reveal a rectangle.
            PosterLyric(line: line, accent: accent, ink: ink, size: size, composition: composition, identity: identity)
                .shadow(color: contrast.opacity(0.55), radius: 9)
                .shadow(color: contrast.opacity(0.35), radius: 2)
        }
        .frame(width: size.width, height: size.height)
    }

    private struct Plan {
        var treatment: MoodTreatment
        var pace: Double?
        var words: [String]
        var delays: [TimeInterval]?
        var hero: Int
    }

    private func plan() -> Plan {
        let words = MoodTreatment.words(line)
        // Poster's headline, found among Mood's words (which drop punctuation-only tokens).
        let posterWords = line.split(separator: " ").map(String.init)
        let hero = PosterLyric.heroIndex(posterWords)
        let heroWord = posterWords.indices.contains(hero) ? posterWords[hero] : ""
        let heroIndex = words.firstIndex(of: heroWord) ?? max(0, words.count - 1)
        if let hold = capture.holds[line] {
            // Captures hold a pace instead of real timing: the line is sung from a beat after it shows.
            let span = hold.wordsPerSecond.map { 0.25...(0.25 + Double(max(1, words.count)) / $0 / MoodTreatment.sungShare) }
            return Plan(treatment: hold.treatment, pace: hold.wordsPerSecond, words: words,
                        delays: MoodTreatment.wordDelays(words: words, span: span, songTime: 0), hero: heroIndex)
        }
        let pace = MoodTreatment.wordsPerSecond(words: words.count, span: span)
        let treatment = MoodTreatment.choose(sentiment: MoodSentiment.score(line), wordsPerSecond: pace, wordCount: words.count)
        return Plan(treatment: treatment, pace: pace, words: words,
                    delays: MoodTreatment.wordDelays(words: words, span: span, songTime: songTime), hero: heroIndex)
    }
}

/// Only the two slow colour fields reach across the Music page. Motifs and word
/// accents stay near the lyric; the theme photograph remains the dominant layer.
struct MoodMusicAmbience: View {
    @ObservedObject var service: TeleprompterService
    let animated: Bool
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var cover = MoodCoverPalette.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if !service.currentText.isEmpty {
                let palette = MoodPalette(accent: theme.notch.accent, ink: theme.nookForeground, cover: cover.colors)
                let scene = MoodScene(treatment: .drift, tempo: 0.65, focus: 0.7,
                                      palette: palette, size: proxy.size, ambience: true)
                MoodBackdrop(scene: scene, beats: [],
                             key: MoodScene.Key(treatment: .drift, focus: 0.7, width: Double(proxy.size.width),
                                                height: Double(proxy.size.height), palette: palette.key),
                             animated: animated && !reduceMotion && !theme.reduceMotion,
                             playing: service.isPlaying, identity: 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// How a line feels (-1 sad … 1 warm), from Apple's on-device sentiment model,
/// re-centred by `MoodTreatment.calibrated`; cached per line text so a returning
/// chorus is scored once.
enum MoodSentiment {
    private static let cache = OSAllocatedUnfairLock(initialState: [String: Double]())

    static func score(_ line: String) -> Double {
        guard !line.isEmpty else { return 0 }
        if let known = cache.withLock({ $0[line] }) { return known }
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = line
        let (tag, _) = tagger.tag(at: line.startIndex, unit: .paragraph, scheme: .sentimentScore)
        // A line the model can't score ("Other") counts as neutral.
        let value = MoodTreatment.calibrated(raw: tag.flatMap { Double($0.rawValue) }, line: line)
        cache.withLock { scores in
            if scores.count > 2_000 { scores.removeAll() }
            scores[line] = value
        }
        return value
    }

    /// A song's lyrics loaded: score every line off the main thread, so a new line
    /// doesn't load the model or run it while the page draws.
    @MainActor
    static func prefetch(_ lines: [String]) {
        guard ThemeStore.shared.lyricStyle == .mood, !lines.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            for line in Set(lines) { _ = score(line) }
        }
    }
}

/// QA captures pin Mood's clock (seconds into the capture) and hold lines to a
/// chosen treatment and pace; the app never sets either.
@MainActor
final class MoodCapture: ObservableObject {
    static let shared = MoodCapture()

    struct Hold {
        var treatment: MoodTreatment
        var wordsPerSecond: Double?
    }

    /// nil runs live.
    @Published var pinnedTime: Double?
    @Published var holds: [String: Hold] = [:]
}

// MARK: Colour

/// Two colours from the album cover (the strongest hue and a distinct second one),
/// as sRGB components.
struct MoodCoverColors: Equatable, Sendable {
    struct RGB: Equatable, Sendable { var red, green, blue: Double }
    var primary: RGB
    var secondary: RGB

    /// The cover's palette, from the small blurred copy the Music page already makes
    /// (`ArtworkWashStore`): hue buckets weighted by saturation and brightness. A grey
    /// cover has no palette, and the theme's own colours carry Mood alone.
    static func extract(from image: CGImage) -> MoodCoverColors? {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        let bins = 24
        var weight = [Double](repeating: 0, count: bins)
        var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: bins)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255, g = Double(pixels[index + 1]) / 255, b = Double(pixels[index + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            guard high > 0.12 else { continue }
            let saturation = (high - low) / high
            guard saturation > 0.12 else { continue }
            var hue: Double
            if high == r { hue = (g - b) / (high - low) } else if high == g { hue = 2 + (b - r) / (high - low) } else { hue = 4 + (r - g) / (high - low) }
            hue = (hue / 6).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            let bin = min(bins - 1, Int(hue * Double(bins)))
            let w = saturation * high
            weight[bin] += w
            sums[bin] = (sums[bin].0 + r * w, sums[bin].1 + g * w, sums[bin].2 + b * w)
        }
        let total = weight.reduce(0, +)
        guard total > 4, let first = weight.indices.max(by: { weight[$0] < weight[$1] }) else { return nil }
        func color(_ bin: Int) -> RGB {
            RGB(red: sums[bin].0 / weight[bin], green: sums[bin].1 / weight[bin], blue: sums[bin].2 / weight[bin])
        }
        // A second hue at least 45° away with a real share of the cover; otherwise the first again.
        let apart = weight.indices.filter { bin in
            let distance = abs(bin - first)
            return min(distance, bins - distance) >= 3 && weight[bin] >= weight[first] * 0.12
        }
        let second = apart.max(by: { weight[$0] < weight[$1] }) ?? first
        return MoodCoverColors(primary: color(first), secondary: color(second))
    }
}

/// The current cover's palette, made off the main thread from the Music page's own
/// blurred copy of the cover and kept for the last few covers.
@MainActor
final class MoodCoverPalette: ObservableObject {
    static let shared = MoodCoverPalette()
    @Published private(set) var colors: MoodCoverColors?
    private var source: NSImage?
    private var recent: [(image: NSImage, colors: MoodCoverColors?)] = []
    private var cancellable: AnyCancellable?
    private let queue = DispatchQueue(label: "dev.opensource.MacSpaces.mood-palette", qos: .utility)

    private init() {
        cancellable = ArtworkWashStore.shared.$image.sink { [weak self] image in self?.prepare(image) }
    }

    private func prepare(_ image: NSImage?) {
        guard image !== source else { return }
        source = image
        guard let image else { colors = nil; return }
        if let known = recent.first(where: { $0.image === image }) { colors = known.colors; return }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { colors = nil; return }
        queue.async { [weak self, cg, image] in
            let found = MoodCoverColors.extract(from: cg)
            DispatchQueue.main.async { [weak self, image, found] in
                guard let self, self.source === image else { return }
                self.recent = [(image, found)] + self.recent.prefix(5)
                self.colors = found
            }
        }
    }
}

/// The colours one scene draws with: the cover's two (made vivid enough for the
/// surface and leaning a little toward the theme's accent), the accent itself and
/// the ink. Without a cover the accent stands in, or the ink for a white accent.
struct MoodPalette {
    let accent: Color
    let ink: Color
    let primary: Color
    let secondary: Color
    /// The theme's surface is dark (its ink is light).
    let dark: Bool
    /// The resolved colours, so the same palette always compares equal.
    let key: String

    init(accent: Color, ink: Color, cover: MoodCoverColors?) {
        let inkColor = NSColor(ink).usingColorSpace(.sRGB) ?? .white
        let accentColor = NSColor(accent).usingColorSpace(.sRGB) ?? .white
        let dark = inkColor.brightnessComponent > 0.5
        func tune(_ color: NSColor) -> NSColor {
            let hue = color.hueComponent, saturation = color.saturationComponent, brightness = color.brightnessComponent
            return dark
                ? NSColor(hue: hue, saturation: min(0.85, max(0.4, saturation * 1.15)), brightness: max(0.88, brightness), alpha: 1)
                : NSColor(hue: hue, saturation: min(0.9, max(0.45, saturation * 1.1)), brightness: min(0.7, max(0.45, brightness)), alpha: 1)
        }
        func rgb(_ value: MoodCoverColors.RGB) -> NSColor {
            NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: 1)
        }
        let first: NSColor, second: NSColor
        if let cover {
            first = tune(rgb(cover.primary)).blended(withFraction: 0.2, of: accentColor) ?? tune(rgb(cover.primary))
            second = tune(rgb(cover.secondary)).blended(withFraction: 0.12, of: accentColor) ?? tune(rgb(cover.secondary))
        } else if accentColor.saturationComponent > 0.18 {
            first = tune(accentColor)
            let shifted = (accentColor.hueComponent + 0.07).truncatingRemainder(dividingBy: 1)
            second = tune(NSColor(hue: shifted, saturation: accentColor.saturationComponent,
                                  brightness: accentColor.brightnessComponent, alpha: 1))
        } else {
            first = accentColor
            second = inkColor.blended(withFraction: 0.35, of: dark ? .gray : .black) ?? inkColor
        }
        self.accent = accent
        self.ink = ink
        self.primary = Color(nsColor: first)
        self.secondary = Color(nsColor: second)
        self.dark = dark
        self.key = [first, second, accentColor, inkColor].map { color in
            let c = color.usingColorSpace(.sRGB) ?? color
            return String(format: "%.3f,%.3f,%.3f", c.redComponent, c.greenComponent, c.blueComponent)
        }.joined(separator: " ")
    }
}

// MARK: Backdrop

/// The motion behind the poster: the treatment's scene keeps going across lines
/// while it holds and crossfades when it changes; each line adds its own beats.
private struct MoodBackdrop: View {
    let scene: MoodScene
    let beats: [MoodElement]
    let key: MoodScene.Key
    let animated: Bool
    let playing: Bool
    let identity: Int
    @ObservedObject private var capture = MoodCapture.shared
    /// When the current line arrived on the pinned capture clock.
    @State private var lineStart: Double = 0

    var body: some View {
        Group {
            if animated, capture.pinnedTime == nil {
                MoodLayerScene(scene: scene, key: key, beats: beats, line: identity, playing: playing)
            } else {
                let pinned = capture.pinnedTime
                let time = pinned ?? scene.stillTime
                let age = pinned.map { $0 - lineStart } ?? scene.stillTime
                ZStack {
                    MoodFrame(size: scene.size, elements: scene.elements, grain: scene.grain, time: time, lineAge: age)
                        .id(key)
                        .transition(.opacity)
                    // Still frames (Reduce Motion, previews) keep only the calm scene.
                    if pinned != nil {
                        MoodFrame(size: scene.size, elements: beats, grain: nil, time: time, lineAge: age)
                            .id(identity)
                            .transition(.opacity)
                    }
                }
                .mask(MoodFrame.falloff(size: scene.size))
                .animation(animated || pinned != nil ? .easeInOut(duration: MoodScene.crossfade) : nil, value: key)
            }
        }
        .frame(width: scene.size.width, height: scene.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { lineStart = capture.pinnedTime ?? 0 }
        .onChange(of: identity) { _ in lineStart = capture.pinnedTime ?? 0 }
    }
}

// MARK: Scene

/// One treatment as three depths of soft elements, each a simple loop described
/// once and played two ways: by Core Animation live, and by SwiftUI at a given
/// moment for still frames and captures. `beats` adds a line's one-pass accents.
struct MoodScene {
    static let crossfade = 0.9

    struct Key: Hashable {
        var treatment: MoodTreatment
        var focus: Double
        var width: Double
        var height: Double
        var palette: String
    }

    /// Film grain over the scene: light specks on dark themes, dark on light.
    struct Grain {
        var light: Bool
        var opacity: Double
    }

    let size: CGSize
    private(set) var elements: [MoodElement] = []
    private(set) var grain: Grain?
    /// The moment a still frame shows, chosen so each treatment reads at a glance.
    private(set) var stillTime: Double = 7.3

    init(treatment: MoodTreatment, tempo: Double, focus: CGFloat, palette: MoodPalette, size: CGSize,
         ambience: Bool = false) {
        self.size = size
        let w = size.width, h = max(1, size.height)
        // Sizes follow the lyric area: the Music page is about 125 pt tall, Settings previews 76.
        let s = max(0.6, h / 110)
        let center = CGPoint(x: w * focus, y: h * 0.5)
        let side: CGFloat = focus < 0.5 ? 1 : -1
        let stage = CGPoint(x: w * (1 - focus), y: h * 0.52)
        let k = max(0.5, tempo)
        let one = palette.primary, two = palette.secondary, accent = palette.accent, ink = palette.ink
        let strength = palette.dark ? 1.0 : 0.8
        var list: [MoodElement] = []
        func add(_ shape: MoodElement.Shape, _ color: Color, at point: CGPoint, _ opacities: [Double],
                 times: [Double]? = nil, over duration: Double, _ configure: (inout MoodElement) -> Void = { _ in }) {
            var element = MoodElement(shape: shape, color: color, from: point, opacities: opacities.map { $0 * strength },
                                      keyTimes: times ?? MoodElement.even(opacities.count), duration: duration)
            configure(&element)
            list.append(element)
        }
        let unit = Self.unit

        // Back: a slow field of the cover's two colours, wandering and breathing.
        let field: Double = (ambience ? 0.28 : 0.7)
            * ([.bloom, .embers].contains(treatment) ? 1.15 : [.rain, .haze].contains(treatment) ? 0.85 : 1)
        add(.oval(width: w * 1.05, height: h * 1.8), one, at: CGPoint(x: stage.x, y: h * 0.12),
            [0.32 * field, 0.5 * field], over: 17 / k) {
            $0.to = CGPoint(x: stage.x - side * w * 0.12, y: h * 0.38); $0.scaleFrom = 0.9; $0.scaleTo = 1.12
            $0.autoreverses = true; $0.timing = .easeInOut
        }
        add(.oval(width: w * 0.86, height: h * 1.5), two, at: CGPoint(x: center.x, y: h * 1.04),
            [0.26 * field, 0.4 * field], over: 23 / k) {
            $0.to = CGPoint(x: center.x + side * w * 0.18, y: h * 0.8); $0.scaleFrom = 1.08; $0.scaleTo = 0.9
            $0.autoreverses = true; $0.timing = .easeInOut; $0.phase = 0.4
        }

        if ambience {
            elements = list
            return
        }

        // Middle: the treatment's motif.
        switch treatment {
        case .drift:
            // A quiet caustic at the edge of the type; suspended, lens-like bokeh
            // has a soft envelope and a tiny hot centre rather than a fuzzy dot.
            add(.ribbon(width: w * 1.15, height: h * 0.8, bend: 0.9, lineWidth: 1.1 * s), two,
                at: CGPoint(x: w * 0.53, y: h * 0.7), [0.16, 0.34], over: 16 / k) {
                $0.to = CGPoint(x: w * 0.46, y: h * 0.57); $0.angle = -8
                $0.autoreverses = true; $0.timing = .easeInOut
            }
            add(.glow(radius: h * 0.75), one, at: center, [0.16, 0.26], over: 9 / k) {
                $0.autoreverses = true; $0.timing = .easeInOut; $0.scaleFrom = 0.92; $0.scaleTo = 1.06
            }
            for i in 0..<12 {
                let x = w * (0.04 + 0.92 * unit(i, 1))
                let near = i % 3 == 0
                add(near ? .glow(radius: (10 + 5 * unit(i, 5)) * s) : .spark(radius: (3 + 2 * unit(i, 5)) * s), [one, two, accent][i % 3],
                    at: CGPoint(x: x, y: h * 1.08), [0, near ? 0.6 : 0.42, near ? 0.6 : 0.42, 0], times: [0, 0.22, 0.72, 1],
                    over: (near ? 9 : 14) / k * (0.85 + 0.3 * unit(i, 3))) {
                    $0.to = CGPoint(x: x + w * (unit(i, 2) - 0.5) * 0.14, y: -h * 0.08)
                    $0.phase = (Double(i) / 12 + unit(i, 4) * 0.08).truncatingRemainder(dividingBy: 1)
                    $0.sway = 9 * s; $0.swayPeriod = 5 + 3 * unit(i, 6)
                }
            }
            stillTime = 7.3
        case .pulse:
            // Offset elliptical orbits, lit along only part of the rim. A slower
            // expansion gives the attack room to settle instead of flashing.
            let life = 3.8 / k
            let orbit = CGPoint(x: center.x + side * w * 0.16, y: h * 0.55)
            add(.glow(radius: h * 0.5), one, at: center, [0.2, 0.38], over: life / 8) {
                $0.autoreverses = true; $0.timing = .easeInOut; $0.scaleFrom = 0.9; $0.scaleTo = 1.08
            }
            for i in 0..<4 {
                add(.arc(width: h * 2.8, height: h * 1.9, lineWidth: (i % 2 == 0 ? 1.2 : 0.65) * s,
                         turn: Double(i) * 61), [accent, one, two, one][i], at: orbit,
                    [0, 0.7, 0.32, 0], times: [0, 0.12, 0.58, 1], over: life) {
                    $0.scaleFrom = 0.18; $0.scaleTo = 1.1; $0.phase = Double(i) / 4; $0.timing = .easeOut
                    $0.angle = -18
                }
            }
            add(.glow(radius: h * 0.9), two, at: center, [0, 0.2, 0], times: [0, 0.2, 1], over: life / 2) {
                $0.scaleFrom = 0.4; $0.scaleTo = 1.2; $0.timing = .easeOut
            }
            stillTime = life * 0.4
        case .bloom:
            let breath = 5.5 / k
            // Translucent petals of light fan out beside the headline. Each holds
            // its own phase, opening slowly around an off-centre luminous heart.
            for i in 0..<5 {
                let angle = Double(i) * 34 - 68
                let radians = angle * .pi / 180
                let point = CGPoint(x: stage.x + CGFloat(cos(radians)) * h * 0.22 * side,
                                    y: stage.y + CGFloat(sin(radians)) * h * 0.3)
                add(.oval(width: h * 1.5, height: h * 0.44), i % 2 == 0 ? one : two, at: point,
                    [0.2, 0.46], over: (6.5 + Double(i) * 0.4) / k) {
                    $0.angle = angle; $0.scaleFrom = 0.66; $0.scaleTo = 1.15
                    $0.autoreverses = true; $0.timing = .easeInOut; $0.phase = Double(i) * 0.12
                }
            }
            add(.arc(width: h * 1.5, height: h * 1.15, lineWidth: 0.65 * s, turn: 32), accent,
                at: stage, [0.12, 0.38], over: breath) {
                $0.scaleFrom = 0.8; $0.scaleTo = 1.18; $0.angle = -22
                $0.autoreverses = true; $0.timing = .easeInOut
            }
            add(.glow(radius: h * 1.05), one, at: center, [0.3, 0.48], over: breath) {
                $0.scaleFrom = 0.82; $0.scaleTo = 1.1; $0.autoreverses = true; $0.timing = .easeInOut
            }
            add(.glow(radius: h * 0.62), two, at: CGPoint(x: center.x + side * w * 0.3, y: h * 0.4), [0.18, 0.32], over: 8.3 / k) {
                $0.to = CGPoint(x: center.x + side * w * 0.36, y: h * 0.6); $0.autoreverses = true; $0.timing = .easeInOut
            }
            add(.glow(radius: h * 0.34), accent, at: center, [0.12, 0.24], over: breath) {
                $0.scaleFrom = 1.08; $0.scaleTo = 0.88; $0.phase = 0.5; $0.autoreverses = true; $0.timing = .easeInOut
            }
            for i in 0..<7 {
                let x = w * (0.08 + 0.84 * unit(i, 11))
                add(.spark(radius: (2.5 + 2 * unit(i, 12)) * s), i % 2 == 0 ? one : accent, at: CGPoint(x: x, y: h * 1.05),
                    [0, 0.5, 0.5, 0], times: [0, 0.25, 0.7, 1], over: 12 / k) {
                    $0.to = CGPoint(x: x + w * 0.05, y: -h * 0.05); $0.phase = Double(i) / 7
                    $0.sway = 7 * s; $0.swayPeriod = 6
                }
            }
            stillTime = breath
        case .rain:
            // Two depths: far streaks thin and slow, near ones longer, brighter and quicker.
            let slant = 0.15 / 1.5
            add(.oval(width: w * 1.2, height: h * 0.6), two, at: CGPoint(x: w * 0.5, y: h * 0.95), [0.16, 0.26], over: 7 / k) {
                $0.autoreverses = true; $0.timing = .easeInOut
            }
            // A reflected horizon, with sparse ripples rather than a busy floor.
            add(.ribbon(width: w * 1.15, height: h * 0.18, bend: 0.5, lineWidth: 0.7 * s), two,
                at: CGPoint(x: w * 0.54, y: h * 0.86), [0.18, 0.3], over: 9 / k) {
                $0.autoreverses = true; $0.timing = .easeInOut; $0.scaleFrom = 0.92; $0.scaleTo = 1.08
            }
            for i in 0..<3 {
                add(.ring(width: (32 + 18 * unit(i, 14)) * s, height: 8 * s, lineWidth: 0.6 * s), two,
                    at: CGPoint(x: w * (0.18 + 0.3 * CGFloat(i)), y: h * (0.78 + 0.08 * unit(i, 15))),
                    [0, 0.38, 0], times: [0, 0.16, 1], over: 3.4 / k) {
                    $0.phase = Double(i) / 3; $0.scaleFrom = 0.25; $0.scaleTo = 1.5; $0.timing = .easeOut
                }
            }
            for i in 0..<26 {
                let near = i % 3 == 0
                let x = w * (0.02 + 0.96 * unit(i, 1)) + h * 0.075
                add(.streak(width: max(0.5, (near ? 0.95 : 0.55) * s), length: (near ? 23 + 12 * unit(i, 2) : 9 + 7 * unit(i, 2)) * s),
                    near ? (i % 2 == 0 ? ink : accent) : (i % 2 == 0 ? two : ink),
                    at: CGPoint(x: x, y: -h * 0.3), [0, near ? 0.55 : 0.3, near ? 0.55 : 0.3, 0], times: [0, 0.15, 0.85, 1],
                    over: (near ? 1.5 + 0.5 * unit(i, 3) : 3 + 1.2 * unit(i, 3)) / k) {
                    $0.to = CGPoint(x: x - h * 0.16, y: h * 1.3); $0.angle = atan(slant) * 180 / .pi; $0.phase = unit(i, 4)
                }
            }
            stillTime = 1.3
        case .sweep:
            // The bands pass with each line (its beats); between them, a glow where they crossed.
            add(.glow(radius: h * 0.95), one, at: center, [0.2, 0.32], over: 7 / k) {
                $0.autoreverses = true; $0.timing = .easeInOut; $0.scaleFrom = 0.94; $0.scaleTo = 1.06
            }
            add(.oval(width: w * 0.9, height: h * 0.18), accent, at: CGPoint(x: center.x, y: h * 0.62),
                [0.1, 0.22], over: 5 / k) {
                $0.angle = -6; $0.autoreverses = true; $0.timing = .easeInOut
            }
            for i in 0..<3 {
                add(.ribbon(width: w * 1.45, height: h * (0.45 + Double(i) * 0.12), bend: 0.65,
                            lineWidth: (i == 1 ? 1.3 : 0.55) * s), i == 1 ? accent : two,
                    at: CGPoint(x: w * 0.5, y: h * (0.33 + Double(i) * 0.17)), [0.16, 0.34], over: (8 + Double(i) * 2) / k) {
                    $0.to = CGPoint(x: w * 0.6, y: h * (0.26 + Double(i) * 0.17))
                    $0.angle = -12; $0.autoreverses = true; $0.timing = .easeInOut; $0.phase = Double(i) * 0.2
                }
            }
            stillTime = 10
        case .aurora:
            // Ribbons of colour flowing sideways at different speeds, each with a brighter seam.
            let ribbons: [(y: CGFloat, angle: Double, color: Color, period: Double, low: Double, high: Double)] = [
                (0.3, -9, one, 13, 0.24, 0.44), (0.54, 7, accent, 17, 0.12, 0.28), (0.76, -4, two, 11, 0.22, 0.4),
            ]
            for (index, ribbon) in ribbons.enumerated() {
                let from = CGPoint(x: w * (index % 2 == 0 ? 0.32 : 0.68), y: h * ribbon.y)
                let to = CGPoint(x: w * (index % 2 == 0 ? 0.66 : 0.34), y: h * (ribbon.y + 0.06))
                add(.ribbon(width: w * 1.45, height: h * 0.9, bend: 1.2 - CGFloat(index) * 0.35, lineWidth: (9 - CGFloat(index) * 2) * s),
                    ribbon.color, at: from, [ribbon.low * 0.8, ribbon.high], over: ribbon.period / k) {
                    $0.to = to; $0.angle = ribbon.angle; $0.scaleFrom = 0.9; $0.scaleTo = 1.12
                    $0.autoreverses = true; $0.timing = .easeInOut; $0.phase = Double(index) * 0.3
                }
                add(.ribbon(width: w * 1.45, height: h * 0.9, bend: 1.2 - CGFloat(index) * 0.35, lineWidth: 0.7 * s),
                    index == 1 ? ink : ribbon.color, at: from, [ribbon.low * 1.2, ribbon.high * 1.3],
                    over: ribbon.period / k) {
                    $0.to = to; $0.angle = ribbon.angle; $0.scaleFrom = 0.9; $0.scaleTo = 1.12
                    $0.autoreverses = true; $0.timing = .easeInOut
                    $0.phase = Double(index) * 0.3
                }
            }
            stillTime = 4
        case .embers:
            // Sparks rising quickly from a warm glow below, shrinking as they cool.
            add(.oval(width: w * 1.3, height: h * 0.8), one, at: CGPoint(x: w * 0.5, y: h * 1.02), [0.26, 0.42], over: 3 / k) {
                $0.autoreverses = true; $0.timing = .easeInOut; $0.scaleFrom = 0.94; $0.scaleTo = 1.06
            }
            add(.ribbon(width: w * 1.2, height: h * 0.7, bend: 1.1, lineWidth: 2 * s), two,
                at: CGPoint(x: stage.x, y: h * 0.94), [0.14, 0.32], over: 4.8 / k) {
                $0.to = CGPoint(x: stage.x - side * w * 0.12, y: h * 0.78); $0.angle = -14
                $0.autoreverses = true; $0.timing = .easeInOut
            }
            for i in 0..<18 {
                let x = w * (0.04 + 0.92 * unit(i, 21))
                add(i % 4 == 0 ? .oval(width: 3 * s, height: 14 * s) : .spark(radius: (2 + 3 * unit(i, 22)) * s),
                    [one, accent, two][i % 3], at: CGPoint(x: x, y: h * 1.1),
                    [0, 0.9, 0.65, 0], times: [0, 0.12, 0.6, 1], over: (2.2 + 1.4 * unit(i, 23)) / k) {
                    $0.to = CGPoint(x: x + w * (unit(i, 24) - 0.5) * 0.2, y: -h * 0.15)
                    $0.scaleFrom = 1; $0.scaleTo = 0.45; $0.phase = unit(i, 25)
                    $0.sway = 8 * s; $0.swayPeriod = 1.5 + unit(i, 26)
                    $0.angle = -12 + 24 * unit(i, 27)
                }
            }
            stillTime = 2.1
        case .haze:
            // A sliver of backlight gives the fog a horizon and depth; almost
            // monochrome ink stays faint so the cover's own colours still lead.
            add(.oval(width: w * 0.85, height: h * 0.11), ink,
                at: CGPoint(x: stage.x, y: h * 0.3), [0.1, 0.2], over: 18 / k) {
                $0.angle = -7; $0.autoreverses = true; $0.timing = .easeInOut
                $0.to = CGPoint(x: stage.x - side * w * 0.1, y: h * 0.37)
            }
            // Banks of fog crossing slowly at different heights and speeds.
            for i in 0..<5 {
                let y = h * (0.2 + 0.15 * CGFloat(i))
                add(.oval(width: w * (0.8 + 0.3 * unit(i, 31)), height: h * (0.45 + 0.25 * unit(i, 32))),
                    [two, ink, one, two, ink][i], at: CGPoint(x: -w * 0.35, y: y),
                    [0, i % 3 == 1 ? 0.2 : 0.34, i % 3 == 1 ? 0.2 : 0.34, 0], times: [0, 0.2, 0.8, 1],
                    over: (24 + 10 * unit(i, 33)) / k) {
                    $0.to = CGPoint(x: w * 1.35, y: y + h * 0.08); $0.phase = Double(i) / 5 + 0.1
                }
            }
            add(.glow(radius: h * 0.8), one, at: center, [0.14, 0.24], over: 11 / k) {
                $0.autoreverses = true; $0.timing = .easeInOut
            }
            stillTime = 9
        }

        // Front: a few pinpricks at a different depth, with a long, quiet envelope.
        if treatment != .rain && treatment != .embers {
            for i in 0..<3 {
                let x = w * (0.1 + 0.8 * unit(i, 41))
                add(.spark(radius: (2.5 + 2 * unit(i, 42)) * s), [accent, ink, one][i % 3], at: CGPoint(x: x, y: h * 1.15),
                    [0, 0.65, 0.38, 0], times: [0, 0.22, 0.65, 1], over: (8 + 3 * unit(i, 43)) / k) {
                    $0.to = CGPoint(x: x + w * 0.16, y: -h * 0.15); $0.phase = Double(i) / 3
                    $0.sway = 6 * s; $0.swayPeriod = 3 + unit(i, 44)
                }
            }
        }
        elements = list
        grain = Grain(light: palette.dark, opacity: palette.dark ? 0.045 : 0.035)
    }

    /// One line's beats: a soft hit as it starts (harder for faster lines) and a small
    /// accent for each word as it's sung, the headline the biggest. Accents step across
    /// the lyric area in reading order; the headline's sits behind it.
    static func beats(treatment: MoodTreatment, words: [String], delays: [TimeInterval]?, hero: Int, hit: Double,
                      focus: CGFloat, palette: MoodPalette, size: CGSize) -> [MoodElement] {
        let w = size.width, h = max(1, size.height)
        let s = max(0.6, h / 110)
        let center = CGPoint(x: w * focus, y: h * 0.5)
        let one = palette.primary, accent = palette.accent, ink = palette.ink
        let strength = palette.dark ? 1.0 : 0.8
        let start = max(0, delays?.first ?? 0.05)
        var list: [MoodElement] = []
        func add(_ shape: MoodElement.Shape, _ color: Color, at point: CGPoint, _ opacities: [Double], times: [Double],
                 over duration: Double, after delay: Double, _ configure: (inout MoodElement) -> Void = { _ in }) {
            var element = MoodElement(shape: shape, color: color, from: point, opacities: opacities.map { $0 * strength },
                                      keyTimes: times, duration: duration)
            element.once = true
            element.delay = delay
            configure(&element)
            list.append(element)
        }

        // The hit.
        add(.glow(radius: h * (0.85 + 0.3 * hit)), one, at: center, [0, 0.5 * hit, 0], times: [0, 0.15, 1], over: 1.2, after: start) {
            $0.scaleFrom = 0.7; $0.scaleTo = 1.15; $0.timing = .settle
        }
        if treatment == .pulse || treatment == .embers {
            add(.ring(width: h * 1.7, height: h * 1.7, lineWidth: 2 * s), accent, at: center, [0, 0.7 * hit, 0], times: [0, 0.1, 1],
                over: 1, after: start) { $0.scaleFrom = 0.2; $0.scaleTo = 1; $0.timing = .settle }
        }
        if treatment == .sweep {
            add(.band(width: max(44 * s, w * 0.26), height: h * 1.8), one, at: CGPoint(x: -w * 0.25, y: h * 0.5),
                [0, 0.45, 0.45, 0], times: [0, 0.2, 0.75, 1], over: 1.4, after: start) {
                $0.to = CGPoint(x: w * 1.25, y: h * 0.5); $0.angle = 14; $0.timing = .easeInOut
            }
            add(.band(width: max(22 * s, w * 0.12), height: h * 1.8), accent, at: CGPoint(x: -w * 0.25, y: h * 0.5),
                [0, 0.35, 0.35, 0], times: [0, 0.2, 0.75, 1], over: 1.4, after: start + 0.18) {
                $0.to = CGPoint(x: w * 1.25, y: h * 0.5); $0.angle = 14; $0.timing = .easeInOut
            }
        }

        // The words.
        guard let delays, !words.isEmpty else { return list }
        let count = min(words.count, delays.count, 16)
        for index in 0..<count where delays[index] > -0.05 {
            let isHero = index == hero
            let scale = isHero ? 2.1 : 1.0
            let power = isHero ? 1.0 : 0.72
            let point = isHero ? center
                : CGPoint(x: w * (0.06 + 0.88 * (CGFloat(index) + 0.5) / CGFloat(count)),
                          y: h * ((index % 2 == 0 ? 0.18 : 0.78) + 0.08 * unit(index, 51)))
            let delay = delays[index]
            if isHero {
                // A wider bloom followed by a fine lower rim: the headline gets
                // a deliberate two-stage arrival without flashing the whole page.
                add(.oval(width: h * 1.8, height: h * 0.85), palette.secondary, at: center,
                    [0, 0.58, 0.18, 0], times: [0, 0.08, 0.36, 1], over: 1.35, after: delay) {
                    $0.scaleFrom = 0.5; $0.scaleTo = 1.2; $0.timing = .settle
                }
                add(.ribbon(width: w * 0.72, height: h * 0.46, bend: 0.7, lineWidth: 1.1 * s), accent,
                    at: CGPoint(x: center.x, y: h * 0.73), [0, 0.76, 0.28, 0], times: [0, 0.09, 0.4, 1],
                    over: 1.1, after: delay + 0.04) {
                    $0.scaleFrom = 0.35; $0.scaleTo = 1.1; $0.timing = .settle; $0.angle = -5
                }
            }
            switch treatment {
            case .pulse:
                add(.arc(width: 48 * s * scale, height: 35 * s * scale, lineWidth: 1.1 * s, turn: Double(index) * 47),
                    index % 2 == 0 ? accent : one, at: point,
                    [0, 0.8 * power, 0], times: [0, 0.12, 1], over: 0.9, after: delay) {
                    $0.scaleFrom = 0.15; $0.scaleTo = 1; $0.timing = .settle
                }
            case .rain:
                // A splash low in the frame.
                let splash = CGPoint(x: point.x, y: h * (0.74 + 0.12 * unit(index, 52)))
                add(.ring(width: 34 * s * scale, height: 11 * s * scale, lineWidth: 1.2 * s), index % 2 == 0 ? ink : accent, at: splash,
                    [0, 0.7 * power, 0], times: [0, 0.12, 1], over: 1, after: delay) {
                    $0.scaleFrom = 0.2; $0.scaleTo = 1; $0.timing = .settle
                }
            case .bloom, .embers:
                add(.glow(radius: 23 * s * scale), index % 2 == 0 ? one : accent, at: point,
                    [0, 0.74 * power, 0], times: [0, 0.12, 1], over: 1.05, after: delay) {
                    $0.scaleFrom = 0.5; $0.scaleTo = 1.25; $0.timing = .settle
                }
                if treatment == .embers {
                    for j in 0..<2 {
                        add(.spark(radius: 3 * s), accent, at: point, [0, 0.9 * power, 0], times: [0, 0.1, 1], over: 1, after: delay) {
                            $0.to = CGPoint(x: point.x + CGFloat(j * 2 - 1) * 8 * s, y: point.y - 26 * s * scale)
                            $0.timing = .settle; $0.scaleTo = 0.5
                        }
                    }
                }
            case .sweep:
                // A gust: a short streak of light blowing past.
                add(.ribbon(width: 64 * s * scale, height: 18 * s, bend: 0.6, lineWidth: 1 * s), ink,
                    at: point, [0, 0.8 * power, 0], times: [0, 0.1, 1],
                    over: 0.7, after: delay) {
                    $0.to = CGPoint(x: point.x + 36 * s * scale, y: point.y); $0.timing = .settle
                }
            case .aurora:
                add(.ribbon(width: 82 * s * scale, height: 36 * s, bend: 1.2, lineWidth: 2.2 * s),
                    index % 2 == 0 ? one : palette.secondary, at: point, [0, 0.8 * power, 0], times: [0, 0.12, 1],
                    over: 1.25, after: delay) {
                    $0.to = CGPoint(x: point.x + 22 * s, y: point.y - 8 * s)
                    $0.scaleFrom = 0.5; $0.scaleTo = 1.2; $0.timing = .settle; $0.angle = -8
                }
            case .haze:
                add(.oval(width: 100 * s * scale, height: 28 * s), palette.secondary,
                    at: CGPoint(x: point.x, y: h * 0.76), [0, 0.46 * power, 0], times: [0, 0.22, 1],
                    over: 1.8, after: delay) {
                    $0.to = CGPoint(x: point.x + 28 * s, y: h * 0.68)
                    $0.scaleFrom = 0.7; $0.scaleTo = 1.3; $0.timing = .settle
                }
            case .drift:
                // A burst of motes.
                let motes = isHero ? 6 : 3
                for j in 0..<motes {
                    let angle = 2 * .pi * (Double(j) / Double(motes) + unit(index, 53))
                    let reach = (18 + 12 * unit(index * 7 + j, 54)) * s * (isHero ? 1.5 : 1)
                    add(.spark(radius: 3.5 * s), j % 2 == 0 ? accent : one, at: point, [0, 0.85 * power, 0], times: [0, 0.1, 1],
                        over: 1.1, after: delay) {
                        $0.to = CGPoint(x: point.x + CGFloat(cos(angle)) * reach, y: point.y + CGFloat(sin(angle)) * reach)
                        $0.timing = .settle; $0.scaleTo = 0.6
                    }
                }
            }
        }
        return list
    }

    /// A colour's sRGB components, so the same theme colour always compares equal.
    static func colorKey(_ color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "\(color)" }
        return String(format: "%.3f %.3f %.3f %.3f", rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
    }

    /// A repeatable 0..<1 value per element, so the same line always looks the same.
    static func unit(_ index: Int, _ salt: Int) -> Double {
        let x = sin(Double(index) * 12.9898 + Double(salt) * 78.233) * 43_758.5453
        return x - x.rounded(.down)
    }

    /// A broad oval falloff, with no straight-sided plateau or visible frame edge.
    /// Shared by the local motifs and the much fainter page-wide light.
    static let falloffStops: [(Double, Double)] = [(0, 1), (0.25, 0.86), (0.5, 0.45), (0.75, 0.1), (1, 0)]

    /// Film grain: specks of random strength, the same every time. Light or dark.
    static func grainImage(light: Bool) -> CGImage? { light ? lightGrain : darkGrain }
    private static let lightGrain = makeGrain(light: true)
    private static let darkGrain = makeGrain(light: false)
    private static func makeGrain(light: Bool) -> CGImage? {
        let width = 512, height = 256
        var state: UInt32 = 0x9E37_79B9
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            state = state &* 1_664_525 &+ 1_013_904_223
            let value = Double(state >> 24) / 255
            // Mostly faint, a few strong specks; premultiplied, so the colour scales with alpha.
            let alpha = UInt8(min(255, pow(value, 3) * 255))
            let tone = light ? alpha : 0
            pixels[index] = tone; pixels[index + 1] = tone; pixels[index + 2] = tone; pixels[index + 3] = alpha
        }
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }
    /// The grain jumps between these offsets about twelve times a second.
    static let grainSteps: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: -7, y: 4), CGPoint(x: 5, y: -6),
                                        CGPoint(x: -3, y: -9), CGPoint(x: 8, y: 7)]
    static let grainStep = 1.0 / 12
}

struct MoodElement {
    enum Shape {
        /// A soft radial glow.
        case glow(radius: CGFloat)
        /// A soft elliptical glow: fog banks, ribbons, haze.
        case oval(width: CGFloat, height: CGFloat)
        /// A bright point with a halo: motes, embers, near sparks.
        case spark(radius: CGFloat)
        case ring(width: CGFloat, height: CGFloat, lineWidth: CGFloat)
        /// An open orbital arc, and an S-shaped filament. Their shared paths are
        /// lit with a feathered rim rather than a flat, uniformly bright outline.
        case arc(width: CGFloat, height: CGFloat, lineWidth: CGFloat, turn: Double)
        case ribbon(width: CGFloat, height: CGFloat, bend: CGFloat, lineWidth: CGFloat)
        /// A fine streak, clear at the top.
        case streak(width: CGFloat, length: CGFloat)
        /// A tall band of light, clear at both sides.
        case band(width: CGFloat, height: CGFloat)

        var size: CGSize {
            switch self {
            case .glow(let radius), .spark(let radius): return CGSize(width: radius * 2, height: radius * 2)
            case .oval(let width, let height), .ring(let width, let height, _), .band(let width, let height),
                 .arc(let width, let height, _, _), .ribbon(let width, let height, _, _): return CGSize(width: width, height: height)
            case .streak(let width, let length): return CGSize(width: width, height: length)
            }
        }

        /// Colour stops (location, opacity) for the radial shapes.
        var radialStops: [(Double, Double)] {
            switch self {
            case .spark: return [(0, 1), (0.055, 1), (0.14, 0.55), (0.36, 0.12), (1, 0)]
            default: return [(0, 0.94), (0.18, 0.8), (0.42, 0.36), (0.72, 0.08), (1, 0)]
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .ring(_, _, let width), .arc(_, _, let width, _), .ribbon(_, _, _, let width): return width
            default: return 0
            }
        }

        /// Identical geometry in SwiftUI and Core Animation; no live path morphing.
        var lightPath: CGPath? {
            let w = size.width, h = size.height
            let inset = min(min(w, h) * 0.12, lineWidth * 3)
            switch self {
            case .ring:
                return CGPath(ellipseIn: CGRect(x: inset, y: inset, width: w - 2 * inset, height: h - 2 * inset), transform: nil)
            case .arc(_, _, _, let turn):
                let path = CGMutablePath()
                var transform = CGAffineTransform(a: w / 2 - inset, b: 0, c: 0, d: h / 2 - inset, tx: w / 2, ty: h / 2)
                path.addArc(center: .zero, radius: 1, startAngle: turn * .pi / 180,
                            endAngle: (turn + 238) * .pi / 180, clockwise: false)
                return path.copy(using: &transform)
            case .ribbon(_, _, let bend, _):
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: h * 0.72))
                path.addCurve(to: CGPoint(x: w, y: h * 0.28),
                              control1: CGPoint(x: w * 0.32, y: h * (0.5 - bend)),
                              control2: CGPoint(x: w * 0.68, y: h * (0.5 + bend)))
                return path
            default: return nil
            }
        }

        static let lightStops: [(Double, Double)] = [(0, 0), (0.18, 0.35), (0.48, 1), (0.76, 0.65), (1, 0)]
        /// Broad faint falloff, then a fine illuminated core; no animated blur.
        static let lightStrokes: [(width: CGFloat, opacity: Double)] = [(8, 0.045), (3, 0.15), (1, 0.9)]
    }

    enum Timing {
        case linear, easeInOut, easeOut, settle

        var function: CAMediaTimingFunction {
            switch self {
            case .linear: return CAMediaTimingFunction(name: .linear)
            case .easeInOut: return CAMediaTimingFunction(name: .easeInEaseOut)
            case .easeOut: return CAMediaTimingFunction(name: .easeOut)
            case .settle: return CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            }
        }

        /// The same curve as `function`, for frames drawn in SwiftUI.
        func value(_ x: Double) -> Double {
            switch self {
            case .linear: return x
            case .easeInOut: return Self.bezier(0.42, 0, 0.58, 1, x)
            case .easeOut: return Self.bezier(0, 0, 0.58, 1, x)
            case .settle: return Self.bezier(0.16, 1, 0.3, 1, x)
            }
        }

        private static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
            func sample(_ a: Double, _ b: Double, _ t: Double) -> Double {
                3 * a * (1 - t) * (1 - t) * t + 3 * b * (1 - t) * t * t + t * t * t
            }
            var low = 0.0, high = 1.0, t = x
            for _ in 0..<24 {
                t = (low + high) / 2
                if sample(x1, x2, t) < x { low = t } else { high = t }
            }
            return sample(y1, y2, t)
        }
    }

    var shape: Shape
    var color: Color
    var from: CGPoint
    /// Opacity keyframes over one pass, at `keyTimes` (0…1).
    var opacities: [Double]
    var keyTimes: [Double]
    /// One pass, in seconds (a loop that reverses takes twice this).
    var duration: Double
    /// nil stays put.
    var to: CGPoint?
    var scaleFrom: CGFloat = 1
    var scaleTo: CGFloat = 1
    /// Degrees clockwise.
    var angle: Double = 0
    /// Where in its loop the element starts (0…1), so loops don't move in step.
    var phase: Double = 0
    var autoreverses = false
    /// Plays one pass `delay` seconds into the line and holds its end, instead of looping.
    var once = false
    var delay: Double = 0
    /// For position and scale; opacity keyframes are always linear.
    var timing: Timing = .linear
    /// A sideways sway (points either side) over `swayPeriod` seconds, on top of the path.
    var sway: CGFloat = 0
    var swayPeriod: Double = 0

    init(shape: Shape, color: Color, from: CGPoint, opacities: [Double], keyTimes: [Double], duration: Double) {
        self.shape = shape
        self.color = color
        self.from = from
        self.opacities = opacities
        self.keyTimes = keyTimes
        self.duration = duration
    }

    /// Evenly spaced key times for `count` keyframes.
    static func even(_ count: Int) -> [Double] {
        count < 2 ? [0] : (0..<count).map { Double($0) / Double(count - 1) }
    }

    /// 0…1 through the pass at `time` seconds into the scene (`lineAge` into the line,
    /// for one-pass elements), exactly as Core Animation plays it.
    func progress(time: Double, lineAge: Double) -> Double {
        if once { return min(1, max(0, (lineAge - delay) / duration)) }
        if autoreverses {
            let x = (max(0, time) / (2 * duration) + phase).truncatingRemainder(dividingBy: 1) * 2
            return x <= 1 ? x : 2 - x
        }
        return (max(0, time) / duration + phase).truncatingRemainder(dividingBy: 1)
    }

    /// Where the element is at `progress`, with its sway at `time`.
    func position(at progress: Double, time: Double) -> CGPoint {
        var point = from
        if let to {
            let eased = CGFloat(timing.value(progress))
            point = CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased)
        }
        if sway != 0, swayPeriod > 0 {
            // An additive back-and-forth, eased, as Core Animation plays it.
            let x = (max(0, time) / swayPeriod + phase).truncatingRemainder(dividingBy: 1) * 2
            let swing = Timing.easeInOut.value(x <= 1 ? x : 2 - x)
            point.x += sway * CGFloat(swing * 2 - 1)
        }
        return point
    }

    func scale(at progress: Double) -> CGFloat {
        scaleFrom + (scaleTo - scaleFrom) * CGFloat(timing.value(progress))
    }

    func opacity(at progress: Double) -> Double {
        guard keyTimes.count == opacities.count, let first = opacities.first else { return 0 }
        for index in keyTimes.indices.dropFirst() where progress <= keyTimes[index] {
            let start = keyTimes[index - 1], end = keyTimes[index]
            let fraction = end > start ? (progress - start) / (end - start) : 1
            return opacities[index - 1] + (opacities[index] - opacities[index - 1]) * max(0, fraction)
        }
        return opacities.last ?? first
    }
}

// MARK: Still frames

/// Elements at one moment, drawn in SwiftUI: still frames (Settings previews,
/// Reduce Motion) and pinned capture frames.
private struct MoodFrame: View {
    let size: CGSize
    let elements: [MoodElement]
    let grain: MoodScene.Grain?
    let time: Double
    let lineAge: Double

    var body: some View {
        ZStack {
            ForEach(elements.indices, id: \.self) { index in
                element(elements[index])
            }
            if let grain, let image = MoodScene.grainImage(light: grain.light) {
                let step = MoodScene.grainSteps[Int(max(0, time) / MoodScene.grainStep) % MoodScene.grainSteps.count]
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: size.width + 24, height: size.height + 24)
                    .offset(x: step.x, y: step.y)
                    .opacity(grain.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func element(_ element: MoodElement) -> some View {
        let progress = element.progress(time: time, lineAge: lineAge)
        return shape(element)
            .scaleEffect(element.scale(at: progress))
            .rotationEffect(.degrees(element.angle))
            .opacity(element.opacity(at: progress))
            .position(element.position(at: progress, time: time))
    }

    @ViewBuilder
    private func shape(_ element: MoodElement) -> some View {
        let color = element.color
        let size = element.shape.size
        switch element.shape {
        case .glow, .spark, .oval:
            // A circle's radial gradient stretched to the shape, as Core Animation draws an elliptical one.
            let side = max(1, size.height)
            Circle()
                .fill(RadialGradient(stops: element.shape.radialStops.map { Gradient.Stop(color: color.opacity($0.1), location: $0.0) },
                                     center: .center, startRadius: 0, endRadius: side / 2))
                .frame(width: side, height: side)
                .scaleEffect(x: size.width / side, y: 1)
                .frame(width: size.width, height: size.height)
        case .ring, .arc, .ribbon:
            LinearGradient(stops: MoodElement.Shape.lightStops.map { .init(color: color.opacity($0.1), location: $0.0) },
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: size.width, height: size.height)
                .mask {
                    if let path = element.shape.lightPath {
                        ZStack {
                            ForEach(MoodElement.Shape.lightStrokes.indices, id: \.self) { index in
                                let stroke = MoodElement.Shape.lightStrokes[index]
                                Path(path).stroke(.white.opacity(stroke.opacity),
                                                  style: StrokeStyle(lineWidth: element.shape.lineWidth * stroke.width, lineCap: .round))
                            }
                        }
                    }
                }
        case .streak:
            Capsule()
                .fill(LinearGradient(colors: [color.opacity(0), color], startPoint: .top, endPoint: .bottom))
                .frame(width: size.width, height: size.height)
        case .band:
            Rectangle()
                .fill(LinearGradient(stops: [.init(color: color.opacity(0), location: 0), .init(color: color, location: 0.5),
                                             .init(color: color.opacity(0), location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: size.width, height: size.height)
        }
    }

    static func falloff(size: CGSize) -> some View {
        let side = max(1, size.height)
        return Circle()
            .fill(RadialGradient(stops: MoodScene.falloffStops.map { .init(color: .black.opacity($0.1), location: $0.0) },
                                 center: .center, startRadius: 0, endRadius: side / 2))
            .frame(width: side, height: side)
            .scaleEffect(x: size.width / side, y: 1)
            .frame(width: size.width, height: size.height)
    }
}

// MARK: Live motion

/// The live scene in Core Animation: every element is one looping (or one-pass)
/// animation in the window server, so nothing runs per frame in the app. A new
/// treatment fades in over the old one; each line's beats are scheduled from the
/// song's timing when the line arrives; pausing the song holds everything.
private struct MoodLayerScene: NSViewRepresentable {
    let scene: MoodScene
    let key: MoodScene.Key
    let beats: [MoodElement]
    let line: Int
    let playing: Bool

    func makeNSView(context: Context) -> SceneView { SceneView() }

    func updateNSView(_ view: SceneView, context: Context) {
        view.show(scene, key: key, beats: beats, line: line, playing: playing)
    }

    final class SceneView: NSView {
        /// Flipped (y down, as SwiftUI lays the scene out), with one oval mask.
        private let canvas = CALayer()
        /// Each treatment's container sits in here.
        private let faded = CALayer()
        private let falloff = CAGradientLayer()
        private var current: (key: MoodScene.Key, container: CALayer, motion: CALayer)?
        private var line: Int?
        /// The last two lines' beats, so a word still sounding finishes after the next line arrives.
        private var beatLayers: [CALayer] = []
        private var playing = true

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            canvas.isGeometryFlipped = true
            falloff.type = .radial
            falloff.colors = MoodScene.falloffStops.map { CGColor(gray: 0, alpha: CGFloat($0.1)) }
            falloff.locations = MoodScene.falloffStops.map { NSNumber(value: $0.0) }
            falloff.startPoint = CGPoint(x: 0.5, y: 0.5)
            falloff.endPoint = CGPoint(x: 1, y: 1)
            canvas.mask = falloff
            canvas.addSublayer(faded)
            layer?.addSublayer(canvas)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            needsLayout = true
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let frame = CGRect(origin: .zero, size: bounds.size)
            for layer in [canvas, faded] { layer.frame = frame }
            // Draw a circular radial gradient, then stretch it into an ellipse;
            // this matches the SwiftUI mask without rectangular edge fades.
            let side = max(1, bounds.height)
            falloff.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            falloff.position = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
            falloff.setAffineTransform(CGAffineTransform(scaleX: bounds.width / side, y: bounds.height / side))
            for container in faded.sublayers ?? [] {
                container.frame = frame
                for motion in container.sublayers ?? [] {
                    motion.frame = frame
                    for beats in beatLayers where beats.superlayer === motion { beats.frame = frame }
                }
            }
            CATransaction.commit()
        }

        func show(_ scene: MoodScene, key: MoodScene.Key, beats: [MoodElement], line: Int, playing: Bool) {
            // The song clock runs slower in website captures, and so does the scene.
            layer?.speed = Float(1 / Design.demoTimeScale)
            if key != current?.key { present(scene, key: key) }
            if line != self.line {
                self.line = line
                add(beats)
            }
            self.playing = playing
            if let motion = current?.motion { playing ? Self.resume(motion) : Self.pause(motion) }
        }

        private func present(_ scene: MoodScene, key: MoodScene.Key) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let frame = CGRect(origin: .zero, size: bounds.size == .zero ? scene.size : bounds.size)
            let container = CALayer(), motion = CALayer()
            container.frame = frame
            motion.frame = frame
            container.addSublayer(motion)
            faded.addSublayer(container)
            let now = motion.convertTime(CACurrentMediaTime(), from: nil)
            for element in scene.elements { motion.addSublayer(Self.layer(for: element, now: now)) }
            if let grain = scene.grain { motion.addSublayer(Self.grainLayer(grain, size: frame.size)) }
            if !playing { Self.pause(motion) }
            container.add(Self.fade(from: 0, to: 1), forKey: "fade")
            CATransaction.commit()

            if let old = current {
                // The outgoing treatment fades from wherever it is and then leaves.
                let from = old.container.presentation()?.opacity ?? old.container.opacity
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                CATransaction.setCompletionBlock { [weak outgoing = old.container] in outgoing?.removeFromSuperlayer() }
                old.container.opacity = 0
                old.container.add(Self.fade(from: from, to: 0), forKey: "fade")
                CATransaction.commit()
            }
            current = (key, container, motion)
        }

        /// Schedules a line's beats in the current scene's time, so they hold with it.
        private func add(_ beats: [MoodElement]) {
            guard let motion = current?.motion else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let holder = CALayer()
            holder.frame = motion.bounds
            motion.addSublayer(holder)
            let now = holder.convertTime(CACurrentMediaTime(), from: nil)
            for element in beats { holder.addSublayer(Self.layer(for: element, now: now)) }
            beatLayers.append(holder)
            while beatLayers.count > 2 { beatLayers.removeFirst().removeFromSuperlayer() }
            CATransaction.commit()
        }

        private static func fade(from: Float, to: Float) -> CABasicAnimation {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = from
            fade.toValue = to
            fade.duration = MoodScene.crossfade
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return fade
        }

        private static func grainLayer(_ grain: MoodScene.Grain, size: CGSize) -> CALayer {
            let layer = CALayer()
            layer.contents = MoodScene.grainImage(light: grain.light)
            layer.magnificationFilter = .nearest
            layer.contentsGravity = .resize
            layer.bounds = CGRect(x: 0, y: 0, width: size.width + 24, height: size.height + 24)
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            layer.position = middle
            layer.opacity = Float(grain.opacity)
            let jitter = CAKeyframeAnimation(keyPath: "position")
            jitter.values = MoodScene.grainSteps.map { NSValue(point: CGPoint(x: middle.x + $0.x, y: middle.y + $0.y)) }
            jitter.calculationMode = .discrete
            jitter.duration = MoodScene.grainStep * Double(MoodScene.grainSteps.count)
            jitter.repeatCount = .infinity
            layer.add(jitter, forKey: "grain")
            return layer
        }

        /// One element: a holder that moves, turns, sways and fades, around a shape that scales.
        private static func layer(for element: MoodElement, now: CFTimeInterval) -> CALayer {
            let color = NSColor(element.color).cgColor
            let clear = color.copy(alpha: 0) ?? CGColor(gray: 0, alpha: 0)
            let size = element.shape.size
            let shape: CALayer
            switch element.shape {
            case .glow, .spark, .oval:
                let glow = CAGradientLayer()
                glow.type = .radial
                glow.colors = element.shape.radialStops.map { color.copy(alpha: color.alpha * CGFloat($0.1)) ?? clear }
                glow.locations = element.shape.radialStops.map { NSNumber(value: $0.0) }
                glow.startPoint = CGPoint(x: 0.5, y: 0.5)
                glow.endPoint = CGPoint(x: 1, y: 1)
                shape = glow
            case .ring, .arc, .ribbon:
                let light = CAGradientLayer()
                light.colors = MoodElement.Shape.lightStops.map { color.copy(alpha: color.alpha * CGFloat($0.1)) ?? clear }
                light.locations = MoodElement.Shape.lightStops.map { NSNumber(value: $0.0) }
                light.startPoint = CGPoint(x: 0, y: 0.5)
                light.endPoint = CGPoint(x: 1, y: 0.5)
                let mask = CALayer()
                mask.frame = CGRect(origin: .zero, size: size)
                let path = element.shape.lightPath
                for stroke in MoodElement.Shape.lightStrokes {
                    let rim = CAShapeLayer()
                    rim.frame = mask.bounds
                    rim.contentsScale = 2
                    rim.path = path
                    rim.fillColor = nil
                    rim.strokeColor = CGColor(gray: 1, alpha: CGFloat(stroke.opacity))
                    rim.lineWidth = element.shape.lineWidth * stroke.width
                    rim.lineCap = .round
                    mask.addSublayer(rim)
                }
                light.mask = mask
                shape = light
            case .streak(let width, _):
                let streak = CAGradientLayer()
                streak.colors = [clear, color]
                streak.startPoint = CGPoint(x: 0.5, y: 0)
                streak.endPoint = CGPoint(x: 0.5, y: 1)
                streak.cornerRadius = width / 2
                shape = streak
            case .band:
                let band = CAGradientLayer()
                band.colors = [clear, color, clear]
                band.locations = [0, 0.5, 1]
                band.startPoint = CGPoint(x: 0, y: 0.5)
                band.endPoint = CGPoint(x: 1, y: 0.5)
                shape = band
            }
            shape.bounds = CGRect(origin: .zero, size: size)
            shape.position = CGPoint(x: size.width / 2, y: size.height / 2)

            let holder = CALayer()
            holder.bounds = CGRect(origin: .zero, size: size)
            holder.position = element.from
            holder.addSublayer(shape)
            if element.angle != 0 { holder.setAffineTransform(CGAffineTransform(rotationAngle: element.angle * .pi / 180)) }
            holder.opacity = Float(element.opacities.first ?? 0)

            func timed(_ animation: CAAnimation) -> CAAnimation {
                animation.duration = element.duration
                animation.autoreverses = element.autoreverses
                animation.isRemovedOnCompletion = false
                if element.once {
                    // Timed from the line's arrival, holding the first frame until then and the last after.
                    animation.beginTime = now + element.delay
                    animation.fillMode = .both
                } else {
                    animation.repeatCount = .infinity
                    animation.timeOffset = element.phase * element.duration * (element.autoreverses ? 2 : 1)
                }
                return animation
            }

            var parts: [CAAnimation] = []
            if let to = element.to {
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = NSValue(point: element.from)
                move.toValue = NSValue(point: to)
                move.duration = element.duration
                move.timingFunction = element.timing.function
                parts.append(move)
            }
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = element.opacities
            opacity.keyTimes = element.keyTimes.map { NSNumber(value: $0) }
            opacity.duration = element.duration
            parts.append(opacity)
            let group = CAAnimationGroup()
            group.animations = parts
            holder.add(timed(group), forKey: "mood")

            if element.scaleFrom != element.scaleTo {
                let scale = CABasicAnimation(keyPath: "transform.scale")
                scale.fromValue = Double(element.scaleFrom)
                scale.toValue = Double(element.scaleTo)
                scale.timingFunction = element.timing.function
                shape.add(timed(scale), forKey: "scale")
            }
            if element.sway != 0, element.swayPeriod > 0 {
                // Added on top of the path; the same phase as the loop.
                let sway = CABasicAnimation(keyPath: "position.x")
                sway.fromValue = -Double(element.sway)
                sway.toValue = Double(element.sway)
                sway.isAdditive = true
                sway.duration = element.swayPeriod / 2
                sway.autoreverses = true
                sway.repeatCount = .infinity
                sway.timeOffset = element.phase * element.swayPeriod
                sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                holder.add(sway, forKey: "sway")
            }
            return holder
        }

        private static func pause(_ layer: CALayer) {
            guard layer.speed != 0 else { return }
            let now = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = now
        }

        private static func resume(_ layer: CALayer) {
            guard layer.speed == 0 else { return }
            let paused = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
        }
    }
}
