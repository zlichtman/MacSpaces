import SwiftUI
import AppKit

/// Wisp's face: two eyes floating on the Nook, with no head, tile or border. They're white on
/// a dark Nook (glass included) and black on a light one. The eyes are the character: rounded
/// shapes that grow, squash, stretch, slant, slide toward the pointer and overshoot, and turn
/// into arcs, lines, hearts and stars, with a small smile under them that changes with the mood.
/// Every mood is one still pose (`WispPose`); blinks, glances, mood changes and the pointer are
/// short spring transitions between poses, and nothing runs between them: a blink every few
/// seconds, now and then a glance, eyes that turn and lean toward the pointer as it moves and
/// widen as it comes close, a startle when poked, and a mouth that opens and closes while
/// speaking. Reduce Motion shows the poses only. After an action a small glyph shows beside the
/// eyes (`WispModel.prop`); shades go over them.
struct WispFace: View {
    var mood: WispMood
    var size: CGFloat
    /// Where the eyes look, each axis -1...1 (nil: straight ahead, glancing now and then).
    var gaze: CGPoint? = nil
    /// The pointer is close: the eyes widen.
    var near = false
    /// The pointer is on the eyes: they open wide and brighten up.
    var curious = false
    /// Captures: draw exactly this, with no live blinks or chatter and no model prop.
    var preview: Preview? = nil

    struct Preview {
        var prop: WispProp? = nil
        /// 0 open, 1 shut.
        var blink: CGFloat = 0
        var glance: CGPoint? = nil
        /// Speaking: the mouth open, or closed between words.
        var mouthOpen = true
    }

    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var model = WispModel.shared
    @State private var blink: CGFloat = 0
    @State private var glance: CGPoint?
    @State private var mouthOpen = true

    private var live: Bool { preview == nil && !theme.reduceMotion }

    /// What restarts the blink loop: it runs only live, in a mood that blinks, with the pointer off the page.
    private struct Rhythm: Equatable {
        let live: Bool, mood: WispMood, pointerAway: Bool, shades: Bool
    }

    private var shownProp: WispProp? {
        if let preview { return preview.prop }
        return model.prop?.prop
    }

    private func currentPose(prop: WispProp?) -> WispPose {
        var look: CGPoint? = gaze ?? preview?.glance ?? glance
        var close = near
        if theme.reduceMotion, preview == nil { look = nil; close = false }
        let shut: CGFloat = preview?.blink ?? blink
        let open: Bool = preview?.mouthOpen ?? mouthOpen
        return WispPose(mood: mood, near: close, curious: curious, gaze: look, blink: shut, mouthOpen: open, prop: prop)
    }

    var body: some View {
        let prop = shownProp
        let pose = currentPose(prop: prop)
        WispFaceArt(pose: pose, size: size, style: .current(theme), prop: prop)
            .animation(live ? .spring(response: 0.36, dampingFraction: 0.58) : nil, value: mood)
            .animation(live ? .spring(response: 0.3, dampingFraction: 0.62) : nil, value: curious)
            .animation(live ? .spring(response: 0.34, dampingFraction: 0.68) : nil, value: near)
            .animation(live ? .spring(response: 0.26, dampingFraction: 0.72) : nil, value: gaze)
            .animation(live ? .spring(response: 0.4, dampingFraction: 0.72) : nil, value: prop)
            .task(id: Rhythm(live: live, mood: mood, pointerAway: gaze == nil, shades: prop == .shades)) {
                guard live, WispPose.blinks(mood), prop != .shades, WispFaceCost.blinking else { blink = 0; glance = nil; return }
                await blinking(glances: gaze == nil && mood == .idle)
            }
            .task(id: live && mood == .speaking) {
                guard live, mood == .speaking else { mouthOpen = true; return }
                await chattering()
            }
            .accessibilityElement()
            .accessibilityLabel(WispPose.words(mood).map { "Wisp, " + $0 } ?? "Wisp")
    }

