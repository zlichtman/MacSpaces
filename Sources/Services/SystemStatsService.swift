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
    /// Details for the System page (bytes, bytes a second, seconds).
    @Published private(set) var memoryUsedBytes: Double = 0
    @Published private(set) var swapUsedBytes: Double = 0
    @Published private(set) var diskFreeBytes: Double = 0
    @Published private(set) var networkInRate: Double = 0
    @Published private(set) var networkOutRate: Double = 0
    @Published private(set) var loadAverage: Double = 0
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    struct Sample {
        let cpu: Double
        let memory: Double
        let disk: Double
        var network: Double = 0
    }
    @Published private(set) var history: [Sample] = []
#if DEBUG
    func setPreview(memoryUsedBytes: Double = 9.1e9, swapUsedBytes: Double = 0.6e9, diskFreeBytes: Double = 182e9) {
        stop()
        cpuUsage = 0.24; memoryUsage = 0.56; diskUsage = 0.63
        self.memoryUsedBytes = memoryUsedBytes; self.swapUsedBytes = swapUsedBytes; self.diskFreeBytes = diskFreeBytes
        networkInRate = 1.8e6; networkOutRate = 0.21e6; loadAverage = 2.4
        history = (0..<60).map { index in
            Sample(cpu: 0.24 + sin(Double(index) * 0.4) * 0.08,
                   memory: 0.56 + sin(Double(index) * 0.1) * 0.02, disk: 0.63,
                   network: 1.2e6 + sin(Double(index) * 0.7) * 0.8e6)
        }
    }
#endif
    private var timer: Timer?
    private let sampleQueue = DispatchQueue(label: "dev.opensource.MacSpaces.stats", qos: .utility)
    private let sampler = SystemStatsSampler()
    private var generation = 0
    private var sampling = false
#if DEBUG
    var beforeSample: (@Sendable () -> Void)?
#endif

    func start() {
        guard timer == nil else { return }
        generation += 1
        let poll = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
        sample()
    }

    func stop() {
        generation += 1
        timer?.invalidate(); timer = nil
    }

    private func sample() {
        guard timer != nil, !sampling else { return }
        sampling = true
        let requested = generation
        let sampler = sampler
#if DEBUG
        let probe = beforeSample
#endif
        sampleQueue.async { [weak self] in
#if DEBUG
            probe?()
#endif
            let reading = sampler.read(session: requested)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.sampling = false
                guard self.timer != nil else { return }
                guard self.generation == requested else { self.sample(); return }
                self.cpuUsage = reading.cpuUsage
                self.memoryUsage = reading.memoryUsage
                self.diskUsage = reading.diskUsage
                self.batteryLevel = reading.batteryLevel
                self.isCharging = reading.isCharging
                self.memoryUsedBytes = reading.memoryUsedBytes
                self.swapUsedBytes = reading.swapUsedBytes
                self.diskFreeBytes = reading.diskFreeBytes
                self.networkInRate = reading.networkInRate
                self.networkOutRate = reading.networkOutRate
                self.loadAverage = reading.loadAverage
                self.thermalState = reading.thermalState
                self.history.append(Sample(cpu: reading.cpuUsage, memory: reading.memoryUsage,
                    disk: reading.diskUsage, network: reading.networkInRate + reading.networkOutRate))
                if self.history.count > 60 { self.history.removeFirst(self.history.count - 60) }
            }
        }
    }

    deinit { timer?.invalidate() }
}

/// Mutable counters never leave SystemStatsService.sampleQueue.
private final class SystemStatsSampler: @unchecked Sendable {
    /// 0...1
    var cpuUsage: Double = 0
    /// 0...1
    var memoryUsage: Double = 0
    /// 0...1
    var diskUsage: Double = 0
    /// 0...100, nil on desktops without a battery
    var batteryLevel: Int?
    var isCharging = false
    /// Details for the System page (bytes, bytes a second, seconds).
    var memoryUsedBytes: Double = 0
    var swapUsedBytes: Double = 0
    var diskFreeBytes: Double = 0
    var networkInRate: Double = 0
    var networkOutRate: Double = 0
    var loadAverage: Double = 0
    var thermalState: ProcessInfo.ThermalState = .nominal
    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    struct Reading: Sendable {
        var cpuUsage: Double; var memoryUsage: Double; var diskUsage: Double
        var batteryLevel: Int?; var isCharging: Bool
        var memoryUsedBytes: Double; var swapUsedBytes: Double; var diskFreeBytes: Double
        var networkInRate: Double; var networkOutRate: Double; var loadAverage: Double
        var thermalState: ProcessInfo.ThermalState
    }
    private var session = -1
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var previousNetwork: (inBytes: UInt64, outBytes: UInt64, at: Date)?

    func read(session: Int) -> Reading {
        if self.session != session {
            self.session = session; previousCPUTicks = nil; previousNetwork = nil
        }
        sampleCPU(); sampleMemory(); sampleDisk(); sampleBattery(); sampleNetwork(); sampleSwap()
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) > 0 { loadAverage = load[0] }
        thermalState = ProcessInfo.processInfo.thermalState
        return Reading(cpuUsage: cpuUsage, memoryUsage: memoryUsage, diskUsage: diskUsage, batteryLevel: batteryLevel, isCharging: isCharging, memoryUsedBytes: memoryUsedBytes, swapUsedBytes: swapUsedBytes, diskFreeBytes: diskFreeBytes, networkInRate: networkInRate, networkOutRate: networkOutRate, loadAverage: loadAverage, thermalState: thermalState)
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
            memoryUsedBytes = used
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
        diskFreeBytes = free
    }

    // MARK: - Network and swap

    /// Bytes a second in and out across active, non-loopback interfaces.
    private func sampleNetwork() {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return }
        defer { freeifaddrs(addresses) }
        var inBytes: UInt64 = 0, outBytes: UInt64 = 0
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            inBytes += UInt64(data.pointee.ifi_ibytes)
            outBytes += UInt64(data.pointee.ifi_obytes)
        }
        let now = Date()
        if let previous = previousNetwork, now > previous.at {
            let seconds = now.timeIntervalSince(previous.at)
            // Counters are 32-bit per interface and can wrap; a wrap reads as zero, not a spike.
            networkInRate = inBytes >= previous.inBytes ? Double(inBytes - previous.inBytes) / seconds : 0
            networkOutRate = outBytes >= previous.outBytes ? Double(outBytes - previous.outBytes) / seconds : 0
        }
        previousNetwork = (inBytes, outBytes, now)
    }

    private func sampleSwap() {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 { swapUsedBytes = Double(usage.xsu_used) }
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

        if let current = description[kIOPSCurrentCapacityKey] as? Int,
           let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
            batteryLevel = min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
        } else { batteryLevel = nil }
        isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
    }

}
