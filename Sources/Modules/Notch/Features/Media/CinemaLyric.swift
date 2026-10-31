import AppKit
import QuartzCore

extension LyricTypographyCanvas {
    /// A quiet title sequence: fine letterbox rules, generous negative space,
    /// centred book type and a barely perceptible push towards the words.
    func cinema(_ line: String, upcoming: String) {
        let w = size.width, h = size.height
        let inset = max(10, w * 0.045)
        let top = h * 0.12, bottom = h * 0.79
        // Letterbox edges are tonal rather than black, so light themes work too.
        rule(CGRect(x: inset, y: top, width: w - inset * 2, height: 0.5), color: ink.withAlphaComponent(0.19))
        rule(CGRect(x: inset, y: bottom, width: w - inset * 2, height: 0.5), color: ink.withAlphaComponent(0.19))
        let mark = rule(CGRect(x: w * 0.5 - 12, y: top - 0.5, width: 24, height: 1.5), color: accent)
        animate(mark, "transform.scale.x", values: [0.15, 1], times: [0, 1], duration: 0.65 / tempo(line))

        let area = CGRect(x: inset + 6, y: top + 9, width: max(1, w - inset * 2 - 12), height: max(1, bottom - top - 17))
        let block = holder(area)
        let fit = fitted(line, width: area.width * 0.96, height: area.height,
                         maximum: min(27, h * 0.215), leading: 1.24) { point in
            let base = NSFont.systemFont(ofSize: point, weight: .medium)
            return NSFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: point) ?? base
        }
        let y = (area.height - CGFloat(fit.rows.count) * fit.step) / 2
        for (index, row) in fit.rows.enumerated() {
            text(row, font: fit.font, color: ink,
                 frame: CGRect(x: 0, y: y + CGFloat(index) * fit.step, width: area.width, height: fit.step + 3), in: block)
        }
        animate(block, "opacity", values: [0, 1], times: [0, 1], duration: min(0.55 / tempo(line), duration * 0.3))
        animate(block, "transform.translation.y", values: [3, 0], times: [0, 1], duration: 0.8 / tempo(line))
        animate(block, "transform.scale", values: [0.965, 1], times: [0, 1],
                duration: min(8, max(1, duration * 0.85)), easing: .easeInEaseOut)

        if !upcoming.isEmpty, upcoming != line {
            let footer = holder(CGRect(x: inset + 4, y: bottom + 7, width: max(1, w - inset * 2 - 8), height: h * 0.15))
            footer.masksToBounds = true
            let next = text(upcoming, font: .systemFont(ofSize: max(10, min(11, h * 0.085)), weight: .regular),
                            color: ink.withAlphaComponent(0.42), frame: footer.bounds, in: footer)
            next.truncationMode = .end
        }
    }
}
