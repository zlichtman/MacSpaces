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
        previousSnapshot = readSnapshot()
        // Fast enough to feel attached to a hardware key press while avoiding
        // continuous CoreAudio churn in an idle menu-bar app.
        let pollingTimer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        RunLoop.main.add(pollingTimer, forMode: .common)
        timer = pollingTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousSnapshot = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
        currentActivity = nil
    }

#if DEBUG
    func setPreviewActivity(_ activity: SystemLiveActivity?) {
        currentActivity = activity
    }
#endif

    private func refresh() {
        let next = readSnapshot()
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

    private func readSnapshot() -> Snapshot {
        let input = defaultAudioDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        let inputScalar = input.flatMap {
            audioScalar(device: $0, scope: kAudioDevicePropertyScopeInput)
        }
        let explicitInputMute = input.flatMap {
            audioMute(device: $0, scope: kAudioDevicePropertyScopeInput)
        }

        return Snapshot(
            microphoneMuted: explicitInputMute ?? inputScalar.map { $0 <= 0.001 },
            focusName: activeFocusName()
        )
    }

    private func defaultAudioDevice(
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

    private func audioScalar(
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

    private func audioMute(
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

    private func activeFocusName() -> String? {
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
