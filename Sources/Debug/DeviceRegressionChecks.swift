#if DEBUG
import Foundation
import IOKit.ps

@MainActor
enum DeviceRegressionChecks {
    static func run() {
        let description: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSIsPresentKey: true, kIOPSCurrentCapacityKey: 4300, kIOPSMaxCapacityKey: 5000,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: false, kIOPSTimeToFullChargeKey: -1]
        let plugged = MacPowerSnapshot.read(description)!
        precondition(plugged.level == 86 && !plugged.charging && plugged.externalPower && plugged.minutesToFull == nil)
        var charging = description; charging[kIOPSIsChargingKey] = true; charging[kIOPSTimeToFullChargeKey] = 42
        precondition(MacPowerSnapshot.read(charging)!.charging && MacPowerSnapshot.read(charging)!.minutesToFull == 42)
        var ups = description; ups[kIOPSTypeKey] = kIOPSUPSType
        precondition(MacPowerSnapshot.read(ups) == nil)
        var invalid = description; invalid[kIOPSMaxCapacityKey] = 0
        precondition(MacPowerSnapshot.read(invalid) == nil)
        precondition(PowerSourceMonitor.lowBatteryThresholdCrossed(from: 21, to: 20))
        precondition(!PowerSourceMonitor.lowBatteryThresholdCrossed(from: 19, to: 18))

        // SMC byte order: integers are little-endian when attribute bit 0x04 is set.
        let si16 = SMCPowerSensors.code("si16"), ui16 = SMCPowerSensors.code("ui16")
        precondition(SMCPowerSensors.decode([0x04, 0x00], type: si16, attributes: 0x84) == 4)
        precondition(SMCPowerSensors.decode([0xFC, 0xFF], type: si16, attributes: 0x84) == -4)
        precondition(SMCPowerSensors.decode([0x18, 0xFC], type: si16, attributes: 0x84) == -1000)
        precondition(SMCPowerSensors.decode([0x50, 0x32], type: ui16, attributes: 0x84) == 12880)
        precondition(SMCPowerSensors.decode([0x32, 0x50], type: ui16, attributes: 0x80) == 12880)
        precondition(SMCPowerSensors.decode([0x01, 0x00], type: SMCPowerSensors.code("sp78"), attributes: 0x80) == 1)
        let float = Float(27.88).bitPattern
        let floatBytes = (0..<4).map { UInt8(truncatingIfNeeded: float >> ($0 * 8)) }
        precondition(SMCPowerSensors.decode(floatBytes, type: SMCPowerSensors.code("flt "), attributes: 0x85) == Double(Float(27.88)))
        precondition(SMCPowerSensors.decode([0x01], type: SMCPowerSensors.code("ch8*"), attributes: 0) == nil)

        // One state: full wins over a top-off trickle; low holds until 23%.
        func raw(_ onAC: Bool, _ level: Int, charging: Bool = false, charged: Bool = false, wasLow: Bool = false) -> BatteryState {
            PowerSourceMonitor.rawState(hasReading: true, hasBattery: true, onAC: onAC, level: level,
                                        isCharging: charging, isCharged: charged, wasLow: wasLow)
        }
        precondition(raw(true, 100, charging: true) == .fullyCharged)
        precondition(raw(true, 96, charged: true) == .fullyCharged)
        precondition(raw(true, 50) == .notCharging && raw(true, 50, charging: true) == .charging)
        precondition(raw(false, 18) == .low && raw(false, 21) == .onBattery)
        precondition(raw(false, 21, wasLow: true) == .low && raw(false, 23, wasLow: true) == .onBattery)
        precondition(raw(true, 18, wasLow: true) == .notCharging)
        precondition(PowerSourceMonitor.rawState(hasReading: true, hasBattery: false, onAC: true, level: 0,
                                                 isCharging: false, isCharged: false) == .noBattery)

