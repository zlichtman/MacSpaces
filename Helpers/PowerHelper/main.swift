import Foundation

// MacSpaces' privileged power helper: a launchd daemon registered with
// `SMAppService.daemon(plistName:)` and approved once in System Settings → General →
// Login Items. It accepts connections only from MacSpaces signed by its team (checked
// by XPC on every message) and offers four fixed operations; see PowerHelperProtocol.

final class PowerHelper: NSObject, PowerHelperProtocol {
    func preventSleep(withReply reply: @escaping (Int32) -> Void) { reply(Self.pmset(["-a", "disablesleep", "1"])) }
    func allowSleep(withReply reply: @escaping (Int32) -> Void) { reply(Self.pmset(["-a", "disablesleep", "0"])) }
    func enableLowPowerMode(withReply reply: @escaping (Int32) -> Void) { reply(Self.pmset(["-a", "lowpowermode", "1"])) }
    func disableLowPowerMode(withReply reply: @escaping (Int32) -> Void) { reply(Self.pmset(["-a", "lowpowermode", "0"])) }

    /// Only ever called with the literal argument lists above.
    private static func pmset(_ arguments: [String]) -> Int32 {
        Activity.begin()
        defer { Activity.end() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.environment = [:]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// Exits after a minute with nothing to do; launchd starts the helper again on the
/// next message. A minute is well past launchd's 10-second respawn throttle.
enum Activity {
    private static let queue = DispatchQueue(label: "dev.opensource.MacSpaces.PowerHelper.activity")
    private static var active = 0
    private static var last = Date()

    static func begin() { queue.sync { active += 1; last = Date() } }
    static func end() { queue.sync { active -= 1; last = Date() } }

    static func exitWhenIdle() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler {
            if active == 0, Date().timeIntervalSince(last) > 60 { exit(0) }
        }
        timer.resume()
        retained = timer
    }
    private static var retained: DispatchSourceTimer?
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Messages from any other process (or another team's build) are rejected and
        // the connection invalidated.
        connection.setCodeSigningRequirement(PowerHelperXPC.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: PowerHelperProtocol.self)
        connection.exportedObject = PowerHelper()
        connection.resume()
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: PowerHelperXPC.label)
listener.delegate = delegate
listener.resume()
Activity.exitWhenIdle()
dispatchMain()
