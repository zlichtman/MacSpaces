import Foundation
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
    @Published private(set) var expiresAt: Date?
    @Published private(set) var error: String?
    private var assertion: IOPMAssertionID = 0
    private var expiration: Timer?

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
        if let minutes {
            let interval = TimeInterval(max(1, min(minutes, 1440)) * 60)
            expiresAt = Date().addingTimeInterval(interval)
            let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.stop() }
            }
            expiration = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        expiration?.invalidate()
        expiration = nil
        if isActive { IOPMAssertionRelease(assertion) }
        assertion = 0
        isActive = false
        expiresAt = nil
    }

    deinit {
        expiration?.invalidate()
        if assertion != 0 { IOPMAssertionRelease(assertion) }
    }
}
