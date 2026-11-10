import AppKit
import QuartzCore
import CoreVideo

protocol FrameClocking: AnyObject {
    @discardableResult func start(screen: NSScreen?, tick: @escaping () -> Void) -> Bool
    func stop()
}

/// Let the display pace work; a second wall-clock filter can skip valid refreshes.
final class FrameClock: NSObject, FrameClocking {
    private var modern: AnyObject?
    private var legacy: CVDisplayLink?
    private var action: (() -> Void)?
    private let lock = NSLock()
    private var epoch = 0
    private var pending = false

    @discardableResult func start(screen: NSScreen?, tick: @escaping () -> Void) -> Bool {
        stop()
        action = tick
        if #available(macOS 14.0, *), let screen {
            let link = screen.displayLink(target: self, selector: #selector(refresh(_:)))
            let rate = Float(max(30, screen.maximumFramesPerSecond))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, rate), maximum: rate, preferred: rate)
            modern = link
            link.add(to: .main, forMode: .common)
        } else {
            var value: CVDisplayLink?
            let display = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
            guard CVDisplayLinkCreateWithCGDisplay(display, &value) == kCVReturnSuccess, let value else { action = nil; return false }
            legacy = value
            CVDisplayLinkSetOutputCallback(value, { _, _, _, _, _, context in
                guard let context else { return kCVReturnSuccess }
                let clock = Unmanaged<FrameClock>.fromOpaque(context).takeUnretainedValue()
                clock.lock.lock()
                guard !clock.pending else { clock.lock.unlock(); return kCVReturnSuccess }
                clock.pending = true
                let ticket = clock.epoch
                clock.lock.unlock()
                DispatchQueue.main.async { [weak clock] in
                    guard let clock else { return }
                    clock.lock.lock()
                    let valid = clock.epoch == ticket
                    if valid { clock.pending = false }
                    clock.lock.unlock()
                    if valid { clock.action?() }
                }
                return kCVReturnSuccess
            }, Unmanaged.passUnretained(self).toOpaque())
            if CVDisplayLinkStart(value) != kCVReturnSuccess { stop(); return false }
        }
        return true
    }

    @available(macOS 14.0, *)
    @objc private func refresh(_ link: CADisplayLink) { action?() }

    func stop() {
        lock.lock(); epoch += 1; pending = false; lock.unlock()
        if #available(macOS 14.0, *), let link = modern as? CADisplayLink { link.invalidate() }
        modern = nil
        if let legacy { CVDisplayLinkStop(legacy) }
        legacy = nil
        action = nil
    }
    deinit { stop() }
}
