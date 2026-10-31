import AppKit
import CoreAudio
import CoreGraphics
import ObjectiveC.runtime

struct SystemLiveActivity: Equatable {
    enum Kind: Equatable {
        case microphone
        case focus
    }

    let kind: Kind
    let label: String
    let systemImage: String
    /// Normalized value for activities that benefit from a compact meter.
    /// Semantic states such as Focus and microphone mute leave this nil.
    let level: Double?

    init(
        kind: Kind,
        label: String,
        systemImage: String,
        level: Double? = nil
    ) {
        self.kind = kind
        self.label = label
        self.systemImage = systemImage
        self.level = level
    }
}

/// Observes microphone mute and Focus, which macOS doesn't show on screen when
/// they change, and publishes a short-lived activity for the closed Nook.
/// Volume and brightness are left to macOS's own indicators.
///
/// The microphone uses public CoreAudio APIs. Focus is loaded dynamically, so
/// unsupported releases simply omit it instead of failing the app.
@MainActor
final class SystemActivityMonitor: ObservableObject {
    @Published private(set) var currentActivity: SystemLiveActivity?

    private struct Snapshot: Equatable {
        var microphoneMuted: Bool?
        var focusName: String?
    }

    private var timer: Timer?
    private var previousSnapshot: Snapshot?
    private var hideWorkItem: DispatchWorkItem?
    private let focusManager: AnyObject?
    /// CoreAudio and Focus answer over IPC; asking on the main thread twice a
    /// second could stall an animation whenever either service was slow.
    private static let readQueue = DispatchQueue(label: "dev.opensource.MacSpaces.system-activity", qos: .utility)
    private var readInFlight = false
    private var generation = 0

    var justChangedRecently: Bool { currentActivity != nil }

    init() {
        _ = dlopen(
            "/System/Library/PrivateFrameworks/Focus.framework/Focus",
            RTLD_NOW
        )
        if let managerClass: AnyClass = NSClassFromString("FCActivityManager") {
            focusManager = (managerClass as AnyObject)
                .perform(NSSelectorFromString("sharedActivityManager"))?
                .takeUnretainedValue() as AnyObject?
        } else {
            focusManager = nil
        }
    }

    func start() {
        guard timer == nil else { return }
        generation += 1
        previousSnapshot = nil
        refresh()
        // The microphone reports its own changes, so it's read when it changes. Focus has
        // no notification, so it alone is read on the same 0.45 s beat as before.
        listenToMicrophone()
        let pollingTimer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(focusOnly: true)
            }
        }
        RunLoop.main.add(pollingTimer, forMode: .common)
        timer = pollingTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        removeMicrophoneListeners()
        generation += 1
        readInFlight = false
        readAgain = false
        previousSnapshot = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
        currentActivity = nil
    }

