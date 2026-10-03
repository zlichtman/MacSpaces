import SwiftUI
import AppKit

/// Sets one lyric in the chosen `LyricStyle`. Sizes follow the space given,
/// so the same view serves the Music page and the small previews in Settings.
/// Motion runs on a timer schedule (30 fps) only when `animated`.
struct StyledLyricView: View {
    let style: LyricStyle
    let current: String
    var previous = ""
    var upcoming = ""
    let accent: Color
    let ink: Color
    var animated = true

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch style {
                case .classic:
                    ClassicLyric(current: current, upcoming: upcoming, accent: accent, size: proxy.size)
                case .poster:
                    PosterLyric(line: current, accent: accent, ink: ink, size: proxy.size)
                case .stanza:
                    StanzaLyric(previous: previous, current: current, upcoming: upcoming,
                                accent: accent, ink: ink, size: proxy.size)
                case .choreography:
                    ChoreographyLyric(line: current, upcoming: upcoming, accent: accent, ink: ink,
                                      size: proxy.size, animated: animated)
                case .waterformed:
                    WaterLyric(line: current, accent: accent, ink: ink, animated: animated)
                case .bloom:
                    BloomLyric(line: current, accent: accent, size: proxy.size, animated: animated)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lyrics: \(current)")
    }
}

// MARK: - Classic

private struct ClassicLyric: View {
    let current: String
    let upcoming: String
    let accent: Color
    let size: CGSize

