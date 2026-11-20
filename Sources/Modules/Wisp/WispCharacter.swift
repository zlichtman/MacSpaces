import SwiftUI

/// Who appears on Wisp's page: Wisp's eyes, or KemoSabe, Tsukumo's companion, in the agent's
/// colours (`AgentPalette`, Settings → Tsukumo). Only the face and name change: the page, its chat,
/// its model and its settings stay the same.
enum WispCharacter: String, CaseIterable, Identifiable {
    case wisp, kemosabe

    var id: String { rawValue }
    var title: String { self == .wisp ? "Wisp" : "KemoSabe" }

    static var current: WispCharacter {
        UserDefaults.standard.string(forKey: WidgetOptions.Keys.wispCharacter).flatMap(WispCharacter.init) ?? .wisp
    }

    /// 3.95 offered glass KemoSabe as a character of its own; that choice becomes KemoSabe with its
    /// saved look "glass" (Pearl at full glass, `AgentColours.ownKemoSabe`).
    static func migrateGlass(_ defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: WidgetOptions.Keys.wispCharacter) == "glass" else { return }
        defaults.set(WispCharacter.kemosabe.rawValue, forKey: WidgetOptions.Keys.wispCharacter)
        if defaults.string(forKey: WidgetOptions.Keys.kemoSabeLook) == nil {
            defaults.set("glass", forKey: WidgetOptions.Keys.kemoSabeLook)
        }
    }
}

/// KemoSabe in the agent's colours as Settings has them (`AgentColourSettings`), for Wisp's page
/// and the Agent card's live choice. On the page it watches the pointer (`gaze`, `near`).
struct KemoSabeAgentFace: View {
    var mood: WispMood
    var size: CGFloat
    var gaze: CGPoint?
    var near: Bool
    // Not private: a private stored property would make the memberwise initialiser private.
    var colours = AgentColourSettings()

    init(mood: WispMood, size: CGFloat, gaze: CGPoint? = nil, near: Bool = false) {
        self.mood = mood; self.size = size; self.gaze = gaze; self.near = near
    }

    var body: some View { KemoSabeFace(mood: mood, size: size, look: colours.kemoSabe(), gaze: gaze, near: near) }
}


