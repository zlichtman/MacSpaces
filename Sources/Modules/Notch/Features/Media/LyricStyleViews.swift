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
