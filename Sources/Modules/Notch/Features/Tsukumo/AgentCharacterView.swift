import SwiftUI

/// Draws one of Tsukumo's bots from its `character` the way Tsukumo does
/// (design/MACSPACES-AGENTS-TAB.md#characters in the Tsukumo repo). Every state has a
/// live motion and a still pose; `animated` false (Reduce Motion, previews) holds the pose.
struct AgentCharacterView: View {
    let character: MacSpacesAgents.Character
    let state: String
    var size: CGFloat = 44
    var animated = false
    /// KemoSabe's companion art from `hello`; drawn instead of a body when present.
    var avatar: NSImage?

    var body: some View {
        if character.shape == "kemosabe", let avatar {
            Image(nsImage: avatar).resizable().interpolation(.high)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .padding(size * 0.08)
                .frame(width: size, height: size)
        } else {
            TimelineView(.periodic(from: .now, by: animated ? 1.0 / 30 : 3600)) { timeline in
                let t = animated ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600) : nil
                Canvas { context, canvasSize in
                    CharacterPainter(character: character, state: state, s: canvasSize.width, t: t).paint(&context)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

private struct CharacterPainter {
    let character: MacSpacesAgents.Character
    let state: String
    let s: CGFloat
    /// Seconds, or nil for the still pose.
    let t: Double?

    private var body: Color { hex(character.body) }
    private var accent: Color { hex(character.accent) }
    private var ink: Color { hex(character.ink) }
    private var time: Double { t ?? 0 }
    private var live: Bool { t != nil }

    /// The body's frame in the unit square, per shape.
    private var frame: CGRect {
        switch character.shape {
        case "gumdrop": return CGRect(x: 0.19, y: 0.26, width: 0.62, height: 0.64)
        case "block": return CGRect(x: 0.20, y: 0.26, width: 0.60, height: 0.58)
        case "mochi": return CGRect(x: 0.14, y: 0.38, width: 0.72, height: 0.46)
        case "sprout": return CGRect(x: 0.20, y: 0.28, width: 0.60, height: 0.56)
        case "pebble": return CGRect(x: 0.20, y: 0.30, width: 0.62, height: 0.54)
        default: return CGRect(x: 0.24, y: 0.20, width: 0.52, height: 0.64)   // bean, kemosabe without art
        }
    }

    func paint(_ context: inout GraphicsContext) {
        let f = frame
        // Ground shadow stays put while the body moves.
        context.fill(Path(ellipseIn: rect(0.28, 0.86, 0.44, 0.06)), with: .color(.black.opacity(0.16)))

        var c = context
        // Whole-body motion: hops, bounces, breathing.
        var lift: CGFloat = 0
        var squash: CGFloat = 1
        if live {
            switch state {
            case "chirping": lift = CGFloat(abs(sin(time * 3))) * 0.16 * f.height * s
            case "needsYou": lift = CGFloat(abs(sin(time * 2.4))) * 0.03 * s
            case "talking": lift = CGFloat(abs(sin(time * 6))) * 0.02 * s
            case "idle": squash = 1 + 0.02 * CGFloat(sin(time * 2 * .pi / 3))
            case "sleeping": squash = 1 + 0.03 * CGFloat(sin(time * 2 * .pi / 4.5))
            default: break
            }
        }
        let floorY = (f.maxY) * s
        c.translateBy(x: 0, y: -lift + floorY * (1 - squash))
        c.scaleBy(x: 1, y: squash)

        arms(&c, f, behind: true)
        bodyShape(&c, f)
        face(&c, f)
        prop(&c, f)
        arms(&c, f, behind: false)
        stateExtras(&c, f)
    }

    // MARK: Body

    private func bodyPath(_ f: CGRect) -> Path {
        switch character.shape {
        case "gumdrop":
            var p = Path()
            p.move(to: pt(0.19, 0.80))
            p.addCurve(to: pt(0.5, 0.26), control1: pt(0.19, 0.50), control2: pt(0.32, 0.26))
            p.addCurve(to: pt(0.81, 0.80), control1: pt(0.68, 0.26), control2: pt(0.81, 0.50))
            p.addQuadCurve(to: pt(0.19, 0.80), control: pt(0.5, 0.92))
            return p
        case "block":
            return Path(roundedRect: rect(0.20, 0.26, 0.60, 0.58), cornerRadius: 0.14 * s, style: .continuous)
        case "mochi":
            var p = Path()
            p.move(to: pt(0.14, 0.80))
            p.addCurve(to: pt(0.5, 0.38), control1: pt(0.14, 0.52), control2: pt(0.30, 0.38))
            p.addCurve(to: pt(0.86, 0.80), control1: pt(0.70, 0.38), control2: pt(0.86, 0.52))
            p.addQuadCurve(to: pt(0.14, 0.80), control: pt(0.5, 0.88))
            return p
        case "sprout":
            return Path(ellipseIn: rect(0.20, 0.28, 0.60, 0.56))
        case "pebble":
            var p = Path()
            p.move(to: pt(0.20, 0.62))
            p.addCurve(to: pt(0.46, 0.30), control1: pt(0.18, 0.42), control2: pt(0.32, 0.30))
            p.addCurve(to: pt(0.82, 0.55), control1: pt(0.64, 0.30), control2: pt(0.84, 0.38))
            p.addCurve(to: pt(0.52, 0.84), control1: pt(0.80, 0.74), control2: pt(0.68, 0.84))
            p.addCurve(to: pt(0.20, 0.62), control1: pt(0.34, 0.84), control2: pt(0.21, 0.78))
            return p
        default:
            return Path(roundedRect: rect(0.24, 0.20, 0.52, 0.64), cornerRadius: 0.26 * s, style: .continuous)
        }
    }

    private func bodyShape(_ c: inout GraphicsContext, _ f: CGRect) {
        if character.shape == "sprout" {
            var stem = Path(); stem.move(to: pt(0.5, 0.29)); stem.addQuadCurve(to: pt(0.5, 0.16), control: pt(0.47, 0.22))
            c.stroke(stem, with: .color(hex("5F8F4E")), lineWidth: 0.03 * s)
            c.fill(Path(ellipseIn: rect(0.5, 0.12, 0.14, 0.07)), with: .color(hex("7DB36A")))
        }
        if character.shape == "block" {
            c.fill(Path(roundedRect: rect(0.485, 0.20, 0.03, 0.06), cornerRadius: 0.01 * s), with: .color(accent))
        }
        let path = bodyPath(f)
        c.fill(path, with: .linearGradient(Gradient(colors: [mix(character.body, "FFFFFF", 0.35), body, mix(character.body, character.accent, 0.18)]),
                                           startPoint: pt(0.5, f.minY), endPoint: pt(0.5, f.maxY)))
        c.stroke(path, with: .color(mix(character.accent, character.ink, 0.35).opacity(0.55)), lineWidth: 0.018 * s)
        // Soft highlight at the top left.
        c.fill(Path(ellipseIn: rect(f.minX + f.width * 0.18, f.minY + f.height * 0.08, f.width * 0.22, f.height * 0.12)),
               with: .color(.white.opacity(0.35)))
    }

    // MARK: Face

    private func face(_ c: inout GraphicsContext, _ f: CGRect) {
        let eyeY = f.minY + f.height * (character.shape == "mochi" ? 0.42 : 0.40)
        let left = CGPoint(x: (f.midX - f.width * 0.20) * s, y: eyeY * s)
        let right = CGPoint(x: (f.midX + f.width * 0.20) * s, y: eyeY * s)
        let eye = 0.075 * s

        // Cheeks
        for p in [left, right] {
            let offset: CGFloat = p.x < f.midX * s ? -1 : 1
            c.fill(Path(ellipseIn: CGRect(x: p.x + offset * eye * 0.6 - eye * 0.55, y: p.y + eye * 0.75, width: eye * 1.1, height: eye * 0.6)),
                   with: .color(accent.opacity(0.32)))
        }

        let blinking = live && state == "idle" && time.truncatingRemainder(dividingBy: 4) < 0.14
        if state == "sleeping" || blinking {
            for p in [left, right] {
                var lid = Path(); lid.move(to: CGPoint(x: p.x - eye * 0.6, y: p.y)); lid.addQuadCurve(to: CGPoint(x: p.x + eye * 0.6, y: p.y), control: CGPoint(x: p.x, y: p.y + eye * 0.5))
                c.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 0.02 * s, lineCap: .round))
            }
        } else if state == "done" {
            for p in [left, right] {
                var happy = Path(); happy.move(to: CGPoint(x: p.x - eye * 0.6, y: p.y + eye * 0.3)); happy.addLine(to: CGPoint(x: p.x, y: p.y - eye * 0.35)); happy.addLine(to: CGPoint(x: p.x + eye * 0.6, y: p.y + eye * 0.3))
                c.stroke(happy, with: .color(ink), style: StrokeStyle(lineWidth: 0.022 * s, lineCap: .round, lineJoin: .round))
            }
        } else if character.eyes == "visor" {
            let band = CGRect(x: (f.midX - f.width * 0.31) * s, y: eyeY * s - eye * 0.7, width: f.width * 0.62 * s, height: eye * 1.4)
            c.fill(Path(roundedRect: band, cornerRadius: eye * 0.7), with: .color(ink))
            for p in [left, right] {
                c.fill(Path(roundedRect: CGRect(x: p.x - eye * 0.45, y: p.y - eye * 0.15, width: eye * 0.9, height: eye * 0.3), cornerRadius: eye * 0.15),
                       with: .color(mix(character.accent, "FFFFFF", 0.4)))
            }
        } else {
            let surprised = state == "needsYou" ? 1.25 : 1
            let lookDown: CGFloat = state == "working" ? eye * 0.25 : 0
            let glance: CGFloat = live && state == "idle" ? CGFloat(sin(time * 0.4)) * eye * 0.25 : 0
            for p in [left, right] {
                let w = eye * surprised, h = character.eyes == "ovals" ? eye * 1.4 * surprised : eye * surprised
                c.fill(Path(ellipseIn: CGRect(x: p.x - w / 2 + glance, y: p.y - h / 2 + lookDown, width: w, height: h)), with: .color(ink))
                if character.eyes != "dots" {
                    c.fill(Path(ellipseIn: CGRect(x: p.x - w * 0.05 + glance, y: p.y - h * 0.35 + lookDown, width: w * 0.35, height: w * 0.35)), with: .color(.white))
                }
            }
        }

        // Mouth: a small smile, open when talking.
        let mouth = CGPoint(x: f.midX * s, y: (eyeY + f.height * 0.17) * s)
        let open = state == "talking" && (!live || sin(time * 10) > 0)
        if open {
            c.fill(Path(ellipseIn: CGRect(x: mouth.x - eye * 0.45, y: mouth.y - eye * 0.25, width: eye * 0.9, height: eye * (live ? 0.75 : 0.5))), with: .color(ink))
        } else {
            var smile = Path(); smile.move(to: CGPoint(x: mouth.x - eye * 0.5, y: mouth.y)); smile.addQuadCurve(to: CGPoint(x: mouth.x + eye * 0.5, y: mouth.y), control: CGPoint(x: mouth.x, y: mouth.y + eye * 0.55))
            c.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 0.018 * s, lineCap: .round))
        }
    }