/// KemoSabe, the original 3D felt art (`KemoSabeArt`) in `look`'s colours, as see-through as
/// `look.glass`: the frosted layer under the felt, the felt fading out as the glass rises, so it's
/// always one pose. Its eyes and mouth are pictures of their own, so they blink, droop, close into
/// happy arcs, widen, talk and frown. It moves in its own way (`KemoSabeMotion`) on a `.periodic`
/// timeline: it breathes and sways, blinks, glances aside, turns its eyes and leans toward the
/// pointer, hops when happy, ponders while thinking, slumps with a tear when sad, and eases between
/// moods with a little reaction (a hop when an answer arrives, a jump when startled). Still under
/// Reduce Motion and when `still` (the colour cards, which also take a smaller repaint), showing
/// the mood's pose.
struct KemoSabeFace: View {
    var mood: WispMood
    var size: CGFloat
    var look: KemoSabeLook = .apricot
    var still = false
    /// Captures: draw exactly this moment of the motion.
    var at: Double? = nil
    /// Where the pointer is from the face, -1...1 each way (Wisp's page), or nil when it's away.
    var gaze: CGPoint? = nil
    /// The pointer is close: the eyes widen a little.
    var near = false
    /// Captures: a mood change to replay at `at` (its `from`, `moodAt` and pointer).
    var scripted: KemoSabeMotion.Change? = nil
    @ObservedObject private var theme = ThemeStore.shared
    /// Bumped as repaints arrive, so they're drawn.
    @State private var painted = 0
    /// The last mood and pointer changes, so the timeline eases from them.
    @State private var change = KemoSabeMotion.Change()

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
        var mouth: CGImage?
    }

    private var pictures: Pictures {
        _ = painted
        let blend: CGImage? = kinds.count == 2 ? KemoSabeArt.blended(look: look, small: still) : nil
        let felt = kinds.contains(.felt) ? KemoSabeArt.cached(.felt, look: look, small: still) : nil
        let frosted = kinds.contains(.glass) && blend == nil ? KemoSabeArt.cached(.glass, look: look, small: still) : nil
        let parts = felt ?? frosted ?? KemoSabeArt.cached(.glass, look: look, small: still)
        return Pictures(frosted: frosted?.base, blend: blend, felt: felt?.base, eyes: parts?.eyes ?? [], mouth: parts?.mouth)
    }

    /// The clock the timeline runs on (website captures slow it, as the scenes do).
    private static var now: Double { Date().timeIntervalSinceReferenceDate / Design.demoTimeScale }

    var body: some View {
        let shown = pictures
        Group {
            if live {
                let pointer = KemoSabeMotion.Pointer(gaze: gaze ?? .zero, near: near, present: gaze != nil)
                TimelineView(.periodic(from: .now, by: 1.0 / KemoSabeMotion.framesPerSecond(mood))) { context in
                    let t = context.date.timeIntervalSinceReferenceDate / Design.demoTimeScale
                    art(KemoSabeMotion.at(t, mood: mood, change: change, pointer: pointer), shown)
                }
            } else if let at {
                art(KemoSabeMotion.at(at, mood: mood, change: scripted,
                                      pointer: KemoSabeMotion.Pointer(gaze: gaze ?? .zero, near: near, present: gaze != nil)), shown)
            } else {
                art(KemoSabeMotion.still(mood), shown)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            change.mood = mood
            change.gazeFrom = gaze ?? .zero; change.gazeTo = gaze ?? .zero
            change.nearFrom = near ? 1 : 0; change.nearTo = near ? 1 : 0
        }
        .onChange(of: mood) { new in
            guard live else { return }
            change.moved(to: new, at: Self.now)
        }
        .onChange(of: gaze) { new in
            guard live else { return }
            change.looked(at: new ?? .zero, near: near, at: Self.now)
        }
        .onChange(of: near) { new in
            guard live else { return }
            change.looked(at: gaze ?? .zero, near: new, at: Self.now)
        }
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

    private func art(_ motion: KemoSabeMotion, _ shown: Pictures) -> some View {
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
                eye(eyes[index], index: index, motion)
            }
            if let mouth = shown.mouth {
                let box = KemoSabeArt.mouth
                Image(decorative: mouth, scale: 1).resizable().interpolation(.high)
                    .frame(width: box.width * size, height: box.height * size)
                    // Wider and deeper for a grin, opening while it talks, turned over into a frown.
                    .scaleEffect(x: motion.mouthX, y: motion.mouthY)
                    .rotationEffect(.degrees(motion.mouthTilt))
                    .offset(x: (box.minX + motion.mouthShift) * size, y: (box.minY + motion.mouthDrop) * size)
            }
            if motion.tear >= 0 { tear(motion.tear) }
            if motion.hearts >= 0 { hearts(motion.hearts) }
            if motion.sparkle >= 0 { sparkles(motion.sparkle) }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .scaleEffect(x: motion.squashX, y: motion.squashY, anchor: .bottom)
        .rotationEffect(.degrees(motion.tilt), anchor: .bottom)
        .offset(x: motion.shift * size, y: -motion.lift * size)
    }

    private func eye(_ picture: CGImage, index: Int, _ motion: KemoSabeMotion) -> some View {
        let box = KemoSabeArt.eyes[index]
        let left = index == 0
        let width: CGFloat = box.width * size, height: CGFloat = box.height * size
        let scale: CGFloat = motion.eyeScale * (left ? 1 : motion.rightEye)
        return Image(decorative: picture, scale: 1).resizable().interpolation(.high)
            .frame(width: width, height: height)
            .overlay {
                // Watery glints when sad or startled.
                if motion.glint > 0.01 {
                    ZStack(alignment: .topLeading) {
                        Ellipse().fill(Color.white.opacity(0.92 * Double(motion.glint)))
                            .frame(width: width * 0.26, height: height * 0.22)
                            .offset(x: width * ((left ? 0.52 : 0.45) - 0.13), y: height * (0.56 - 0.11))
                        Ellipse().fill(Color.white.opacity(0.85 * Double(motion.glint)))
                            .frame(width: width * 0.14, height: height * 0.1)
                            .offset(x: width * ((left ? 0.31 : 0.69) - 0.07), y: height * (0.745 - 0.05))
                    }
                    .frame(width: width, height: height, alignment: .topLeading)
                }
            }
            // Sad lids droop from the outer corner; happy eyes close into arcs from below.
            .mask(KemoSabeEyeMask(droop: motion.droop, crescent: motion.crescent, left: left).fill(style: FillStyle(eoFill: true)))
            // A blink shuts the eye from the top down to a line.
            .scaleEffect(x: (1 + 0.08 * motion.lid) * scale, y: max(0.08, 1 - motion.lid) * scale, anchor: UnitPoint(x: 0.5, y: 0.74))
            .offset(x: (box.minX + motion.eyeX) * size, y: (box.minY + motion.eyeY) * size)
    }

    /// One tear from under the left eye: it wells up, rolls down a little and fades.
    private func tear(_ phase: CGFloat) -> some View {
        let width: CGFloat = size * 0.042, height: CGFloat = size * 0.06
        let grow: CGFloat = min(1, phase / 0.15)
        let roll: CGFloat = phase < 0.15 ? 0 : min(1, (phase - 0.15) / 0.7)
        let eased: CGFloat = roll * roll * (3 - 2 * roll)
        let fade: Double = phase < 0.75 ? 1 : Double(max(0, 1 - (phase - 0.75) / 0.25))
        let x: CGFloat = (153 - 4 * eased) / 480, y: CGFloat = (297 + 40 * eased) / 480
        let shape = KemoSabeTearShape()
        return ZStack(alignment: .topLeading) {
            shape.fill(LinearGradient(colors: [Color(.sRGB, red: 0.8, green: 0.93, blue: 1, opacity: 0.95),
                                               Color(.sRGB, red: 0.42, green: 0.72, blue: 0.95, opacity: 0.95)],
                                      startPoint: .top, endPoint: .bottom))
            shape.stroke(Color(.sRGB, red: 0.3, green: 0.58, blue: 0.85, opacity: 0.55), lineWidth: max(0.5, size * 0.0025))
            Ellipse().fill(Color.white.opacity(0.9))
                .frame(width: width * 0.24, height: height * 0.26)
                .offset(x: width * 0.2, y: height * 0.52)
        }
        .frame(width: width, height: height)
        .scaleEffect(max(0.01, grow), anchor: .top)
        .opacity(fade)
        .offset(x: x * size - width / 2, y: y * size - height * 0.2)
    }

    /// Two little hearts in the face colour, floating up from the top right.
    private func hearts(_ phase: CGFloat) -> some View {
        let colour = KemoSabeRGB(hex: look.face).color
        return ZStack(alignment: .topLeading) {
            ForEach(0..<2, id: \.self) { index in
                let p: CGFloat = (phase + CGFloat(index) * 0.5).truncatingRemainder(dividingBy: 1)
                let side: CGFloat = size * (index == 0 ? 0.085 : 0.055)
                let fade: Double = Double(min(1, p / 0.2, (1 - p) / 0.3))
                let x: CGFloat = (index == 0 ? 0.8 : 0.9) + 0.03 * p
                let y: CGFloat = (index == 0 ? 0.24 : 0.16) - 0.12 * p
                WispHeart().fill(colour)
                    .frame(width: side, height: side * 0.92)
                    .scaleEffect(0.6 + 0.4 * min(1, p / 0.3))
                    .rotationEffect(.degrees(index == 0 ? 14 : 22))
                    .opacity(max(0, fade))
                    .offset(x: x * size - side / 2, y: y * size - side / 2)
            }
        }
    }

    /// Three sparkles in the face colour, twinkling in turn around it.
    private func sparkles(_ phase: CGFloat) -> some View {
        let colour = KemoSabeRGB(hex: look.face).color
        let spots: [(CGFloat, CGFloat)] = [(0.12, 0.2), (0.88, 0.26), (0.5, 0.04)]
        return ZStack(alignment: .topLeading) {
            ForEach(0..<spots.count, id: \.self) { index in
                let p: CGFloat = (phase + CGFloat(index) / 3).truncatingRemainder(dividingBy: 1)
                let pop: CGFloat = max(0, sin(.pi * min(1, p / 0.6)))
                let side: CGFloat = size * 0.07
                WispStar().fill(colour)
                    .frame(width: side, height: side)
                    .scaleEffect(max(0.01, pop))
                    .rotationEffect(.degrees(Double(p) * 40))
                    .offset(x: spots[index].0 * size - side / 2, y: spots[index].1 * size - side / 2)
            }
        }
    }
}

