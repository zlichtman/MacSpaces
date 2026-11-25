import Foundation

/// The Status icon's readings: what's available, how full each ring is, its number, its menu
/// line and when it warns.
@main struct StatusChecks {
    static func main() {
        var mac = StatusSnapshot(batteryLevel: 82, minutesToEmpty: 190, cpu: 0.24, memory: 0.56, memoryUsedBytes: 9.1e9, disk: 0.63,
                                 diskFreeBytes: 182e9, networkIn: 1.8e6, networkOut: 0.21e6)
        precondition(StatusGauge.available(mac) == StatusReading.allCases && StatusReading.allCases.first == .combined)
        var battery = StatusGauge.gauge(.battery, mac)
        precondition(battery.fraction == 0.82 && battery.value == "82%" && battery.detail == "82% · 3:10 left" && battery.level == .normal)
        mac.batteryLevel = 18
        precondition(StatusGauge.gauge(.battery, mac).level == .warning)
        mac.batteryLevel = 9
        precondition(StatusGauge.gauge(.battery, mac).level == .critical)
        mac.charging = true; mac.onPower = true; mac.minutesToFull = 45
        battery = StatusGauge.gauge(.battery, mac)
        precondition(battery.level == .normal && battery.detail == "9% · 0:45 to full" && battery.symbol == "bolt.fill", "Charging never warns")
        mac.charging = false; mac.minutesToFull = nil
        precondition(StatusGauge.gauge(.battery, mac).detail == "9% · on power")
        mac.batteryLevel = 140
        precondition(StatusGauge.gauge(.battery, mac).fraction == 1 && StatusGauge.gauge(.battery, mac).value == "100%")

        // A desktop Mac: no Battery, and a saved Battery choice shows CPU.
        let desktop = StatusSnapshot(cpu: 0.5)
        precondition(StatusGauge.available(desktop) == [.combined, .cpu, .memory, .disk, .network])
        precondition(StatusGauge.shown(.battery, snapshot: desktop) == .cpu && StatusGauge.shown(.disk, snapshot: desktop) == .disk)
        precondition(StatusGauge.shown(.battery, snapshot: mac) == .battery)

        // CPU, memory and disk.
        precondition(StatusGauge.gauge(.cpu, mac).value == "24%" && StatusGauge.gauge(.cpu, mac).fraction == 0.24)
        var busy = mac
        busy.cpu = 0.83; busy.memory = 0.96; busy.disk = 0.91
        precondition(StatusGauge.gauge(.cpu, busy).level == .warning && StatusGauge.gauge(.memory, busy).level == .critical && StatusGauge.gauge(.disk, busy).level == .warning)
        precondition(StatusGauge.gauge(.memory, mac).detail == "56% · 9.1 GB used" && StatusGauge.gauge(.disk, mac).detail == "63% · 182 GB free")
        busy.cpu = .nan
        precondition(StatusGauge.gauge(.cpu, busy).fraction == 0 && StatusGauge.gauge(.cpu, busy).value == "0%", "A bad reading draws empty")
        precondition(StatusGauge.stepped(0.249) == 0.24 && StatusGauge.stepped(0.251) == 0.26 && StatusGauge.stepped(7) == 1 && StatusGauge.stepped(-1) == 0)

        // Network.
        let network = StatusGauge.gauge(.network, mac)
        precondition(network.detail == "↓ 1.8 MB/s  ↑ 210 KB/s" && network.value == "2.0 MB/s" && network.level == .normal)
        precondition(StatusGauge.networkFraction(500) == 0 && StatusGauge.networkFraction(10e6) == 1 && StatusGauge.networkFraction(50e6) == 1)
        precondition(abs(StatusGauge.networkFraction(100_000) - 0.5) < 0.001)
        precondition(StatusGauge.rate(0) == "0 KB/s" && StatusGauge.rate(499) == "0 KB/s" && StatusGauge.rate(999_600) == "1.0 MB/s" && StatusGauge.rate(12_300) == "12 KB/s")
        precondition(StatusGauge.bytes(640e6) == "640 MB" && StatusGauge.bytes(1.5e9) == "1.5 GB" && StatusGauge.bytes(0) == "0 MB")
        precondition(StatusGauge.clock(59) == "0:59" && StatusGauge.clock(190) == "3:10")
        // All in One: the battery as the ring, Wi-Fi in the middle, the volume beside it.
        var laptop = StatusSnapshot(batteryLevel: 82, minutesToEmpty: 190, cpu: 0.24, wifi: .connected(signal: -55), volume: 0.45)
        var all = StatusGauge.gauge(.combined, laptop)
        precondition(all.reading == .combined && all.fraction == 0.82 && all.value == "82%" && all.symbol == "wifi" && all.symbolStrength == 1)
        precondition(all.bar == 0.46 && !all.barMuted && all.detail == "82% · Wi-Fi strong · volume 45%" && all.level == .normal)
        laptop.batteryLevel = 12; laptop.muted = true; laptop.wifi = .off
        all = StatusGauge.gauge(.combined, laptop)
        precondition(all.level == .warning && all.bar == 0 && all.barMuted && all.symbol == "wifi.slash" && all.symbolStrength == 0)
        precondition(all.detail == "12% · Wi-Fi off · volume muted")
        // A Mac without a battery, Wi-Fi or a volume of its own: the CPU as the ring, no bar.
        all = StatusGauge.gauge(.combined, StatusSnapshot(cpu: 0.5))
        precondition(all.fraction == 0.5 && all.symbol == "cpu.fill" && all.bar == nil && all.symbolStrength == nil && all.detail == "CPU 50%")
        precondition(StatusWiFi.connected(signal: -60) == .connected(bars: 3) && StatusWiFi.connected(signal: -61) == .connected(bars: 2))
        precondition(StatusWiFi.connected(signal: -73) == .connected(bars: 1) && StatusWiFi.connected(bars: 2).detail == "Fair")
        precondition(StatusWiFi.notConnected.symbol == "wifi.exclamationmark" && abs(StatusWiFi.connected(bars: 2).strength - 2.0 / 3) < 0.001)
        precondition(StatusGauge.volumeDetail(StatusSnapshot(volume: 0.3)) == "30%" && StatusGauge.volumeDetail(StatusSnapshot()) == nil)
        print("Status checks passed")
    }
}