    var body: some View {
        let scale = min(1.6, max(0.6, size.height / 110))
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text(current)
                .font(.system(size: 14 * scale, weight: .semibold))
                .foregroundStyle(accent)
                .lineLimit(2).minimumScaleFactor(0.85)
                .id(current)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            // A repeated line (a chorus hook) would otherwise show twice.
            if !upcoming.isEmpty, upcoming != current {
                Text(upcoming)
                    .font(.system(size: 12 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Lyric poster

/// The line's longest word becomes the headline; what comes before reads as an
/// italic lead-in, what follows sits beside it in small type.
private struct PosterLyric: View {
    let line: String
    let accent: Color
    let ink: Color
    let size: CGSize

    var body: some View {
        let parts = Self.split(line)
        let hero = min(size.height * 0.56, 72)
        VStack(alignment: .leading, spacing: 0) {
            if !parts.lead.isEmpty {
                Text(parts.lead)
                    .font(.system(size: max(9, hero * 0.27), design: .serif).italic())
                    .foregroundStyle(ink.opacity(0.92))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.bottom, -hero * 0.06)
            }
            HStack(alignment: .lastTextBaseline, spacing: hero * 0.16) {
                Text(parts.hero.uppercased())
                    .font(.system(size: hero, weight: .black).width(.compressed))
                    .foregroundStyle(accent)
                    .lineLimit(1).minimumScaleFactor(0.3)
                    .layoutPriority(1)
                if !parts.trail.isEmpty {
                    Text(parts.trail)
                        .font(.system(size: max(8, hero * 0.21), weight: .medium))
                        .foregroundStyle(ink.opacity(0.88))
                        .lineLimit(3).minimumScaleFactor(0.7)
                        .frame(maxWidth: size.width * 0.34, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background { Scanlines(ink: ink) }
        .id(line)
        .transition(.asymmetric(insertion: .scale(scale: 0.92, anchor: .leading).combined(with: .opacity),
                                removal: .opacity))
    }

    static func split(_ line: String) -> (lead: String, hero: String, trail: String) {
        let words = line.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return ("", line, "") }
        // Longest word wins; on a tie the later one, which usually lands the phrase.
        var index = 0, best = -1
        for (i, word) in words.enumerated() {
            let length = word.filter { $0.isLetter || $0.isNumber }.count
            if length >= best { best = length; index = i }
        }
        let hero = words[index].trimmingCharacters(in: .punctuationCharacters)
        return (words[..<index].joined(separator: " "), hero.isEmpty ? words[index] : hero,
                words[(index + 1)...].joined(separator: " "))
    }
}

/// Faint print lines behind the poster, fading out to the right.
private struct Scanlines: View {
    let ink: Color

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 1
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.6)), with: .color(ink.opacity(0.07)))
                y += 3
            }
        }
        .mask(LinearGradient(colors: [.black, .black.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing))
        .accessibilityHidden(true)
    }
}

// MARK: - Stanza stage

/// Three lines on a stage: the one just sung, the one now, the one next. Lines
/// keep their identity as they move, so a new line rolls everything upward.
private struct StanzaLyric: View {
    let previous: String
    let current: String
    let upcoming: String
    let accent: Color
    let ink: Color
    let size: CGSize

    private enum Role { case previous, current, upcoming }
    private struct Entry: Identifiable { let id: String; let text: String; let role: Role }

    private var entries: [Entry] {
        var seen: [String: Int] = [:]
        func entry(_ text: String, _ role: Role) -> Entry {
            let count = seen[text, default: 0]; seen[text] = count + 1
            return Entry(id: count == 0 ? text : "\(text)#\(count)", text: text, role: role)
        }
        var list: [Entry] = []
        if !previous.isEmpty, previous != current { list.append(entry(previous, .previous)) }
        list.append(entry(current, .current))
        if !upcoming.isEmpty, upcoming != current { list.append(entry(upcoming, .upcoming)) }
        return list
    }

    var body: some View {
        let scale = min(1.5, max(0.55, size.height / 120))
        VStack(alignment: .leading, spacing: 7 * scale) {
            ForEach(entries) { entry in
                line(entry, scale: scale)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            // A soft spotlight where the current line plays, fading to nothing at its edge.
            Rectangle()
                .fill(EllipticalGradient(colors: [accent.opacity(0.26), accent.opacity(0.08), .clear],
                                         center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
                .frame(width: size.width * 0.9, height: size.height * 0.95)
                .offset(x: -size.width * 0.08)
                .accessibilityHidden(true)
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.86), value: current)
    }

    @ViewBuilder
    private func line(_ entry: Entry, scale: CGFloat) -> some View {
        switch entry.role {
        case .previous:
            Text(entry.text)
                .font(.system(size: 11.5 * scale, weight: .medium))
                .foregroundStyle(ink.opacity(0.32)).lineLimit(1)
        case .current:
            HStack(alignment: .center, spacing: 9 * scale) {
                Capsule().fill(accent).frame(width: 3 * scale, height: 22 * scale)
                Text(entry.text)
                    .font(.system(size: 18 * scale, weight: .bold))
                    .foregroundStyle(ink)
                    .lineLimit(2).minimumScaleFactor(0.75)
                    .shadow(color: accent.opacity(0.35), radius: 10 * scale)
            }
        case .upcoming:
            Text(entry.text)
                .font(.system(size: 12.5 * scale, weight: .medium))
                .foregroundStyle(ink.opacity(0.55)).lineLimit(1)
                .padding(.leading, 12 * scale)
        }
    }
}

// MARK: - Phrase choreography

/// Words enter one after another, each rising and sharpening into place; the
/// line's strongest word takes the accent.
private struct ChoreographyLyric: View {
    let line: String
    let upcoming: String
    let accent: Color
    let ink: Color
    let size: CGSize
    let animated: Bool

    var body: some View {
        let words = line.split(separator: " ").map(String.init)
        let hero = Self.heroIndex(words)
        let base = min(26, size.height * 0.24) * (words.count > 9 ? 0.72 : words.count > 5 ? 0.86 : 1)
        VStack(alignment: .leading, spacing: base * 0.45) {
            WordFlow(spacing: base * 0.3, lineSpacing: base * 0.1) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    ChoreographedWord(word: word, index: index, hero: index == hero, size: base,
                                      accent: accent, ink: ink, animated: animated)
                }
            }
            .id(line)
            if !upcoming.isEmpty, upcoming != line {
                Text(upcoming)
                    .font(.system(size: max(9, base * 0.46), weight: .medium))
                    .foregroundStyle(ink.opacity(0.45)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    static func heroIndex(_ words: [String]) -> Int {
        var index = 0, best = -1
        for (i, word) in words.enumerated() where word.count >= best { best = word.count; index = i }
        return index
    }
}

private struct ChoreographedWord: View {
    let word: String
    let index: Int
    let hero: Bool
    let size: CGFloat
    let accent: Color
    let ink: Color
    let animated: Bool
    @State private var shown = false

    var body: some View {
        Text(word)
            .font(.system(size: hero ? size * 1.12 : size, weight: hero ? .heavy : .semibold, design: .rounded))
            .foregroundStyle(hero ? accent : ink)
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 5)
            .offset(y: shown ? 0 : size * 0.5)
            .scaleEffect(shown ? 1 : 0.86, anchor: .bottom)
            .onAppear {
                guard animated else { shown = true; return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.68).delay(Double(index) * 0.075)) { shown = true }
            }
    }
}

/// Lays words out left to right, wrapping like text.
private struct WordFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                // Baselines line up within a row even when the hero word is larger.
                subviews[index].place(at: CGPoint(x: x, y: y + row.height - size.height), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += size.width + gap
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

// MARK: - Waterformed

/// Letters ride a slow swell, with a rippling reflection below a waterline.
private struct WaterLyric: View {
    let line: String
    let accent: Color
    let ink: Color
    let animated: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: animated ? 1.0 / 30 : 3600)) { timeline in
            let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { context, size in
                draw(in: &context, size: size, time: time)
            }
        }
        .id(line)
        .transition(.opacity)
    }

    private struct Glyph { let text: GraphicsContext.ResolvedText; let x: CGFloat; let row: Int; let width: CGFloat }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let fontSize = min(26, max(11, size.height * 0.2))
        let font = Font.system(size: fontSize, weight: .semibold, design: .rounded)
        let lineHeight = fontSize * 1.18
        let glyphs = layout(line, font: font, width: size.width, lineHeight: lineHeight, context: context)
        let rows = (glyphs.map(\.row).max() ?? 0) + 1
        let blockHeight = CGFloat(rows) * lineHeight
        // Text sits above the middle; the waterline and reflection fill the rest.
        let top = max(2, size.height * 0.48 - blockHeight)
        let waterline = top + blockHeight + fontSize * 0.12

        func wave(_ x: CGFloat, _ phase: Double) -> CGFloat {
            CGFloat(sin(time * 2.1 + Double(x) / 19 + phase)) * fontSize * 0.09
        }

        // Reflection: mirrored about the waterline, squashed, fading with depth.
        context.drawLayer { layer in
            layer.translateBy(x: 0, y: waterline)
            layer.scaleBy(x: 1, y: -0.7)
            layer.translateBy(x: 0, y: -waterline)
            layer.addFilter(.blur(radius: 0.9))
            for glyph in glyphs {
                let x = glyph.x + CGFloat(sin(time * 3.3 + Double(glyph.x) / 9)) * fontSize * 0.05
                let y = top + CGFloat(glyph.row) * lineHeight - wave(glyph.x, 1.4)
                layer.opacity = 0.28 - Double(glyph.row) * 0.06
                layer.draw(glyph.text, at: CGPoint(x: x, y: y), anchor: .topLeading)
            }
        }
        // Surface ripples along the waterline.
        for band in 0..<3 {
            var path = Path()
            let y = waterline + CGFloat(band) * fontSize * 0.34 + 2
            path.move(to: CGPoint(x: 0, y: y))
            for x in stride(from: 0, through: size.width, by: 6) {
                path.addLine(to: CGPoint(x: x, y: y + CGFloat(sin(time * 1.7 + Double(x) / 24 + Double(band))) * 1.4))
            }
            context.stroke(path, with: .linearGradient(Gradient(colors: [.clear, accent.opacity(0.22 - Double(band) * 0.06), .clear]),
                                                       startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                           lineWidth: 0.8)
        }
        // The letters ride the swell.
        for glyph in glyphs {
            let y = top + CGFloat(glyph.row) * lineHeight + wave(glyph.x, 0)
            context.draw(glyph.text, at: CGPoint(x: glyph.x, y: y), anchor: .topLeading)
        }
    }

    /// One resolved glyph per character, wrapped at word boundaries.
    private func layout(_ text: String, font: Font, width: CGFloat, lineHeight: CGFloat,
                        context: GraphicsContext) -> [Glyph] {
        let crest = accent.mix(with: .white, by: 0.4)
        let total = max(1, CGFloat(text.count))
        var position: CGFloat = 0
        let space = context.resolve(Text(" ").font(font)).measure(in: CGSize(width: 1000, height: 1000)).width
        var glyphs: [Glyph] = []
        var x: CGFloat = 0, row = 0
        for word in text.split(separator: " ") {
            let resolved = word.map { character -> (GraphicsContext.ResolvedText, CGFloat) in
                position += 1
                let shade = accent.mix(with: crest, by: Double(position / total))
                let item = context.resolve(Text(String(character)).font(font).foregroundColor(shade))
                return (item, item.measure(in: CGSize(width: 1000, height: 1000)).width)
            }
            let wordWidth = resolved.reduce(0) { $0 + $1.1 }
            if x > 0, x + wordWidth > width { x = 0; row += 1 }
            for (item, glyphWidth) in resolved {
                glyphs.append(Glyph(text: item, x: x, row: row, width: glyphWidth))
                x += glyphWidth
            }
            x += space
        }
        return glyphs
    }
}

// MARK: - Psychedelic bloom

/// Heavy rounded type filled with drifting colour, glowing over slow blooms.
private struct BloomLyric: View {
    let line: String
    let accent: Color
    let size: CGSize
    let animated: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: animated ? 1.0 / 30 : 3600)) { timeline in
            let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            let palette = Self.palette(from: accent, shift: time * 0.025)
            let fill = LinearGradient(colors: palette + [palette[0]],
                                      startPoint: UnitPoint(x: 0.5 + 0.5 * cos(time * 0.5), y: 0),
                                      endPoint: UnitPoint(x: 0.5 - 0.5 * cos(time * 0.5), y: 1))
            let fontSize = min(30, max(11, size.height * 0.26))
            let text = Text(line)
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            ZStack(alignment: .leading) {
                // Blooms drifting behind the words.
                ForEach(0..<3, id: \.self) { index in
                    let angle = time * 0.35 + Double(index) * 2.1
                    Circle()
                        .fill(RadialGradient(colors: [palette[index * 2 % palette.count].opacity(0.34), .clear],
                                             center: .center, startRadius: 0, endRadius: size.height * 0.5))
                        .frame(width: size.height, height: size.height)
                        .offset(x: size.width * (0.25 + 0.2 * CGFloat(cos(angle))) - size.height * 0.5,
                                y: size.height * 0.12 * CGFloat(sin(angle * 1.3)))
                }
                text.foregroundStyle(fill).blur(radius: fontSize * 0.42).opacity(0.75)
                text.foregroundStyle(fill).blur(radius: fontSize * 0.1).opacity(0.6)
                text.foregroundStyle(fill)
            }
            .lineLimit(3).minimumScaleFactor(0.55)
            .scaleEffect(1 + 0.018 * CGFloat(sin(time * 1.5)), anchor: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .id(line)
        .transition(.asymmetric(insertion: .scale(scale: 0.86, anchor: .leading).combined(with: .opacity),
                                removal: .opacity))
    }

    /// Five hues fanned out from the accent, rotating slowly with `shift`.
    static func palette(from accent: Color, shift: Double) -> [Color] {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        (NSColor(accent).usingColorSpace(.sRGB) ?? .systemPink)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return [0, 0.14, 0.32, 0.55, 0.78].map { offset in
            let h = (Double(hue) + offset + shift).truncatingRemainder(dividingBy: 1)
            return Color(hue: h, saturation: 0.72, brightness: 1)
        }
    }
}