/// The part of an eye picture that shows: below a lid that droops from the outer corner (sad), and
/// above an arc that rises from below (happy: the eye becomes a ^). Fill it even-odd.
struct KemoSabeEyeMask: Shape {
    var droop: CGFloat
    var crescent: CGFloat
    var left: Bool

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(droop, crescent) }
        set { droop = newValue.first; crescent = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        // In fractions of the eye's box: the painted eye runs from 0.08 to 0.92 down.
        let above: CGFloat = -0.1
        let outerY: CGFloat = above + (0.415 - above) * droop
        let innerY: CGFloat = above + (0.178 - above) * droop
        let bow: CGFloat = 0.064 * droop
        let outerX: CGFloat = left ? rect.minX - 0.1 * w : rect.maxX + 0.1 * w
        let innerX: CGFloat = left ? rect.maxX + 0.1 * w : rect.minX - 0.1 * w
        var path = Path()
        path.move(to: CGPoint(x: outerX, y: rect.minY + outerY * h))
        path.addQuadCurve(to: CGPoint(x: innerX, y: rect.minY + innerY * h),
                          control: CGPoint(x: rect.midX, y: rect.minY + ((outerY + innerY) / 2 - bow) * h))
        path.addLine(to: CGPoint(x: innerX, y: rect.minY + 1.1 * h))
        path.addLine(to: CGPoint(x: outerX, y: rect.minY + 1.1 * h))
        path.closeSubpath()
        // The arc: an eye-sized oval rising from below the eye takes away its lower part.
        let top: CGFloat = 1.15 + (0.346 - 1.15) * crescent
        path.addEllipse(in: CGRect(x: rect.minX + 0.088 * w, y: rect.minY + top * h, width: 0.825 * w, height: 0.846 * h))
        return path
    }
}

