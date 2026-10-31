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
    /// How much of the line Typewriter has typed (0–1), from the song's clock;
    /// nil types on its own clock (Settings previews).
    var typed: Double?
    /// The line's sung span, from which Mood and Scenes read the pace; nil for untimed lyrics.
    var span: ClosedRange<TimeInterval>?
    /// The song's position as the view was built, so a Scenes scene that opens mid-line starts there.
    var songTime: TimeInterval?
    /// Mood's and Scenes' motion holds while the song is paused.
    var playing = true

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch style {
                case .classic:
                    ClassicLyric(current: current, upcoming: upcoming, accent: accent, ink: ink, size: proxy.size, identity: sequence)
                case .poster:
                    PosterLyric(line: current, accent: accent, ink: ink, size: proxy.size,
                                composition: PosterLyric.composition(for: current), identity: sequence)
                case .mood:
                    MoodLyric(line: current, accent: accent, ink: ink, size: proxy.size, animated: animated, playing: playing,
                              span: span, songTime: songTime, composition: PosterLyric.composition(for: current), identity: sequence)
                case .choreography:
                    ChoreographyLyric(line: current, upcoming: upcoming, accent: accent, ink: ink,
                                      size: proxy.size, animated: animated, identity: sequence)
                case .stickers:
                    StickerLyric(line: current, accent: accent, ink: ink, size: proxy.size, animated: animated, playing: playing,
                                 span: span, songTime: songTime, composition: PosterLyric.composition(for: current),
                                 identity: sequence)
                case .karaoke:
                    KaraokeLyric(line: current, upcoming: upcoming, accent: accent, ink: ink, size: proxy.size,
                                 progress: animated ? progress : 1, identity: sequence)
                case .typewriter:
                    TypewriterLyric(line: current, accent: accent, ink: ink, size: proxy.size, animated: animated,
                                    typed: typed, identity: sequence)
                case .cinema, .departure:
                    TypographyLyric(style: style, line: current, upcoming: upcoming, accent: accent, ink: ink,
                                    size: proxy.size, animated: animated, playing: playing,
                                    span: span, songTime: songTime, identity: sequence)
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
    let ink: Color
    let size: CGSize
    var identity = 0

    var body: some View {
        // Never smaller than the song title's weight of text above it.
        let scale = min(1.6, max(1.1, size.height / 110))
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text(current)
                .font(.system(size: 14 * scale, weight: .semibold))
                .foregroundStyle(accent)
                .lineLimit(2).minimumScaleFactor(0.85)
                .id(identity)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            // A repeated line (a chorus hook) would otherwise show twice. The row
            // keeps its height, so hiding it never moves the current line.
            Text(upcoming.isEmpty ? " " : upcoming)
                .font(.system(size: 12 * scale, weight: .medium))
                .foregroundStyle(ink.opacity(0.5))
                .lineLimit(1)
                .opacity(upcoming.isEmpty || upcoming == current ? 0 : 1)
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
        /// Italic lead-in above, the rest plain beneath the headline.
        case stacked
        /// The whole poster set flush right.
        case flushRight
    }

    let line: String
    let accent: Color
    let ink: Color
    let size: CGSize
    var composition: Composition = .leadAbove
    var identity = 0

    /// Each line keeps its own composition, so a returning chorus line looks the
    /// same every time. Most lines stay left-aligned (the eye doesn't have to hunt
    /// for them); flush right is kept for short, punchy lines.
    static func composition(for line: String) -> Composition {
        let seed = line.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value }
        let words = line.split(separator: " ").count
        if words <= 4, seed % 4 == 0 { return .flushRight }
        return seed % 2 == 0 ? .stacked : .leadAbove
    }

    var body: some View {
        let parts = Self.split(line)
        let hero = min(size.height * (composition == .leadAbove ? 0.56 : 0.48), 72)
        let alignment: HorizontalAlignment = composition == .flushRight ? .trailing : .leading
        let frameAlignment: Alignment = composition == .flushRight ? .trailing : .leading
        VStack(alignment: alignment, spacing: 0) {
            switch composition {
            case .leadAbove where !Self.fitsBeside(parts, hero: hero, width: size.width):
                // Not enough room for a side column without crushing the headline:
                // the rest goes beneath, in the italic voice.
                if !parts.lead.isEmpty { italic(parts.lead, hero: hero).padding(.bottom, -hero * 0.06) }
                headline(parts.hero, hero: hero, alignment: .leading)
                if !parts.trail.isEmpty { italic(parts.trail, hero: hero).padding(.top, -hero * 0.04) }
            case .leadAbove:
                if !parts.lead.isEmpty { italic(parts.lead, hero: hero).padding(.bottom, -hero * 0.06) }
                // The words after the headline always get a readable column; the
                // headline shrinks into what's left rather than crushing them.
                HStack(alignment: .lastTextBaseline, spacing: max(6, hero * 0.12)) {
                    // Keep short words together; an expanding headline frame pushes
                    // the tail to the far edge of the lyric area.
                    headline(parts.hero, hero: hero, alignment: .leading, fillsWidth: false)
                    if !parts.trail.isEmpty {
                        Text(parts.trail)
                            .font(.system(size: max(12, hero * 0.21), weight: .medium))
                            .foregroundStyle(ink.opacity(0.88))
                            .lineLimit(4).minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: min(max(size.width * 0.3, 72), 150), alignment: .leading)
                    }
                }
            case .stacked:
                // The words read as one sentence into the headline: the lead in the
                // italic voice at nearly full ink (a pale, tracked all-caps caption
                // read as a label, not as the lyric), the tail plain beneath.
                if !parts.lead.isEmpty { italic(parts.lead, hero: hero).padding(.bottom, -hero * 0.06) }
                headline(parts.hero, hero: hero, alignment: .leading)
                if !parts.trail.isEmpty {
                    Text(parts.trail)
                        .font(.system(size: max(12, hero * 0.22), weight: .semibold))
                        .foregroundStyle(ink.opacity(0.92))
                        .lineLimit(2).minimumScaleFactor(0.85)
                        .padding(.top, -hero * 0.02)
                }
            case .flushRight:
                if !parts.lead.isEmpty { italic(parts.lead, hero: hero).multilineTextAlignment(.trailing).padding(.bottom, -hero * 0.06) }
                headline(parts.hero, hero: hero, alignment: .trailing)
                if !parts.trail.isEmpty {
                    Text(parts.trail)
                        .font(.system(size: max(12, hero * 0.22), weight: .semibold))
                        .foregroundStyle(ink.opacity(0.88))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2).minimumScaleFactor(0.85)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
        .id(identity)
        .transition(.asymmetric(insertion: .scale(scale: 0.92, anchor: composition == .flushRight ? .trailing : .leading)
                                    .combined(with: .opacity),
                                removal: .opacity))
    }

    private func headline(_ word: String, hero: CGFloat, alignment: Alignment, fillsWidth: Bool = true) -> some View {
        Text(word.uppercased())
            .font(.system(size: hero, weight: .black).width(.compressed))
            .foregroundStyle(accent)
            .lineLimit(1).minimumScaleFactor(0.3)
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: alignment)
    }

    private func italic(_ text: String, hero: CGFloat) -> some View {
        Text(text)
            .font(.system(size: max(13, hero * 0.27), design: .serif).italic())
            .foregroundStyle(ink.opacity(0.92))
            .lineLimit(2).minimumScaleFactor(0.85)
    }

    /// Whether a short tail fits in a side column beside the full-size headline.
    static func fitsBeside(_ parts: (lead: String, hero: String, trail: String), hero: CGFloat, width: CGFloat) -> Bool {
        guard !parts.trail.isEmpty else { return true }
        // A side column only suits a short tail; longer ones stack into a cramped column.
        guard parts.trail.split(separator: " ").count <= 3 else { return false }
        // Compressed black capitals run about 0.5 em wide.
        let headline = CGFloat(parts.hero.count) * hero * 0.5
        let column = min(max(width * 0.3, 72), 150)
        return headline + hero * 0.16 + column <= width
    }

    static func split(_ line: String) -> (lead: String, hero: String, trail: String) {
        // Bracketed ad-libs never become the headline; they follow the line, small.
        let parts = Lyrics.asides(line)
        let words = parts.sung.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return ("", line, "") }
        let index = heroIndex(words)
        // Commas and full stops go; an apostrophe, ? or ! stays part of the word.
        let hero = words[index].trimmingCharacters(in: CharacterSet(charactersIn: ",.;:\"“”()"))
        let asides = parts.asides.map { "(\($0))" }
        return (words[..<index].joined(separator: " "), hero.isEmpty ? words[index] : hero,
                (Array(words[(index + 1)...]) + asides).joined(separator: " "))
    }

    /// Longest word wins; on a tie the later one, which usually lands the phrase.
    /// Long filler ("something", "everything") gives way to a word that means more.
    static func heroIndex(_ words: [String]) -> Int {
        let letters = words.map { $0.filter { $0.isLetter || $0.isNumber } }
        let candidates = words.indices.filter { !filler.contains(letters[$0].lowercased()) }
        var index = 0, best = -1
        for i in candidates.isEmpty ? Array(words.indices) : candidates where letters[i].count >= best {
            best = letters[i].count; index = i
        }
        return index
    }

    static let filler: Set<String> = ["something", "everything", "nothing", "anything", "somebody", "everybody",
                                      "nobody", "anybody", "someone", "everyone", "because", "without", "another",
                                      "through", "though", "should", "would", "could", "about", "there", "where"]
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
    var identity = 0

    var body: some View {
        let words = line.split(separator: " ").map(String.init)
        let hero = PosterLyric.heroIndex(words)
        // The whole line is in place within about half a second, however long it is.
        let stagger = min(0.075, 0.45 / Double(max(words.count, 1)))
        let base = min(26, size.height * 0.24) * (words.count > 9 ? 0.72 : words.count > 5 ? 0.86 : 1)
        VStack(alignment: .leading, spacing: base * 0.45) {
            WordFlow(spacing: base * 0.3, lineSpacing: base * 0.1) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    ChoreographedWord(word: word, delay: Double(index) * stagger, hero: index == hero, size: base,
                                      accent: accent, ink: ink, animated: animated)
                }
            }
            .id(identity)
            if !upcoming.isEmpty, upcoming != line {
                Text(upcoming)
                    .font(.system(size: max(9, base * 0.46), weight: .medium))
                    .foregroundStyle(ink.opacity(0.45)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

}

private struct ChoreographedWord: View {
    let word: String
    let delay: Double
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
            .blur(radius: shown ? 0 : 3)
            .offset(y: shown ? 0 : size * 0.4)
            .scaleEffect(shown ? 1 : 0.86, anchor: .bottom)
            .onAppear {
                guard animated else { shown = true; return }
                withAnimation(Design.timed(.spring(response: 0.36, dampingFraction: 0.72).delay(delay))) { shown = true }
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

// MARK: - Karaoke

/// The line in ink, filled with the accent from left to right as it's sung.
private struct KaraokeLyric: View {
    let line: String
    let upcoming: String
    let accent: Color
    let ink: Color
    let size: CGSize
    let progress: Double
    var identity = 0

    var body: some View {
        // Filled letter by letter in one text, so a line that wraps fills its
        // first row before its second, and the layout never changes as it fills.
        let characters = Array(line)
        let filled = Int((Double(characters.count) * progress).rounded())
        VStack(alignment: .leading, spacing: 8) {
            (Text(String(characters.prefix(filled))).foregroundColor(accent)
             + Text(String(characters.dropFirst(filled))).foregroundColor(ink.opacity(0.35)))
                .font(.system(size: min(26, size.height * 0.24), weight: .heavy, design: .rounded))
                .lineLimit(2).minimumScaleFactor(0.6)
                .id(identity)
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
    /// Typed so far (0–1) from the song's clock; nil types on its own clock.
    var typed: Double?
    var identity = 0
    @State private var started = Date()

    var body: some View {
        if let typed {
            text(typed: typed, caretOn: typed < 1 || Int(Date().timeIntervalSince(started) * 2) % 2 == 0)
                .id(identity)
                .onAppear { started = Date() }
        } else {
            TimelineView(.periodic(from: .now, by: animated ? 1.0 / 30 : 3600)) { context in
                let elapsed = animated ? context.date.timeIntervalSince(started) : 60
                text(typed: min(1, elapsed / 1.1), caretOn: elapsed < 1.1 || Int(elapsed * 2) % 2 == 0)
            }
            .id(identity)
            .onAppear { started = Date() }
        }
    }

    /// The whole line is always laid out (the untyped part clear), so the words
    /// never jump to another row as they're typed.
    private func text(typed: Double, caretOn: Bool) -> some View {
        let characters = Array(line)
        let shown = min(characters.count, Int((Double(characters.count) * typed).rounded()))
        return (Text(String(characters.prefix(shown))).foregroundColor(ink)
                + Text("▍").foregroundColor(caretOn ? accent : .clear)
                + Text(String(characters.dropFirst(shown))).foregroundColor(.clear))
            .font(.system(size: min(22, size.height * 0.2), weight: .semibold, design: .monospaced))
            .lineLimit(3).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
