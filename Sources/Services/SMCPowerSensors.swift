import Foundation
import IOKit
import os

/// Live readings at the Mac's power input from the System Management Controller, read
/// through the AppleSMC user client (read-only; no helper or entitlement). The battery
/// service in the I/O Registry copies one of these readings once a minute; the SMC
/// updates every second.
///
/// Keys: PDTR, the power coming in from the charger (W), and VD0R, its voltage (V), both
/// `flt`. A Mac without a key reports nil for it.
///
/// Byte order: `flt` is a little-endian Float32. Integer and `sp78` keys are
/// little-endian when the key's attribute byte has bit 0x04 set (every battery and
/// charger key on Apple silicon) and big-endian otherwise.
final class SMCPowerSensors: @unchecked Sendable {
    static let shared = SMCPowerSensors()

    struct Reading: Equatable {
        var inputWatts: Double?
        var inputVolts: Double?
    }

    private struct KeyInfo { let size: UInt32; let type: UInt32; let attributes: UInt8 }

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    /// Failed opens back off: 5 s, then 30 s, then every 5 minutes.
    private var openFailures = 0
    private var nextOpenAttempt: Date?
    /// Each key's size, type and attributes, looked up once.
    private var info: [UInt32: KeyInfo] = [:]
    /// Keys whose lookup failed, retried after a minute.
    private var missing: [UInt32: Date] = [:]
    private var loggedTypes: Set<UInt32> = []

    /// nil when neither key could be read.
    func read() -> Reading? {
        lock.lock(); defer { lock.unlock() }
        guard open() else { return nil }
        let reading = Reading(inputWatts: value("PDTR"), inputVolts: value("VD0R"))
        return reading == Reading() ? nil : reading
    }

    /// Decodes a key's raw bytes by its type and attribute byte; nil for a type
    /// this doesn't read or bytes of the wrong length.
    static func decode(_ bytes: [UInt8], type: UInt32, attributes: UInt8) -> Double? {
        let little = attributes & 0x04 != 0
        func unsigned(_ count: Int) -> UInt64? {
            guard bytes.count == count else { return nil }
            let ordered = little ? bytes.reversed() : bytes
            return ordered.reduce(0) { $0 << 8 | UInt64($1) }
        }
        switch type {
        case code("flt "):
            guard bytes.count == 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case code("ui8 "): return unsigned(1).map { Double($0) }
        case code("si8 "): return unsigned(1).map { Double(Int8(bitPattern: UInt8($0))) }
        case code("ui16"): return unsigned(2).map { Double($0) }
        case code("si16"): return unsigned(2).map { Double(Int16(bitPattern: UInt16($0))) }
        case code("sp78"): return unsigned(2).map { Double(Int16(bitPattern: UInt16($0))) / 256 }
        case code("ui32"): return unsigned(4).map { Double($0) }
        case code("si32"): return unsigned(4).map { Double(Int32(bitPattern: UInt32($0))) }
        default: return nil
        }
    }

    static func code(_ key: String) -> UInt32 { key.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    // MARK: AppleSMC

    /// The kernel's SMCKeyData_t (80 bytes); the padding after keyInfo matches C's layout.
    private struct KeyData {
        var key: UInt32 = 0
        var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
        var pLimit: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
        var keyInfo: (size: UInt32, type: UInt32, attributes: UInt8, pad: (UInt8, UInt8, UInt8)) = (0, 0, 0, (0, 0, 0))
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }
    private static let readKeyInfo: UInt8 = 9
    private static let readBytes: UInt8 = 5

    private func open() -> Bool {
        if connection != 0 { return true }
        if let nextOpenAttempt, Date() < nextOpenAttempt { return false }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        defer { if service != 0 { IOObjectRelease(service) } }
        var opened: io_connect_t = 0
        guard service != 0, IOServiceOpen(service, mach_task_self_, 0, &opened) == kIOReturnSuccess, opened != 0 else {
            openFailures += 1
            nextOpenAttempt = Date().addingTimeInterval(openFailures == 1 ? 5 : openFailures == 2 ? 30 : 300)
            return false
        }
        connection = opened
        openFailures = 0
        nextOpenAttempt = nil
        return true
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var size = MemoryLayout<KeyData>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<KeyData>.stride, &output, &size)
        return result == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    private func value(_ name: String) -> Double? {
        let key = Self.code(name)
        if info[key] == nil {
            if let failed = missing[key], Date().timeIntervalSince(failed) < 60 { return nil }
            var request = KeyData(); request.key = key; request.command = Self.readKeyInfo
            guard let reply = call(&request) else { missing[key] = Date(); return nil }
            missing[key] = nil
            info[key] = KeyInfo(size: reply.keyInfo.size, type: reply.keyInfo.type, attributes: reply.keyInfo.attributes)
        }
        guard let key = info[key].map({ (code: key, info: $0) }), key.info.size > 0, key.info.size <= 32 else { return nil }
        var request = KeyData(); request.key = key.code; request.keyInfo.size = key.info.size; request.command = Self.readBytes
        guard let reply = call(&request) else { return nil }
        let bytes = withUnsafeBytes(of: reply.bytes) { Array($0.prefix(Int(key.info.size))) }
        guard let decoded = Self.decode(bytes, type: key.info.type, attributes: key.info.attributes) else {
            if loggedTypes.insert(key.code).inserted {
                os_log(.info, "SMC key %{public}@ has a type this doesn't read (%u bytes)", name, key.info.size)
            }
            return nil
        }
        return decoded
    }
}