#if DEBUG
#endif

    /// CoreAudio listeners: the default input changing, and that input's mute and volume.
    private var microphoneListeners: [(object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []
    private var listenedInput: AudioDeviceID?

    private func listenToMicrophone() {
        removeMicrophoneListeners()
        let input = Self.defaultAudioDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        listenedInput = input
        let changed: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.timer != nil else { return }
                // Another microphone became the default: listen to that one instead.
                if Self.defaultAudioDevice(selector: kAudioHardwarePropertyDefaultInputDevice) != self.listenedInput {
                    self.listenToMicrophone()
                }
                self.refresh()
            }
        }
        var addresses = [(AudioObjectID(kAudioObjectSystemObject),
                          AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain))]
        if let input {
            addresses.append((input, AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                                mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)))
            for element in [kAudioObjectPropertyElementMain, 1, 2] as [AudioObjectPropertyElement] {
                addresses.append((input, AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                                    mScope: kAudioDevicePropertyScopeInput, mElement: element)))
            }
        }
        for (object, address) in addresses {
            var address = address
            guard AudioObjectHasProperty(object, &address),
                  AudioObjectAddPropertyListenerBlock(object, &address, Self.readQueue, changed) == noErr else { continue }
            microphoneListeners.append((object, address, changed))
        }
    }

    private func removeMicrophoneListeners() {
        for listener in microphoneListeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(listener.object, &address, Self.readQueue, listener.block)
        }
        microphoneListeners = []
        listenedInput = nil
    }

    /// A change arrived while a read was under way: read once more after it.
    private var readAgain = false

    private func refresh(focusOnly: Bool = false) {
        guard !readInFlight else { if !focusOnly { readAgain = true }; return }
        readInFlight = true
        let source = FocusSource(manager: focusManager), requested = generation
        // A Focus-only read keeps the microphone as last read (nil before the first read).
        let microphone: Bool?? = focusOnly && previousSnapshot != nil ? .some(previousSnapshot?.microphoneMuted) : nil
        Self.readQueue.async {
            let next = Self.readSnapshot(focus: source, microphone: microphone)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == requested else { return }
                self.readInFlight = false
                self.apply(next)
                if self.readAgain { self.readAgain = false; self.refresh() }
            }
        }
    }

    private func apply(_ next: Snapshot) {
        defer { previousSnapshot = next }
        guard let previousSnapshot else { return }

        let settings = NookSettings.shared
        if settings.showMicrophoneLiveActivity,
           let muted = next.microphoneMuted,
           muted != previousSnapshot.microphoneMuted {
            show(
                SystemLiveActivity(
                    kind: .microphone,
                    label: muted ? "Muted" : "Mic live",
                    systemImage: muted ? "mic.slash.fill" : "mic.fill"
                )
            )
            return
        }

        if settings.showFocusLiveActivity,
           next.focusName != previousSnapshot.focusName {
            let name = next.focusName
            show(
                SystemLiveActivity(
                    kind: .focus,
                    label: name ?? "Focus off",
                    systemImage: name == nil ? "moon" : "moon.fill"
                )
            )
        }
    }

    private func show(_ activity: SystemLiveActivity) {
        hideWorkItem?.cancel()
        currentActivity = activity
        let work = DispatchWorkItem { [weak self] in
            self?.currentActivity = nil
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    /// Carries the Focus manager to the read queue; it is only read there.
    private final class FocusSource: @unchecked Sendable {
        let manager: AnyObject?
        init(manager: AnyObject?) { self.manager = manager }
    }

    nonisolated private static func readSnapshot(focus: FocusSource, microphone known: Bool??) -> Snapshot {
        if let known { return Snapshot(microphoneMuted: known, focusName: activeFocusName(focus.manager)) }
        let input = defaultAudioDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        let inputScalar = input.flatMap {
            audioScalar(device: $0, scope: kAudioDevicePropertyScopeInput)
        }
        let explicitInputMute = input.flatMap {
            audioMute(device: $0, scope: kAudioDevicePropertyScopeInput)
        }

        return Snapshot(
            microphoneMuted: explicitInputMute ?? inputScalar.map { $0 <= 0.001 },
            focusName: activeFocusName(focus.manager)
        )
    }

    nonisolated private static func defaultAudioDevice(
        selector: AudioObjectPropertySelector
    ) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    nonisolated private static func audioScalar(
        device: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> Float? {
        let elements: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain,
            1,
            2,
        ]
        let values = elements.compactMap { element -> Float? in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: scope,
                mElement: element
            )
            guard AudioObjectHasProperty(device, &address) else { return nil }
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(
                device,
                &address,
                0,
                nil,
                &size,
                &value
            ) == noErr else {
                return nil
            }
            return value
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    nonisolated private static func audioMute(
        device: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr else {
            return nil
        }
        return value != 0
    }

    nonisolated private static func activeFocusName(_ focusManager: AnyObject?) -> String? {
        guard let activity = focusManager?
            .perform(NSSelectorFromString("activeActivity"))?
            .takeUnretainedValue() as AnyObject? else {
            return nil
        }
        let name = activity
            .perform(NSSelectorFromString("activityDisplayName"))?
            .takeUnretainedValue() as? String
        return name?.isEmpty == false ? name : "Focus"
    }

    deinit {
        timer?.invalidate()
        hideWorkItem?.cancel()
    }
}
