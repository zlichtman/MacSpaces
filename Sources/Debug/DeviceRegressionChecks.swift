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
        print("Power source semantics and Bluetooth component parsing checks passed")
    }
}
#endif
