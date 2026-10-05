import SwiftUI
import AppKit

/// Sets one lyric in the chosen `LyricStyle`. Sizes follow the space given,
/// so the same view serves the Music page and the small previews in Settings.
/// Words animate in only when `animated`.
struct StyledLyricView: View {
    let style: LyricStyle
    let current: String
    var upcoming = ""
    let accent: Color
    let ink: Color
    var animated = true
    /// Counts line changes, so styles with several compositions never repeat one twice in a row.
    var sequence = 0
    /// How far through the line the song is (0–1), for Karaoke.
    var progress: Double = 0

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch style {
                case .classic:
                    ClassicLyric(current: current, upcoming: upcoming, accent: accent, size: proxy.size)
                case .poster:
                    PosterLyric(line: current, accent: accent, ink: ink, size: proxy.size,
                                composition: PosterLyric.Composition.allCases[sequence % PosterLyric.Composition.allCases.count])
                case .choreography:
                    ChoreographyLyric(line: current, upcoming: upcoming, accent: accent, ink: ink,
                                      size: proxy.size, animated: animated)
                case .stickers:
                    StickerLyric(line: current, accent: accent, ink: ink, size: proxy.size, animated: animated,
                                 composition: PosterLyric.Composition.allCases[sequence % PosterLyric.Composition.allCases.count])
                case .karaoke:
                    KaraokeLyric(line: current, upcoming: upcoming, accent: accent, ink: ink, size: proxy.size,
                                 progress: animated ? progress : 1)
                case .typewriter:
                    TypewriterLyric(line: current, accent: accent, ink: ink, size: proxy.size, animated: animated)
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

/// The line's longest word becomes the headline, with the rest arranged around
/// it in one of three compositions that take turns line by line.
struct PosterLyric: View {
    enum Composition: CaseIterable {
        /// Italic lead-in above, the rest in a column beside the headline.
        case leadAbove
        /// A small tracked caption above, the rest in italic serif beneath.
        case stacked
        /// The whole poster set flush right.
        case flushRight
    }

    let line: String
    let accent: Color
    let ink: Color
    let size: CGSize
    var composition: Composition = .leadAbove

    var body: some View {
        let parts = Self.split(line)
        let hero = min(size.height * (composition == .leadAbove ? 0.56 : 0.48), 72)
        let alignment: HorizontalAlignment = composition == .flushRight ? .trailing : .leading
        let frameAlignment: Alignment = composition == .flushRight ? .trailing : .leading
        VStack(alignment: alignment, spacing: 0) {
            switch composition {
            case .leadAbove:
                if !parts.lead.isEmpty { italic(parts.lead, hero: hero).padding(.bottom, -hero * 0.06) }
                // The words after the headline always get a readable column; the
                // headline shrinks into what's left rather than crushing them.
                HStack(alignment: .lastTextBaseline, spacing: hero * 0.16) {
                    headline(parts.hero, hero: hero, alignment: .leading)
                    if !parts.trail.isEmpty {
                        Text(parts.trail)
                            .font(.system(size: max(8, hero * 0.21), weight: .medium))
                            .foregroundStyle(ink.opacity(0.88))
                            .lineLimit(4).minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: min(max(size.width * 0.3, 72), 150), alignment: .leading)
                    }
                }
            case .stacked:
                if !parts.lead.isEmpty {
                    Text(parts.lead.uppercased())
                        .font(.system(size: max(8, hero * 0.17), weight: .bold))
                        .tracking(hero * 0.04)
                        .foregroundStyle(ink.opacity(0.7))
                        .lineLimit(2).minimumScaleFactor(0.6)
                        .padding(.bottom, hero * 0.02)
                }
                headline(parts.hero, hero: hero, alignment: .leading)
                if !parts.trail.isEmpty { italic(parts.trail, hero: hero).padding(.top, -hero * 0.04) }
            case .flushRight:
                if !parts.lead.isEmpty { italic(parts.lead, hero: hero).multilineTextAlignment(.trailing).padding(.bottom, -hero * 0.06) }
                headline(parts.hero, hero: hero, alignment: .trailing)
                if !parts.trail.isEmpty {
                    Text(parts.trail)
                        .font(.system(size: max(8, hero * 0.22), weight: .semibold))
                        .foregroundStyle(ink.opacity(0.88))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2).minimumScaleFactor(0.6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
        .id(line)
        .transition(.asymmetric(insertion: .scale(scale: 0.92, anchor: composition == .flushRight ? .trailing : .leading)
                                    .combined(with: .opacity),
                                removal: .opacity))
    }

    private func headline(_ word: String, hero: CGFloat, alignment: Alignment) -> some View {
        Text(word.uppercased())
            .font(.system(size: hero, weight: .black).width(.compressed))
            .foregroundStyle(accent)
            .lineLimit(1).minimumScaleFactor(0.3)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func italic(_ text: String, hero: CGFloat) -> some View {
        Text(text)
            .font(.system(size: max(9, hero * 0.27), design: .serif).italic())
            .foregroundStyle(ink.opacity(0.92))
            .lineLimit(2).minimumScaleFactor(0.6)
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
                withAnimation(Design.timed(.spring(response: 0.42, dampingFraction: 0.68).delay(Double(index) * 0.075))) { shown = true }
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

// MARK: - Stickers

/// Poster, with a small animated sticker when the line mentions something
/// drawable: one general word list (no per-song work), drawn from SF Symbols in
/// code so it stays smooth and light. Still under Reduce Motion.
private struct StickerLyric: View {
    let line: String
    let accent: Color
    let ink: Color
    let size: CGSize
    let animated: Bool
    let composition: PosterLyric.Composition

    var body: some View {
        let sticker = LyricSticker.match(line)
        // The sticker gets its whole frame beside the poster (never on top of the
        // headline): wide symbols such as the eye fill most of it.
        let stickerSize = min(54, size.height * 0.4)
        let reserved = sticker == nil ? 0 : stickerSize * 1.5 + 6
        HStack(alignment: .top, spacing: 0) {
            if let sticker, composition == .flushRight { stickerView(sticker, size: stickerSize).padding(.trailing, 6) }
            PosterLyric(line: line, accent: accent, ink: ink,
                        size: CGSize(width: size.width - reserved, height: size.height),
                        composition: composition)
                .frame(width: size.width - reserved, height: size.height)
            if let sticker, composition != .flushRight { stickerView(sticker, size: stickerSize).padding(.leading, 6) }
        }
        .frame(width: size.width, height: size.height)
    }

    private func stickerView(_ sticker: LyricSticker, size stickerSize: CGFloat) -> some View {
        StickerView(sticker: sticker, accent: accent, size: stickerSize, animated: animated)
            .padding(.top, size.height * 0.06)
            .frame(maxHeight: .infinity, alignment: .top)
            .id(line)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }
}

enum LyricSticker: String, CaseIterable {
    case brokenHeart, heart, map, fire, rain, stars, moon, sun, phone, tears, music, car, plane, home, time, money, ocean, snow, world, dance, eyes, kiss, flower

    /// Whole words that call for each sticker, checked in this order (a broken
    /// heart before a heart). Plurals and simple endings count.
    static let words: [(LyricSticker, [String])] = [
        (.brokenHeart, ["heartbreak", "heartbroken", "brokenhearted"]),
        (.heart, ["heart", "hearts", "love", "loves", "loved", "loving", "lover"]),
        (.map, ["map", "maps", "lost", "compass"]),
        (.fire, ["fire", "burn", "burning", "flame", "flames", "blaze"]),
        (.rain, ["rain", "raining", "storm", "thunder"]),
        (.stars, ["star", "stars", "shine", "shining", "sparkle", "glitter"]),
        (.moon, ["moon", "midnight", "night", "tonight"]),
        (.sun, ["sun", "sunshine", "summer", "daylight"]),
        (.phone, ["phone", "call", "calling", "text", "ring"]),
        (.tears, ["cry", "crying", "tears", "tear"]),
        (.music, ["song", "sing", "singing", "music", "radio", "melody"]),
        (.car, ["drive", "driving", "car", "highway", "road"]),
        (.plane, ["fly", "flying", "sky", "plane", "wings"]),
        (.home, ["home", "house"]),
        (.time, ["time", "clock", "forever", "minute", "hours"]),
        (.money, ["money", "cash", "gold", "dollar", "rich"]),
        (.ocean, ["ocean", "sea", "waves", "tide", "water"]),
        (.snow, ["snow", "cold", "winter", "ice", "frozen"]),
        (.world, ["world", "earth", "globe"]),
        (.dance, ["dance", "dancing", "move", "party"]),
        (.eyes, ["eyes", "see", "look", "watch"]),
        (.kiss, ["kiss", "kissed", "lips"]),
        (.flower, ["flower", "flowers", "rose", "roses", "bloom"]),
    ]

    static func match(_ line: String) -> LyricSticker? {
        let words = Set(line.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
        let joined = line.lowercased()
        // "break(ing) my heart" and friends.
        if words.contains("heart") || words.contains("hearts"),
           !words.isDisjoint(with: ["break", "breaking", "broke", "broken", "breaks"]) { return .brokenHeart }
        _ = joined
        return Self.words.first { !words.isDisjoint(with: $0.1) }?.0
    }

    var symbol: String {
        switch self {
        case .brokenHeart, .heart: return "heart.fill"
        case .map: return "map.fill"
        case .fire: return "flame.fill"
        case .rain: return "cloud.rain.fill"
        case .stars: return "sparkles"
        case .moon: return "moon.stars.fill"
        case .sun: return "sun.max.fill"
        case .phone: return "phone.fill"
        case .tears: return "drop.fill"
        case .music: return "music.note"
        case .car: return "car.fill"
        case .plane: return "airplane"
        case .home: return "house.fill"
        case .time: return "clock.fill"
        case .money: return "dollarsign.circle.fill"
        case .ocean: return "water.waves"
        case .snow: return "snowflake"
        case .world: return "globe.americas.fill"
        case .dance: return "figure.dance"
        case .eyes: return "eye.fill"
        case .kiss: return "mouth.fill"
        case .flower: return "camera.macro"
        }
    }
}

/// One sticker: a main figure with its own motion, a springy entrance with a soft
/// glow, and a small particle scene (hearts rising, embers, rain, sparkles,
/// shards). Everything is computed from time in a 60 fps TimelineView, so it never
/// depends on an animation schedule macOS might pause, and holds still under
/// Reduce Motion.
private struct StickerView: View {
    let sticker: LyricSticker
    let accent: Color
    let size: CGFloat
    let animated: Bool
    /// QA captures pin the moment to draw.
    var fixedTime: Double?
    @State private var appeared = Date()

    private var tint: Color {
        switch sticker {
        case .heart, .brokenHeart, .kiss: return Color(red: 1, green: 0.3, blue: 0.42)
        case .fire: return Color(red: 1, green: 0.55, blue: 0.15)
        case .sun, .money, .stars: return Color(red: 1, green: 0.8, blue: 0.3)
        default: return accent
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: animated ? 1.0 / 60 : 3600)) { context in
            let t = fixedTime ?? (animated ? context.date.timeIntervalSince(appeared) : 2.5)
            ZStack {
                // A soft glow behind, breathing slowly (not behind a heart that splits open).
                if sticker != .brokenHeart {
                    Circle().fill(tint.opacity(0.22)).frame(width: size * 1.1, height: size * 1.1)
                        .blur(radius: size * 0.22)
                        .scaleEffect(0.9 + 0.1 * sin(t * 2))
                }
                particles(t)
                figure(t)
            }
            // Pop in: overshoot, settle, a little turn.
            .scaleEffect(Self.pop(t))
            .rotationEffect(.degrees(-14 * max(0, 1 - t / 0.45) * cos(t * 9)))
        }
        .frame(width: size * 1.5, height: size * 1.5)
        .onAppear { appeared = Date() }
        .accessibilityHidden(true)
    }

    /// A damped spring from 0.3 to 1.
    static func pop(_ t: Double) -> CGFloat {
        guard t < 1.2 else { return 1 }
        return CGFloat(1 - 0.7 * exp(-7 * t) * cos(t * 14))
    }

    // MARK: Figures

    @ViewBuilder
    private func figure(_ t: Double) -> some View {
        switch sticker {
        case .brokenHeart: BrokenHeart(t: t, size: size, tint: tint)
        case .heart:
            // Lub-dub: two beats close together, then a rest.
            let phase = t.truncatingRemainder(dividingBy: 1.1)
            let beat = Self.bump(phase, at: 0.0, width: 0.12) * 0.16 + Self.bump(phase, at: 0.2, width: 0.12) * 0.1
            symbol("heart.fill").scaleEffect(1 + beat)
        case .map:
            ZStack {
                symbol("map.fill", scale: 0.95)
                // A pin drops onto the map and bounces.
                let drop = min(1, t / 0.55)
                let bounce = drop < 1 ? 0 : abs(sin((t - 0.55) * 7)) * exp(-(t - 0.55) * 4) * size * 0.12
                Image(systemName: "mappin.circle.fill").font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white, Color(red: 1, green: 0.32, blue: 0.3))
                    .offset(x: size * 0.12, y: -size * 0.2 - (1 - drop * drop) * size * 0.9 - bounce)
                    .opacity(drop > 0 ? 1 : 0)
            }
        case .fire:
            symbol("flame.fill").scaleEffect(x: 1 + 0.06 * sin(t * 13), y: 1 + 0.1 * sin(t * 10 + 1), anchor: .bottom)
                .overlay(symbol("flame.fill", scale: 0.55, color: Color(red: 1, green: 0.9, blue: 0.4))
                    .scaleEffect(y: 1 + 0.15 * sin(t * 15), anchor: .bottom).offset(y: size * 0.18))
        case .rain: symbol("cloud.fill").offset(y: -size * 0.15 + sin(t * 1.6) * size * 0.03)
        case .snow: symbol("snowflake").rotationEffect(.degrees(t * 35))
        case .stars: symbol("sparkle").scaleEffect(0.85 + 0.2 * abs(sin(t * 2.4))).rotationEffect(.degrees(sin(t * 1.2) * 12))
        case .moon: symbol("moon.fill").rotationEffect(.degrees(-20 + sin(t * 1.3) * 8))
        case .sun:
            symbol("sun.max.fill").rotationEffect(.degrees(t * 25))
        case .phone:
            // Rings in bursts: a fast shake, then a pause.
            let ringing = t.truncatingRemainder(dividingBy: 1.6) < 0.7
            symbol("phone.fill").rotationEffect(.degrees(ringing ? sin(t * 40) * 14 : 0))
        case .tears:
            // A drop falls, then the cycle repeats.
            let cycle = t.truncatingRemainder(dividingBy: 1.5) / 1.5
            symbol("drop.fill", scale: 0.7).offset(y: -size * 0.4 + cycle * cycle * size * 0.75)
                .opacity(cycle < 0.85 ? 1 : (1 - cycle) / 0.15)
        case .music: symbol("music.note").offset(y: -abs(sin(t * 3.4)) * size * 0.14).rotationEffect(.degrees(sin(t * 3.4) * 8))
        case .car:
            symbol("car.side.fill").offset(x: sin(t * 2) * size * 0.06, y: abs(sin(t * 18)) * -size * 0.02)
        case .plane:
            symbol("airplane").rotationEffect(.degrees(-20)).offset(x: sin(t * 1.5) * size * 0.1, y: cos(t * 1.5) * size * 0.06)
        case .home:
            // Warm light through the doorway (drawn behind the house, so only the
            // door shows it), flickering like a fire inside; smoke from the chimney.
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(Color(red: 1, green: 0.78, blue: 0.35)
                        .opacity(0.78 + 0.12 * sin(t * 7) + 0.08 * sin(t * 13.3)))
                    .frame(width: size * 0.4, height: size * 0.5).offset(y: size * 0.24)
                symbol("house.fill")
                ForEach(0..<3, id: \.self) { puff in
                    let phase = (t * 0.55 + Double(puff) / 3).truncatingRemainder(dividingBy: 1)
                    Circle().fill(Color.white.opacity(0.5 * (1 - phase) * min(1, phase * 6)))
                        .frame(width: size * (0.09 + 0.12 * phase), height: size * (0.09 + 0.12 * phase))
                        .offset(x: size * (0.34 + 0.1 * phase + 0.03 * sin(phase * 9)), y: -size * (0.42 + 0.4 * phase))
                }
            }
        case .time: ClockFace(t: t, size: size, tint: tint)
        case .money: symbol("dollarsign.circle.fill").rotation3DEffect(.degrees(t * 160), axis: (x: 0, y: 1, z: 0))
        case .ocean:
            ZStack {
                symbol("water.waves").offset(x: sin(t * 2) * size * 0.08)
                symbol("water.waves", scale: 0.8).opacity(0.5).offset(x: -sin(t * 2) * size * 0.08, y: size * 0.18)
            }
        case .world: symbol("globe.americas.fill").rotation3DEffect(.degrees(sin(t * 0.8) * 25), axis: (x: 0, y: 1, z: 0))
        case .dance: symbol("figure.dance").rotationEffect(.degrees(sin(t * 5) * 10)).offset(y: -abs(sin(t * 5)) * size * 0.08)
        case .eyes:
            symbol("eye.fill").scaleEffect(x: 1, y: (t.truncatingRemainder(dividingBy: 2.8)) > 2.65 ? 0.1 : 1)
        case .kiss: symbol("mouth.fill").scaleEffect(1 + 0.08 * Self.bump(t.truncatingRemainder(dividingBy: 1.4), at: 0.1, width: 0.2))
        case .flower:
            // Blooms open, then sways.
            symbol("camera.macro").scaleEffect(min(1, t / 0.6)).rotationEffect(.degrees(min(1, t / 0.6) * 0 + sin(t * 1.8) * 6))
        }
    }

    private func symbol(_ name: String, scale: CGFloat = 1, color: Color? = nil) -> some View {
        Image(systemName: name).font(.system(size: size * scale, weight: .semibold))
            .foregroundStyle(color ?? tint)
            .shadow(color: (color ?? tint).opacity(0.45), radius: size * 0.08)
    }

    /// A smooth 0→1→0 bump centred at `at`.
    static func bump(_ x: Double, at: Double, width: Double) -> Double {
        let d = (x - at) / width
        return abs(d) >= 1 ? 0 : 0.5 * (1 + cos(d * .pi))
    }

    // MARK: Particles

    @ViewBuilder
    private func particles(_ t: Double) -> some View {
        switch sticker {
        case .heart, .kiss: Emitter(t: t, symbol: "heart.fill", count: 5, tint: tint, size: size, motion: .rise)
        case .fire: Emitter(t: t, symbol: "circle.fill", count: 8, tint: Color(red: 1, green: 0.7, blue: 0.2), size: size * 0.35, motion: .rise)
        case .rain: Emitter(t: t, symbol: "drop.fill", count: 7, tint: accent, size: size * 0.45, motion: .fall)
        case .snow: Emitter(t: t, symbol: "snowflake", count: 7, tint: .white, size: size * 0.5, motion: .fall)
        case .stars, .moon, .dance, .money: Emitter(t: t, symbol: "sparkle", count: 6, tint: Color(red: 1, green: 0.85, blue: 0.4), size: size * 0.6, motion: .twinkle)
        case .music: Emitter(t: t, symbol: "music.note", count: 4, tint: accent, size: size * 0.7, motion: .rise)
        case .flower: Emitter(t: t, symbol: "leaf.fill", count: 5, tint: Color(red: 1, green: 0.55, blue: 0.7), size: size * 0.5, motion: .fall)
        case .phone: Ripples(t: t, tint: tint, size: size, every: 1.6, count: 3)
        case .tears: Ripples(t: t + 0.25, tint: accent, size: size, every: 1.5, count: 1).offset(y: size * 0.38).scaleEffect(y: 0.35)
        case .brokenHeart: EmptyView()
        default: EmptyView()
        }
    }
}

/// Small figures that rise, fall or twinkle on a loop, each on its own track.
private struct Emitter: View {
    enum Motion { case rise, fall, twinkle }
    let t: Double
    let symbol: String
    let count: Int
    let tint: Color
    let size: CGFloat
    let motion: Motion

    var body: some View {
        Canvas { context, canvas in
            guard let mark = context.resolveSymbol(id: 0) else { return }
            for index in 0..<count {
                let seed = Double(index) * 1.618
                let period = 1.6 + (seed.truncatingRemainder(dividingBy: 0.9))
                let phase = ((t + seed) / period).truncatingRemainder(dividingBy: 1)
                let x = canvas.width * (0.15 + 0.7 * ((seed * 0.37).truncatingRemainder(dividingBy: 1)))
                var copy = context
                switch motion {
                case .rise:
                    let y = canvas.height * (0.85 - 0.75 * phase)
                    copy.opacity = sin(phase * .pi) * 0.9
                    copy.translateBy(x: x + sin(phase * 6 + seed) * 6, y: y)
                    copy.scaleBy(x: 0.25 + 0.2 * phase, y: 0.25 + 0.2 * phase)
                case .fall:
                    let y = canvas.height * (0.3 + 0.7 * phase)
                    copy.opacity = sin(phase * .pi) * 0.85
                    copy.translateBy(x: x + sin(phase * 4 + seed) * 5, y: y)
                    copy.scaleBy(x: 0.3, y: 0.3)
                case .twinkle:
                    let y = canvas.height * (0.1 + 0.8 * ((seed * 0.53).truncatingRemainder(dividingBy: 1)))
                    copy.opacity = max(0, sin(phase * .pi * 2)) * 0.95
                    copy.translateBy(x: x, y: y)
                    let s = 0.2 + 0.25 * max(0, sin(phase * .pi * 2))
                    copy.scaleBy(x: s, y: s)
                }
                copy.draw(mark, at: .zero)
            }
        } symbols: {
            Image(systemName: symbol).font(.system(size: size, weight: .bold)).foregroundStyle(tint).tag(0)
        }
    }
}

/// Rings spreading out, like sound or a splash.
private struct Ripples: View {
    let t: Double
    let tint: Color
    let size: CGFloat
    let every: Double
    let count: Int

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let phase = ((t - Double(index) * 0.25) / every).truncatingRemainder(dividingBy: 1)
                Circle().strokeBorder(tint.opacity(max(0, 0.7 * (1 - phase * 1.4))), lineWidth: 2)
                    .frame(width: size * (0.7 + phase * 1.0), height: size * (0.7 + phase * 1.0))
            }
        }
    }
}

/// A clock face whose hand sweeps round.
private struct ClockFace: View {
    let t: Double
    let size: CGFloat
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint).frame(width: size, height: size)
            Circle().fill(Color.white.opacity(0.92)).frame(width: size * 0.82, height: size * 0.82)
            Capsule().fill(Color.black.opacity(0.8)).frame(width: size * 0.07, height: size * 0.3)
                .offset(y: -size * 0.12).rotationEffect(.degrees(t * 120))
            Capsule().fill(Color.black.opacity(0.8)).frame(width: size * 0.07, height: size * 0.22)
                .offset(y: -size * 0.09).rotationEffect(.degrees(t * 10))
            Circle().fill(Color.black).frame(width: size * 0.1)
        }
        .shadow(color: tint.opacity(0.45), radius: size * 0.08)
    }
}

