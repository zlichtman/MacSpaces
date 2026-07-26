import AppKit
import CoreAudio
import Foundation

struct AppAudioSession: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let processObjectIDs: [AudioObjectID]
    let isProducingAudio: Bool
    var volume: Double
    var level: Double

    var isMuted: Bool { volume <= 0.001 }
    var isManaged: Bool { volume < 0.999 }
}

/// Discovers Core Audio process objects and applies saved per-app gain through
/// private process taps. Apps left at 100% stay on their original zero-latency
/// system path; only apps the user actually changes are looped through the
/// mixer engine.
@MainActor
final class AudioMixerService: ObservableObject {
    @Published private(set) var sessions: [AppAudioSession] = []
    @Published private(set) var outputName = "System Output"
    @Published private(set) var masterVolume: Double = 0.5
    @Published private(set) var masterMuted = false
    @Published private(set) var engineError: String?
    @Published private(set) var isMixerRunning = false

    private struct ProcessInfo {
        let objectID: AudioObjectID
        let pid: pid_t
        let bundleID: String
        let isRunningOutput: Bool
    }

    private struct SessionGroup {
        var key: String
        var name: String
        var icon: NSImage?
        var processObjectIDs: [AudioObjectID]
        var isProducingAudio: Bool
    }

    private let engine = MSAudioMixerEngine()
    private let defaults = UserDefaults.standard
    private let volumesKey = "audioMixer.appVolumes.v1"
    private let lastAudibleVolumesKey = "audioMixer.lastAudibleVolumes.v1"
    private var savedVolumes: [String: Double] = [:]
    private var lastAudibleVolumes: [String: Double] = [:]
    private var pollTimer: Timer?
    private var meterTimer: Timer?
    private var rebuildWorkItem: DispatchWorkItem?
    private var engineSignature = ""
    private var outputDeviceID = AudioDeviceID(kAudioObjectUnknown)

    var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    var activeAppCount: Int {
        sessions.filter(\.isProducingAudio).count
    }

    init() {
        savedVolumes = defaults.dictionary(forKey: volumesKey)?
            .compactMapValues { ($0 as? NSNumber)?.doubleValue } ?? [:]
        lastAudibleVolumes = defaults.dictionary(forKey: lastAudibleVolumesKey)?
            .compactMapValues { ($0 as? NSNumber)?.doubleValue } ?? [:]
    }

    func start() {
        guard pollTimer == nil else { return }
        refresh()

        let poll = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll

        let meter = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshMeters() }
        }
        RunLoop.main.add(meter, forMode: .common)
        meterTimer = meter
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        meterTimer?.invalidate()
        meterTimer = nil
        rebuildWorkItem?.cancel()
        rebuildWorkItem = nil
        engine.stop()
        isMixerRunning = false
        engineSignature = ""
    }

    func setMasterVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        masterVolume = clamped
        masterMuted = false
        guard outputDeviceID != kAudioObjectUnknown else { return }
        setAudioScalar(clamped, device: outputDeviceID)
        setAudioMute(false, device: outputDeviceID)
    }

    func toggleMasterMute() {
        masterMuted.toggle()
        guard outputDeviceID != kAudioObjectUnknown else { return }
        setAudioMute(masterMuted, device: outputDeviceID)
    }

    func setVolume(_ value: Double, for sessionID: String) {
        let clamped = min(max(value, 0), 1)
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        let wasManaged = sessions[index].isManaged
        sessions[index].volume = clamped
        if clamped > 0.001 {
            lastAudibleVolumes[sessionID] = clamped
        }
        if clamped >= 0.999 {
            savedVolumes.removeValue(forKey: sessionID)
        } else {
            savedVolumes[sessionID] = clamped
        }
        persistVolumes()

        if wasManaged && clamped < 0.999 && engine.isRunning {
            engine.setGain(Float(clamped), forKey: sessionID)
        } else {
            scheduleEngineRebuild()
        }
    }

    func toggleMute(for sessionID: String) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return
        }
        if session.isMuted {
            setVolume(lastAudibleVolumes[sessionID] ?? 1, for: sessionID)
        } else {
            lastAudibleVolumes[sessionID] = max(session.volume, 0.12)
            setVolume(0, for: sessionID)
        }
    }

    func reset(_ sessionID: String) {
        setVolume(1, for: sessionID)
    }

    func retryMixer() {
        engineSignature = ""
        engineError = nil
        scheduleEngineRebuild(immediate: true)
    }

