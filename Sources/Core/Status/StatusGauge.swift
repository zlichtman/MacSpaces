import Foundation

/// What the Status icon can show. All in One stands in for three of the system's own icons: the
/// battery as the ring, Wi-Fi in its middle and the volume as a bar beside it. The others are one
/// reading as a ring. Everything is also in the icon's menu.
enum StatusReading: String, CaseIterable, Identifiable {
    case combined, battery, cpu, memory, disk, network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combined: return "All in One"
        case .battery: return "Battery"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        }
    }
}

/// Wi-Fi as the Status icon shows it. The network's name is never read: that needs Location.
enum StatusWiFi: Equatable {
    case off, notConnected
    /// 1 (weak) to 3 (strong).
    case connected(bars: Int)

    /// From the signal in dBm: strong from -60, fair from -72, else weak.
    static func connected(signal: Int) -> StatusWiFi { .connected(bars: signal >= -60 ? 3 : signal >= -72 ? 2 : 1) }

    var symbol: String {
        switch self {
        case .off: return "wifi.slash"
        case .notConnected: return "wifi.exclamationmark"
        case .connected: return "wifi"
        }
    }

    /// How much of the Wi-Fi symbol is lit, for symbols drawn with a variable value.
    var strength: Double {
        if case .connected(let bars) = self { return Double(min(3, max(1, bars))) / 3 }
        return 0
    }

    var detail: String {
        switch self {
        case .off: return "Off"
        case .notConnected: return "Not connected"
        case .connected(let bars): return bars >= 3 ? "Strong" : bars == 2 ? "Fair" : "Weak"
        }
    }
}

/// The Mac's readings at one moment, as the Status icon needs them.
struct StatusSnapshot: Equatable {
    /// nil on a Mac without a battery.
    var batteryLevel: Int?
    var charging = false
    var onPower = false
    var minutesToEmpty: Int?
    var minutesToFull: Int?
    /// 0 to 1.
    var cpu = 0.0
    var memory = 0.0
    var memoryUsedBytes = 0.0
    /// The part of the disk in use, 0 to 1.
    var disk = 0.0
    var diskFreeBytes = 0.0
    /// Bytes a second.
    var networkIn = 0.0
    var networkOut = 0.0
    /// nil on a Mac without Wi-Fi, or before it's been read.
    var wifi: StatusWiFi?
    /// The output volume, 0 to 1; nil when the output has no volume of its own (some displays).
    var volume: Double?
    var muted = false
}

/// One reading as drawn: how full its ring is, its symbol, its number, and its line in the menu.
struct StatusGauge: Equatable {
    enum Level: Equatable { case normal, warning, critical }

    let reading: StatusReading
    /// 0 to 1, in fiftieths so a redraw happens only when the ring would look different.
    let fraction: Double
    /// An SF Symbol for the ring's middle.
    let symbol: String
    /// Beside the ring when numbers are shown: "82%".
    let value: String
    /// The menu's line after the name: "82% · 3:10 left".
    let detail: String
    let level: Level
    /// All in One only: how lit the Wi-Fi symbol in the middle is (0 to 1), and the volume bar
    /// beside the ring (nil for no bar).
    var symbolStrength: Double?
    var bar: Double?
    var barMuted = false

    /// The readings this Mac has: no Battery on a Mac without one.
    static func available(_ snapshot: StatusSnapshot) -> [StatusReading] {
        StatusReading.allCases.filter { $0 != .battery || snapshot.batteryLevel != nil }
    }

    /// The reading to show: the chosen one, or CPU when this Mac doesn't have it.
    static func shown(_ chosen: StatusReading, snapshot: StatusSnapshot) -> StatusReading {
        available(snapshot).contains(chosen) ? chosen : .cpu
    }

