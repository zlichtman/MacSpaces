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
        ZStack(alignment: composition == .flushRight ? .topLeading : .topTrailing) {
            PosterLyric(line: line, accent: accent, ink: ink,
                        size: CGSize(width: size.width - (sticker == nil ? 0 : min(70, size.height * 0.5)), height: size.height),
                        composition: composition)
                .padding(composition == .flushRight ? .leading : .trailing, sticker == nil ? 0 : min(70, size.height * 0.5))
            if let sticker {
                StickerView(sticker: sticker, accent: accent, size: min(58, size.height * 0.42), animated: animated)
                    .padding(.top, size.height * 0.06)
                    .id(line)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: size.width, height: size.height)
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

/// One sticker and its motion, computed from time (TimelineView) so it never
/// depends on an animation schedule that macOS might pause.
private struct StickerView: View {
    let sticker: LyricSticker
    let accent: Color
    let size: CGFloat
    let animated: Bool
    @State private var appeared = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: animated ? 1.0 / 30 : 3600)) { context in
            let t = animated ? context.date.timeIntervalSince(appeared) : 10
            content(t)
        }
        .frame(width: size * 1.2, height: size * 1.2)
        .onAppear { appeared = Date() }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(_ t: Double) -> some View {
        let tint = sticker == .heart || sticker == .brokenHeart || sticker == .kiss ? Color(red: 1, green: 0.32, blue: 0.4) : accent
        switch sticker {
        case .brokenHeart:
            // Whole for a moment, then the two halves crack apart and tilt.
            let split = min(1, max(0, (t - 0.45) / 0.35))
            ZStack {
                half(tint, left: true).offset(x: -split * size * 0.14, y: split * size * 0.05).rotationEffect(.degrees(-split * 14))
                half(tint, left: false).offset(x: split * size * 0.14, y: split * size * 0.05).rotationEffect(.degrees(split * 14))
            }
        case .heart:
            let beat = pow(max(0, sin(t * 2 * .pi * 1.25)), 6)
            symbol(tint).scaleEffect(1 + 0.16 * beat)
        case .map, .phone:
            symbol(tint).rotationEffect(.degrees(sin(t * 7) * (sticker == .phone ? 9 : 5) * max(0, 1 - (t.truncatingRemainder(dividingBy: 2.4)) / 0.8)))
        case .fire:
            symbol(Color.orange).scaleEffect(x: 1 + 0.05 * sin(t * 11), y: 1 + 0.09 * sin(t * 9 + 1), anchor: .bottom)
                .opacity(0.85 + 0.15 * sin(t * 13))
        case .rain, .snow, .tears:
            symbol(tint).offset(y: sin(t * 2.2) * size * 0.05)
        case .stars:
            symbol(tint).opacity(0.55 + 0.45 * abs(sin(t * 2.6))).scaleEffect(0.92 + 0.1 * abs(sin(t * 2.6)))
        case .sun, .world, .time:
            symbol(tint).rotationEffect(.degrees(t * (sticker == .time ? 40 : 18)))
        case .music, .dance, .home, .kiss, .flower:
            symbol(tint).offset(y: -abs(sin(t * 3.2)) * size * 0.1)
        case .car, .plane:
            symbol(tint).offset(x: sin(t * 1.6) * size * 0.08, y: sticker == .plane ? cos(t * 1.6) * size * 0.04 : 0)
        case .money:
            symbol(tint).rotation3DEffect(.degrees(t * 120), axis: (x: 0, y: 1, z: 0))
        case .ocean, .moon:
            symbol(tint).offset(y: sin(t * 1.8) * size * 0.04).rotationEffect(.degrees(sin(t * 1.4) * 4))
        case .eyes:
            symbol(tint).scaleEffect(x: 1, y: (t.truncatingRemainder(dividingBy: 3)) > 2.85 ? 0.1 : 1)
        }
    }

    private func symbol(_ tint: Color) -> some View {
        Image(systemName: sticker.symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(tint)
    }

    private func half(_ tint: Color, left: Bool) -> some View {
        symbol(tint).mask(alignment: left ? .leading : .trailing) {
            Rectangle().frame(width: size * 0.62)
        }
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
