import Foundation
import IOKit.ps
import Combine
@preconcurrency import UserNotifications

/// Only the internal battery belongs in the Mac's battery tile. Capacity units
/// vary by source, and external power does not necessarily mean charging.
struct MacPowerSnapshot: Equatable {
    let level: Int
    let externalPower: Bool
    let charging: Bool

    static func read(_ description: [String: Any]) -> Self? {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              description[kIOPSIsPresentKey] as? Bool != false,
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int,
              maximum > 0, current >= 0 else { return nil }
        let external = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        return Self(level: min(100, Int((Double(current) / Double(maximum) * 100).rounded())),
                    externalPower: external,
                    charging: external && (description[kIOPSIsChargingKey] as? Bool == true))
    }

    var status: String {
        if charging { return "Charging" }
        if externalPower { return level >= 100 ? "Fully charged" : "Plugged in" }
        return "On battery"
    }
}

/// Watches the battery via IOKit power sources and briefly surfaces changes
/// (plug in / unplug) as a live activity beside the notch.
@MainActor
final class PowerSourceMonitor: ObservableObject {
    @Published private(set) var batteryLevel: Int = 0
    @Published private(set) var isCharging = false
    @Published private(set) var hasBattery = false
    @Published private(set) var hasReading = false
    @Published private(set) var isOnExternalPower = false

    var statusLabel: String {
        guard hasReading else { return "Battery unavailable" }
        guard hasBattery else { return "External power" }
        return MacPowerSnapshot(level: batteryLevel, externalPower: isOnExternalPower, charging: isCharging).status
    }
    /// True for a few seconds after the power source changes.
    @Published private(set) var justChangedRecently = false
    @Published private(set) var activityLabel = "Battery"
    @Published private(set) var activitySystemImage = "battery.100percent"
    @Published private(set) var isLowBatteryActivity = false

    private var runLoopSource: CFRunLoopSource?
    private var hideWorkItem: DispatchWorkItem?
    private var previousBatteryLevel: Int?

    func start() {
        guard runLoopSource == nil else { return }
        refresh(announce: false)

        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                monitor.refresh(announce: true)
            }
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        hideWorkItem?.cancel()
        hideWorkItem = nil
        justChangedRecently = false
        previousBatteryLevel = nil
    }

    private func refresh(announce: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }

        let descriptions = sources.compactMap { source in
            IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        }
        guard let snapshot = descriptions.compactMap(MacPowerSnapshot.read).first else {
            // Missing capacity data is unknown, not a desktop or a full battery.
            hasBattery = descriptions.contains { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
            hasReading = !hasBattery
            return
        }
        let wasExternal = isOnExternalPower
        let wasCharging = isCharging
        let oldLevel = previousBatteryLevel
        hasBattery = true
        hasReading = true
        batteryLevel = snapshot.level
        isOnExternalPower = snapshot.externalPower
        isCharging = snapshot.charging
        if announce && (wasExternal != isOnExternalPower || wasCharging != isCharging) {
            isLowBatteryActivity = false
            activityLabel = "\(snapshot.status) · \(batteryLevel)%"
            activitySystemImage = isCharging ? "bolt.fill" : "battery.100percent"
            showTemporarily(duration: 6)
        } else if announce, !isOnExternalPower, let oldLevel,
                  Self.lowBatteryThresholdCrossed(from: oldLevel, to: batteryLevel) {
            isLowBatteryActivity = true
            activityLabel = "Low battery · \(batteryLevel)%"
            activitySystemImage = batteryLevel <= 10 ? "battery.0percent" : "battery.25percent"
            showTemporarily(duration: 8)
            deliverLowBatteryNotification()
        }
        previousBatteryLevel = batteryLevel
    }

#if DEBUG
    func setPreview(level: Int, externalPower: Bool = false, charging: Bool = false, activity: Bool = true) {
        hasBattery = true; hasReading = true
        batteryLevel = min(100, max(0, level))
        isOnExternalPower = externalPower; isCharging = charging && externalPower
        isLowBatteryActivity = !externalPower && level <= 20
        activityLabel = "\(isLowBatteryActivity ? "Low battery" : statusLabel) · \(batteryLevel)%"
        justChangedRecently = activity
    }
#endif

    private func showTemporarily(duration: TimeInterval) {
        hideWorkItem?.cancel()
        justChangedRecently = true

        let work = DispatchWorkItem { [weak self] in
            self?.justChangedRecently = false
            self?.isLowBatteryActivity = false
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    static func lowBatteryThresholdCrossed(from old: Int, to new: Int) -> Bool {
        guard new < old else { return false }
        return [20, 10, 5].contains { old > $0 && new <= $0 }
    }

    private func deliverLowBatteryNotification() {
        let level = batteryLevel
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let deliver = {
                let content = UNMutableNotificationContent()
                content.title = "Low battery"
                content.body = "Your Mac is at \(level)%."
                content.sound = .default
                center.add(
                    UNNotificationRequest(
                        identifier: "dev.opensource.MacSpaces.low-battery.\(level)",
                        content: content,
                        trigger: nil
                    )
                )
            }

            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { deliver() }
                }
            case .authorized, .provisional:
                deliver()
            default:
                break
            }
        }
    }

    deinit {
        // The IOKit callback holds an unretained pointer to self; invalidate
        // the source (thread-safe, detaches from all run loops) so it can
        // never fire after deallocation. CFRunLoopRemoveSource would only be
        // safe from the main thread, which deinit is not guaranteed to be on.
        if let runLoopSource {
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        hideWorkItem?.cancel()
    }
}
