#if DEBUG
import SwiftUI
import AppKit

/// KemoSabe's motion for review, the `kemosabe-motion` scope, in `kemosabe-motion/`:
/// - `motion-<look>.png` (Apricot felt, Lavender glass): contact sheets, a frame every 0.25 s over
///   3 s for idle (a blink, then a glance), the pointer crossing, thinking, an answer arriving
///   (thinking to idle, and to happy), love, celebrating, speaking, a poke and sad.
/// - `moods-<look>.png` (and Rose felt): every mood live and as Reduce Motion shows it.
/// - `promo/kemosabe-<mood>-<look>.png`: 1024 px stills on a transparent background (never committed).
/// - `cost.txt`: CPU with each face live in a window off the visible screen, 8 s each, with 4.09's
///   KemoSabe (`KemoSabeFace409`, kept here only to compare) beside today's.
@MainActor
enum KemoSabeMotionCaptures {
    static let scale: CGFloat = 2

    static func capture(to directory: URL) async {
        let root = directory.appendingPathComponent("kemosabe-motion")
        let promo = root.appendingPathComponent("promo")
        try? FileManager.default.createDirectory(at: promo, withIntermediateDirectories: true)
        let theme = ThemeStore.shared
        let saved = theme.family
        theme.setPreviewSystemReduceMotion(false)
        theme.selectFamily(.macspaces)
        let looks: [(String, KemoSabeLook)] = [
            ("apricot", .apricot),
            ("lavender-glass", KemoSabeLook(AgentPalette.named("lavender"), glass: 1)),
            ("rose", KemoSabeLook(AgentPalette.named("rose"))),
        ]
        for (_, look) in looks {
            for kind in [KemoSabeArt.Kind.felt, .glass] {
                _ = await KemoSabeArt.make(kind, look: look, small: false)
                _ = await KemoSabeArt.make(kind, look: look, small: true)
            }
        }
        for (name, look) in looks.prefix(2) {
            let rows = motionRows()
            let width: CGFloat = 150 + CGFloat(frames.count) * 92 + 24
            write(sheet(rows, look: look).frame(width: width, alignment: .leading).background(theme.notch.surface),
                  size: NSSize(width: width, height: CGFloat(rows.count) * 96 + 60),
                  to: root.appendingPathComponent("motion-\(name).png"))
        }
        for (name, look) in looks {
            write(moods(look).background(theme.notch.surface), size: NSSize(width: 11 * 100 + 24, height: 2 * 118 + 56),
                  to: root.appendingPathComponent("moods-\(name).png"))
        }
        // Promo stills: 512 pt at 2x, nothing behind.
        let stills: [(String, WispMood, Double)] = [("sad", .sad, 1.9), ("happy", .happy, 0.8), ("love", .love, 0.8)]
        for (name, look) in looks {
            for (mood, kind, t) in stills {
                write(KemoSabeFace(mood: kind, size: 440, look: look, at: t).frame(width: 512, height: 512),
                      size: NSSize(width: 512, height: 512), to: promo.appendingPathComponent("kemosabe-\(mood)-\(name).png"))
            }
        }
        await measureCost(to: root)
        theme.selectFamily(saved)
        theme.setPreviewSystemReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        print("KemoSabe motion captures written")
    }

    // MARK: Contact sheets

    private static let frames: [Double] = (0...12).map { Double($0) * 0.25 }

    /// A row: its label and, for each moment (0 to 3 s), the mood, any mood change to replay and the pointer.
    private struct Row {
        let label: String
        /// Where on the clock the row starts.
        var offset: Double = 0
        let frame: (Double) -> (mood: WispMood, change: KemoSabeMotion.Change?, gaze: CGPoint?)
    }

    private static func change(from: WispMood, to: WispMood, at t: Double) -> KemoSabeMotion.Change {
        var change = KemoSabeMotion.Change()
        change.mood = to; change.from = from; change.moodAt = t
        return change
    }