    /// A blink every few seconds (sometimes two), and with nothing else going on a glance aside
    /// every few blinks. Between them the task sleeps and nothing draws.
    private func blinking(glances: Bool) async {
        var count = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 2.6...5.2) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            count += 1
            if glances, count % 3 == 0 {
                let side: CGFloat = Bool.random() ? 1 : -1
                let up: CGFloat = Bool.random() ? -0.4 : 0.3
                withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { glance = CGPoint(x: 0.85 * side, y: up) }
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { glance = nil }
                continue
            }
            let twice = Double.random(in: 0...1) < 0.2
            for _ in 0..<(twice ? 2 : 1) {
                withAnimation(.easeIn(duration: 0.07)) { blink = 1 }
                try? await Task.sleep(nanoseconds: 100_000_000)
                withAnimation(.easeOut(duration: 0.12)) { blink = 0 }
                try? await Task.sleep(nanoseconds: 170_000_000)
            }
        }
    }

    /// Speaking: the mouth opens and closes at a talking pace, each a quick transition.
    private func chattering() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.12...0.24) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.09)) { mouthOpen.toggle() }
        }
    }
}

// MARK: Cost switches

/// What the wisp scope's cost cases switch off to find what the face costs. The shipping face
/// keeps the defaults.
@MainActor enum WispFaceCost {
    #if DEBUG
    static var blinking = true
    #else
    static let blinking = true
    #endif
}

// MARK: Poses

/// One still pose of the eyes, in fractions of the face's size (and degrees). Each mood is one;
/// the view springs between them, and captures can mix two (`mixed`).
struct WispPose: Equatable {
    var eyeWidth: CGFloat = 0.3
    var eyeHeight: CGFloat = 0.5
    /// The eyes' corner radius against half their width: 1 a round end, smaller a rounder rectangle.
    var round: CGFloat = 0.85
    /// 0 a plain eye, 1 a thick rounded arc in its place (happy ^, or closed).
    var arc: CGFloat = 0
    /// The arc's bend: 1 a ^ (happy), -1 a gentle cup (closed and content).
    var bend: CGFloat = 1
    /// 1 open, 0 shut to a line.
    var open: CGFloat = 1
    /// Each eye's height against the pose's (one smaller when confused; the far one smaller when looking aside).
    var leftScale: CGFloat = 1
    var rightScale: CGFloat = 1
    /// How far each eye's top drops at its outer corner (negative: at its inner corner), against its height.
    var leftSlant: CGFloat = 0
    var rightSlant: CGFloat = 0
    /// Half the distance between the eyes' centres.
    var spread: CGFloat = 0.235
    /// 1 heart eyes, 1 star eyes.
    var heart: CGFloat = 0
    var star: CGFloat = 0
    /// Where the eyes sit, from the middle.
    var x: CGFloat = 0
    var y: CGFloat = -0.04
    /// The pair's lean, in degrees.
    var tilt: Double = 0
    /// The smile under the eyes: its width and how far its top and bottom edges bow down at the
    /// middle (equal: a line; negative top: an o).
    var mouthWidth: CGFloat = 0.14
    var mouthTop: CGFloat = 0.035
    var mouthBottom: CGFloat = 0.035
    /// Extras, each 0 (gone) to 1.
    var shades: CGFloat = 0
    var zzz: CGFloat = 0

    init() {}

