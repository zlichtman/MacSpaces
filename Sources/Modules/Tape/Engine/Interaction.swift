import Foundation
import CoreGraphics

/// Protect a new keyboard selection from an older in-flight window scan.
struct FocusIntent {
    private(set) var target: WindowID?
    private var expires: TimeInterval = 0
    init() {}
    mutating func request(_ id: WindowID, now: TimeInterval) {
        target = id
        expires = now + 0.6
    }
    mutating func resolve(observed: WindowID?, available: Set<WindowID>, now: TimeInterval) -> WindowID? {
        if let target, available.contains(target), now < expires {
            if observed == target { self.target = nil }
            return target
        }
        target = nil
        return observed
    }
}

/// Resize once, then translate. Repeated resizing forces apps to redraw at every tick.
enum FrameMotion {
    static func interpolate(from origin: CGRect, to target: CGRect, progress: Double) -> CGRect {
        let p = min(max(progress.isFinite ? progress : 1, 0), 1)
        let eased = 1 - pow(1 - p, 3)
        return CGRect(x: origin.minX + (target.minX - origin.minX) * eased,
                      y: origin.minY + (target.minY - origin.minY) * eased,
                      width: target.width, height: target.height)
    }
    static func needsMove(from previous: CGRect?, to frame: CGRect) -> Bool {
        guard let previous else { return true }
        return abs(previous.minX - frame.minX) >= 0.5 || abs(previous.minY - frame.minY) >= 0.5
    }
    static func needsResize(from previous: CGRect?, to frame: CGRect) -> Bool {
        guard let previous else { return true }
        return abs(previous.width - frame.width) >= 0.5 || abs(previous.height - frame.height) >= 0.5
    }
}