    private static func motionRows() -> [Row] {
        // Moments worth seeing: the first blink, and the first glance aside, a second before each.
        var blink = 0.0, glance = 0.0
        for step in 0..<6000 where KemoSabeMotion.at(Double(step) * 0.01, mood: .idle).lid > 0.9 { blink = Double(step) * 0.01; break }
        for step in 0..<6000 where abs(KemoSabeMotion.at(Double(step) * 0.01, mood: .idle).shift) > 0.02 { glance = Double(step) * 0.01; break }
        let start = 40.0
        return [
            Row(label: "idle, a blink", offset: max(0, blink - 1)) { _ in (.idle, nil, nil) },
            Row(label: "idle, a glance", offset: max(0, glance - 0.5)) { _ in (.idle, nil, nil) },
            Row(label: "pointer crossing", offset: start) { t in (.idle, nil, CGPoint(x: -1 + 2 * t / 3, y: 0.25)) },
            Row(label: "thinking", offset: start) { _ in (.thinking, nil, nil) },
            Row(label: "answer arrives") { t in t < 0.5 ? (.thinking, nil, nil) : (.idle, change(from: .thinking, to: .idle, at: 0.5), nil) },
            Row(label: "answer, happy") { t in t < 0.5 ? (.thinking, nil, nil) : (.happy, change(from: .thinking, to: .happy, at: 0.5), nil) },
            Row(label: "love", offset: start) { _ in (.love, nil, nil) },
            Row(label: "celebrating", offset: start) { _ in (.celebrating, nil, nil) },
            Row(label: "speaking", offset: start) { _ in (.speaking, nil, nil) },
            Row(label: "poke") { t in
                t < 0.25 ? (.idle, nil, nil) : t < 0.75 ? (.surprised, change(from: .idle, to: .surprised, at: 0.25), nil)
                    : (.happy, change(from: .surprised, to: .happy, at: 0.75), nil)
            },
            Row(label: "becoming sad") { t in t < 0.25 ? (.idle, nil, nil) : (.sad, change(from: .idle, to: .sad, at: 0.25), nil) },
            Row(label: "sad", offset: start) { _ in (.sad, nil, nil) },
        ]
    }

