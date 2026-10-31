import SwiftUI
import AppKit
import QuartzCore

/// A compact equalizer animated entirely by Core Animation. Only five tiny
/// compositor layers move; the always-visible SwiftUI notch stays idle.
struct AudioSpectrumView: View {
    var isPlaying: Bool
    /// Bars in one colour (the playing cover's) instead of the theme's accents.
    var tint: Color? = nil

    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SpectrumBarsView(
            isPlaying: isPlaying,
            animates: !reduceMotion && !theme.reduceMotion,
            primaryColor: NSColor(tint ?? theme.notch.accent),
            secondaryColor: tint.map { NSColor($0).blended(withFraction: 0.3, of: .black) ?? NSColor($0) } ?? NSColor(theme.notch.secondaryAccent)
        )
        .frame(width: 26, height: 18)
        .accessibilityElement()
        .accessibilityLabel(isPlaying ? "Audio playing" : "Audio paused")
    }
}

private struct SpectrumBarsView: NSViewRepresentable {
    let isPlaying: Bool
    let animates: Bool
    let primaryColor: NSColor
    let secondaryColor: NSColor

    func makeNSView(context: Context) -> SpectrumBarsNSView {
        SpectrumBarsNSView()
    }

    func updateNSView(_ view: SpectrumBarsNSView, context: Context) {
        view.update(
            isPlaying: isPlaying,
            animates: animates,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor
        )
    }
}

private final class SpectrumBarsNSView: NSView {
    private let bars = (0..<7).map { _ in CAGradientLayer() }
    private let baseScales: [CGFloat] = [0.38, 0.68, 0.50, 0.96, 0.60, 0.80, 0.42]
    private var lastState: (playing: Bool, animates: Bool)?
    /// Removed in deinit: the closed notch rebuilds this view on every open and
    /// close, and each one used to leave two observers behind.
    private var wakeObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false

        wakeObservers = [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification].map { name in
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeIfNeeded() }
            }
        }

        bars.forEach {
            $0.startPoint = CGPoint(x: 0.5, y: 1)
            $0.endPoint = CGPoint(x: 0.5, y: 0)
            $0.cornerRadius = 1.25
            $0.masksToBounds = true
            layer?.addSublayer($0)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        wakeObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resumeIfNeeded()
    }

    private func resumeIfNeeded() {
        guard let lastState, lastState.playing, lastState.animates, window != nil,
              bars.first?.animation(forKey: "spectrum") == nil else { return }
        startAnimations()
    }

    override func layout() {
        super.layout()
        let barWidth: CGFloat = 2
        let spacing: CGFloat = 1.5
        let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * spacing
        let startX = (bounds.width - totalWidth) / 2
        let barHeight = min(16, bounds.height)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let height = barHeight * baseScales[index]
            bar.frame = CGRect(
                x: startX + CGFloat(index) * (barWidth + spacing),
                y: (bounds.height - height) / 2,
                width: barWidth,
                height: height
            )
        }
        CATransaction.commit()
    }

    func update(isPlaying: Bool, animates: Bool, primaryColor: NSColor, secondaryColor: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach {
            $0.colors = [primaryColor.cgColor, secondaryColor.cgColor]
            $0.opacity = isPlaying ? 1 : 0.42
        }
        CATransaction.commit()

        // Core Animation drops animations after sleep, a display change or the panel
        // leaving the screen; restart them whenever they should be running but aren't.
        let stalled = isPlaying && animates && bars.first?.animation(forKey: "spectrum") == nil
        guard stalled || lastState?.playing != isPlaying || lastState?.animates != animates else { return }
        lastState = (isPlaying, animates)
        // Reduce Motion keeps the bars still at their resting heights.
        isPlaying && animates ? startAnimations() : stopAnimations()
    }

    private func startAnimations() {
        let patterns: [[CGFloat]] = [
            [0.30, 0.76, 0.44, 0.88, 0.30],
            [0.66, 0.38, 0.92, 0.52, 0.66],
            [0.46, 0.86, 0.58, 0.34, 0.46],
            [0.92, 0.54, 1.00, 0.42, 0.92],
            [0.56, 0.30, 0.78, 0.48, 0.56],
            [0.78, 0.96, 0.40, 0.68, 0.78],
            [0.38, 0.62, 0.88, 0.34, 0.38],
        ]
        for (index, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            bar.transform = CATransform3DIdentity

            let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
            animation.values = patterns[index]
            animation.keyTimes = [0, 0.22, 0.5, 0.76, 1]
            animation.duration = 0.72 + Double(index) * 0.045
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.beginTime = bar.convertTime(CACurrentMediaTime(), from: nil)
                + Double(index) * 0.035
            bar.add(animation, forKey: "spectrum")
        }
    }

    private func stopAnimations() {
        let pausedScales: [CGFloat] = [0.30, 0.48, 0.66, 0.82, 0.58, 0.42, 0.28]
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.16)
        for (index, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            bar.transform = CATransform3DMakeScale(1, pausedScales[index], 1)
        }
        CATransaction.commit()
    }
}
