import Foundation
import Combine
import ServiceManagement

/// Keeps the Mac (and the coding agents on it) running with the lid closed, as
/// lid-closed keep-awake apps do. macOS sleeps on lid close whatever apps ask, unless
/// sleep is disabled system-wide (`pmset -a disablesleep 1`), which only root can set.
/// MacSpaces does that through its privileged helper (`PowerHelperProtocol`, a launchd
/// daemon registered with `SMAppService` and approved once in Login Items), with no
/// prompt. Until the helper is approved, each change shows the administrator password
/// prompt instead (no standing sudoers exception, owner). The state shown is always read
/// back from `pmset -g`, so it stays true even if something else changes it. It turns
/// itself off when MacSpaces quits and on battery at `AgentPowerAlert.threshold`%.
@MainActor
final class LidClosedAwake: ObservableObject {
    static let shared = LidClosedAwake()

    enum HelperState: Equatable {
        /// QA/demo bundles never register or call the helper.
        case unavailable
        case notInstalled
        /// Registered; waiting for the switch in System Settings → General → Login Items.
        case needsApproval
        case ready
    }

    @Published private(set) var isEnabled = false
    @Published private(set) var isChanging = false
    @Published private(set) var helper: HelperState = .unavailable
    @Published private(set) var error: String?

    private var observer: AnyCancellable?
    private var turnedOffForBattery = false
    private var approvalWatch: Task<Void, Never>?

    /// Only the real app touches power settings or the helper.
    nonisolated static var isMainBundle: Bool {
        Bundle.main.bundleIdentifier == PowerHelperXPC.appBundleIdentifier
    }

    init() { refresh() }

    /// Reads whether system sleep is disabled, and the helper's registration.
    func refresh() {
        Task.detached(priority: .utility) {
            let disabled = Self.readSleepDisabled()
            let helper = Self.readHelperState()
            await MainActor.run {
                self.isEnabled = disabled
                self.helper = helper
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        // Isolated QA/demo builds never change power settings.
        guard Self.isMainBundle, !isChanging else { return }
        isChanging = true
        error = nil
        let useHelper = helper == .ready
        Task.detached(priority: .userInitiated) {
            let viaHelper = useHelper && Self.callHelper(disableSleep: enabled, timeout: 10)
            if !viaHelper {
                // A cancelled password prompt fails quietly; the switch shows the real state.
                let script = "do shell script \"/usr/bin/pmset -a disablesleep \(enabled ? 1 : 0)\" with administrator privileges"
                _ = Self.run("/usr/bin/osascript", ["-e", script])
            }
            await MainActor.run {
                if useHelper && !viaHelper { self.error = "The helper didn't answer, so macOS asked for your password." }
                self.isChanging = false
                self.refresh()
            }
        }
    }

    // MARK: Helper

    /// Registers the helper; macOS then lists it in Login Items for the user to allow.
    func installHelper() {
        guard Self.isMainBundle else { return }
        error = nil
        let service = SMAppService.daemon(plistName: PowerHelperXPC.plistName)
        var failure: Error?
        // Registering a daemon that still needs approval throws even though it worked.
        do { try service.register() } catch { failure = error }
        helper = Self.state(of: service)
        switch helper {
        case .ready:
            break
        case .needsApproval:
            openLoginItems()
        case .notInstalled, .unavailable:
            error = "Couldn't add the helper" + (failure.map { ": \($0.localizedDescription)" } ?? ".")
        }
    }

    /// Opens Login Items and notices when the helper is allowed there.
    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
        approvalWatch?.cancel()
        approvalWatch = Task { [weak self] in
            for _ in 0..<90 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.helper = Self.readHelperState()
                if self.helper != .needsApproval { return }
            }
        }
    }