    init(mood: WispMood, near: Bool = false, curious: Bool = false, gaze: CGPoint? = nil, blink: CGFloat = 0,
         mouthOpen: Bool = true, prop: WispProp? = nil) {
        switch mood {
        case .idle:
            if curious {
                eyeWidth = 0.36; eyeHeight = 0.62; spread = 0.26; round = 0.95
            } else if near {
                eyeWidth = 0.33; eyeHeight = 0.56; spread = 0.25
            }
        case .listening:
            eyeWidth = 0.31; eyeHeight = 0.6; round = 0.95
            y = -0.06
        case .thinking:
            eyeWidth = 0.31; eyeHeight = 0.3
            x = 0.14; y = -0.14
            rightScale = 1.12
            tilt = -6
            mouthWidth = 0.08; mouthTop = 0; mouthBottom = 0
        case .speaking:
            eyeWidth = 0.29; eyeHeight = 0.44; y = -0.1
            mouthWidth = 0.13
            mouthTop = mouthOpen ? 0.0 : 0.02
            mouthBottom = mouthOpen ? 0.075 : 0.03
        case .happy:
            arc = 1; eyeWidth = 0.3; eyeHeight = 0.3
            y = -0.07
            mouthWidth = 0.17; mouthTop = 0.055; mouthBottom = 0.055
        case .celebrating:
            star = 1
            eyeWidth = 0.34; eyeHeight = 0.34; spread = 0.25
            y = -0.06
            mouthWidth = 0.17; mouthTop = 0.01; mouthBottom = 0.08
        case .surprised:
            eyeWidth = 0.38; eyeHeight = 0.6; round = 1; spread = 0.27
            y = -0.15
            mouthWidth = 0.055; mouthTop = -0.035; mouthBottom = 0.035
        case .sleepy:
            arc = 1; bend = -1; open = 0; eyeWidth = 0.3
            y = 0.06
            tilt = 4
            mouthWidth = 0.08; mouthTop = 0; mouthBottom = 0
            zzz = 1
        case .confused:
            eyeWidth = 0.3; eyeHeight = 0.5
            rightScale = 0.5
            x = -0.03
            tilt = 8
            mouthWidth = 0.1; mouthTop = 0; mouthBottom = 0
        case .love:
            heart = 1
            eyeWidth = 0.36; eyeHeight = 0.36; spread = 0.25
            tilt = -4
            mouthWidth = 0.14; mouthTop = 0.045; mouthBottom = 0.045
        }
        var look: CGPoint?
        if let gaze, mood != .thinking, mood != .sleepy {
            look = CGPoint(x: max(-1, min(1, gaze.x)), y: max(-1, min(1, gaze.y)))
        } else if let prop, prop != .shades, mood != .sleepy, mood != .thinking {
            // A look at what it's holding up, off to the bottom right (a glance, hardly a slide,
            // so the eyes keep clear of it).
            look = CGPoint(x: 0.3, y: 0.6)
        }
        if let look {
            // Slide toward it, lean into it, and the far eye gets a little smaller, as if turning.
            x += look.x * 0.16
            y += look.y * 0.1
            tilt += Double(look.x * 5)
            leftScale *= 1 + look.x * 0.12
            rightScale *= 1 - look.x * 0.12
        }
        if Self.blinks(mood) { open *= 1 - 0.93 * min(1, max(0, blink)) }
        if prop == .shades { shades = 1 }
    }

    /// Moods whose eyes blink (arcs, hearts and stars don't).
    static func blinks(_ mood: WispMood) -> Bool {
        ![.happy, .celebrating, .sleepy, .love].contains(mood)
    }

    /// For VoiceOver.
    static func words(_ mood: WispMood) -> String? {
        switch mood {
        case .idle: return nil
        case .listening: return "listening"
        case .thinking: return "thinking"
        case .speaking: return "talking"
        case .happy: return "happy"
        case .celebrating: return "celebrating"
        case .surprised: return "surprised"
        case .sleepy: return "dozing"
        case .confused: return "confused"
        case .love: return "pleased"
        }
    }

    /// `self` moved `amount` (0...1) of the way to `other`, as an animation passes through it.
    func mixed(with other: WispPose, _ amount: CGFloat) -> WispPose {
        func m(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * amount }
        var pose = self
        pose.eyeWidth = m(eyeWidth, other.eyeWidth); pose.eyeHeight = m(eyeHeight, other.eyeHeight)
        pose.round = m(round, other.round); pose.arc = m(arc, other.arc); pose.bend = m(bend, other.bend); pose.open = m(open, other.open)
        pose.leftScale = m(leftScale, other.leftScale); pose.rightScale = m(rightScale, other.rightScale)
        pose.leftSlant = m(leftSlant, other.leftSlant); pose.rightSlant = m(rightSlant, other.rightSlant)
        pose.spread = m(spread, other.spread); pose.heart = m(heart, other.heart); pose.star = m(star, other.star)
        pose.x = m(x, other.x); pose.y = m(y, other.y)
        pose.tilt = tilt + (other.tilt - tilt) * Double(amount)
        pose.mouthWidth = m(mouthWidth, other.mouthWidth)
        pose.mouthTop = m(mouthTop, other.mouthTop); pose.mouthBottom = m(mouthBottom, other.mouthBottom)
        pose.shades = m(shades, other.shades); pose.zzz = m(zzz, other.zzz)
        return pose
    }
}

