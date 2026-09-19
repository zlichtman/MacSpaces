import Foundation
import IOKit.ps
import Combine

/// Periodically samples CPU load, memory pressure, and battery level using
/// Mach host statistics and IOKit power sources.
@MainActor
final class SystemStatsService: ObservableObject {
    /// 0...1
    @Published private(set) var cpuUsage: Double = 0
    /// 0...1
    @Published private(set) var memoryUsage: Double = 0
    /// 0...1
    @Published private(set) var diskUsage: Double = 0
    /// 0...100, nil on desktops without a battery
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var isCharging = false

    private var timer: Timer?
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sample()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousCPUTicks = nil
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleDisk()
        sampleBattery()
    }

    // MARK: - CPU

    private func sampleCPU() {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPointer, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let ticks = (user: UInt64(info.cpu_ticks.0),
                     system: UInt64(info.cpu_ticks.1),
                     idle: UInt64(info.cpu_ticks.2),
                     nice: UInt64(info.cpu_ticks.3))

        defer { previousCPUTicks = ticks }
        guard let previous = previousCPUTicks else { return }

        let userDelta = Double(ticks.user &- previous.user)
        let systemDelta = Double(ticks.system &- previous.system)
        let idleDelta = Double(ticks.idle &- previous.idle)
        let niceDelta = Double(ticks.nice &- previous.nice)
        let total = userDelta + systemDelta + idleDelta + niceDelta

        if total > 0 {
            cpuUsage = min(1, max(0, (userDelta + systemDelta + niceDelta) / total))
        }
    }

    // MARK: - Memory

    private func sampleMemory() {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPointer, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count)
                    + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)

        if total > 0 {
            memoryUsage = min(1, max(0, used / total))
        }
    }

    // MARK: - Disk

    private func sampleDisk() {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(
            forPath: "/"
        ),
        let total = (attributes[.systemSize] as? NSNumber)?.doubleValue,
        let free = (attributes[.systemFreeSize] as? NSNumber)?.doubleValue,
        total > 0 else { return }

        diskUsage = min(1, max(0, 1 - free / total))
    }

    // MARK: - Battery

    private func sampleBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, source)?
                  .takeUnretainedValue() as? [String: Any] else {
            batteryLevel = nil
            return
        }

        batteryLevel = description[kIOPSCurrentCapacityKey] as? Int
        isCharging = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
    }

    deinit {
        timer?.invalidate()
    }
}