    /// Unregisters the helper, first letting the Mac sleep again (afterwards that
    /// would need the password).
    func removeHelper() {
        guard Self.isMainBundle, helper != .unavailable, !isChanging else { return }
        isChanging = true
        error = nil
        let allowSleepFirst = isEnabled && helper == .ready
        Task.detached(priority: .userInitiated) {
            if allowSleepFirst { _ = Self.callHelper(disableSleep: false, timeout: 10) }
            let failure: String?
            do {
                try await SMAppService.daemon(plistName: PowerHelperXPC.plistName).unregister()
                failure = nil
            } catch {
                failure = "Couldn't remove the helper: \(error.localizedDescription)"
            }
            await MainActor.run {
                self.error = failure
                self.isChanging = false
                self.refresh()
            }
        }
    }

    // MARK: Safety

    /// Lets the Mac sleep again as MacSpaces quits. Only through the helper: a password
    /// prompt while quitting would be out of place. Waits at most two seconds.
    func turnOffForQuit() {
        guard Self.isMainBundle, Self.readSleepDisabled(),
              Self.readHelperState() == .ready else { return }
        _ = Self.callHelper(disableSleep: false, timeout: 2)
    }

    /// Follows the battery. Called once at launch.
    func observe(_ monitor: PowerSourceMonitor) {
        observer = monitor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak monitor] _ in
                DispatchQueue.main.async {
                    guard let self, let monitor else { return }
                    self.evaluate(monitor)
                }
            }
    }

    private func evaluate(_ monitor: PowerSourceMonitor) {
        let low = monitor.hasBattery && monitor.hasReading && !monitor.isOnExternalPower
            && monitor.batteryLevel <= AgentPowerAlert.threshold
        if !low { turnedOffForBattery = false; return }
        guard isEnabled, !turnedOffForBattery else { return }
        // Once per low-battery stretch, so a declined prompt (without the helper)
        // doesn't keep returning.
        turnedOffForBattery = true
        setEnabled(false)
    }

    // MARK: System

    nonisolated private static func readSleepDisabled() -> Bool {
        let output = run("/usr/bin/pmset", ["-g"]) ?? ""
        return output.split(separator: "\n").contains { line in
            let parts = line.split(whereSeparator: \.isWhitespace)
            return parts.first == "SleepDisabled" && parts.last == "1"
        }
    }

    nonisolated private static func readHelperState() -> HelperState {
        guard isMainBundle else { return .unavailable }
        return state(of: SMAppService.daemon(plistName: PowerHelperXPC.plistName))
    }

    nonisolated private static func state(of service: SMAppService) -> HelperState {
        switch service.status {
        case .enabled: return .ready
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound: return .notInstalled
        @unknown default: return .notInstalled
        }
    }

    /// Asks the helper to set `disablesleep`; true when pmset succeeded. The helper's
    /// signature is checked against `PowerHelperXPC.helperRequirement`.
    nonisolated private static func callHelper(disableSleep: Bool, timeout: TimeInterval) -> Bool {
        guard isMainBundle else { return false }
        return callHelper(timeout: timeout) { helper, reply in
            if disableSleep { helper.preventSleep(withReply: reply) } else { helper.allowSleep(withReply: reply) }
        }
    }

    /// Sends one operation to the helper; true when pmset succeeded. Also used by
    /// `LowPowerMode`.
    nonisolated static func callHelper(timeout: TimeInterval,
                                       _ send: (PowerHelperProtocol, @escaping (Int32) -> Void) -> Void) -> Bool {
        guard isMainBundle else { return false }
        let connection = NSXPCConnection(machServiceName: PowerHelperXPC.label, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: PowerHelperProtocol.self)
        connection.setCodeSigningRequirement(PowerHelperXPC.helperRequirement)
        connection.resume()
        defer { connection.invalidate() }

        final class Result: @unchecked Sendable { var status: Int32 = -1 }
        let result = Result()
        let done = DispatchSemaphore(value: 0)
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in done.signal() }
        guard let helper = proxy as? PowerHelperProtocol else { return false }
        let reply: (Int32) -> Void = { status in
            result.status = status
            done.signal()
        }
        send(helper, reply)
        guard done.wait(timeout: .now() + timeout) == .success else { return false }
        return result.status == 0
    }

    /// Runs a tool and returns its output, or nil when it fails.
    nonisolated private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