/// A teardrop, its point up.
struct KemoSabeTearShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let c = CGPoint(x: rect.midX, y: rect.minY + h * 0.68)
        let r: CGFloat = w / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: c.y), control1: CGPoint(x: rect.midX + w * 0.12, y: rect.minY + h * 0.3),
                      control2: CGPoint(x: rect.maxX, y: rect.minY + h * 0.42))
        path.addArc(center: c, radius: r, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY), control1: CGPoint(x: rect.minX, y: rect.minY + h * 0.42),
                      control2: CGPoint(x: rect.midX - w * 0.12, y: rect.minY + h * 0.3))
        path.closeSubpath()
        return path
    }
}

/// KemoSabe's motion at a moment, worked out from the clock (and the last mood and pointer change)
/// so nothing waits: squash and stretch from the bottom, a lift, a tilt about its base, a sideways
/// lean, lids, where the eyes look and how they're shaped, the mouth, and a tear, hearts or sparkles.
struct KemoSabeMotion: Equatable {
    var squashX: CGFloat = 1
    var squashY: CGFloat = 1
    /// Up, in fractions of its size.
    var lift: CGFloat = 0
    var tilt: Double = 0
    var shift: CGFloat = 0
    /// 0 open, 1 shut.
    var lid: CGFloat = 0
    /// Where the eyes are moved, in fractions of its size.
    var eyeX: CGFloat = 0
    var eyeY: CGFloat = 0
    var eyeScale: CGFloat = 1
    /// The right eye's size against the left (a confused squint).
    var rightEye: CGFloat = 1
    /// 0 to 1: sad lids, low at the outer corners.
    var droop: CGFloat = 0
    /// 0 to 1: happy eyes closed into arcs.
    var crescent: CGFloat = 0
    /// 0 to 1: white glints in the eyes.
    var glint: CGFloat = 0
    /// The mouth's scale (a negative height turns the smile into a frown) and place.
    var mouthX: CGFloat = 1
    var mouthY: CGFloat = 1
    var mouthShift: CGFloat = 0
    var mouthDrop: CGFloat = 0
    var mouthTilt: Double = 0
    /// Each overlay's phase, 0 to 1, or below 0 when it isn't shown.
    var tear: CGFloat = -1
    var hearts: CGFloat = -1
    var sparkle: CGFloat = -1

    /// The pointer as the page reports it.
    struct Pointer: Equatable {
        var gaze: CGPoint = .zero
        var near = false
        var present = false
    }

    /// The last mood change and pointer move, with where the eyes were looking, so the motion eases
    /// from them instead of jumping.
    struct Change: Equatable {
        var mood: WispMood?
        var from: WispMood = .idle
        var moodAt: Double = -1000
        var gazeFrom: CGPoint = .zero
        var gazeTo: CGPoint = .zero
        var nearFrom: CGFloat = 0
        var nearTo: CGFloat = 0
        var gazeAt: Double = -1000