    static func gauge(_ reading: StatusReading, _ snapshot: StatusSnapshot) -> StatusGauge {
        switch reading {
        case .combined:
            // The ring is the battery, or the CPU on a Mac without one.
            let ring = gauge(snapshot.batteryLevel != nil ? .battery : .cpu, snapshot)
            var parts = [(ring.reading == .battery ? "" : "CPU ") + ring.value]
            if let wifi = snapshot.wifi { parts.append("Wi-Fi " + wifi.detail.lowercased()) }
            if let line = volumeDetail(snapshot) { parts.append("volume " + line.lowercased()) }
            var all = StatusGauge(reading: .combined, fraction: ring.fraction, symbol: snapshot.wifi?.symbol ?? ring.symbol, value: ring.value,
                                  detail: parts.joined(separator: " · "), level: ring.level)
            all.symbolStrength = snapshot.wifi.map(\.strength)
            all.bar = snapshot.volume.map { stepped(snapshot.muted ? 0 : $0) }
            all.barMuted = snapshot.muted
            return all
        case .battery:
            let level = min(100, max(0, snapshot.batteryLevel ?? 0))
            var detail = "\(level)%"
            if snapshot.charging, let minutes = snapshot.minutesToFull, minutes > 0 { detail += " · \(clock(minutes)) to full" }
            else if snapshot.charging { detail += " · charging" }
            else if snapshot.onPower { detail += " · on power" }
            else if let minutes = snapshot.minutesToEmpty, minutes > 0 { detail += " · \(clock(minutes)) left" }
            let low: StatusGauge.Level = snapshot.onPower || snapshot.charging ? .normal : level <= 10 ? .critical : level <= 20 ? .warning : .normal
            return StatusGauge(reading: reading, fraction: stepped(Double(level) / 100),
                               symbol: snapshot.charging || snapshot.onPower ? "bolt.fill" : "minus.plus.batteryblock.fill",
                               value: "\(level)%", detail: detail, level: low)
        case .cpu:
            return StatusGauge(reading: reading, fraction: stepped(snapshot.cpu), symbol: "cpu.fill", value: percent(snapshot.cpu),
                               detail: percent(snapshot.cpu), level: busy(snapshot.cpu, warning: 0.8, critical: 0.95))
        case .memory:
            return StatusGauge(reading: reading, fraction: stepped(snapshot.memory), symbol: "memorychip.fill", value: percent(snapshot.memory),
                               detail: "\(percent(snapshot.memory)) · \(bytes(snapshot.memoryUsedBytes)) used",
                               level: busy(snapshot.memory, warning: 0.85, critical: 0.95))
        case .disk:
            return StatusGauge(reading: reading, fraction: stepped(snapshot.disk), symbol: "internaldrive.fill", value: percent(snapshot.disk),
                               detail: "\(percent(snapshot.disk)) · \(bytes(snapshot.diskFreeBytes)) free",
                               level: busy(snapshot.disk, warning: 0.9, critical: 0.97))
        case .network:
            let total = snapshot.networkIn + snapshot.networkOut
            return StatusGauge(reading: reading, fraction: stepped(networkFraction(total)), symbol: "arrow.up.arrow.down",
                               value: rate(total), detail: "↓ \(rate(snapshot.networkIn))  ↑ \(rate(snapshot.networkOut))", level: .normal)
        }
    }

    /// "45%" or "Muted"; nil when the output has no volume to read.
    static func volumeDetail(_ snapshot: StatusSnapshot) -> String? {
        guard let volume = snapshot.volume else { return nil }
        return snapshot.muted ? "Muted" : percent(volume)
    }

    private static func busy(_ value: Double, warning: Double, critical: Double) -> Level {
        value >= critical ? .critical : value >= warning ? .warning : .normal
    }

    static func stepped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (min(1, max(0, value)) * 50).rounded() / 50
    }

    static func percent(_ value: Double) -> String {
        "\(Int((min(1, max(0, value.isFinite ? value : 0)) * 100).rounded()))%"
    }

    /// Empty at 1 KB/s or less, full at 10 MB/s or more, by powers of ten between.
    static func networkFraction(_ bytesPerSecond: Double) -> Double {
        guard bytesPerSecond.isFinite, bytesPerSecond > 1_000 else { return 0 }
        return min(1, log10(bytesPerSecond / 1_000) / 4)
    }

    /// "3:10" from 190 minutes.
    static func clock(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }

    /// "182 GB", "9.1 GB", "640 MB": decimal units, as Finder shows sizes.
    static func bytes(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0 MB" }
        let gb = value / 1e9
        if gb >= 100 { return "\(Int(gb.rounded())) GB" }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return "\(Int((value / 1e6).rounded())) MB"
    }

    /// "1.8 MB/s", "210 KB/s", "0 KB/s".
    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 500 else { return "0 KB/s" }
        if bytesPerSecond >= 999_500 { return String(format: "%.1f MB/s", bytesPerSecond / 1e6) }
        return "\(Int((bytesPerSecond / 1e3).rounded())) KB/s"
    }
}