        // Debounce, with injected times.
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
        var plug = BatteryStateDebouncer(.onBattery)
        precondition(plug.feed(.notCharging, at: at(0)) == nil)
        precondition(plug.feed(.charging, at: at(1.2)) == nil)
        precondition(plug.poll(at: at(2.0)) == nil && plug.committed == .onBattery)
        precondition(plug.poll(at: at(3.2)) == .charging && plug.committed == .charging)
        var wiggle = BatteryStateDebouncer(.onBattery)
        precondition(wiggle.feed(.charging, at: at(0)) == nil)
        precondition(wiggle.feed(.onBattery, at: at(1.5)) == nil)
        precondition(wiggle.poll(at: at(5)) == nil && wiggle.committed == .onBattery && wiggle.dueDate == nil)
        var unplug = BatteryStateDebouncer(.charging)
        precondition(unplug.feed(.onBattery, at: at(0)) == .onBattery)
        var topOff = BatteryStateDebouncer(.onBattery)
        _ = topOff.feed(.fullyCharged, at: at(0))
        precondition(topOff.poll(at: at(2)) == .fullyCharged)
        precondition(topOff.feed(.charging, at: at(100)) == nil)
        precondition(topOff.poll(at: at(129)) == nil && topOff.poll(at: at(130)) == .charging)
        var stopping = BatteryStateDebouncer(.charging)
        precondition(stopping.feed(.notCharging, at: at(0)) == nil && stopping.poll(at: at(9)) == nil)
        precondition(stopping.poll(at: at(10)) == .notCharging)
        var drainWarning = BatteryStateDebouncer(.charging)
        precondition(drainWarning.feed(.draining, at: at(0)) == .draining)

        // Time to full: rounding, and only stepping up after two higher estimates.
        precondition(BatteryStatusText.fullIn(4) == "under 5 min" && BatteryStatusText.fullIn(23) == "about 25 min")
        precondition(BatteryStatusText.fullIn(62) == "about 1 h" && BatteryStatusText.fullIn(80) == "about 1 h 20 min")
        precondition(BatteryStatusText.fullIn(600) == "more than 10 h")
        var filter = TimeToFullFilter()
        precondition(filter.update(40) == 40 && filter.update(35) == 35)
        precondition(filter.update(60) == 35 && filter.update(38) == 35)
        precondition(filter.update(60) == 35 && filter.update(61) == 61)
        precondition(BatteryStatusText.line(.charging, minutesToFull: 40, since: nil, now: t0) == "Charging · full in about 40 min")
        precondition(BatteryStatusText.line(.charging, minutesToFull: nil, since: nil, now: t0) == "Charging")

        // Time since unplugging.
        func since(_ minutes: Double) -> String? { BatteryStatusText.onBatteryFor(since: at(-minutes * 60), now: t0) }
        precondition(since(0) == nil && since(12) == "for 12 min" && since(80) == "for 1 h 20 min" && since(120) == "for 2 h")
        precondition(BatteryStatusText.line(.onBattery, minutesToFull: nil, since: at(-80 * 60), now: t0) == "On battery for 1 h 20 min")
        precondition(BatteryStatusText.line(.onBattery, minutesToFull: nil, since: nil, now: t0) == "On battery")

        // Live input: USB-C steps, the step hysteresis and the watts deadband.
        precondition(PowerInputSampler.step(forVolts: 19.4) == "20 V" && PowerInputSampler.step(forVolts: 27.9) == "28 V")
        precondition(PowerInputSampler.step(forVolts: 12.0) == "12.0 V")
        var steps = PowerInputSampler.StepFilter()
        precondition(steps.feed("20 V") == "20 V")
        for _ in 0..<9 { precondition(steps.feed("28 V") == "20 V") }
        precondition(steps.feed("28 V") == "28 V")
        precondition(PowerInputSampler.nextWatts(shown: 28, mean: 30) == 28 && PowerInputSampler.nextWatts(shown: 28, mean: 31) == 31)
        precondition(PowerInputSampler.nextWatts(shown: nil, mean: 27.6) == 28)
        var limit = PowerInputSampler.LimitTracker()
        for _ in 0..<5 { precondition(!limit.feed(mean: 58, connectionWatts: 60)) }
        precondition(limit.feed(mean: 58, connectionWatts: 60) && !limit.feed(mean: 58, connectionWatts: nil))

