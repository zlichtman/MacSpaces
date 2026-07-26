import Foundation
import IOBluetooth
import ObjectiveC.runtime

struct BluetoothDeviceSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let batteryPercent: Int?

    var activityLabel: String {
        if let batteryPercent {
            return "\(name) \(batteryPercent)%"
        }
        return name
    }
}

/// Polls the local Bluetooth controller for connection transitions. It never
/// scans for new devices; it only reads the user's already-paired hardware.
@MainActor
final class BluetoothMonitor: ObservableObject {
    @Published private(set) var connectedDevices: [BluetoothDeviceSnapshot] = []
    @Published private(set) var justChangedRecently = false
    @Published private(set) var lastChangedDeviceName: String?
    @Published private(set) var activityLabel = "Bluetooth"
    @Published private(set) var activitySystemImage = "wave.3.right"

    private var timer: Timer?
    private var previousIDs: Set<String> = []
    private var previousDevices: [String: BluetoothDeviceSnapshot] = [:]
    private var hideWorkItem: DispatchWorkItem?
    private let queryQueue = DispatchQueue(
        label: "dev.opensource.MacSpaces.bluetooth-query",
        qos: .utility
    )
    private var queryInFlight = false
    private var isRunning = false

    func start() {
        guard timer == nil else { return }
        isRunning = true
        refresh(announce: false)
        let pollingTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh(announce: true) }
        }
        RunLoop.main.add(pollingTimer, forMode: .common)
        timer = pollingTimer
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
        justChangedRecently = false
    }

#if DEBUG
    /// Deterministic transient state used by the local visual-QA harness.
    func setPreviewChange(deviceName: String, batteryPercent: Int? = nil) {
        lastChangedDeviceName = deviceName
        activityLabel = batteryPercent.map { "\(deviceName) \($0)%" } ?? deviceName
        activitySystemImage = batteryPercent == nil ? "wave.3.right" : "airpodspro"
        justChangedRecently = true
    }
#endif

    private func refresh(announce: Bool) {
        guard !queryInFlight else { return }
        queryInFlight = true

        queryQueue.async { [weak self] in
            let devices = Self.loadConnectedDevices()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.queryInFlight = false
                guard self.isRunning else { return }
                self.apply(devices, announce: announce)
            }
        }
    }

    nonisolated private static func loadConnectedDevices() -> [BluetoothDeviceSnapshot] {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .filter { $0.isConnected() }
            .map {
                BluetoothDeviceSnapshot(
                    // Stable sentinel: a fresh UUID per poll would make an
                    // anonymous device look newly connected on every refresh.
                    id: $0.addressString ?? $0.name ?? "unknown-bluetooth-device",
                    name: $0.name ?? "Bluetooth device",
                    batteryPercent: Self.batteryPercent(for: $0)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return devices
    }

    private func apply(_ devices: [BluetoothDeviceSnapshot], announce: Bool) {
        let ids = Set(devices.map(\.id))
        if announce, ids != previousIDs {
            let changedID = ids.symmetricDifference(previousIDs).first
            let connected = devices.first(where: { $0.id == changedID })
            let disconnected = connectedDevices.first(where: { $0.id == changedID })
            let changed = connected ?? disconnected
            lastChangedDeviceName = changed?.name ?? "Bluetooth"
            if let connected {
                activityLabel = connected.activityLabel
                activitySystemImage = connected.batteryPercent == nil
                    ? "wave.3.right"
                    : "airpodspro"
            } else {
                activityLabel = "\(disconnected?.name ?? "Bluetooth") disconnected"
                activitySystemImage = "wave.3.left"
            }
            showTemporarily()
        } else if announce,
                  let changed = devices.first(where: { device in
                      guard let old = previousDevices[device.id],
                            let oldBattery = old.batteryPercent,
                            let newBattery = device.batteryPercent else {
                          return false
                      }
                      return abs(newBattery - oldBattery) >= 5
                  }) {
            lastChangedDeviceName = changed.name
            activityLabel = changed.activityLabel
            activitySystemImage = "airpodspro"
            showTemporarily()
        }
        connectedDevices = devices
        previousIDs = ids
        previousDevices = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
    }

    nonisolated private static func batteryPercent(for device: IOBluetoothDevice) -> Int? {
        typealias BatteryFunction = @convention(c) (AnyObject, Selector) -> UInt8
        let selectors = [
            "batteryPercentCombined",
            "batteryPercentSingle",
            "headsetBattery",
        ]
        for selectorName in selectors {
            let selector = NSSelectorFromString(selectorName)
            guard device.responds(to: selector),
                  let implementation = class_getMethodImplementation(
                    type(of: device),
                    selector
                  ) else {
                continue
            }
            let function = unsafeBitCast(implementation, to: BatteryFunction.self)
            let value = Int(function(device, selector))
            if (0...100).contains(value) {
                return value
            }
        }

        let channelSelectors = ["batteryPercentLeft", "batteryPercentRight"]
        let channels = channelSelectors.compactMap { selectorName -> Int? in
            let selector = NSSelectorFromString(selectorName)
            guard device.responds(to: selector),
                  let implementation = class_getMethodImplementation(
                    type(of: device),
                    selector
                  ) else {
                return nil
            }
            let function = unsafeBitCast(implementation, to: BatteryFunction.self)
            let value = Int(function(device, selector))
            return (0...100).contains(value) ? value : nil
        }
        guard !channels.isEmpty else { return nil }
        return Int(
            (Double(channels.reduce(0, +)) / Double(channels.count)).rounded()
        )
    }

    private func showTemporarily() {
        hideWorkItem?.cancel()
        justChangedRecently = true
        let work = DispatchWorkItem { [weak self] in
            self?.justChangedRecently = false
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    deinit {
        timer?.invalidate()
        hideWorkItem?.cancel()
    }
}
