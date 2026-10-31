import AppKit
import QuartzCore

extension LyricTypographyCanvas {
    /// A little departure board. Individual plates compress and open in a
    /// diagonal wave, then become perfectly still. The original word order and
    /// every grapheme are preserved, including scripts without spaces.
    func departure(_ line: String, upcoming: String) {
        let w = size.width, h = size.height
        let inset: CGFloat = 8
        let available = max(1, w - inset * 2)
        let boardHeight = h * 0.76
        let upper = line.uppercased()
        // A cell is deliberately wider than its glyph: narrow gutters and a
        // centre seam give the sign its rhythm without tiny decorative labels.
        var point = min(23, h * 0.185)
        var plan = departureRows(upper, point: point, width: available)
        while point > 10, CGFloat(plan.rows.count) * point * 1.55 > boardHeight {
            point -= 1
            plan = departureRows(upper, point: point, width: available)
        }
        let step = point * 1.55
        let cellHeight = step - 3
        let top = max(3, (boardHeight - CGFloat(plan.rows.count) * step) / 2 + h * 0.035)
        let face = NSFont.monospacedSystemFont(ofSize: point, weight: .semibold)
        let turn = min(0.38 / tempo(line), duration * 0.22)
        let wave = min(0.5 / tempo(line), duration * 0.24)
        let count = max(1, plan.rows.reduce(0) { $0 + $1.count })
        var position = 0
        for (rowIndex, row) in plan.rows.enumerated() {
            let left = (w - CGFloat(row.count) * plan.cell) / 2
            for (column, character) in row.enumerated() {
                defer { position += 1 }
                guard !character.isWhitespace else { continue }
                let plate = holder(CGRect(x: left + CGFloat(column) * plan.cell,
                                          y: top + CGFloat(rowIndex) * step,
                                          width: plan.cell - 2, height: cellHeight))
                plate.cornerRadius = 2
                plate.backgroundColor = ink.withAlphaComponent(0.055).cgColor
                plate.borderColor = ink.withAlphaComponent(0.13).cgColor
                plate.borderWidth = 0.5
                plate.masksToBounds = true
                // A slight tonal division reads as two separate leaves.
                rule(CGRect(x: 0, y: cellHeight * 0.5, width: plate.bounds.width, height: cellHeight * 0.5),
                     color: accent.withAlphaComponent(0.055), in: plate)
                let glyph = text(String(character), font: face, color: accent,
                                 frame: CGRect(x: 0, y: (cellHeight - point * 1.25) / 2,
                                               width: plate.bounds.width, height: point * 1.35), in: plate)
                // Wide fallback glyphs (CJK, emoji) get a wider cell rather
                // than being squeezed into an English character's slot.
                glyph.truncationMode = .none
                rule(CGRect(x: 0, y: floor(cellHeight * 0.5), width: plate.bounds.width, height: 0.65),
                     color: ink.withAlphaComponent(0.18), in: plate)
                let delay = Double(position) / Double(count) * wave
                animate(glyph, "transform.scale.y", values: [0.06, 1.06, 1], times: [0, 0.72, 1],
                        duration: turn, delay: delay)
                animate(glyph, "opacity", values: [0, 1], times: [0, 1], duration: turn * 0.65, delay: delay)
            }
        }

        if !upcoming.isEmpty, upcoming != line {
            let footer = holder(CGRect(x: inset + 3, y: h * 0.85, width: max(1, available - 6), height: h * 0.14))
            footer.masksToBounds = true
            rule(CGRect(x: 0, y: 3, width: 2, height: 7), color: accent.withAlphaComponent(0.65), in: footer)
            let next = text(upcoming, font: .monospacedSystemFont(ofSize: 10, weight: .regular),
                            color: ink.withAlphaComponent(0.48),
                            frame: CGRect(x: 9, y: 0, width: max(1, footer.bounds.width - 9), height: footer.bounds.height),
                            alignment: .left, in: footer)
            next.truncationMode = .end
        }
    }

    private func departureRows(_ line: String, point: CGFloat, width: CGFloat) -> (rows: [[Character]], cell: CGFloat) {
        let font = NSFont.monospacedSystemFont(ofSize: point, weight: .semibold)
        let characters = Array(line)
        let widest = characters.map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? point * 0.6
        let cell = max(point * 0.79, widest + 5)
        let columns = max(1, Int(width / cell))
        var result: [[Character]] = []
        var remaining = characters[...]
        while !remaining.isEmpty {
            while remaining.first?.isWhitespace == true { remaining = remaining.dropFirst() }
            guard !remaining.isEmpty else { break }
            let prefix = Array(remaining.prefix(columns))
            var length = prefix.count
            if remaining.count > columns, remaining.dropFirst(columns).first?.isWhitespace != true,
               let space = prefix.lastIndex(where: { $0.isWhitespace }), space > 0 {
                length = space
            }
            result.append(Array(remaining.prefix(length)))
            remaining = remaining.dropFirst(length)
        }
        return (result, cell)
    }
}