    // MARK: Arms

    /// Angles from straight down, raising outward (degrees).
    private var armAngles: (left: Double, right: Double) {
        switch state {
        case "working":
            let tap = live ? sin(time * 14) * 10 : 0
            return (-25 + tap, -25 - tap)
        case "thinking": return (12, 150)
        case "chirping": return (12, live ? 150 + sin(time * 8) * 20 : 160)
        case "needsYou": return (12, 178)
        case "done": return live && time.truncatingRemainder(dividingBy: 6) < 1.2 ? (160, 160) : (20, 20)
        default: return (12, 12)
        }
    }

    private func arms(_ c: inout GraphicsContext, _ f: CGRect, behind: Bool) {
        // Raised arms draw in front of the body; hanging ones sit behind it.
        let angles = armAngles
        for (side, angle) in [(-1.0, angles.left), (1.0, angles.right)] where (angle > 90) != behind {
            let shoulder = CGPoint(x: (side < 0 ? f.minX + 0.02 : f.maxX - 0.02) * s, y: (f.minY + f.height * 0.55) * s)
            let radians = angle * .pi / 180
            let end = CGPoint(x: shoulder.x + CGFloat(sin(radians) * side) * 0.20 * s, y: shoulder.y + CGFloat(cos(radians)) * 0.20 * s)
            var arm = Path(); arm.move(to: shoulder); arm.addLine(to: end)
            c.stroke(arm, with: .color(mix(character.accent, character.ink, 0.35).opacity(0.55)), style: StrokeStyle(lineWidth: 0.09 * s + 0.018 * s, lineCap: .round))
            c.stroke(arm, with: .color(body), style: StrokeStyle(lineWidth: 0.09 * s, lineCap: .round))
            if side > 0 && !behind || side > 0 && angle <= 90 { handProp(&c, end) }
        }
    }