// MARK: Colours

/// Plain black and white: white eyes on a dark Nook (glass and Clear included), black on a
/// light one. The theme's accent shows only as emotion (the hearts).
struct WispFaceStyle {
    var eye: Color
    /// What's behind the eyes, for the lines cut into a glyph.
    var behind: Color
    var heart: Color

    @MainActor static func current(_ theme: ThemeStore) -> WispFaceStyle {
        let light = theme.nookScheme == .light
        let eye: Color = light ? .black : .white
        let behind: Color = light ? .white : .black
        return WispFaceStyle(eye: eye, behind: behind, heart: theme.notch.accent)
    }
}

// MARK: Drawing

/// The eyes in one pose: plain SwiftUI shapes whose sizes and places animate between poses.
/// Nothing here runs a clock.
struct WispFaceArt: View {
    let pose: WispPose
    let size: CGFloat
    let style: WispFaceStyle
    var prop: WispProp? = nil

    /// The poses' unit: the eyes are drawn big for the space they're given, and may reach past it.
    private var unit: CGFloat { size * 1.3 }

    var body: some View {
        ZStack {
            ZStack {
                eye(scale: pose.leftScale, slant: pose.leftSlant)
                    .offset(x: -pose.spread * unit)
                eye(scale: pose.rightScale, slant: -pose.rightSlant)
                    .offset(x: pose.spread * unit)
                mouth
                    .offset(y: mouthY)
                shades
            }
            .rotationEffect(.degrees(pose.tilt))
            .offset(x: pose.x * unit, y: pose.y * unit)
            zzz
            if let prop, prop != .shades {
                // Off to the side, clear of the eyes and the smile.
                WispPropGlyph(prop: prop, side: size * 0.2, style: style)
                    .offset(x: size * 0.76, y: size * 0.42)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: size * 1.45, height: size * 1.15)
    }

    /// The smile sits under the eyes, a little lower when they're tall.
    private var mouthY: CGFloat {
        let tallest: CGFloat = pose.eyeHeight * max(pose.leftScale, pose.rightScale) * (1 - pose.arc)
        return unit * max(0.3, tallest * 0.5 + 0.07)
    }

    /// One eye: the morphing shape, or a thick rounded arc, a heart or a star in its place.
    private func eye(scale: CGFloat, slant: CGFloat) -> some View {
        let w: CGFloat = pose.eyeWidth * unit
        let h: CGFloat = pose.eyeHeight * unit * scale
        let shape = WispEyeShape(width: w, height: h, round: pose.round, open: pose.open, slant: slant)
        let arcLine = StrokeStyle(lineWidth: unit * 0.085, lineCap: .round, lineJoin: .round)
        let arcHeight: CGFloat = unit * (0.08 + 0.06 * max(0, pose.bend))
        let mark: CGFloat = min(1, pose.heart + pose.star + pose.arc)
        let plain: Double = Double(max(0, 1 - mark * 3))
        let plainShrink: CGFloat = 1 - 0.75 * mark
        let heartGrow: CGFloat = 0.3 + 0.7 * pose.heart
        let starGrow: CGFloat = 0.3 + 0.7 * pose.star
        let markSide: CGFloat = pose.eyeWidth * unit * 1.15
        return ZStack {
            shape.fill(style.eye).scaleEffect(plainShrink).opacity(plain)
            WispArcShape(bend: pose.bend)
                .stroke(style.eye, style: arcLine)
                .frame(width: w * 0.92, height: arcHeight)
                .scaleEffect(0.5 + 0.5 * pose.arc)
                .opacity(Double(min(1, pose.arc * 2.5)))
            WispHeart()
                .fill(style.heart)
                .frame(width: markSide, height: markSide * 0.92)
                .scaleEffect(heartGrow)
                .opacity(Double(min(1, pose.heart * 2.5)))
            WispStar()
                .fill(style.eye)
                .frame(width: markSide, height: markSide)
                .scaleEffect(starGrow)
                .rotationEffect(.degrees(Double(pose.star) * 12 - 12))
                .opacity(Double(min(1, pose.star * 2.5)))
        }
        .frame(width: unit * 0.5, height: unit * 0.75)
    }

    private var mouth: some View {
        let shape = WispMouthShape(width: pose.mouthWidth * unit, top: pose.mouthTop * unit, bottom: pose.mouthBottom * unit)
        let line = StrokeStyle(lineWidth: unit * 0.038, lineCap: .round, lineJoin: .round)
        return ZStack {
            shape.fill(style.eye)
            shape.stroke(style.eye, style: line)
        }
        .frame(width: unit * 0.3, height: unit * 0.2)
    }

    /// Shades over the eyes, sliding down from above.
    private var shades: some View {
        let drop: CGFloat = (1 - pose.shades) * unit * 0.3
        let bridgeW: CGFloat = unit * 0.1, bridgeH: CGFloat = unit * 0.03
        return ZStack {
            lens.offset(x: -unit * 0.2)
            lens.offset(x: unit * 0.2)
            Capsule().fill(style.eye).frame(width: bridgeW, height: bridgeH).offset(y: -unit * 0.06)
        }
        .offset(y: -drop)
        .opacity(Double(pose.shades))
    }

    private var lens: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.08, style: .continuous)
        let rimWidth: CGFloat = unit * 0.03
        let glintW: CGFloat = unit * 0.03, glintH: CGFloat = unit * 0.12
        return ZStack {
            shape.fill(Color.black)
            shape.strokeBorder(style.eye, lineWidth: rimWidth)
            Capsule().fill(Color.white.opacity(0.8)).frame(width: glintW, height: glintH)
                .rotationEffect(.degrees(35)).offset(x: -unit * 0.06, y: -unit * 0.03)
        }
        .frame(width: unit * 0.36, height: unit * 0.3)
    }

    private var zzz: some View {
        let big: CGFloat = size * 0.17, small: CGFloat = size * 0.12
        let drift: CGFloat = (1 - pose.zzz) * size * 0.1
        return ZStack {
            Text("z").font(.system(size: big, weight: .heavy, design: .rounded))
            Text("z").font(.system(size: small, weight: .heavy, design: .rounded))
                .offset(x: size * 0.13, y: -size * 0.13)
        }
        .foregroundStyle(style.eye)
        .offset(x: size * 0.5, y: -size * 0.28 + drift)
        .opacity(Double(pose.zzz))
    }
}

