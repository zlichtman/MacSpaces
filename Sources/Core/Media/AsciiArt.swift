import Foundation

/// How ASCII art turns a cell's 2×4 pixels into a character.
enum AsciiStyle: String, CaseIterable, Identifiable {
    case braille, classic, fine, blocks, scanline, contour, binary
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// What the ASCII cover draws before it's turned into characters.
enum AsciiScene: String, CaseIterable, Identifiable {
    case vinyl, cover, pulse, horizon, spiral
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Where the ASCII art's colours come from: the theme (pick a theme for a white, red or amber
/// look) or the cover.
enum AsciiColouring: String, CaseIterable, Identifiable {
    case theme, cover
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// How big the characters are: smaller means more of them.
enum AsciiDetail: String, CaseIterable, Identifiable {
    case fine, medium, chunky
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var fontSize: Double {
        switch self {
        case .fine: return 7
        case .medium: return 8.5
        case .chunky: return 10.5
        }
    }
}

/// One character cell: what to draw and how bright it is (0…1), which picks its colour.
/// Braille cells carry their dots in `dots` (bit order of U+2800) and draw no character.
struct AsciiCell: Equatable {
    var character: Character = " "
    var dots: UInt8 = 0
    var level: Float = 0
    var isBlank: Bool { dots == 0 && character == " " }
    /// The colour bucket: 0 dim, 1 middle, 2 accent.
    var bucket: Int { level < 0.33 ? 0 : level < 0.68 ? 1 : 2 }
}

/// Luminance (2×cols by 4×rows, row-major) to a grid of characters, after the
/// reference player's renderer.
enum AsciiArt {
    static let classic = Array(" .:-=+*#%@")
    static let fine = Array(" .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$")
    static let blocks = Array(" ░▒▓█")
    static let scan = Array(" ·-=≡▬")
    static let bayer: [[Float]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    /// Braille dot bits by row (0–3) and column (0–1).
    static let brailleBits: [[UInt8]] = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]]

    /// The slight contrast curve applied to every sample: (L − 0.03) × 1.12, clamped.
    static func contrast(_ value: Float) -> Float { min(1, max(0, (value - 0.03) * 1.12)) }

    static func convert(_ luminance: [Float], style: AsciiStyle, columns: Int, rows: Int, tick: Int) -> [AsciiCell] {
        let width = columns * 2
        guard luminance.count >= width * rows * 4, columns > 0, rows > 0 else { return [] }
        func cellMean(_ c: Int, _ r: Int) -> Float {
            var sum: Float = 0
            for y in 0..<4 { for x in 0..<2 { sum += luminance[(r * 4 + y) * width + c * 2 + x] } }
            return sum / 8
        }
        var means: [Float] = []
        if style == .contour {
            means = (0..<(columns * rows)).map { cellMean($0 % columns, $0 / columns) }
        }
        var cells = [AsciiCell](repeating: AsciiCell(), count: columns * rows)
        for r in 0..<rows {
            for c in 0..<columns {
                var cell = AsciiCell()
                switch style {
                case .braille:
                    var bits: UInt8 = 0, sum: Float = 0
                    for y in 0..<4 {
                        for x in 0..<2 {
                            let px = c * 2 + x, py = r * 4 + y
                            let v = luminance[py * width + px]
                            sum += v
                            if v > (bayer[py & 3][px & 3] + 0.5) / 16 { bits |= brailleBits[y][x] }
                        }
                    }
                    cell.level = sum / 8
                    cell.dots = bits
                case .classic:
                    cell.level = cellMean(c, r)
                    cell.character = classic[min(classic.count - 1, Int(cell.level * Float(classic.count)))]
                case .fine:
                    cell.level = cellMean(c, r)
                    cell.character = fine[min(fine.count - 1, Int(cell.level * Float(fine.count)))]
                case .blocks:
                    cell.level = cellMean(c, r)
                    let jitter = (bayer[r & 3][c & 3] / 16 - 0.5) * 0.2
                    cell.character = blocks[max(0, min(4, Int((cell.level + jitter) * 5)))]
                case .scanline:
                    cell.level = cellMean(c, r)
                    cell.character = r % 2 == 1 ? " " : scan[min(5, Int(cell.level * 6))]
                case .binary:
                    cell.level = cellMean(c, r)
                    if cell.level > 0.1 {
                        let hash = UInt32(truncatingIfNeeded: (c &* 73_856_093) ^ (r &* 19_349_663) ^ (tick &* 83_492_791))
                        cell.character = hash % 7 < 3 ? "1" : "0"
                    }
                case .contour:
                    cell.level = means[r * columns + c]
                    func g(_ cc: Int, _ rr: Int) -> Float {
                        means[max(0, min(rows - 1, rr)) * columns + max(0, min(columns - 1, cc))]
                    }
                    let gx = (g(c + 1, r - 1) + 2 * g(c + 1, r) + g(c + 1, r + 1)) - (g(c - 1, r - 1) + 2 * g(c - 1, r) + g(c - 1, r + 1))
                    let gy = (g(c - 1, r + 1) + 2 * g(c, r + 1) + g(c + 1, r + 1)) - (g(c - 1, r - 1) + 2 * g(c, r - 1) + g(c + 1, r - 1))
                    if (gx * gx + gy * gy * 4).squareRoot() > 0.6 {
                        var angle = atan2(Double(gy * 2), Double(gx)) + .pi / 2
                        angle = (angle.truncatingRemainder(dividingBy: .pi) + .pi).truncatingRemainder(dividingBy: .pi)
                        cell.character = Array("-\\|/")[Int((angle / (.pi / 4)).rounded()) % 4]
                        cell.level = max(cell.level, 0.75)
                    } else {
                        cell.character = Array(" .:")[min(2, Int(cell.level * 3.2))]
                    }
                }
                cells[r * columns + c] = cell
            }
        }
        return cells
    }

    /// The beat's envelope, 1 on the beat and falling away: exp(−phase × 5).
    static func beat(position: Double, tempo: Double) -> Double {
        let beats = max(0, position) * max(40, tempo) / 60
        return exp(-(beats - beats.rounded(.down)) * 5)
    }
}