    private func handProp(_ c: inout GraphicsContext, _ hand: CGPoint) {
        switch character.prop {
        case "wrench":
            var w = Path(); w.move(to: hand); w.addLine(to: CGPoint(x: hand.x + 0.08 * s, y: hand.y - 0.06 * s))
            c.stroke(w, with: .color(hex("9AA0A6")), style: StrokeStyle(lineWidth: 0.03 * s, lineCap: .round))
            c.stroke(Path(ellipseIn: CGRect(x: hand.x + 0.065 * s, y: hand.y - 0.095 * s, width: 0.05 * s, height: 0.05 * s)), with: .color(hex("9AA0A6")), lineWidth: 0.02 * s)
        case "paintbrush":
            var b = Path(); b.move(to: hand); b.addLine(to: CGPoint(x: hand.x + 0.06 * s, y: hand.y - 0.09 * s))
            c.stroke(b, with: .color(hex("8A5A3C")), style: StrokeStyle(lineWidth: 0.022 * s, lineCap: .round))
            c.fill(Path(ellipseIn: CGRect(x: hand.x + 0.045 * s, y: hand.y - 0.125 * s, width: 0.035 * s, height: 0.05 * s)), with: .color(accent))
        default: break
        }
    }

    // MARK: Props worn

    private func prop(_ c: inout GraphicsContext, _ f: CGRect) {
        let eyeY = (f.minY + f.height * (character.shape == "mochi" ? 0.42 : 0.40)) * s
        switch character.prop {
        case "hardHat":
            var dome = Path()
            dome.addArc(center: CGPoint(x: f.midX * s, y: (f.minY + 0.05) * s), radius: f.width * 0.36 * s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            dome.closeSubpath()
            c.fill(dome, with: .color(hex("F2C230")))
            c.fill(Path(roundedRect: CGRect(x: (f.midX - f.width * 0.46) * s, y: (f.minY + 0.04) * s, width: f.width * 0.92 * s, height: 0.035 * s), cornerRadius: 0.015 * s),
                   with: .color(hex("E0AE1C")))
        case "glasses":
            for dx in [-0.20, 0.20] {
                let center = CGPoint(x: (f.midX + f.width * CGFloat(dx)) * s, y: eyeY)
                c.stroke(Path(ellipseIn: CGRect(x: center.x - 0.065 * s, y: center.y - 0.065 * s, width: 0.13 * s, height: 0.13 * s)), with: .color(ink), lineWidth: 0.014 * s)
            }
        case "pencil":
            var pencil = c
            pencil.translateBy(x: (f.maxX - 0.02) * s, y: (f.minY + 0.08) * s)
            pencil.rotate(by: .degrees(-35))
            pencil.fill(Path(roundedRect: CGRect(x: 0, y: -0.015 * s, width: 0.14 * s, height: 0.03 * s), cornerRadius: 0.006 * s), with: .color(hex("F2C230")))
            pencil.fill(Path(roundedRect: CGRect(x: 0.13 * s, y: -0.015 * s, width: 0.03 * s, height: 0.03 * s), cornerRadius: 0.008 * s), with: .color(hex("F29BB0")))
        case "headset":
            var band = Path()
            band.addArc(center: CGPoint(x: f.midX * s, y: eyeY), radius: f.width * 0.52 * s, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            c.stroke(band, with: .color(ink.opacity(0.8)), lineWidth: 0.02 * s)
            for dx in [-0.52, 0.52] {
                c.fill(Path(roundedRect: CGRect(x: (f.midX + f.width * CGFloat(dx)) * s - 0.03 * s, y: eyeY - 0.03 * s, width: 0.06 * s, height: 0.09 * s), cornerRadius: 0.02 * s), with: .color(accent))
            }
            var mic = Path(); mic.move(to: CGPoint(x: (f.midX + f.width * 0.5) * s, y: eyeY + 0.05 * s)); mic.addQuadCurve(to: CGPoint(x: (f.midX + f.width * 0.15) * s, y: eyeY + 0.14 * s), control: CGPoint(x: (f.midX + f.width * 0.45) * s, y: eyeY + 0.14 * s))
            c.stroke(mic, with: .color(ink.opacity(0.8)), lineWidth: 0.012 * s)
        case "book":
            c.fill(Path(roundedRect: CGRect(x: (f.midX - 0.10) * s, y: (f.maxY - 0.16) * s, width: 0.20 * s, height: 0.12 * s), cornerRadius: 0.012 * s), with: .color(accent))
            c.fill(Path(CGRect(x: (f.midX - 0.004) * s, y: (f.maxY - 0.16) * s, width: 0.008 * s, height: 0.12 * s)), with: .color(.white.opacity(0.6)))
        case "antenna":
            var stem = Path(); stem.move(to: pt(f.midX, f.minY + 0.01)); stem.addLine(to: pt(f.midX, f.minY - 0.08))
            c.stroke(stem, with: .color(ink.opacity(0.7)), lineWidth: 0.015 * s)
            c.fill(Path(ellipseIn: rect(f.midX - 0.03, f.minY - 0.12, 0.06, 0.06)), with: .color(accent))
        default: break
        }
    }

    // MARK: State extras

    private func stateExtras(_ c: inout GraphicsContext, _ f: CGRect) {
        switch state {
        case "working":
            c.fill(Path(roundedRect: rect(0.28, f.maxY - 0.10, 0.44, 0.08), cornerRadius: 0.02 * s), with: .color(ink.opacity(0.85)))
            for k in 0..<4 {
                let lit = live ? Int(time * 8) % 4 == k : k == 1
                c.fill(Path(roundedRect: rect(0.31 + Double(k) * 0.1, f.maxY - 0.085, 0.07, 0.03), cornerRadius: 0.006 * s),
                       with: .color(lit ? accent : .white.opacity(0.35)))
            }
        case "thinking":
            for k in 0..<3 {
                let angle = (live ? time * 2.2 : 0.6) + Double(k) * 2.09
                let center = CGPoint(x: (0.5 + 0.11 * cos(angle)) * s, y: (f.minY - 0.08 + 0.035 * sin(angle)) * s)
                c.fill(Path(ellipseIn: CGRect(x: center.x - 0.03 * s, y: center.y - 0.03 * s, width: 0.06 * s, height: 0.06 * s)), with: .color(accent))
            }
        case "chirping":
            let bubble = rect(0.58, max(0.0, f.minY - 0.20), 0.30, 0.18)
            c.fill(Path(roundedRect: bubble, cornerRadius: 0.06 * s), with: .color(.white))
            c.draw(Text("!").font(.system(size: 0.14 * s, weight: .black)).foregroundStyle(accent), at: CGPoint(x: bubble.midX, y: bubble.midY))
        case "sleeping":
            let drift = live ? CGFloat(time.truncatingRemainder(dividingBy: 2.5) / 2.5) : 0.3
            for k in 0..<(live ? 2 : 1) {
                let rise = (drift + CGFloat(k) * 0.5).truncatingRemainder(dividingBy: 1)
                var z = c
                z.opacity = Double(1 - rise)
                z.draw(Text("z").font(.system(size: (0.12 + 0.04 * rise) * s, weight: .bold)).foregroundStyle(accent),
                       at: CGPoint(x: (f.maxX - 0.02 + 0.06 * rise) * s, y: (f.minY - 0.02 - 0.16 * rise) * s))
            }
        case "done":
            if live, time.truncatingRemainder(dividingBy: 6) < 1.2 {
                for k in 0..<8 {
                    let a = Double(k) * 0.785 + time
                    c.fill(Path(rect(0.5 + 0.32 * cos(a), Double(f.minY) - 0.02 + 0.12 * sin(a), 0.03, 0.03)),
                           with: .color(Color(hue: Double(k) / 8, saturation: 0.7, brightness: 1)))
                }
            }
        default: break
        }
    }

    // MARK: Helpers

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * s, y: y * s, width: w * s, height: h * s) }
    private func hex(_ value: String) -> Color { Color(themeHex: value) ?? .gray }

    /// Mixes two "RRGGBB" colors.
    private func mix(_ a: String, _ b: String, _ amount: Double) -> Color {
        func rgb(_ hex: String) -> (Double, Double, Double) {
            let v = UInt32(hex, radix: 16) ?? 0
            return (Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
        }
        let (ar, ag, ab) = rgb(a), (br, bg, bb) = rgb(b)
        return Color(red: ar + (br - ar) * amount, green: ag + (bg - ag) * amount, blue: ab + (bb - ab) * amount)
    }
}
