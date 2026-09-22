#if DEBUG
import Foundation
import IOKit.ps

@MainActor
enum DeviceRegressionChecks {
    static func run() {
        let description: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSIsPresentKey: true, kIOPSCurrentCapacityKey: 4300, kIOPSMaxCapacityKey: 5000,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: false]
        let plugged = MacPowerSnapshot.read(description)!
        precondition(plugged.level == 86 && !plugged.charging && plugged.status == "Plugged in")
        var charging = description; charging[kIOPSIsChargingKey] = true
        precondition(MacPowerSnapshot.read(charging)!.status == "Charging")
        var ups = description; ups[kIOPSTypeKey] = kIOPSUPSType
        precondition(MacPowerSnapshot.read(ups) == nil)
        var invalid = description; invalid[kIOPSMaxCapacityKey] = 0
        precondition(MacPowerSnapshot.read(invalid) == nil)
        precondition(MacPowerSnapshot(level: 100, externalPower: true, charging: false).status == "Fully charged")
        precondition(PowerSourceMonitor.lowBatteryThresholdCrossed(from: 21, to: 20))
        precondition(!PowerSourceMonitor.lowBatteryThresholdCrossed(from: 19, to: 18))
        let payload = #"{"SPBluetoothDataType":[{"device_connected":[{"Headphones":{"device_address":"AA-BB-CC-11-22-33","device_minorType":"Headphones","device_batteryLevelLeft":"80%","device_batteryLevelRight":"60%","device_batteryLevelCase":"1%"}},{"Keyboard":{"device_address":"AA-BB-CC-44-55-66","device_batteryLevel":"255%"}}],"device_not_connected":[{"Old device":{"device_address":"00-00-00-00-00-00","device_batteryLevel":"100%"}}]}]}"#
        let report = BluetoothBatteryReport.parse(Data(payload.utf8))
        let earbuds = report[BluetoothBatteryReport.addressKey("aa:bb:cc:11:22:33")]!
        precondition(earbuds.batteries.primary == 60 && earbuds.batteries.caseLevel == 1)
        precondition(earbuds.batteries.summary == "Left 80% · Right 60% · Case 1%")
        precondition(report["aabbcc445566"]!.batteries.primary == nil)
        precondition(report.count == 2 && report["aabbcc445566"]!.name == "Keyboard")
        precondition(BluetoothBatteryReport.parse(Data("invalid".utf8)).isEmpty)
        func device(_ level: Int?) -> BluetoothDeviceSnapshot {
            BluetoothDeviceSnapshot(id: "test", name: "Studio headphones", batteryPercent: level)
        }
        let gradual = BluetoothMonitor()
        gradual.apply([device(80)], announce: false)
        for value in [79, 78, 77, 76] { gradual.apply([device(value)], announce: true) }
        precondition(!gradual.justChangedRecently)
        gradual.apply([device(75)], announce: true)
        precondition(gradual.justChangedRecently && gradual.activityBatteryPercent == 75 && gradual.activityState == .battery)
        gradual.stop()
        let delayed = BluetoothMonitor()
        delayed.apply([device(nil)], announce: false)
        delayed.apply([device(64)], announce: true)
        precondition(delayed.justChangedRecently && delayed.activityBatteryPercent == 64)
        delayed.stop()
        let disconnect = BluetoothMonitor()
        disconnect.apply([device(60)], announce: false)
        disconnect.apply([], announce: true)
        precondition(disconnect.activityState == .disconnected && disconnect.activityBatteryPercent == nil)
        disconnect.stop()
        print("Power source semantics, Bluetooth component parsing, gradual battery changes and disconnect checks passed")
    }
}
#endif