        mutating func moved(to new: WispMood, at t: Double) {
            from = mood ?? from
            mood = new
            moodAt = t
        }

        mutating func looked(at gaze: CGPoint, near: Bool, at t: Double) {
            let now = looking(t)
            gazeFrom = now.gaze; nearFrom = now.near
            gazeTo = gaze; nearTo = near ? 1 : 0
            gazeAt = t
        }

        /// Where the eyes look at `t`, easing toward the pointer over a quarter second.
        func looking(_ t: Double) -> (gaze: CGPoint, near: CGFloat) {
            let a = CGFloat(KemoSabeMotion.ease(min(1, max(0, (t - gazeAt) / 0.28))))
            return (CGPoint(x: gazeFrom.x + (gazeTo.x - gazeFrom.x) * a, y: gazeFrom.y + (gazeTo.y - gazeFrom.y) * a),
                    nearFrom + (nearTo - nearFrom) * a)
        }
    }

    /// Hops, chatter, hearts and sparkles at 30 frames a second; the calm moods at 20.
    static func framesPerSecond(_ mood: WispMood) -> Double {
        switch mood {
        case .happy, .love, .celebrating, .speaking: return 30
        default: return 20
        }
    }

    /// The mood's still pose (Reduce Motion and the colour cards).
    static func still(_ mood: WispMood) -> KemoSabeMotion {
        var m = KemoSabeMotion()
        switch mood {
        case .idle: break
        case .listening:
            m.tilt = 4; m.eyeScale = 1.05; m.eyeY = -0.006
        case .thinking:
            m.lid = 0.22; m.eyeX = 0.016; m.eyeY = -0.014
            m.mouthX = 0.7; m.mouthY = 0.5; m.mouthShift = 0.012
        case .speaking:
            m.mouthY = 1.3
        case .happy, .love, .celebrating:
            m.squashY = 1.02; m.squashX = 0.99
            m.crescent = 1; m.eyeY = 0.0125
            m.mouthX = 1.25; m.mouthY = 1.35; m.mouthDrop = -0.002
            if mood == .love { m.hearts = 0.35 }
            if mood == .celebrating { m.sparkle = 0.3 }
        case .surprised:
            m.squashY = 1.04; m.squashX = 0.98; m.lift = 0.02
            m.eyeScale = 1.14; m.glint = 1
            m.mouthX = 0.55; m.mouthY = 1.5; m.mouthDrop = 0.004
        case .sleepy:
            m.lid = 0.62; m.tilt = 5; m.squashY = 0.975; m.squashX = 1.015
            m.mouthX = 0.8; m.mouthY = 0.5
        case .confused:
            m.tilt = -7; m.rightEye = 0.82
            m.mouthX = 0.8; m.mouthY = 0.4; m.mouthTilt = -10
        case .sad:
            // Slumped a little, lids drooping, looking down, eyes wet, the smile turned over, a tear.
            m.squashY = 0.96; m.squashX = 1.03; m.tilt = -2
            m.droop = 1; m.glint = 1; m.eyeY = 0.0146
            m.mouthX = 0.82; m.mouthY = -0.9; m.mouthDrop = 0.0125
            m.tear = 0.42
        }
        return m
    }

    /// The motion at `t`. Live, `change` eases from the last mood (with a little reaction) and the
    /// pointer turns the eyes; captures pass only `t` and the mood.
    static func at(_ t: Double, mood: WispMood, change: Change? = nil, pointer: Pointer = Pointer()) -> KemoSabeMotion {
        let look: (gaze: CGPoint, near: CGFloat) = change.map { $0.looking(t) } ?? (gaze: pointer.gaze, near: pointer.near ? 1 : 0)
        var m = pose(t, mood: mood, gaze: look.gaze, near: look.near, pointer: pointer.present)
        guard let change, change.mood != nil else { return m }
        let since = t - change.moodAt
        guard since >= 0, since < 0.7 else { return m }
        if since < 0.35, change.from != mood {
            let before = pose(t, mood: change.from, gaze: look.gaze, near: look.near, pointer: pointer.present)
            m = before.mixed(with: m, CGFloat(ease(since / 0.35)))
        }
        m.react(since, from: change.from, to: mood)
        return m
    }

