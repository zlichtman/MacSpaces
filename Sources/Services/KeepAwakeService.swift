import AppKit
import Combine
import IOKit.pwr_mgt

/// Prevents idle sleep only while explicitly enabled. It does not bypass lid
/// closure, explicit Sleep, session locking, or low-battery system safeguards.
@MainActor
final class KeepAwakeService: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case system = "Keep Mac awake"
        case display = "Keep display awake"
        var id: String { rawValue }
    }
    @Published private(set) var isActive = false
    /// What it's holding awake while active.
    @Published private(set) var mode: Mode?
    @Published private(set) var expiresAt: Date?
    /// The time limit it was started with, for the closed notch's progress ring.
    private(set) var duration: TimeInterval?
    @Published private(set) var error: String?
    private var assertion: IOPMAssertionID = 0
    private var expiration: Timer?
    private var wakeObserver: NSObjectProtocol?

    func start(mode: Mode, minutes: Int?) {
        stop()
        let type = mode == .display ? kIOPMAssertionTypeNoDisplaySleep : kIOPMAssertionTypeNoIdleSleep
        let result = IOPMAssertionCreateWithName(type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), "MacSpaces Keep Awake" as CFString, &assertion)
        guard result == kIOReturnSuccess else {
            error = "Unable to keep this Mac awake (\(result))."
            return
        }
        error = nil
        isActive = true
        self.mode = mode
        if let minutes {
            let interval = TimeInterval(max(1, min(minutes, 1440)) * 60)
            expiresAt = Date().addingTimeInterval(interval)
            duration = interval
            arm(after: interval)
            // A run-loop timer doesn't count sleep, so the clock decides again on waking.
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let end = self.expiresAt else { return }
                    if end <= Date() { self.stop() } else { self.arm(after: end.timeIntervalSinceNow) }
                }
            }
        }
    }

    private func arm(after interval: TimeInterval) {
        expiration?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
        }
        expiration = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        expiration?.invalidate()
        expiration = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver); self.wakeObserver = nil }
        if isActive, assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = 0
        isActive = false
        mode = nil
        expiresAt = nil
        duration = nil
    }

#if DEBUG
    /// Captures: shows Keep Awake on (with `remaining` of `total` left, or no limit)
    /// without taking a power assertion.
    func setPreview(remaining: TimeInterval?, total: TimeInterval? = nil) {
        stop()
        isActive = true
        expiresAt = remaining.map { Date().addingTimeInterval($0) }
        duration = remaining.map { total ?? $0 }
    }
#endif

    deinit {
        expiration?.invalidate()
        if assertion != 0 { IOPMAssertionRelease(assertion) }
    }
}
