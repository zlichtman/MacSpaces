import SwiftUI
import AppKit

/// Sets one lyric in the chosen `LyricStyle`. Sizes follow the space given, so the same view
/// serves the Music page and the preview in Settings.
struct StyledLyricView: View {
    let style: LyricStyle
    let current: String
    let accent: Color
    let ink: Color
    var animated = true
    /// Counts line changes, so a repeated line (a chorus hook) still turns over.
    var sequence = 0

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch style {
                case .poster:
                    PosterLyric(line: current, accent: accent, ink: ink, size: proxy.size,
                                composition: PosterLyric.composition(for: current), identity: sequence)
                case .terminal:
                    TerminalLyricLine(line: current, accent: accent, identity: sequence, animated: animated)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lyrics: \(current)")
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