    private static func pose(_ t: Double, mood: WispMood, gaze: CGPoint, near: CGFloat, pointer: Bool) -> KemoSabeMotion {
        var m = still(mood)
        let breath: Double
        switch mood {
        case .sleepy:
            // Slow, deep breaths, the lids heavier at the bottom of each.
            breath = 1.3 * sin(t * 1.1)
            m.lid = 0.55 + 0.3 * CGFloat(0.5 + 0.5 * sin(t * 0.55))
            m.tilt = 5 + 1.5 * sin(t * 0.4)
        case .thinking:
            // Pondering: a slow sway, rising and settling, eyes up and drifting from side to side.
            breath = sin(t * 1.5)
            m.tilt = 3.5 * sin(t * 1.2)
            m.lift = CGFloat(0.012 * (1 + sin(t * 1.1)))
            m.eyeX = 0.018 * CGFloat(tanh(2.5 * sin(t * 1.1)))
            m.mouthShift = 0.012 * CGFloat(tanh(2.5 * sin(t * 1.1)))
        case .happy, .love, .celebrating:
            breath = 0
            let hop = hopShape(t, period: mood == .celebrating ? 0.9 : 1.4)
            m.lift = CGFloat(hop.lift) * (mood == .celebrating ? 0.09 : 0.06)
            m.squashY = 1 - CGFloat(hop.squash) * 0.07
            m.squashX = 1 + CGFloat(hop.squash) * 0.06
            m.mouthY *= 1 + 0.08 * CGFloat(hop.lift)
            if mood == .love {
                m.tilt = 3 * sin(t * 2.2)
                m.hearts = CGFloat((t / 2.4).truncatingRemainder(dividingBy: 1))
            }
            if mood == .celebrating { m.sparkle = CGFloat((t / 1.8).truncatingRemainder(dividingBy: 1)) }
        case .speaking:
            breath = 0
            // Chatter, uneven like speech: the body squashes a touch as the mouth opens.
            let chatter = abs(sin(t * 9)) * (0.6 + 0.4 * abs(sin(t * 2.3)))
            m.squashY = 1 - CGFloat(chatter) * 0.025
            m.squashX = 1 + CGFloat(chatter) * 0.015
            m.mouthY = 0.9 + 0.75 * CGFloat(chatter)
            m.mouthX = 1.02 - 0.12 * CGFloat(chatter)
        case .confused:
            breath = sin(t * 1.9)
            m.tilt = -7 + 1.5 * sin(t * 0.9)
        case .sad:
            // Slow breaths with a sigh now and then, a slight sway, and a tear every few seconds.
            let cycle = (t / 6.5).truncatingRemainder(dividingBy: 1)
            let sigh = cycle < 0.25 ? sin(.pi * cycle / 0.25) : 0
            breath = 0.8 * sin(t * 1.0) + 1.6 * sigh
            m.tilt = -2 + 1.2 * sin(t * 0.6)
            m.eyeY += 0.003 * CGFloat(sin(t * 1.0))
            m.tear = CGFloat((t / 4.2).truncatingRemainder(dividingBy: 1))
        case .idle:
            breath = sin(t * 1.9)
            // A gentle sway, so it's never quite still.
            m.tilt = 0.9 * sin(t * 0.7)
        default:
            breath = sin(t * 1.9)
        }
        m.squashX *= 1 + 0.012 * CGFloat(breath)
        m.squashY *= 1 - 0.018 * CGFloat(breath)
        if ![WispMood.sleepy, .surprised, .happy, .love, .celebrating].contains(mood) {
            let beat = blinkAndGlance(t, glances: mood == .idle && !pointer)
            m.lid = max(m.lid, beat.lid)
            m.shift += beat.lean * 0.025
            m.tilt += Double(beat.lean) * 3
            m.eyeX += beat.lean * 0.02
            m.lift += beat.bob * 0.03
            m.squashY *= 1 + beat.bob * 0.02
        }
        if mood != .thinking, mood != .sleepy {
            // Eyes slide toward the pointer and the body leans into it; close by, the eyes widen.
            m.eyeX += gaze.x * 0.022
            m.eyeY += gaze.y * 0.014
            m.tilt += Double(gaze.x) * 2.2
            m.shift += gaze.x * 0.008
            m.eyeScale *= 1 + 0.06 * near
        }
        return m
    }

