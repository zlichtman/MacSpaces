import CoreAudio
import CoreBluetooth
import Foundation
import IOBluetooth

/// Sound outputs (built-in speakers, headphones, AirPods, displays, AirPlay
/// devices that are connected) and which one macOS is using. Choosing one makes
/// it the system's default output. Read when the menu opens; no permission needed.
enum AudioOutputs {
    struct Device: Identifiable, Equatable {
        let id: AudioObjectID
        let name: String
        let symbol: String
    }

    static func list() -> [Device] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutput(id), let name = name(of: id) else { return nil }
            return Device(id: id, name: name, symbol: symbol(for: id, name: name))
        }
    }

    /// Headphones and speakers paired with this Mac that aren't connected now
    /// (AirPods in their case, for example), so they can be connected from the menu.
    struct PairedDevice: Identifiable, Equatable {
        let id: String   // Bluetooth address
        let name: String
        var symbol: String { name.lowercased().contains("airpods") ? "airpods" : "headphones" }
    }

    /// Bluetooth access already granted; reading paired devices before that would prompt.
    static var bluetoothAllowed: Bool { CBCentralManager.authorization == .allowedAlways }

    static func pairedAudioDevices() -> [PairedDevice] {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let connected = Set(list().map { $0.name })
        return devices.compactMap { device in
            // Major class 0x04 is audio/video: headphones, earbuds, speakers.
            guard device.deviceClassMajor == 0x04, !device.isConnected(),
                  let name = device.name, !connected.contains(name), let address = device.addressString else { return nil }
            return PairedDevice(id: address, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Connects a paired device over Bluetooth, then makes it the output once
    /// macOS lists it (a few seconds). Calls back with whether it worked.
    static func connect(_ paired: PairedDevice, completion: @escaping @MainActor (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let opened = IOBluetoothDevice(addressString: paired.id)?.openConnection() == kIOReturnSuccess
            guard opened else { DispatchQueue.main.async { completion(false) }; return }
            for _ in 0..<20 {
                if let device = list().first(where: { $0.name == paired.name }) {
                    select(device)
                    DispatchQueue.main.async { completion(true) }
                    return
                }
                Thread.sleep(forTimeInterval: 0.4)
            }
            DispatchQueue.main.async { completion(false) }
        }
    }

    static var current: AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return nil }
        return id
    }

    static func select(_ device: Device) {
        var id = device.id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &id)
        }
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }

    private static func symbol(for id: AudioObjectID, name: String) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        let lower = name.lowercased()
        if lower.contains("airpods") { return "airpods" }
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: return "tv"
        case kAudioDeviceTransportTypeBuiltIn: return lower.contains("headphone") ? "headphones" : "laptopcomputer"
        default: return "hifispeaker"
        }
    }
}