/// A heart that beats, cracks along a jagged line drawn down its middle, then
/// splits: the halves part along that edge, tilt and drop a little, and a few
/// shards fly off and fall.
private struct BrokenHeart: View {
    let t: Double
    let size: CGFloat
    let tint: Color

    /// The crack, top to bottom, in unit coordinates.
    static let crack: [CGPoint] = [CGPoint(x: 0.5, y: 0.14), CGPoint(x: 0.43, y: 0.32), CGPoint(x: 0.56, y: 0.48),
                                   CGPoint(x: 0.45, y: 0.63), CGPoint(x: 0.53, y: 0.78), CGPoint(x: 0.5, y: 0.94)]

    var body: some View {
        let beat = t < 0.55 ? StickerBeat.bump(t, at: 0.18, width: 0.16) * 0.14 : 0
        let crackDraw = min(1, max(0, (t - 0.5) / 0.3))
        let split = min(1, max(0, (t - 0.85) / 0.45))
        let eased = 1 - pow(1 - split, 3)
        let sway = split >= 1 ? sin((t - 1.3) * 2.2) * 2.5 : 0
        ZStack {
            if split == 0 {
                // Whole until it gives, so no seam shows.
                Image(systemName: "heart.fill").resizable().scaledToFit()
                    .foregroundStyle(LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size, height: size)
                    .shadow(color: tint.opacity(0.45), radius: size * 0.06)
            } else {
            half(left: true)
                .rotationEffect(.degrees(-9 * eased - sway), anchor: .bottom)
                .offset(x: -size * 0.06 * eased, y: size * 0.04 * eased)
            half(left: false)
                .rotationEffect(.degrees(9 * eased + sway), anchor: .bottom)
                .offset(x: size * 0.06 * eased, y: size * 0.04 * eased)
            }
            // The crack drawing itself before the heart gives.
            CrackLine().trim(from: 0, to: crackDraw)
                .stroke(Color.white.opacity(split > 0 ? max(0, 1 - split * 2) : 0.95),
                        style: StrokeStyle(lineWidth: max(1.5, size * 0.05), lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
            if split > 0 { shards(split) }
        }
        .scaleEffect(1 + beat)
        .frame(width: size, height: size)
    }

    /// Apple's heart symbol, cut along the jagged crack.
    private func half(left: Bool) -> some View {
        Image(systemName: "heart.fill").resizable().scaledToFit()
            .foregroundStyle(LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .mask(CrackSide(left: left).frame(width: size, height: size))
            .shadow(color: tint.opacity(0.45), radius: size * 0.06)
    }

    /// Five small pieces thrown out from the crack, falling under gravity.
    private func shards(_ progress: Double) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                let angle = -.pi / 2 + Double(index - 2) * 0.55
                let speed = 0.55 + 0.1 * Double(index % 3)
                let time = progress * 1.2
                let x = cos(angle) * speed * time * size
                let y = sin(angle) * speed * time * size + 0.9 * time * time * size
                Triangle().fill(tint.opacity(max(0, 1 - progress)))
                    .frame(width: size * 0.12, height: size * 0.12)
                    .rotationEffect(.degrees(Double(index) * 70 + progress * 220))
                    .offset(x: x, y: y + size * 0.05)
            }
        }
    }
}