        // System Information's health: what it says, or nothing.
        let profile = #"{"SPPowerDataType":[{"_name":"spbattery_information","sppower_battery_health_info":{"sppower_battery_cycle_count":343,"sppower_battery_health":"Good","sppower_battery_health_maximum_capacity":"87%"}}]}"#
        let health = BatteryHealth.parse(Data(profile.utf8), at: t0)!
        precondition(health.maximumCapacity == 87 && health.conditionNormal == true)
        let empty = BatteryHealth.parse(Data(#"{"SPPowerDataType":[{"_name":"sppower_information"}]}"#.utf8), at: t0)!
        precondition(empty.maximumCapacity == nil && empty.conditionNormal == nil)
        precondition(BatteryStatusText.healthLine(health, cycles: 343) == "Maximum capacity 87% · 343 cycles")
        precondition(BatteryStatusText.healthLine(BatteryHealth(maximumCapacity: 76, conditionNormal: false, fetchedAt: t0), cycles: 900)
                     == "Maximum capacity 76% · service recommended")
        precondition(BatteryStatusText.healthLine(nil, cycles: 343) == nil)

        // The charger as macOS names it.
        let adapter = ChargerInfo(adapterDetails: ["Name": "140W USB-C Power Adapter", "Watts": 60, "Description": "pd charger"])
        precondition(adapter.ratedWatts == 140 && adapter.connectionWatts == 60)
        precondition(ChargerInfo(adapterDetails: ["Description": "pd charger"]).name == "USB-C charger")
        precondition(ChargerInfo(adapterDetails: [:]) == ChargerInfo(name: "Charger", connectionWatts: nil, ratedWatts: nil))
        precondition(ChargerInfo.ratedWatts(in: "96 W USB-C") == 96 && ChargerInfo.ratedWatts(in: "USB-C charger") == nil)

        // The drain warning: three points down while the charger gives all it can.
        precondition(DrainDetector.fires(peak: 64, level: 61, onACFor: 600, mean60: 54, connectionWatts: 60, isLive: true))
        precondition(!DrainDetector.fires(peak: 64, level: 61, onACFor: 600, mean60: 24, connectionWatts: 60, isLive: true))
        precondition(!DrainDetector.fires(peak: 64, level: 62, onACFor: 600, mean60: 57, connectionWatts: 60, isLive: true))
        precondition(!DrainDetector.fires(peak: 64, level: 61, onACFor: 600, mean60: 54, connectionWatts: nil, isLive: true))
        precondition(!DrainDetector.fires(peak: 64, level: 61, onACFor: 600, mean60: 54, connectionWatts: 60, isLive: false))
        precondition(!DrainDetector.fires(peak: 64, level: 61, onACFor: 120, mean60: 54, connectionWatts: 60, isLive: true))

        let payload = #"{"SPBluetoothDataType":[{"device_connected":[{"Headphones":{"device_address":"AA-BB-CC-11-22-33","device_minorType":"Headphones","device_batteryLevelLeft":"80%","device_batteryLevelRight":"60%","device_batteryLevelCase":"1%"}},{"Keyboard":{"device_address":"AA-BB-CC-44-55-66","device_batteryLevel":"255%"}}],"device_not_connected":[{"Old device":{"device_address":"00-00-00-00-00-00","device_batteryLevel":"100%"}}]}]}"#
        let report = BluetoothBatteryReport.parse(Data(payload.utf8))
        let earbuds = report[BluetoothBatteryReport.addressKey("aa:bb:cc:11:22:33")]!
        precondition(earbuds.batteries.primary == 60 && earbuds.batteries.caseLevel == 1)
        precondition(report["aabbcc445566"]!.batteries.primary == nil)
        precondition(report.count == 2 && report["aabbcc445566"]!.name == "Keyboard")
        precondition(BluetoothBatteryReport.parse(Data("invalid".utf8)).isEmpty)
        print("Power source semantics, SMC byte order, battery state, debounce, wording, live input, health, charger, drain warning and Bluetooth component parsing checks passed")
    }
}
#endif
