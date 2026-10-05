import SwiftUI

/// World clocks on a dot-matrix board: "06:28 LOS ANGELES", one city a row, each
/// character a 5×7 grid of dots with the unlit ones faintly showing. Your own
/// city lights in the accent; when the minute turns, changing characters flick
/// through a few others like a split-flap board.
struct WorldClockWidget: View {
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let zones = options.worldClockCities.compactMap { id in
            WidgetOptions.worldClockZones.first { $0.identifier == id }
        }
        TimelineView(FlipSchedule(flips: !reduceMotion)) { context in
            DotBoard(rows: zones.map { Self.row($0.title, zone: TimeZone(identifier: $0.identifier), at: context.date) },
                     local: zones.map { $0.identifier == TimeZone.current.identifier },
                     date: context.date, flips: !reduceMotion,
                     ink: theme.nookForeground, accent: theme.notch.accent)
        }
        .padding(10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(zones.map { "\($0.title) \(Self.time(TimeZone(identifier: $0.identifier), at: Date()))" }.joined(separator: ", "))
    }

    static func time(_ zone: TimeZone?, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// "06:28 LOS ANGELES", in the characters the board can show.
    static func row(_ city: String, zone: TimeZone?, at date: Date) -> String {
        let name = city.folding(options: .diacriticInsensitive, locale: nil).uppercased()
        return time(zone, at: date) + " " + name
    }
}

/// Every second, plus quick frames just after each minute turns for the flip.
private struct FlipSchedule: TimelineSchedule {
    let flips: Bool
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next = startDate
        return AnyIterator {
            defer {
                let second = Calendar.current.component(.second, from: next)
                let fraction = next.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
                next = flips && mode != .lowFrequency && second == 0 && fraction < 0.6
                    ? next.addingTimeInterval(0.07)
                    : Date(timeIntervalSince1970: floor(next.timeIntervalSince1970) + 1)
            }
            return next
        }
    }
}

private struct DotBoard: View {
    let rows: [String]
    let local: [Bool]
    let date: Date
    let flips: Bool
    let ink: Color
    let accent: Color

    /// Columns per row: the time, a space and the longest city, at least eleven.
    private var columns: Int { max(17, rows.map(\.count).max() ?? 17) }

    var body: some View {
        Canvas { context, size in
            guard !rows.isEmpty else { return }
            let cellWidth = 6, cellHeight = 9          // 5×7 glyph plus a dot of space, rows a little apart
            let pitch = min(size.width / CGFloat(columns * cellWidth - 1), size.height / CGFloat(rows.count * cellHeight - 2))
            let dot = pitch * 0.78
            let boardWidth = CGFloat(columns * cellWidth - 1) * pitch
            let boardHeight = CGFloat(rows.count * cellHeight - 2) * pitch
            let origin = CGPoint(x: (size.width - boardWidth) / 2, y: (size.height - boardHeight) / 2)
            let seconds = date.timeIntervalSince1970
            let flipping = flips && Calendar.current.component(.second, from: date) == 0 && seconds.truncatingRemainder(dividingBy: 1) < 0.55
            let blink = Int(seconds) % 2 == 0
            for (r, row) in rows.enumerated() {
                let characters = Array(row.padding(toLength: columns, withPad: " ", startingAt: 0))
                let lit = local[safe: r] == true ? accent : ink
                for (c, character) in characters.enumerated() {
                    var shown = character
                    // The minute digits flick through others for a moment as they change.
                    if flipping, c == 3 || c == 4 {
                        shown = Array("0123456789")[Int(seconds * 14 + Double(r * 3 + c)) % 10]
                    }
                    if c == 2, !blink { shown = " " }   // the colon ticks
                    let glyph = DotFont.glyph(shown)
                    for y in 0..<7 {
                        for x in 0..<5 {
                            let on = glyph[y] & (1 << (4 - x)) != 0
                            let point = CGPoint(x: origin.x + CGFloat(c * cellWidth + x) * pitch,
                                                y: origin.y + CGFloat(r * cellHeight + y) * pitch)
                            let rect = CGRect(x: point.x, y: point.y, width: dot, height: dot)
                            context.fill(Path(ellipseIn: rect), with: .color(on ? lit : ink.opacity(0.09)))
                        }
                    }
                }
            }
        }
    }
}

/// A 5×7 dot font: each row's five bits, top to bottom.
enum DotFont {
    static func glyph(_ character: Character) -> [UInt8] { table[character] ?? table[" "]! }

    static let table: [Character: [UInt8]] = [
        " ": [0, 0, 0, 0, 0, 0, 0],
        ":": [0, 0b00100, 0b00100, 0, 0b00100, 0b00100, 0],
        ".": [0, 0, 0, 0, 0, 0b00110, 0b00110],
        "-": [0, 0, 0, 0b11111, 0, 0, 0],
        "'": [0b00100, 0b00100, 0, 0, 0, 0, 0],
        "0": [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110],
        "1": [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
        "2": [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111],
        "3": [0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110],
        "4": [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010],
        "5": [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110],
        "6": [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110],
        "7": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000],
        "8": [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110],
        "9": [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100],
        "A": [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
        "B": [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110],
        "C": [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110],
        "D": [0b11100, 0b10010, 0b10001, 0b10001, 0b10001, 0b10010, 0b11100],
        "E": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111],
        "F": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000],
        "G": [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111],
        "H": [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
        "I": [0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
        "J": [0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100],
        "K": [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001],
        "L": [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111],
        "M": [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001],
        "N": [0b10001, 0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001],
        "O": [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
        "P": [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000],
        "Q": [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101],
        "R": [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001],
        "S": [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110],
        "T": [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100],
        "U": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
        "V": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100],
        "W": [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010],
        "X": [0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001],
        "Y": [0b10001, 0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100],
        "Z": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111],
    ]
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
