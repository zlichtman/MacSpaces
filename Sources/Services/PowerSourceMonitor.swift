import Foundation
import IOKit.ps
import Combine
@preconcurrency import UserNotifications

/// Watches the battery via IOKit power sources and briefly surfaces changes
/// (plug in / unplug) as a live activity beside the notch.
@MainActor
final class PowerSourceMonitor: ObservableObject {
    @Published private(set) var batteryLevel: Int = 100
    @Published private(set) var isCharging = false
    @Published private(set) var hasBattery = false
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
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
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

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            hasBattery = true
            let wasCharging = isCharging
            let oldBatteryLevel = previousBatteryLevel

            if let capacity = description[kIOPSCurrentCapacityKey] as? Int {
                batteryLevel = capacity
            }
            if let state = description[kIOPSPowerSourceStateKey] as? String {
                isCharging = state == kIOPSACPowerValue
            }

            if announce && wasCharging != isCharging {
                isLowBatteryActivity = false
                activityLabel = isCharging ? "Charging \(batteryLevel)%" : "On battery"
                activitySystemImage = isCharging ? "bolt.fill" : "battery.100percent"
                showTemporarily(duration: 4)
            } else if announce,
                      !isCharging,
                      let oldBatteryLevel,
                      Self.lowBatteryThresholdCrossed(
                          from: oldBatteryLevel,
                          to: batteryLevel
                      ) {
                isLowBatteryActivity = true
                activityLabel = "Low \(batteryLevel)%"
                activitySystemImage = batteryLevel <= 10
                    ? "battery.0percent"
                    : "battery.25percent"
                showTemporarily(duration: 7)
                deliverLowBatteryNotification()
            }
            previousBatteryLevel = batteryLevel
            break
        }
    }

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

    private static func lowBatteryThresholdCrossed(from old: Int, to new: Int) -> Bool {
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