#if DEBUG
    func setPreview(
        sessions: [AppAudioSession],
        outputName: String = "MacBook Pro Speakers",
        masterVolume: Double = 0.64
    ) {
        self.sessions = sessions
        self.outputName = outputName
        self.masterVolume = masterVolume
        masterMuted = false
        engineError = nil
        isMixerRunning = sessions.contains(where: \.isManaged)
    }
#endif

    private func refresh() {
        let previousDevice = outputDeviceID
        outputDeviceID = defaultOutputDevice() ?? kAudioObjectUnknown
        if outputDeviceID != kAudioObjectUnknown {
            outputName = audioObjectString(
                outputDeviceID,
                selector: kAudioObjectPropertyName
            ) ?? "System Output"
            masterVolume = audioScalar(device: outputDeviceID) ?? masterVolume
            masterMuted = audioMute(device: outputDeviceID) ?? masterMuted
        }

        let groups = groupedAudioProcesses()
        let existingLevels = Dictionary(
            uniqueKeysWithValues: sessions.map { ($0.id, $0.level) }
        )
        sessions = groups
            .filter {
                $0.isProducingAudio || savedVolumes[$0.key] != nil
            }
            .map { group in
                AppAudioSession(
                    id: group.key,
                    name: group.name,
                    icon: group.icon,
                    processObjectIDs: group.processObjectIDs.sorted(),
                    isProducingAudio: group.isProducingAudio,
                    volume: savedVolumes[group.key] ?? 1,
                    level: existingLevels[group.key] ?? 0
                )
            }
            .sorted {
                if $0.isProducingAudio != $1.isProducingAudio {
                    return $0.isProducingAudio && !$1.isProducingAudio
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        if previousDevice != outputDeviceID {
            engineSignature = ""
        }
        scheduleEngineRebuild()
    }

    private func refreshMeters() {
        guard !sessions.isEmpty else { return }
        var changed = false
        for index in sessions.indices {
            let target: Double
            if sessions[index].isManaged && engine.isRunning {
                target = Double(engine.level(forKey: sessions[index].id))
            } else {
                target = sessions[index].isProducingAudio ? 0.42 : 0
            }
            let next = max(target, sessions[index].level * 0.72)
            if abs(next - sessions[index].level) > 0.005 {
                sessions[index].level = min(max(next, 0), 1)
                changed = true
            }
        }
        if changed {
            objectWillChange.send()
        }
    }

    private func scheduleEngineRebuild(immediate: Bool = false) {
        rebuildWorkItem?.cancel()
        let signature = mixerSignature()
        guard signature != engineSignature else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.rebuildEngine(signature: signature)
            }
        }
        rebuildWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (immediate ? 0 : 0.12),
            execute: work
        )
    }

    private func mixerSignature() -> String {
        let controlled = sessions
            .filter(\.isManaged)
            .map {
                "\($0.id):\($0.processObjectIDs.map(String.init).joined(separator: ","))"
            }
            .joined(separator: "|")
        return "\(outputDeviceID)#\(controlled)"
    }

    private func rebuildEngine(signature: String) {
        rebuildWorkItem = nil
        engineSignature = signature

        let controlled = sessions.filter(\.isManaged)
        guard !controlled.isEmpty else {
            engine.stop()
            engineError = nil
            isMixerRunning = false
            return
        }
        guard isSupported, outputDeviceID != kAudioObjectUnknown else {
            engine.stop()
            engineError = "Per-app audio requires macOS 14.2 or later."
            isMixerRunning = false
            return
        }

        let didStart = engine.configure(
            withProcessGroups: controlled.map {
                $0.processObjectIDs.map(NSNumber.init(value:))
            },
            keys: controlled.map(\.id),
            gains: controlled.map { NSNumber(value: $0.volume) },
            outputDeviceID: outputDeviceID
        )
        isMixerRunning = didStart
        engineError = didStart ? nil : engine.lastError
    }

    private func persistVolumes() {
        defaults.set(savedVolumes, forKey: volumesKey)
        defaults.set(lastAudibleVolumes, forKey: lastAudibleVolumesKey)
    }

    private func groupedAudioProcesses() -> [SessionGroup] {
        var groups: [String: SessionGroup] = [:]
        for process in audioProcesses() {
            guard process.pid != Foundation.ProcessInfo.processInfo.processIdentifier else {
                continue
            }
            let app = NSRunningApplication(processIdentifier: process.pid)
            let resolvedBundleID = app?.bundleIdentifier?.isEmpty == false
                ? app?.bundleIdentifier
                : process.bundleID
            let key = resolvedBundleID?.isEmpty == false
                ? resolvedBundleID!
                : "pid:\(process.pid)"
            let appURL = resolvedBundleID.flatMap {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }
            let name = app?.localizedName
                ?? appURL?.deletingPathExtension().lastPathComponent
                ?? process.bundleID.split(separator: ".").last.map(String.init)
                ?? "Audio App"
            let icon = app?.icon ?? appURL.map {
                NSWorkspace.shared.icon(forFile: $0.path)
            }

            if var group = groups[key] {
                group.processObjectIDs.append(process.objectID)
                group.isProducingAudio =
                    group.isProducingAudio || process.isRunningOutput
                if group.icon == nil { group.icon = icon }
                groups[key] = group
            } else {
                groups[key] = SessionGroup(
                    key: key,
                    name: name,
                    icon: icon,
                    processObjectIDs: [process.objectID],
                    isProducingAudio: process.isRunningOutput
                )
            }
        }
        return Array(groups.values)
    }

    private func audioProcesses() -> [ProcessInfo] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            system,
            &address,
            0,
            nil,
            &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            system,
            &address,
            0,
            nil,
            &size,
            &ids
        ) == noErr else { return [] }

        return ids.compactMap { objectID in
            guard let pid: Int32 = audioObjectValue(
                objectID,
                selector: kAudioProcessPropertyPID
            ) else { return nil }
            let running: UInt32 = audioObjectValue(
                objectID,
                selector: kAudioProcessPropertyIsRunningOutput
            ) ?? 0
            return ProcessInfo(
                objectID: objectID,
                pid: pid,
                bundleID: audioObjectString(
                    objectID,
                    selector: kAudioProcessPropertyBundleID
                ) ?? "",
                isRunningOutput: running != 0
            )
        }
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        audioObjectValue(
            AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice
        )
    }

    private func audioObjectValue<T>(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            value
        ) == noErr else { return nil }
        return value.move()
    }

    private func audioObjectString(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.stride)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                $0
            )
        }
        return status == noErr ? value as String : nil
    }

    private func audioScalar(device: AudioDeviceID) -> Double? {
        let elements: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain, 1, 2,
        ]
        let values: [Float32] = elements.compactMap {
            audioObjectValue(
                device,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: $0
            )
        }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +) / Float32(values.count))
    }

    private func setAudioScalar(_ scalar: Double, device: AudioDeviceID) {
        for element: AudioObjectPropertyElement in [
            kAudioObjectPropertyElementMain, 1, 2,
        ] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(device, &address) else { continue }
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(
                device,
                &address,
                &settable
            ) == noErr, settable.boolValue else { continue }
            var value = Float32(scalar)
            AudioObjectSetPropertyData(
                device,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float32>.size),
                &value
            )
        }
    }

    private func audioMute(device: AudioDeviceID) -> Bool? {
        let value: UInt32? = audioObjectValue(
            device,
            selector: kAudioDevicePropertyMute,
            scope: kAudioDevicePropertyScopeOutput
        )
        return value.map { $0 != 0 }
    }

    private func setAudioMute(_ muted: Bool, device: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else {
            if muted { setAudioScalar(0, device: device) }
            return
        }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
    }

    deinit {
        pollTimer?.invalidate()
        meterTimer?.invalidate()
        rebuildWorkItem?.cancel()
    }
}