    /// `self` moved `amount` (0...1) of the way to `other`; the overlays are the new mood's, faded in.
    func mixed(with other: KemoSabeMotion, _ amount: CGFloat) -> KemoSabeMotion {
        func m(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * amount }
        var out = other
        out.squashX = m(squashX, other.squashX); out.squashY = m(squashY, other.squashY)
        out.lift = m(lift, other.lift); out.tilt = tilt + (other.tilt - tilt) * Double(amount)
        out.shift = m(shift, other.shift); out.lid = m(lid, other.lid)
        out.eyeX = m(eyeX, other.eyeX); out.eyeY = m(eyeY, other.eyeY)
        out.eyeScale = m(eyeScale, other.eyeScale); out.rightEye = m(rightEye, other.rightEye)
        out.droop = m(droop, other.droop); out.crescent = m(crescent, other.crescent); out.glint = m(glint, other.glint)
        out.mouthX = m(mouthX, other.mouthX); out.mouthY = m(mouthY, other.mouthY)
        out.mouthShift = m(mouthShift, other.mouthShift); out.mouthDrop = m(mouthDrop, other.mouthDrop)
        out.mouthTilt = mouthTilt + (other.mouthTilt - mouthTilt) * Double(amount)
        return out
    }

    /// A reaction to a new mood, `since` seconds in: a hop for good news (and when an answer
    /// arrives after thinking), a jump when startled, a sinking when sad, else a little wobble.
    private mutating func react(_ since: Double, from: WispMood, to: WispMood) {
        guard from != to else { return }
        let cheerful: Bool = [WispMood.happy, .love, .celebrating].contains(to) || (from == .thinking && (to == .idle || to == .speaking))
        if cheerful {
            if since < 0.4 {
                let k = CGFloat(sin(.pi * since / 0.4))
                lift += 0.055 * k; squashY *= 1 + 0.04 * k; squashX *= 1 - 0.03 * k
            } else if since < 0.62 {
                let k = CGFloat(sin(.pi * (since - 0.4) / 0.22))
                squashY *= 1 - 0.07 * k; squashX *= 1 + 0.06 * k
            }
        } else if to == .surprised {
            let k = CGFloat(since < 0.3 ? sin(.pi * since / 0.3) : 0)
            squashY *= 1 + 0.08 * k; squashX *= 1 - 0.05 * k; lift += 0.02 * k
        } else if to == .sad {
            let k = CGFloat(since < 0.6 ? sin(.pi * since / 0.6) : 0)
            squashY *= 1 - 0.04 * k; squashX *= 1 + 0.03 * k
        } else {
            tilt += 2.5 * sin(since * 16) * exp(-since * 6)
        }
    }

    static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// A hop each period: up and down, a squash on landing and a little one before take-off.
    private static func hopShape(_ t: Double, period: Double) -> (lift: Double, squash: Double) {
        let p = (t / period).truncatingRemainder(dividingBy: 1)
        if p < 0.45 { return (sin(.pi * p / 0.45), 0) }
        if p < 0.6 { return (0, sin(.pi * (p - 0.45) / 0.15)) }
        if p > 0.85 { return (0, 0.4 * sin(.pi * (p - 0.85) / 0.15)) }
        return (0, 0)
    }

    /// Wisp's rhythm without its task: one beat every 2.6 to 5.2 s, a blink (sometimes two), and
    /// at idle every third beat a glance to one side for 1.3 s instead, and every fifth a little bob.
    private static func blinkAndGlance(_ t: Double, glances: Bool) -> (lid: CGFloat, lean: CGFloat, bob: CGFloat) {
        let slot = 3.9
        let n = Int(floor(t / slot))
        var lid: CGFloat = 0, lean: CGFloat = 0, bob: CGFloat = 0
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
            if glances, k % 5 == 1, since >= 0, since < 0.5 {
                bob = CGFloat(sin(.pi * since / 0.5))
            }
            let twice = noise(k + 101) < 0.2
            for offset in twice ? [0, 0.3] : [0] {
                let s = since - offset
                guard s >= 0, s < 0.22 else { continue }
                let shut = s < 0.07 ? s / 0.07 : s < 0.1 ? 1 : 1 - (s - 0.1) / 0.12
                lid = max(lid, CGFloat(shut))
            }
        }
        return (lid, lean, bob)
    }

    private static func noise(_ n: Int) -> Double {
        let x = sin(Double(n) * 12.9898 + 78.233) * 43758.5453
        return x - floor(x)
    }
}
