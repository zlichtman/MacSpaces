import CoreAudio
import SwiftUI

/// One device macOS can play through.
struct AudioOutput: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let symbol: String
}

/// The audio outputs CoreAudio already has and the current default, for the Music page's Play
/// On button. It reads and writes on a utility queue, listens only while a view needs it and
/// publishes only changes. Nothing here scans for or connects devices, asks for a permission
/// or touches the network; the default changes only when `select` is called.
@MainActor
final class AudioOutputs: ObservableObject {
    static let shared = AudioOutputs()

    @Published private(set) var outputs: [AudioOutput] = []
    @Published private(set) var currentID: AudioDeviceID?

    private nonisolated static let queue = DispatchQueue(label: "dev.opensource.MacSpaces.audio-outputs", qos: .utility)
    /// Debug harnesses and sample views never read or change the real devices.
    private static var readsDevices: Bool { Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" }
    private nonisolated static let watched: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice,
    ]

    private var holders = Set<UUID>()
    private var listener: AudioObjectPropertyListenerBlock?
    /// A newer read (or stopping) drops an older read's result.
    private var generation = 0

    /// Called as a view that needs the list appears and disappears.
    func setNeeded(_ needed: Bool, id: UUID) {
        if needed { holders.insert(id) } else { holders.remove(id) }
        guard Self.readsDevices else { return }
        if holders.isEmpty { stopListening() } else { startListening() }
    }

    /// Makes `id` the default output, and the system output for alerts where it can be.
    func select(_ id: AudioDeviceID) {
        if currentID != id { currentID = id }
        guard Self.readsDevices else { return }
        Self.queue.async { [weak self] in
            Self.setDefault(id)
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

#if DEBUG
    func setPreview(_ outputs: [AudioOutput], current: AudioDeviceID?) {
        self.outputs = outputs
        currentID = current
    }
#endif

    private func startListening() {
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        listener = block
        Self.queue.async {
            for selector in Self.watched {
                var address = Self.address(selector)
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, Self.queue, block)
            }
        }
        refresh()
    }

    private func stopListening() {
        guard let block = listener else { return }
        listener = nil
        generation += 1
        Self.queue.async {
            for selector in Self.watched {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, Self.queue, block)
            }
        }
    }

    private func refresh() {
        generation += 1
        let requested = generation
        Self.queue.async { [weak self] in
            let (outputs, current) = Self.read()
            Task { @MainActor [weak self] in
                guard let self, self.generation == requested else { return }
                if self.outputs != outputs { self.outputs = outputs }
                if self.currentID != current { self.currentID = current }
            }
        }
    }

    // MARK: - CoreAudio, on the utility queue

    private nonisolated static func address(_ selector: AudioObjectPropertySelector,
                                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private nonisolated static func read() -> ([AudioOutput], AudioDeviceID?) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return ([], nil) }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return ([], nil) }
        let outputs = ids.compactMap(output(for:)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var defaultAddress = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var current: AudioDeviceID = 0
        var currentSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let found = AudioObjectGetPropertyData(system, &defaultAddress, 0, nil, &currentSize, &current) == noErr && current != 0
        return (outputs, found ? current : nil)
    }

    /// A device the Sound settings would offer: it has output streams and can be the default
    /// (which leaves out apps' private aggregates).
    private nonisolated static func output(for id: AudioDeviceID) -> AudioOutput? {
        var streams = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &size) == noErr, size > 0,
              flag(kAudioDevicePropertyDeviceCanBeDefaultDevice, of: id), let name = name(of: id) else { return nil }
        return AudioOutput(id: id, name: name, symbol: AudioOutputSymbol.symbol(name: name, transport: transport(of: id)))
    }

    private nonisolated static func flag(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> Bool {
        var address = address(selector, scope: kAudioDevicePropertyScopeOutput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private nonisolated static func name(of id: AudioDeviceID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, UnsafeMutableRawPointer($0))
        }
        guard status == noErr, let name = value?.takeRetainedValue() as String?, !name.isEmpty else { return nil }
        return name
    }

    private nonisolated static func transport(of id: AudioDeviceID) -> AudioOutputSymbol.Transport {
        var address = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return .other }
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        default: return .other
        }
    }

    private nonisolated static func setDefault(_ id: AudioDeviceID) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var device = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var output = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(system, &output, 0, nil, size, &device)
        guard flag(kAudioDevicePropertyDeviceCanBeDefaultSystemDevice, of: id) else { return }
        var systemOutput = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        AudioObjectSetPropertyData(system, &systemOutput, 0, nil, size, &device)
    }
}
