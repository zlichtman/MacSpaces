import AppKit
import QuartzCore
import CoreVideo

protocol WindowAnimator: AnyObject {
    var current: [WindowID: CGRect] { get }
    var isAnimating: Bool { get }
    func animate(to frames: [WindowID: CGRect], from initial: [WindowID: CGRect],
                 screen: NSScreen?, geometry: ScreenGeometry, reduceMotion: Bool,
                 write: @escaping ([WindowID: CGRect]) -> Void, completion: @escaping () -> Void)
    func cancel()
}

final class Animator: NSObject, WindowAnimator {
    private let clock: FrameClocking
    private let now: () -> TimeInterval
    private let systemReduceMotion: () -> Bool
    private var started: TimeInterval = 0
    private var duration: TimeInterval = 0.14
    private var origins: [WindowID: CGRect] = [:]
    private var targets: [WindowID: CGRect] = [:]
    private var screenGeometry: ScreenGeometry?
    private var write: (([WindowID: CGRect]) -> Void)?
    private var completion: (() -> Void)?
    private(set) var current: [WindowID: CGRect] = [:]
    private(set) var isAnimating = false

    init(clock: FrameClocking = FrameClock(), now: @escaping () -> TimeInterval = CACurrentMediaTime,
         systemReduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.clock = clock
        self.now = now
        self.systemReduceMotion = systemReduceMotion
        super.init()
    }

    func animate(to frames: [WindowID: CGRect], from initial: [WindowID: CGRect],
                 screen: NSScreen?, geometry: ScreenGeometry, reduceMotion: Bool,
                 write: @escaping ([WindowID: CGRect]) -> Void, completion: @escaping () -> Void) {
        let interrupted = isAnimating
        let instant = now()
        let remaining = interrupted ? max(0.04, started + duration - instant) : 0.14
        stopLink()
        self.write = write
        self.completion = completion
        self.screenGeometry = geometry
        origins = frames.mapValues { $0 }
        for id in frames.keys { origins[id] = (interrupted ? current[id] : nil) ?? initial[id] ?? frames[id] }
        targets = frames
        started = instant
        duration = (systemReduceMotion() || reduceMotion) ? 0 : remaining
        guard duration > 0, targets.contains(where: { origins[$0.key] != $0.value }) else {
            current = frames
            write(frames)
            self.completion = nil
            completion()
            return
        }
        isAnimating = true
        // Write the first step immediately when a key arrives.
        step(progress: 0)
        if !clock.start(screen: screen, tick: { [weak self] in self?.tick() }) { finish() }
    }

    func cancel() {
        stopLink()
        completion = nil
        write = nil
        current.removeAll()
    }

    private func tick() {
        guard isAnimating else { return }
        let progress = min(1, (now() - started) / duration)
        if progress >= 1 { finish() } else { step(progress: progress) }
    }

    private func step(progress: Double) {
        var frames: [WindowID: CGRect] = [:]
        for (id, target) in targets {
            let origin = origins[id] ?? target
            let rect = FrameMotion.interpolate(from: origin, to: target, progress: progress)
            frames[id] = screenGeometry.map { StripLayout.parked(rect, on: $0) } ?? rect
        }
        current = frames
        write?(frames)
    }

    private func finish() {
        step(progress: 1)
        stopLink()
        let done = completion
        completion = nil
        write = nil
        done?()
    }

    private func stopLink() {
        isAnimating = false
        clock.stop()
    }
    deinit { stopLink() }
}
