import Foundation

/// Battery values published by macOS for already-paired devices. Unknown values
/// stay nil; the case never substitutes for a known left/right earbud level.
struct BluetoothBatteryLevels: Equatable, Sendable {
    var main: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    var primary: Int? { [left, right].compactMap { $0 }.min() ?? main ?? caseLevel }
    var summary: String {
        let parts: [(String, Int?)] = [("Left", left), ("Right", right), ("Case", caseLevel)]
        let components = parts.compactMap { name, value in value.map { "\(name) \($0)%" } }
        return components.isEmpty ? main.map { "\($0)%" } ?? "Battery unavailable" : components.joined(separator: " · ")
    }
}

struct BluetoothBatteryReport: Sendable {
    let batteries: BluetoothBatteryLevels
    let category: String
    let name: String

    static func addressKey(_ value: String) -> String {
        value.lowercased().filter { $0.isHexDigit }
    }

    static func parse(_ data: Data) -> [String: Self] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = json["SPBluetoothDataType"] as? [[String: Any]] else { return [:] }
        var result: [String: Self] = [:]
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, raw) in entry {
                    guard let device = raw as? [String: Any], let address = device["device_address"] as? String else { continue }
                    let batteries = BluetoothBatteryLevels(
                        main: percentage(device["device_batteryLevelMain"]) ?? percentage(device["device_batteryLevel"]),
                        left: percentage(device["device_batteryLevelLeft"]),
                        right: percentage(device["device_batteryLevelRight"]),
                        caseLevel: percentage(device["device_batteryLevelCase"]))
                    result[addressKey(address)] = Self(batteries: batteries, category: device["device_minorType"] as? String ?? "", name: name)
                }
            }
        }
        return result
    }

    private static func percentage(_ value: Any?) -> Int? {
        let number: Int?
        if let text = value as? String {
            number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: ""))
        } else { number = (value as? NSNumber)?.intValue }
        guard let number, (0...100).contains(number) else { return nil }
        return number
    }

    /// Runs off the main thread: every 30 seconds for battery updates, or four
    /// seconds when needed for connection detection. A timeout bounds slow reads.
    static func load() -> [String: Self]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return parse(data)
    }
}
