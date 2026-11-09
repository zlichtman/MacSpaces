import AppKit
import ApplicationServices

/// Public scroll events, not undocumented multi-finger gesture events.
/// The callback performs no remote AX calls and never activates an app.
/// An active tap delays every scroll event in the session until it returns, so it runs on its
/// own thread: work on Tape's main thread can never stall scrolling in other apps.
final class ScrollInput {
    /// Called on the main thread with the horizontal delta and the pointer location.
    var onScroll: ((Double, CGPoint) -> Void)?
    private let lock = NSLock()
    private var gesture = ScrollGesture()
    /// Display frames (Accessibility coordinates) where a new gesture may start.
    private var eligible: [CGRect] = []
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?

    /// Updated by the controller on the main thread; read by the tap thread.
    var targets: [CGRect] {
        get { lock.lock(); defer { lock.unlock() }; return eligible }
        set { lock.lock(); eligible = newValue; lock.unlock() }
    }

    @discardableResult func start() -> Bool {
        stop()
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<ScrollInput>.fromOpaque(context).takeUnretainedValue().receive(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        lock.lock(); self.tap = tap; lock.unlock()
        let ready = DispatchSemaphore(value: 0)
        var loop: CFRunLoop?
        let thread = Thread {
            loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "dev.opensource.MacSpaces.tape.scroll"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        runLoop = loop
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// End browsing for the current gesture: its remaining events, including momentum, are
    /// still swallowed so they cannot reach the app underneath, but no longer move the strip.
    func suppressCurrentGesture() {
        lock.lock(); gesture.suppress(); lock.unlock()
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock(); gesture.reset(); let tap = self.tap; lock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel, let scroll = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
        let flags = event.flags
        let modifiers = flags.contains(.maskControl) && flags.contains(.maskAlternate)
            && !flags.contains(.maskCommand) && !flags.contains(.maskShift)
        let phase = scroll.phase, momentum = scroll.momentumPhase
        let location = event.location
        let delta = scroll.scrollingDeltaX
        lock.lock()
        let consume = gesture.consume(x: delta, y: scroll.scrollingDeltaY,
            precise: scroll.hasPreciseScrollingDeltas, modifiers: modifiers,
            eligible: eligible.contains { $0.contains(location) },
            begins: phase.contains(.began) || phase.contains(.mayBegin), momentum: !momentum.isEmpty,
            cancelled: phase.contains(.cancelled), finishesMomentum: momentum.contains(.ended),
            now: ProcessInfo.processInfo.systemUptime)
        let forward = consume && !gesture.isSuppressed && delta != 0
        lock.unlock()
        guard consume else { return Unmanaged.passUnretained(event) }
        if forward {
            DispatchQueue.main.async { [weak self] in self?.onScroll?(-delta, location) }
        }
        return nil
    }

    func stop() {
        lock.lock(); gesture.reset(); let tap = self.tap; self.tap = nil; lock.unlock()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        // Invalidating the port removes its source; stopping the loop ends the thread.
        if let runLoop { CFRunLoopStop(runLoop) }
        runLoop = nil
    }
    deinit { stop() }
}