private enum StickerBeat {
    static func bump(_ x: Double, at: Double, width: Double) -> Double {
        let d = (x - at) / width
        return abs(d) >= 1 ? 0 : 0.5 * (1 + cos(d * .pi))
    }
}

/// Everything on one side of the jagged crack.
private struct CrackSide: Shape {
    let left: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = BrokenHeart.crack.map { CGPoint(x: $0.x * rect.width, y: $0.y * rect.height) }
        let edge = left ? rect.minX - rect.width : rect.maxX + rect.width
        path.move(to: CGPoint(x: edge, y: rect.minY - rect.height))
        path.addLine(to: CGPoint(x: points[0].x, y: rect.minY - rect.height))
        for point in points { path.addLine(to: point) }
        path.addLine(to: CGPoint(x: points.last!.x, y: rect.maxY + rect.height))
        path.addLine(to: CGPoint(x: edge, y: rect.maxY + rect.height))
        path.closeSubpath()
        return path
    }
}

/// The crack itself, for drawing in.
private struct CrackLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = BrokenHeart.crack.map { CGPoint(x: $0.x * rect.width, y: $0.y * rect.height) }
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Karaoke

/// The line in ink, filled with the accent from left to right as it's sung.
private struct KaraokeLyric: View {
    let line: String
    let upcoming: String
    let accent: Color
    let ink: Color
    let size: CGSize
    let progress: Double