/// An eye: a rounded rectangle whose top can slant like a lid, and which shuts to a rounded
/// line a little below its middle. Nothing is ever cut out of it.
struct WispEyeShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var round: CGFloat
    var open: CGFloat
    var slant: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { AnimatablePair(AnimatablePair(width, height), AnimatablePair(round, AnimatablePair(open, slant))) }
        set {
            width = newValue.first.first; height = newValue.first.second
            round = newValue.second.first
            open = newValue.second.second.first; slant = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let o: CGFloat = max(0.06, min(1, open))
        let h: CGFloat = max(width * 0.12, height * o)
        let cx: CGFloat = rect.midX
        let cy: CGFloat = rect.midY + (height - h) * 0.18
        let x0: CGFloat = cx - width / 2, x1: CGFloat = cx + width / 2
        let y0: CGFloat = cy - h / 2, y1: CGFloat = cy + h / 2
        // The lid: the outer (left) corner drops for a positive slant, the inner for a negative one.
        let drop: CGFloat = slant * h * 0.45
        let yl: CGFloat = y0 + max(0, drop), yr: CGFloat = y0 + max(0, -drop)
        let shortest: CGFloat = min(width, y1 - max(yl, yr))
        let r: CGFloat = max(0, min(shortest / 2, width / 2 * round))
        var path = Path()
        // Corners as circle quarters (cubic, k = 0.552).
        let k: CGFloat = 0.448
        path.move(to: CGPoint(x: x0, y: yl + r))
        path.addCurve(to: CGPoint(x: x0 + r, y: yl), control1: CGPoint(x: x0, y: yl + r * k), control2: CGPoint(x: x0 + r * k, y: yl))
        path.addLine(to: CGPoint(x: x1 - r, y: yr))
        path.addCurve(to: CGPoint(x: x1, y: yr + r), control1: CGPoint(x: x1 - r * k, y: yr), control2: CGPoint(x: x1, y: yr + r * k))
        path.addLine(to: CGPoint(x: x1, y: y1 - r))
        path.addCurve(to: CGPoint(x: x1 - r, y: y1), control1: CGPoint(x: x1, y: y1 - r * k), control2: CGPoint(x: x1 - r * k, y: y1))
        path.addLine(to: CGPoint(x: x0 + r, y: y1))
        path.addCurve(to: CGPoint(x: x0, y: y1 - r), control1: CGPoint(x: x0 + r * k, y: y1), control2: CGPoint(x: x0, y: y1 - r * k))
        path.closeSubpath()
        return path
    }
}

