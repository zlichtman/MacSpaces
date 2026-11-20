import AppKit
import Combine

/// macOS Low Power Mode (`pmset -a lowpowermode`), switched from the battery popover. Reading it is
/// free (`ProcessInfo.isLowPowerModeEnabled`); changing it needs root, so it goes
/// through the power helper when approved, otherwise the administrator password
/// prompt, as `LidClosedAwake` does.
@MainActor
final class LowPowerMode: ObservableObject {
    static let shared = LowPowerMode()

    @Published private(set) var isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var isChanging = false
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                                          object: nil, queue: .main) { _ in
            Task { @MainActor in LowPowerMode.shared.isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
    }

    func setEnabled(_ enabled: Bool) {
        // Isolated QA/demo builds never change power settings.
        guard LidClosedAwake.isMainBundle, !isChanging, enabled != isEnabled else { return }
        isChanging = true
        let useHelper = LidClosedAwake.shared.helper == .ready
        Task.detached(priority: .userInitiated) {
            let viaHelper = useHelper && LidClosedAwake.callHelper(timeout: 10) { helper, reply in
                if enabled { helper.enableLowPowerMode(withReply: reply) } else { helper.disableLowPowerMode(withReply: reply) }
            }
            if !viaHelper {
                // A cancelled password prompt fails quietly; the switch shows the real state.
                let script = "do shell script \"/usr/bin/pmset -a lowpowermode \(enabled ? 1 : 0)\" with administrator privileges"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
            }
            await MainActor.run {
                self.isChanging = false
                self.isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}
