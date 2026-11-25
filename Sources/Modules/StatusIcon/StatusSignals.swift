import CoreAudio
import CoreWLAN

/// Wi-Fi and the output volume for the Status icon's All in One: read only while the icon is on,
/// off the main thread, publishing only changes. Wi-Fi is whether it's on, joined and how strong;
/// the network's name is never read (that needs Location), nothing is scanned or joined, and
/// nothing here asks for a permission. The volume is the default output's, heard about from
/// CoreAudio when it or the output changes.
@MainActor
final class StatusSignals: ObservableObject {
    @Published private(set) var wifi: StatusWiFi?
    @Published private(set) var volume: Double?
    @Published private(set) var muted = false

    private nonisolated static let queue = DispatchQueue(label: "dev.opensource.MacSpaces.status-signals", qos: .utility)
    private var running = false
    /// A newer read (or stopping) drops an older read's result.
    private var generation = 0
    private var listener: AudioObjectPropertyListenerBlock?
    /// The output whose volume and mute are being listened to.
    private var listened: AudioDeviceID?

    private nonisolated static let system = AudioObjectID(kAudioObjectSystemObject)
    /// The volume as the system's slider shows it, and the device's own as a fallback.
    private nonisolated static let virtualVolume = AudioObjectPropertySelector(0x766D7663) // 'vmvc'

    func start() {
        guard !running else { return }
        running = true
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        listener = block
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(Self.system, &address, Self.queue, block)
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        generation += 1
        if let listener {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            AudioObjectRemovePropertyListenerBlock(Self.system, &address, Self.queue, listener)
            follow(nil)
        }
        listener = nil
        wifi = nil; volume = nil; muted = false
    }

    /// Reads both again: on each system sample, and when CoreAudio says something changed.
    func refresh() {
        guard running else { return }
        generation += 1
        let requested = generation
        Self.queue.async { [weak self] in
            let wifi = Self.readWiFi()
            let device = Self.defaultOutput()
            let sound = device.map(Self.readVolume) ?? (nil, false)
            Task { @MainActor [weak self] in
                guard let self, self.running, self.generation == requested else { return }
                self.follow(device)
                if self.wifi != wifi { self.wifi = wifi }
                if self.volume != sound.0 { self.volume = sound.0 }
                if self.muted != sound.1 { self.muted = sound.1 }
            }
        }
    }

    /// Listens to this output's volume and mute, and stops listening to the one before.
    private func follow(_ device: AudioDeviceID?) {
        guard device != listened, let listener else { return }
        for selector in [Self.virtualVolume, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            var address = Self.address(selector)
            if let old = listened { AudioObjectRemovePropertyListenerBlock(old, &address, Self.queue, listener) }
            if let device, AudioObjectHasProperty(device, &address) { AudioObjectAddPropertyListenerBlock(device, &address, Self.queue, listener) }
        }
        listened = device
    }

    private nonisolated static func address(_ selector: AudioObjectPropertySelector,
                                            scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
                                            element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private nonisolated static func defaultOutput() -> AudioDeviceID? {
        var place = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &place, 0, nil, &size, &device) == noErr, device != 0 else { return nil }
        return device
    }

    /// The output's volume (the system slider's value, else the device's own, else its first
    /// two channels' average) and whether it's muted; nil when it has no volume to read.
    private nonisolated static func readVolume(of device: AudioDeviceID) -> (Double?, Bool) {
        func scalar(_ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Double? {
            var place = Self.address(selector, element: element)
            var value = Float32(0), size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectHasProperty(device, &place),
                  AudioObjectGetPropertyData(device, &place, 0, nil, &size, &value) == noErr, value.isFinite else { return nil }
            return Double(min(1, max(0, value)))
        }
        var volume = scalar(virtualVolume) ?? scalar(kAudioDevicePropertyVolumeScalar)
        if volume == nil {
            let channels = [1, 2].compactMap { scalar(kAudioDevicePropertyVolumeScalar, element: AudioObjectPropertyElement($0)) }
            if !channels.isEmpty { volume = channels.reduce(0, +) / Double(channels.count) }
        }
        var mute = Self.address(kAudioDevicePropertyMute)
        var flag = UInt32(0), size = UInt32(MemoryLayout<UInt32>.size)
        let muted = AudioObjectHasProperty(device, &mute)
            && AudioObjectGetPropertyData(device, &mute, 0, nil, &size, &flag) == noErr && flag != 0
        return (volume, muted)
    }

    /// Whether Wi-Fi is on, joined and how strong. A Mac without Wi-Fi gives nil.
    private nonisolated static func readWiFi() -> StatusWiFi? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        guard interface.powerOn() else { return .off }
        let signal = interface.rssiValue()
        return signal == 0 ? .notConnected : .connected(signal: signal)
    }
}