/// A happy or closed eye: one curve to be stroked thick with round caps. A bend of 1 is a ^,
/// -1 a gentle cup.
struct WispArcShape: Shape {
    var bend: CGFloat

    var animatableData: CGFloat {
        get { bend }
        set { bend = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let ends: CGFloat = rect.midY + bend * rect.height / 2
        let control: CGFloat = rect.midY - bend * rect.height * 1.5
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: ends))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: ends), control: CGPoint(x: rect.midX, y: control))
        return path
    }
}

/// The mouth: a top and a bottom edge, each bowing down at the middle by its own amount. Equal
/// edges are a line; a lower bottom opens it.
struct WispMouthShape: Shape {
    var width: CGFloat
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(width, AnimatablePair(top, bottom)) }
        set { width = newValue.first; top = newValue.second.first; bottom = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.15)
        let half: CGFloat = width / 2
        // Cubic control points at 4/3 of the bow put the edge's middle at the bow.
        let t: CGFloat = top * 4 / 3, b: CGFloat = bottom * 4 / 3
        var path = Path()
        path.move(to: CGPoint(x: c.x - half, y: c.y))
        path.addCurve(to: CGPoint(x: c.x + half, y: c.y), control1: CGPoint(x: c.x - half / 2, y: c.y + t),
                      control2: CGPoint(x: c.x + half / 2, y: c.y + t))
        path.addCurve(to: CGPoint(x: c.x - half, y: c.y), control1: CGPoint(x: c.x + half / 2, y: c.y + b),
                      control2: CGPoint(x: c.x - half / 2, y: c.y + b))
        path.closeSubpath()
        return path
    }
}

struct WispHeart: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.95))
        path.addCurve(to: CGPoint(x: x, y: y + h * 0.32), control1: CGPoint(x: x + w * 0.2, y: y + h * 0.72), control2: CGPoint(x: x, y: y + h * 0.55))
        path.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.2), control1: CGPoint(x: x, y: y + h * 0.02), control2: CGPoint(x: x + w * 0.4, y: y))
        path.addCurve(to: CGPoint(x: x + w, y: y + h * 0.32), control1: CGPoint(x: x + w * 0.6, y: y), control2: CGPoint(x: x + w, y: y + h * 0.02))
        path.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.95), control1: CGPoint(x: x + w, y: y + h * 0.55), control2: CGPoint(x: x + w * 0.8, y: y + h * 0.72))
        path.closeSubpath()
        return path
    }
}

/// A five-pointed star with softly rounded points.
struct WispStar: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.04)
        let outer: CGFloat = min(rect.width, rect.height) / 2, inner: CGFloat = outer * 0.48
        var points: [CGPoint] = []
        for index in 0..<10 {
            let radius: CGFloat = index % 2 == 0 ? outer : inner
            let angle: Double = Double(index) * .pi / 5 - .pi / 2
            points.append(CGPoint(x: c.x + radius * CGFloat(cos(angle)), y: c.y + radius * CGFloat(sin(angle))))
        }
        var path = Path()
        // Each point rounded: run between the midpoints of the edges, curving through the corners.
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: mid(points[9], points[0]))
        for index in 0..<10 {
            path.addQuadCurve(to: mid(points[index], points[(index + 1) % 10]), control: points[index])
        }
        path.closeSubpath()
        return path
    }
}

