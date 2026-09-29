import Foundation
import IOBluetooth

struct BluetoothDeviceSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let batteryPercent: Int?
    var batteryLevels = BluetoothBatteryLevels()
    var category = ""

    var systemImage: String { BluetoothMonitor.systemImage(for: name, category: category) }
}

/// Reads already-paired devices for the Battery widget only; it never scans,
/// initiates connections or announces connection changes.
@MainActor
final class BluetoothMonitor: ObservableObject {
    @Published private(set) var connectedDevices: [BluetoothDeviceSnapshot] = []

    private var timer: Timer?
    private var generation = 0
    private var queryInFlight = false
    private var isRunning = false
    private let queryQueue = DispatchQueue(label: "dev.opensource.MacSpaces.bluetooth-query", qos: .utility)
    private let reader = PairedBluetoothReader()

    func start() {
        guard timer == nil else { return }
        isRunning = true
        generation += 1
        refresh()
        let poll = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
    }

    func stop() {
        isRunning = false
        generation += 1
        timer?.invalidate(); timer = nil
        connectedDevices = []
    }

    func refreshBatteries() { refresh(forceBattery: true) }

    private func refresh(forceBattery: Bool = false) {
        guard isRunning, !queryInFlight else { return }
        queryInFlight = true
        let requestedGeneration = generation
        queryQueue.async { [weak self] in
            guard let self else { return }
            let devices = self.reader.load(forceBattery: forceBattery)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.queryInFlight = false
                guard self.isRunning, self.generation == requestedGeneration else { return }
                if self.connectedDevices != devices { self.connectedDevices = devices }
            }
        }
    }

    nonisolated static func systemImage(for name: String, category: String = "") -> String {
        let value = "\(name) \(category)".lowercased()
        if value.contains("airpods pro") { return "airpodspro" }
        if value.contains("airpods max") { return "airpodsmax" }
        if value.contains("airpods") { return "airpods" }
        if value.contains("headphone") || value.contains("beats") { return "headphones" }
        if value.contains("keyboard") { return "keyboard" }
        if value.contains("trackpad") { return "trackpad" }
        if value.contains("mouse") { return "computermouse" }
        return "antenna.radiowaves.left.and.right"
    }

#if DEBUG
    func setPreviewDevices(_ devices: [BluetoothDeviceSnapshot]) { connectedDevices = devices }
#endif

    deinit { timer?.invalidate() }
}

/// Mutable cache is confined to BluetoothMonitor.queryQueue. Keeping it outside
/// the main-actor model avoids unsafe actor-isolation overrides.
private final class PairedBluetoothReader: @unchecked Sendable {
    private var batteryCache: [String: BluetoothBatteryReport] = [:]
    private var batteryReadAt = Date.distantPast
    private var batteryAttemptAt = Date.distantPast
    private var queriedIDs: Set<String> = []

    func load(forceBattery: Bool) -> [BluetoothDeviceSnapshot] {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { $0.isConnected() }
        let ids = Set(paired.compactMap { $0.addressString }.map(BluetoothBatteryReport.addressKey))
        // Newer macOS versions can omit connected accessories from IOBluetooth.
        // Use macOS's connected-device report for those devices, refreshing the
        // fallback promptly so a disconnect is not shown as connected for 30s.
        let needsConnectionFallback = paired.isEmpty || !Set(batteryCache.keys).isSubset(of: ids)
        let interval: TimeInterval = needsConnectionFallback ? 4 : 30
        if forceBattery || ids != queriedIDs || Date().timeIntervalSince(batteryAttemptAt) >= interval {
            batteryAttemptAt = Date()
            if let report = BluetoothBatteryReport.load() {
                batteryCache = report
                batteryReadAt = Date()
            }
            queriedIDs = ids
        }
        let usableCache = Date().timeIntervalSince(batteryReadAt) < 90 ? batteryCache : [:]
        var devices: [String: BluetoothDeviceSnapshot] = [:]
        for device in paired where device.isConnected() {
            let id = device.addressString.map(BluetoothBatteryReport.addressKey) ?? device.name ?? "unknown-bluetooth-device"
            let report = usableCache[id]
            let levels = report?.batteries ?? BluetoothBatteryLevels()
            devices[id] = BluetoothDeviceSnapshot(id: id, name: device.name ?? report?.name ?? "Bluetooth device",
                batteryPercent: levels.primary, batteryLevels: levels, category: report?.category ?? "")
        }
        // Only fresh reports can supply connection state. A failed query must
        // not leave a disconnected accessory visible indefinitely.
        if Date().timeIntervalSince(batteryReadAt) < 12 {
            for (id, report) in usableCache where devices[id] == nil {
                devices[id] = BluetoothDeviceSnapshot(id: id, name: report.name,
                    batteryPercent: report.batteries.primary, batteryLevels: report.batteries, category: report.category)
            }
        }
        return devices.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