    var body: some View {
        let font = Font.system(size: min(26, size.height * 0.24), weight: .heavy, design: .rounded)
        VStack(alignment: .leading, spacing: 8) {
            Text(line)
                .font(font)
                .foregroundStyle(ink.opacity(0.35))
                .lineLimit(2).minimumScaleFactor(0.6)
                .overlay(alignment: .leading) {
                    Text(line).font(font).foregroundStyle(accent)
                        .lineLimit(2).minimumScaleFactor(0.6)
                        .mask(alignment: .leading) {
                            GeometryReader { proxy in
                                Rectangle().frame(width: proxy.size.width * progress)
                            }
                        }
                        .animation(.linear(duration: 0.25), value: progress)
                }
                .id(line)
            if !upcoming.isEmpty, upcoming != line {
                Text(upcoming).font(.system(size: max(9, size.height * 0.11), weight: .medium))
                    .foregroundStyle(ink.opacity(0.45)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Typewriter

/// Each line types itself out in a monospaced face, with a blinking cursor.
private struct TypewriterLyric: View {
    let line: String
    let accent: Color
    let ink: Color
    let size: CGSize
    let animated: Bool
    @State private var started = Date()

    var body: some View {
        let characters = Array(line)
        TimelineView(.periodic(from: .now, by: animated ? 1.0 / 30 : 3600)) { context in
            let elapsed = animated ? context.date.timeIntervalSince(started) : 60
            let perCharacter = min(0.045, 1.1 / Double(max(characters.count, 1)))
            let shown = min(characters.count, Int(elapsed / perCharacter))
            let caretOn = shown < characters.count || Int(elapsed * 2) % 2 == 0
            (Text(String(characters.prefix(shown))).foregroundColor(ink)
             + Text(caretOn ? "▍" : " ").foregroundColor(accent))
                .font(.system(size: min(22, size.height * 0.2), weight: .semibold, design: .monospaced))
                .lineLimit(3).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .id(line)
        .onAppear { started = Date() }
    }
}

#if DEBUG
/// QA: one sticker at a fixed moment.
struct StickerPreview: View {
    let sticker: LyricSticker
    let accent: Color
    let time: Double
    var body: some View { StickerView(sticker: sticker, accent: accent, size: 60, animated: true, fixedTime: time) }
}
#endif
