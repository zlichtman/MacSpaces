import AppKit
import CoreText
import QuartzCore
import SwiftUI

/// Three small typographic stages, with finite animations owned by the window
/// server. Neither playing nor resting needs a timer or a SwiftUI frame clock.
struct TypographyLyric: View {
    let style: LyricStyle
    let line: String
    let upcoming: String
    let accent: Color
    let ink: Color
    let size: CGSize
    let animated: Bool
    let playing: Bool
    let span: ClosedRange<TimeInterval>?
    let songTime: TimeInterval?
    let identity: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        LyricTypographySurface(style: style, line: line, upcoming: upcoming,
                               accent: NSColor(accent), ink: NSColor(ink), size: size,
                               animated: animated && !reduceMotion && !theme.reduceMotion,
                               playing: playing, span: span, songTime: songTime, identity: identity)
            .frame(width: size.width, height: size.height)
            .id(identity)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct LyricTypographySurface: NSViewRepresentable {
    let style: LyricStyle
    let line: String
    let upcoming: String
    let accent: NSColor
    let ink: NSColor
    let size: CGSize
    let animated: Bool
    let playing: Bool
    let span: ClosedRange<TimeInterval>?
    let songTime: TimeInterval?
    let identity: Int

    struct Key: Equatable {
        let style: LyricStyle
        let line: String
        let upcoming: String
        let accent: NSColor
        let ink: NSColor
        let size: CGSize
        let animated: Bool
        let span: ClosedRange<TimeInterval>?
        let identity: Int
    }

    func makeNSView(context: Context) -> StageView { StageView() }

    func updateNSView(_ view: StageView, context: Context) {
        view.show(self)
    }

    final class StageView: NSView {
        private let stage = CALayer()
        private var key: Key?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            stage.isGeometryFlipped = true
            stage.masksToBounds = true
            layer?.addSublayer(stage)
        }

        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stage.frame = bounds
            CATransaction.commit()
        }

        func show(_ input: LyricTypographySurface) {
            let next = Key(style: input.style, line: input.line, upcoming: input.upcoming,
                           accent: input.accent, ink: input.ink, size: input.size,
                           animated: input.animated, span: input.span, identity: input.identity)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.speed = Float(1 / Design.demoTimeScale)
            if next != key {
                key = next
                stage.sublayers?.forEach { $0.removeFromSuperlayer() }
                stage.speed = 1
                stage.timeOffset = 0
                stage.beginTime = 0
                stage.frame = CGRect(origin: .zero, size: input.size)
                let age = input.span.flatMap { span in input.songTime.map { max(0, $0 - span.lowerBound) } } ?? 0
                let start = stage.convertTime(CACurrentMediaTime(), from: nil) - age
                let canvas = LyricTypographyCanvas(root: stage, size: input.size,
                                                   accent: input.accent, ink: input.ink,
                                                   moving: input.animated && input.playing,
                                                   start: start, span: input.span,
                                                   scale: window?.backingScaleFactor ?? 2)
                if input.size.width > 32, input.size.height > 24,
                   !input.line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    switch input.style {
                    case .cinema: canvas.cinema(input.line, upcoming: input.upcoming)
                    case .departure: canvas.departure(input.line, upcoming: input.upcoming)
                    default: break
                    }
                }
            }
            if input.playing {
                if stage.speed == 0 {
                    let held = stage.timeOffset
                    stage.speed = 1
                    stage.timeOffset = 0
                    stage.beginTime = 0
                    stage.beginTime = stage.convertTime(CACurrentMediaTime(), from: nil) - held
                }
            } else if stage.speed != 0 {
                let held = stage.convertTime(CACurrentMediaTime(), from: nil)
                stage.speed = 0
                stage.timeOffset = held
            }
            CATransaction.commit()
        }
    }
}

/// Shared drawing tools; all three compositions use the same exact settled
/// layers under Reduce Motion. Coordinates run downwards, like SwiftUI.
struct LyricTypographyCanvas {
    let root: CALayer
    let size: CGSize
    let accent: NSColor
    let ink: NSColor
    let moving: Bool
    let start: CFTimeInterval
    let span: ClosedRange<TimeInterval>?
    let scale: CGFloat

    var duration: Double { span.map { max(0.5, $0.upperBound - $0.lowerBound) } ?? 4.5 }

    func tempo(_ line: String) -> Double {
        MoodTreatment.tempo(wordsPerSecond: MoodTreatment.wordsPerSecond(words: MoodTreatment.wordCount(line), span: span))
    }

    func holder(_ frame: CGRect, in parent: CALayer? = nil) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        (parent ?? root).addSublayer(layer)
        return layer
    }

    @discardableResult
    func rule(_ frame: CGRect, color: NSColor, in parent: CALayer? = nil) -> CALayer {
        let layer = holder(frame, in: parent)
        layer.backgroundColor = color.cgColor
        return layer
    }

    @discardableResult
    func text(_ string: String, font: NSFont, color: NSColor, frame: CGRect,
              alignment: NSTextAlignment = .center, tracking: CGFloat = 0,
              stroke: CGFloat? = nil, in parent: CALayer? = nil) -> CATextLayer {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph, .kern: tracking
        ]
        if let stroke {
            attributes[.strokeWidth] = stroke
            attributes[.strokeColor] = color
        }
        let layer = CATextLayer()
        layer.frame = frame
        layer.contentsScale = scale
        layer.string = NSAttributedString(string: string, attributes: attributes)
        layer.alignmentMode = alignment == .left ? .left : alignment == .right ? .right : .center
        layer.isWrapped = false
        (parent ?? root).addSublayer(layer)
        return layer
    }

    /// Core Text handles word boundaries, long unbroken words and non-Latin
    /// scripts. Size is fitted once per line, never during an animation.
    func rows(_ line: String, font: NSFont, width: CGFloat) -> [String] {
        let string = NSAttributedString(string: line, attributes: [.font: font])
        let typesetter = CTTypesetterCreateWithAttributedString(string as CFAttributedString)
        let source = line as NSString
        var result: [String] = []
        var offset = 0
        while offset < source.length {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, Double(max(1, width))))
            result.append(source.substring(with: NSRange(location: offset, length: min(count, source.length - offset)))
                .trimmingCharacters(in: .whitespacesAndNewlines))
            offset += count
        }
        return result
    }

    func fitted(_ line: String, width: CGFloat, height: CGFloat, maximum: CGFloat,
                leading: CGFloat = 1.2, font: (CGFloat) -> NSFont) -> (font: NSFont, rows: [String], step: CGFloat) {
        var point = maximum
        var face = font(point)
        var lines = rows(line, font: face, width: width)
        while point > 10, CGFloat(lines.count) * point * leading > height {
            point = max(10, point - 1)
            face = font(point)
            lines = rows(line, font: face, width: width)
        }
        return (face, lines, point * leading)
    }

    /// The model is always the finished pose. Animations have no repeat and
    /// remove themselves on completion, leaving no running work at rest.
    func animate(_ layer: CALayer, _ property: String, values: [Double], times: [Double],
                 duration: Double, delay: Double = 0, easing: CAMediaTimingFunctionName = .easeOut) {
        guard moving else { return }
        let animation = CAKeyframeAnimation(keyPath: property)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.duration = max(0.01, duration)
        animation.beginTime = start + delay
        animation.fillMode = .backwards
        animation.timingFunctions = (1..<values.count).map { _ in CAMediaTimingFunction(name: easing) }
        layer.add(animation, forKey: property)
    }
}