// MARK: Props

/// A prop as a tiny glyph beside the eyes, in the eye colour with nothing round it: a mug for a
/// tea timer, a stopwatch for a timer, a bell for a reminder, a page for a note.
struct WispPropGlyph: View {
    let prop: WispProp
    let side: CGFloat
    let style: WispFaceStyle

    var body: some View {
        glyph.frame(width: side, height: side)
    }

    @ViewBuilder private var glyph: some View {
        let ink = style.eye
        switch prop {
        case .mug:
            ZStack {
                UnitShape { r in Path(roundedRect: r.unit(0.1, 0.38, 0.58, 0.54), cornerRadius: r.width * 0.12) }.fill(ink)
                UnitShape { r in Path(ellipseIn: r.unit(0.56, 0.48, 0.32, 0.3)) }
                    .stroke(ink, lineWidth: side * 0.11)
                UnitShape { r in
                    var path = Path()
                    for x in [0.28, 0.5] as [CGFloat] {
                        path.move(to: r.point(x, 0.3))
                        path.addCurve(to: r.point(x, 0.02), control1: r.point(x - 0.09, 0.2), control2: r.point(x + 0.09, 0.12))
                    }
                    return path
                }
                .stroke(ink.opacity(0.75), style: StrokeStyle(lineWidth: side * 0.08, lineCap: .round))
            }
        case .stopwatch:
            ZStack {
                UnitShape { r in Path(ellipseIn: r.unit(0.12, 0.2, 0.76, 0.76)) }.stroke(ink, lineWidth: side * 0.12)
                UnitShape { r in Path(roundedRect: r.unit(0.4, 0.0, 0.2, 0.14), cornerRadius: r.width * 0.04) }.fill(ink)
                UnitShape { r in
                    var path = Path()
                    path.move(to: r.point(0.5, 0.58)); path.addLine(to: r.point(0.66, 0.4))
                    return path
                }
                .stroke(ink, style: StrokeStyle(lineWidth: side * 0.1, lineCap: .round))
            }
        case .bell:
            ZStack {
                UnitShape { r in
                    var path = Path()
                    path.move(to: r.point(0.06, 0.76))
                    path.addCurve(to: r.point(0.5, 0.06), control1: r.point(0.24, 0.62), control2: r.point(0.14, 0.06))
                    path.addCurve(to: r.point(0.94, 0.76), control1: r.point(0.86, 0.06), control2: r.point(0.76, 0.62))
                    path.closeSubpath()
                    return path
                }
                .fill(ink)
                UnitShape { r in Path(ellipseIn: r.unit(0.38, 0.8, 0.24, 0.2)) }.fill(ink)
            }
        case .note:
            ZStack {
                UnitShape { r in Path(roundedRect: r.unit(0.16, 0.04, 0.68, 0.92), cornerRadius: r.width * 0.1) }.fill(ink)
                UnitShape { r in
                    var path = Path()
                    for y in [0.32, 0.5, 0.68] as [CGFloat] {
                        path.move(to: r.point(0.3, y)); path.addLine(to: r.point(y == 0.68 ? 0.56 : 0.7, y))
                    }
                    return path
                }
                .stroke(style.behind, style: StrokeStyle(lineWidth: side * 0.08, lineCap: .round))
            }
        case .shades:
            EmptyView()
        }
    }
}

/// A shape drawn in its rect's unit square.
private struct UnitShape: Shape {
    let make: @Sendable (CGRect) -> Path
    func path(in rect: CGRect) -> Path { make(rect) }
}

private extension CGRect {
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: minX + width * x, y: minY + height * y) }
    func unit(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: minX + width * x, y: minY + height * y, width: width * w, height: height * h)
    }
}