    private static func sheet(_ rows: [Row], look: KemoSabeLook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("KemoSabe's motion, a frame every 0.25 s over 3 s").font(.headline).foregroundStyle(.white)
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 2) {
                    Text(rows[index].label).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                        .frame(width: 148, alignment: .leading)
                    ForEach(frames, id: \.self) { t in
                        let frame = rows[index].frame(t)
                        KemoSabeFace(mood: frame.mood, size: 80, look: look, at: t + rows[index].offset, gaze: frame.gaze,
                                     scripted: frame.change)
                            .frame(width: 90, height: 92)
                    }
                }
            }
        }
        .padding(12)
    }

    private static func moods(_ look: KemoSabeLook) -> some View {
        let all: [WispMood] = [.idle, .listening, .thinking, .speaking, .happy, .celebrating, .surprised, .sleepy, .confused, .love, .sad]
        return VStack(alignment: .leading, spacing: 6) {
            Text("Every mood live (top) and as Reduce Motion shows it").font(.headline).foregroundStyle(.white)
            ForEach([false, true], id: \.self) { still in
                HStack(spacing: 0) {
                    ForEach(all.indices, id: \.self) { index in
                        VStack(spacing: 2) {
                            if still {
                                KemoSabeFace(mood: all[index], size: 84, look: look, still: true)
                            } else {
                                KemoSabeFace(mood: all[index], size: 84, look: look, at: 1.9)
                            }
                            Text(String(describing: all[index])).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                        }
                        .frame(width: 100, height: 112)
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: Cost

    /// Moves the gaze about at the page's throttled rate, as a pointer crossing the page does.
    @MainActor private final class Pointer: ObservableObject {
        @Published var gaze: CGPoint? = nil
        private var timer: Timer?
        private var step = 0
        func start() {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advance() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        private func advance() {
            step += 1
            gaze = CGPoint(x: CGFloat((step % 9) - 4) / 4, y: CGFloat(((step / 9) % 5) - 2) / 4)
        }
        func stop() { timer?.invalidate(); timer = nil }
    }

    private struct Following: View {
        @ObservedObject var pointer: Pointer
        var body: some View { KemoSabeFace(mood: .idle, size: 92, gaze: pointer.gaze, near: pointer.gaze != nil) }
    }

    private static func measureCost(to root: URL) async {
        let theme = ThemeStore.shared
        let half = KemoSabeLook(.apricot, glass: 0.5)
        for kind in [KemoSabeArt.Kind.felt, .glass] { _ = await KemoSabeArt.make(kind, look: half, small: false) }
        _ = await KemoSabeArt.makeBlend(look: half, small: false)
        let pointer = Pointer()
        let cases: [(String, AnyView, Bool)] = [
            ("nothing", AnyView(Color.clear), false),
            ("Wisp idle", AnyView(WispFace(mood: .idle, size: 80)), false),
            ("4.09 KemoSabe idle", AnyView(KemoSabeFace409(mood: .idle, size: 92)), false),
            ("KemoSabe idle", AnyView(KemoSabeFace(mood: .idle, size: 92)), false),
            ("KemoSabe idle, pointer moving (gaze every 100 ms)", AnyView(Following(pointer: pointer)), true),
            ("4.09 KemoSabe thinking", AnyView(KemoSabeFace409(mood: .thinking, size: 92)), false),
            ("KemoSabe thinking", AnyView(KemoSabeFace(mood: .thinking, size: 92)), false),
            ("4.09 KemoSabe happy", AnyView(KemoSabeFace409(mood: .happy, size: 92)), false),
            ("KemoSabe happy", AnyView(KemoSabeFace(mood: .happy, size: 92)), false),
            ("KemoSabe love (hearts)", AnyView(KemoSabeFace(mood: .love, size: 92)), false),
            ("KemoSabe speaking", AnyView(KemoSabeFace(mood: .speaking, size: 92)), false),
            ("KemoSabe sad (tear)", AnyView(KemoSabeFace(mood: .sad, size: 92)), false),
            ("4.09 KemoSabe idle, half glass", AnyView(KemoSabeFace409(mood: .idle, size: 92, look: half)), false),
            ("KemoSabe idle, half glass", AnyView(KemoSabeFace(mood: .idle, size: 92, look: half)), false),
            ("nothing, after", AnyView(Color.clear), false),
        ]
        var report: [String] = []
        for (name, view, moving) in cases {
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 200, height: 160), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view.frame(width: 200, height: 160).background(theme.notch.surface))
            window.orderFrontRegardless()
            if moving { pointer.start() }
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            let start = FeatureQAHarness.cpuSeconds()
            RunLoop.main.run(until: Date().addingTimeInterval(8))
            let line = String(format: "%@: %.1f%% CPU", name, (FeatureQAHarness.cpuSeconds() - start) / 8 * 100)
            print(line)
            report.append(line)
            pointer.stop()
            window.orderOut(nil)
            window.contentView = nil
        }
        try? report.joined(separator: "\n").write(to: root.appendingPathComponent("cost.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Drawing

    private static func write<V: View>(_ view: V, size: NSSize, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: url) }
    }
}

// MARK: 4.09's KemoSabe, to compare costs with

fileprivate struct KemoSabeFace409: View {
    var mood: WispMood
    var size: CGFloat
    var look: KemoSabeLook = .apricot
    var still = false
    /// Captures: draw exactly this moment of the motion.
    var at: Double? = nil
    @ObservedObject private var theme = ThemeStore.shared
    /// Bumped as repaints arrive, so they're drawn.
    @State private var painted = 0

    private var live: Bool { !still && !theme.reduceMotion && at == nil }
    private var glass: Double { max(0, min(1, look.glass)) }
    private var kinds: [KemoSabeArt.Kind] {
        if glass <= 0.001 { return [.felt] }
        return glass >= 0.999 ? [.glass] : [.glass, .felt]
    }

    /// The pictures to draw, looked up once per update, never per frame: the timeline only moves them.
    private struct Pictures {
        var frosted: CGImage?
        var blend: CGImage?
        var felt: CGImage?
        var eyes: [CGImage]
    }

    private var pictures: Pictures {
        _ = painted
        let blend: CGImage? = kinds.count == 2 ? KemoSabeArt.blended(look: look, small: still) : nil
        let felt = kinds.contains(.felt) ? KemoSabeArt.cached(.felt, look: look, small: still) : nil
        let frosted = kinds.contains(.glass) && blend == nil ? KemoSabeArt.cached(.glass, look: look, small: still) : nil
        let eyes: [CGImage] = (felt ?? frosted)?.eyes ?? KemoSabeArt.cached(.glass, look: look, small: still)?.eyes ?? []
        return Pictures(frosted: frosted?.base, blend: blend, felt: felt?.base, eyes: eyes)
    }

    var body: some View {
        let shown = pictures
        Group {
            if live {
                TimelineView(.periodic(from: .now, by: 1.0 / KemoSabeMotion409.framesPerSecond(mood))) { context in
                    // Website captures slow time (`demoTimeScale`, 1 in the app), as the scenes do.
                    art(KemoSabeMotion409.at(context.date.timeIntervalSinceReferenceDate / Design.demoTimeScale, mood: mood), shown)
                }
            } else if let at {
                art(KemoSabeMotion409.at(at, mood: mood), shown)
            } else {
                art(KemoSabeMotion409.still(mood), shown)
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(look.body)|\(look.face)|\(kinds.map(\.rawValue))|\(still)") {
            for kind in kinds where await KemoSabeArt.make(kind, look: look, small: still) { painted += 1 }
        }
        .task(id: "\(look.body)|\(look.face)|\(Int((glass * 20).rounded()))|\(painted)|\(still)") {
            // Between felt and glass, one blended picture, made once both repaints are in.
            if kinds.count == 2, KemoSabeArt.blended(look: look, small: still) == nil,
               await KemoSabeArt.makeBlend(look: look, small: still) { painted += 1 }
        }
        .accessibilityElement()
        .accessibilityLabel(WispPose.words(mood).map { "KemoSabe, " + $0 } ?? "KemoSabe")
    }

    private func art(_ motion: KemoSabeMotion409, _ shown: Pictures) -> some View {
        let blend = shown.blend, felt = shown.felt, frosted = shown.frosted, eyes = shown.eyes
        // On a light Nook a faint shadow keeps the glass's edge.
        let edge: Double = theme.nookScheme == .light ? 0.22 * glass : 0
        return ZStack(alignment: .topLeading) {
            if let frosted {
                Image(decorative: frosted, scale: 1).resizable().interpolation(.high)
                    .shadow(color: .black.opacity(edge), radius: edge > 0 ? size * 0.015 : 0)
            }
            if let blend {
                Image(decorative: blend, scale: 1).resizable().interpolation(.high)
                    .shadow(color: .black.opacity(edge), radius: edge > 0 ? size * 0.015 : 0)
            } else if let felt {
                Image(decorative: felt, scale: 1).resizable().interpolation(.high)
                    .opacity(frosted == nil ? 1 : 1 - glass)
            }
            ForEach(0..<eyes.count, id: \.self) { index in
                let box = KemoSabeArt.eyes[index]
                Image(decorative: eyes[index], scale: 1).resizable().interpolation(.high)
                    .frame(width: box.width * size, height: box.height * size)
                    // A blink shuts the eye from the top down to a line.
                    .scaleEffect(x: 1 + 0.08 * motion.lid, y: max(0.08, 1 - motion.lid), anchor: UnitPoint(x: 0.5, y: 0.74))
                    .offset(x: box.minX * size, y: box.minY * size)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .scaleEffect(x: motion.squashX, y: motion.squashY, anchor: .bottom)
        .rotationEffect(.degrees(motion.tilt), anchor: .bottom)
        .offset(x: motion.shift * size, y: -motion.lift * size)
    }
}

/// KemoSabe's motion at a moment, worked out from the clock alone so nothing waits or keeps state:
/// squash and stretch from the bottom, a lift, a tilt about its base, a sideways lean and lids.
fileprivate struct KemoSabeMotion409: Equatable {
    var squashX: CGFloat = 1
    var squashY: CGFloat = 1
    /// Up, in fractions of its size.
    var lift: CGFloat = 0
    var tilt: Double = 0
    var shift: CGFloat = 0
    /// 0 open, 1 shut.
    var lid: CGFloat = 0

    /// Hops and chatter at 30 frames a second; the calm moods (breathing, blinks, a sway) at 20.
    static func framesPerSecond(_ mood: WispMood) -> Double {
        switch mood {
        case .happy, .love, .celebrating, .speaking: return 30
        default: return 20
        }
    }

    /// The mood's still pose (Reduce Motion and the colour cards).
    static func still(_ mood: WispMood) -> KemoSabeMotion409 {
        var m = KemoSabeMotion409()
        switch mood {
        case .sleepy: m.lid = 0.62; m.tilt = 5; m.squashY = 0.975; m.squashX = 1.015
        case .confused: m.tilt = -7
        case .listening: m.tilt = 4
        case .surprised: m.squashY = 1.04; m.squashX = 0.98; m.lift = 0.02
        case .happy, .love, .celebrating: m.squashY = 1.02; m.squashX = 0.99
        default: break
        }
        return m
    }

    static func at(_ t: Double, mood: WispMood) -> KemoSabeMotion409 {
        var m = still(mood)
        let breath: Double
        switch mood {
        case .sleepy:
            // Slow, deep breaths, the lids heavier at the bottom of each.
            breath = 1.3 * sin(t * 1.1)
            m.lid = 0.55 + 0.3 * CGFloat(0.5 + 0.5 * sin(t * 0.55))
            m.tilt = 5 + 1.5 * sin(t * 0.4)
        case .thinking:
            breath = sin(t * 1.5)
            m.tilt = 3.5 * sin(t * 1.2)
            m.lift = CGFloat(0.012 * (1 + sin(t * 1.1)))
        case .happy, .love, .celebrating:
            breath = 0
            let hop = hopShape(t, period: mood == .celebrating ? 0.9 : 1.4)
            m.lift = CGFloat(hop.lift) * (mood == .celebrating ? 0.09 : 0.06)
            m.squashY = 1 - CGFloat(hop.squash) * 0.07
            m.squashX = 1 + CGFloat(hop.squash) * 0.06
            if mood == .love { m.tilt = 3 * sin(t * 2.2) }
        case .speaking:
            breath = 0
            let chatter = abs(sin(t * 9))
            m.squashY = 1 - CGFloat(chatter) * 0.025
            m.squashX = 1 + CGFloat(chatter) * 0.015
        case .confused:
            breath = sin(t * 1.9)
            m.tilt = -7 + 1.5 * sin(t * 0.9)
        default:
            breath = sin(t * 1.9)
        }
        m.squashX *= 1 + 0.012 * CGFloat(breath)
        m.squashY *= 1 - 0.018 * CGFloat(breath)
        if mood != .sleepy && mood != .surprised {
            let beat = blinkAndGlance(t, glances: mood == .idle)
            m.lid = max(m.lid, beat.lid)
            m.shift += beat.lean * 0.025
            m.tilt += Double(beat.lean) * 3
        }
        return m
    }

    /// A hop each period: up and down, a squash on landing and a little one before take-off.
    private static func hopShape(_ t: Double, period: Double) -> (lift: Double, squash: Double) {
        let p = (t / period).truncatingRemainder(dividingBy: 1)
        if p < 0.45 { return (sin(.pi * p / 0.45), 0) }
        if p < 0.6 { return (0, sin(.pi * (p - 0.45) / 0.15)) }
        if p > 0.85 { return (0, 0.4 * sin(.pi * (p - 0.85) / 0.15)) }
        return (0, 0)
    }

    /// Wisp's rhythm without its task: one beat every 2.6 to 5.2 s, a blink (sometimes two), and
    /// at idle every third beat a glance to one side for 1.3 s instead.
    private static func blinkAndGlance(_ t: Double, glances: Bool) -> (lid: CGFloat, lean: CGFloat) {
        let slot = 3.9
        let n = Int(floor(t / slot))
        var lid: CGFloat = 0, lean: CGFloat = 0
        // The beat in this slot and the last, which may run into this one.
        for k in [n - 1, n] {
            let start = Double(k) * slot + noise(k) * (slot - 1.4)
            let since = t - start
            if glances, k % 3 == 0 {
                guard since >= 0, since < 1.3 else { continue }
                let side: CGFloat = noise(k + 7) < 0.5 ? -1 : 1
                let ease = min(since / 0.25, (1.3 - since) / 0.25, 1)
                lean = side * CGFloat(ease * ease * (3 - 2 * ease))
                continue
            }
            let twice = noise(k + 101) < 0.2
            for offset in twice ? [0, 0.3] : [0] {
                let s = since - offset
                guard s >= 0, s < 0.22 else { continue }
                let shut = s < 0.07 ? s / 0.07 : s < 0.1 ? 1 : 1 - (s - 0.1) / 0.12
                lid = max(lid, CGFloat(shut))
            }
        }
        return (lid, lean)
    }

    private static func noise(_ n: Int) -> Double {
        let x = sin(Double(n) * 12.9898 + 78.233) * 43758.5453
        return x - floor(x)
    }
}
#endif
