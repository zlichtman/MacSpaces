import SwiftUI

/// The Clock's Dot style: one place a row, its name in small capitals and its time in
/// dot-matrix digits ("LOS ANGELES  +1  06:28"). Only the digits' own dots show,
/// faintly when unlit; where you are is in the accent. When the minute turns, the
/// minute digits flick through a few others like a split-flap board. Small shows
/// just one time, filling the tile.
struct DotClock: View {
    let places: [String]
    var compact = false
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(FlipSchedule(flips: !reduceMotion)) { context in
            if compact {
                DotTime(text: Self.time(WidgetOptions.zone(places.first ?? WidgetOptions.local), at: Design.clockDate(context.date)),
                        date: Design.clockDate(context.date), flips: !reduceMotion, lit: theme.nookForeground, unlit: theme.nookForeground.opacity(0.06))
                    .aspectRatio(DotTime.aspect, contentMode: .fit)
                    .padding(.horizontal, 12).padding(.vertical, 14)
            } else {
                GeometryReader { proxy in
                    let rowHeight = proxy.size.height / CGFloat(max(places.count, 1))
                    VStack(spacing: 0) {
                        ForEach(Array(places.enumerated()), id: \.offset) { index, place in
                            row(place, date: Design.clockDate(context.date), height: rowHeight)
                            if index < places.count - 1 {
                                Rectangle().fill(theme.nookForeground.opacity(0.06)).frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(places.map { "\(WidgetOptions.placeName($0)) \(Self.time(WidgetOptions.zone($0), at: Date()))" }.joined(separator: ", "))
    }

    private func row(_ place: String, date: Date, height: CGFloat) -> some View {
        let here = place == WidgetOptions.local || place == TimeZone.current.identifier
        let ink = here ? theme.notch.accent : theme.nookForeground
        let zone = WidgetOptions.zone(place)
        return HStack(spacing: 8) {
            Circle().fill(theme.notch.accent).frame(width: 4, height: 4).opacity(here ? 1 : 0)
            Text(WidgetOptions.placeName(place).uppercased())
                .font(.system(size: min(11, height * 0.34), weight: .semibold)).tracking(0.8)
                .foregroundStyle(ink.opacity(here ? 1 : 0.75))
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            if let offset = Self.dayOffset(zone, at: date) {
                Text(offset).font(.system(size: min(9, height * 0.28), weight: .bold, design: .rounded))
                    .foregroundStyle(theme.nookForeground.opacity(0.45))
            }
            // A fixed width keeps every row's time in the same column.
            DotTime(text: Self.time(zone, at: date), date: date, flips: !reduceMotion,
                    lit: ink, unlit: theme.nookForeground.opacity(0.06))
                .frame(width: max(8, height * 0.56) * DotTime.aspect, height: max(8, height * 0.56))
        }
        .frame(height: height - 1)
    }

    static func time(_ zone: TimeZone?, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// "+1" or "−1" when it's already tomorrow, or still yesterday, there.
    static func dayOffset(_ zone: TimeZone?, at date: Date) -> String? {
        guard let zone else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        let here = calendar.dateComponents([.year, .month, .day], from: date)
        calendar.timeZone = zone
        let there = calendar.dateComponents([.year, .month, .day], from: date)
        guard here != there, let a = Calendar.current.date(from: here), let b = Calendar.current.date(from: there) else { return nil }
        return b > a ? "+1" : "−1"
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

/// "HH:mm" in 5×7 dot digits with a one-column colon, scaled to fit its frame.
struct DotTime: View {
    /// Width to height for "HH:mm": 25 columns by 7 rows.
    static let aspect: CGFloat = 25.0 / 7.0
    let text: String
    var date = Date()
    var flips = false
    let lit: Color
    let unlit: Color

    var body: some View {
        Canvas { context, size in
            let characters = Array(text)
            // Digits are five columns, the colon one; a column of space between each.
            let widths = characters.map { $0 == ":" ? 1 : 5 }
            let columns = widths.reduce(0, +) + max(0, characters.count - 1)
            let pitch = min(size.width / CGFloat(columns), size.height / 7)
            let dot = pitch * 0.8
            var x = (size.width - CGFloat(columns) * pitch) / 2 + (pitch - dot) / 2
            let top = (size.height - 7 * pitch) / 2 + (pitch - dot) / 2
            let seconds = date.timeIntervalSince1970
            let flipping = flips && Calendar.current.component(.second, from: date) == 0
                && seconds.truncatingRemainder(dividingBy: 1) < 0.55
            for (index, character) in characters.enumerated() {
                var shown = character
                // The minute digits flick through others for a moment as they change.
                if flipping, index >= characters.count - 2, character.isNumber {
                    shown = Array("0123456789")[Int(seconds * 14 + Double(index)) % 10]
                }
                let glyph = DotFont.glyph(shown)
                let width = widths[index]
                for row in 0..<7 {
                    for column in 0..<width {
                        // The colon uses the middle column of its glyph.
                        let bit = width == 1 ? 2 : column
                        let on = glyph[row] & (1 << (4 - bit)) != 0
                        guard on || width > 1 else { continue }
                        let rect = CGRect(x: x + CGFloat(column) * pitch, y: top + CGFloat(row) * pitch, width: dot, height: dot)
                        context.fill(Path(ellipseIn: rect), with: .color(on ? lit : unlit))
                    }
                }
                x += CGFloat(width + 1) * pitch
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
