import AppKit
import CoreAudio
import CoreGraphics
import ObjectiveC.runtime

struct SystemLiveActivity: Equatable {
    enum Kind: Equatable {
        case volume
        case displayBrightness
        case keyboardBrightness
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

/// Observes the Mac controls people change from the keyboard and Control
/// Center, then publishes a short-lived snapshot for the closed Nook.
///
/// Audio uses public CoreAudio APIs. Display/keyboard brightness and Focus are
/// loaded dynamically from system frameworks so unsupported OS releases and
/// hardware simply omit those activities instead of failing the app.
@MainActor
final class SystemActivityMonitor: ObservableObject {
    @Published private(set) var currentActivity: SystemLiveActivity?

    private struct Snapshot: Equatable {
        var volume: Int?
        var outputMuted: Bool?
        var displayBrightness: Int?
        var keyboardBrightness: Int?
        var microphoneMuted: Bool?
        var focusName: String?
    }

    private typealias DisplayBrightnessFunction =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias KeyboardBrightnessFunction =
        @convention(c) (AnyObject, Selector, UInt64) -> Float

    private var timer: Timer?
    private var previousSnapshot: Snapshot?
    private var hideWorkItem: DispatchWorkItem?
    private let getDisplayBrightness: DisplayBrightnessFunction?
    private let keyboardClient: AnyObject?
    private let getKeyboardBrightness: KeyboardBrightnessFunction?
    private let keyboardBrightnessSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let focusManager: AnyObject?

    var justChangedRecently: Bool { currentActivity != nil }

    init() {
        if let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW
        ), let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getDisplayBrightness = unsafeBitCast(symbol, to: DisplayBrightnessFunction.self)
        } else {
            getDisplayBrightness = nil
        }

        _ = dlopen(
            "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
            RTLD_NOW
        )
        if let keyboardClass: AnyClass = NSClassFromString("KeyboardBrightnessClient"),
           let unmanagedClient = (keyboardClass as AnyObject)
            .perform(NSSelectorFromString("new")) {
            let client = unmanagedClient.takeRetainedValue() as AnyObject
            keyboardClient = client
            if let implementation = class_getMethodImplementation(
                keyboardClass,
                keyboardBrightnessSelector
            ) {
                getKeyboardBrightness = unsafeBitCast(
                    implementation,
                    to: KeyboardBrightnessFunction.self
                )
            } else {
                getKeyboardBrightness = nil
            }
        } else {
            keyboardClient = nil
            getKeyboardBrightness = nil
        }

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
        // continuous CoreAudio/CoreBrightness churn in an idle menu-bar app.
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

        if settings.showVolumeLiveActivity,
           let volume = next.volume,
           volume != previousSnapshot.volume
                || next.outputMuted != previousSnapshot.outputMuted {
            let muted = next.outputMuted == true
            show(
                SystemLiveActivity(
                    kind: .volume,
                    label: muted ? "Muted" : "\(volume)%",
                    systemImage: muted ? "speaker.slash.fill" : volumeSymbol(for: volume),
                    level: muted ? 0 : Double(volume) / 100
                )
            )
            return
        }

        if settings.showBrightnessLiveActivity,
           let brightness = next.displayBrightness,
           brightness != previousSnapshot.displayBrightness {
            show(
                SystemLiveActivity(
                    kind: .displayBrightness,
                    label: "\(brightness)%",
                    systemImage: "sun.max.fill",
                    level: Double(brightness) / 100
                )
            )
            return
        }

        if settings.showKeyboardBrightnessLiveActivity,
           let brightness = next.keyboardBrightness,
           brightness != previousSnapshot.keyboardBrightness {
            show(
                SystemLiveActivity(
                    kind: .keyboardBrightness,
                    label: "\(brightness)%",
                    systemImage: "keyboard.fill",
                    level: Double(brightness) / 100
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
        let output = defaultAudioDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let input = defaultAudioDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        let outputScalar = output.flatMap {
            audioScalar(device: $0, scope: kAudioDevicePropertyScopeOutput)
        }
        let inputScalar = input.flatMap {
            audioScalar(device: $0, scope: kAudioDevicePropertyScopeInput)
        }
        let explicitInputMute = input.flatMap {
            audioMute(device: $0, scope: kAudioDevicePropertyScopeInput)
        }

        return Snapshot(
            volume: outputScalar.map { Int(($0 * 100).rounded()) },
            outputMuted: output.flatMap {
                audioMute(device: $0, scope: kAudioDevicePropertyScopeOutput)
            },
            displayBrightness: displayBrightness(),
            keyboardBrightness: keyboardBrightness(),
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

    private func displayBrightness() -> Int? {
        guard let getDisplayBrightness else { return nil }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return nil
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return nil
        }

        for display in displays.sorted(by: { CGDisplayIsBuiltin($0) > CGDisplayIsBuiltin($1) }) {
            var value: Float = 0
            guard getDisplayBrightness(display, &value) == 0,
                  value.isFinite,
                  (0...1).contains(value) else {
                continue
            }
            return Int((value * 100).rounded())
        }
        return nil
    }

    private func keyboardBrightness() -> Int? {
        guard let keyboardClient,
              let getKeyboardBrightness,
              let unmanagedIdentifiers = keyboardClient
                .perform(NSSelectorFromString("copyKeyboardBacklightIDs")) else {
            return nil
        }
        let rawIdentifiers = unmanagedIdentifiers.takeRetainedValue()
        guard let identifiers = rawIdentifiers as? [NSNumber],
              let identifier = identifiers.first else {
            return nil
        }
        let value = getKeyboardBrightness(
            keyboardClient,
            keyboardBrightnessSelector,
            identifier.uint64Value
        )
        guard value.isFinite, (0...1).contains(value) else { return nil }
        return Int((value * 100).rounded())
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

    private func volumeSymbol(for volume: Int) -> String {
        switch volume {
        case ...0: return "speaker.fill"
        case 1...33: return "speaker.wave.1.fill"
        case 34...66: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    deinit {
        timer?.invalidate()
        hideWorkItem?.cancel()
    }
}
