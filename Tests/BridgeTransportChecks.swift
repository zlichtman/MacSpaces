import Foundation
import Darwin

/// Signed two-process transport checks. Diagnostics are redacted: they name the stage a
/// connection stopped at (identity, request, reply, write) and timings, never payloads or paths.
@main enum BridgeTransportChecks {
    static func diagnose(_ line: String) { fputs("[bridge-diagnostic] " + line + "\n", stderr) }
    static func main() throws {
        let args = CommandLine.arguments, url = URL(fileURLWithPath: args[2])
        switch args[1] {
        case "server":
            let listener = LocalBridgeListener()
            listener.onFailure = { diagnose("server closed a connection at stage=\($0.rawValue)") }
            try listener.start(at: url) { _, reply in diagnose("server replied"); reply(Data("authenticated".utf8)) }
            try Data().write(to: url.appendingPathExtension("ready"))
            // Runs until the script stops it (60 s backstop), so a slow first signature check
            // can't outlive the fixture.
            withExtendedLifetime(listener) { RunLoop.current.run(until: Date().addingTimeInterval(60)) }
        case "delayed":
            // Verifies the server, then waits before writing, as a busy client would. The server
            // must wait for the frame (up to its 5 s timeout) rather than fail with EAGAIN.
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            precondition(fd >= 0); defer { close(fd) }
            LocalBridgeTransport.configure(fd)
            var address = try LocalBridgeTransport.address(url)
            let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            precondition(connected == 0, "Delayed client could not connect")
            try LocalBridgeTransport.authenticate(fd, requirement: MacSpacesBridge.serverRequirement)
            Thread.sleep(forTimeInterval: 1.5)
            try LocalBridgeTransport.writeFrame(Data(), to: fd)
            let reply = try LocalBridgeTransport.readFrame(from: fd)
            precondition(reply == Data("authenticated".utf8), "Delayed client got no reply")
            print("Delayed signed peer accepted")
        default:
            let started = Date()
            var accepted = false
            do { accepted = try LocalBridgeTransport.exchange(Data(), at: url) == Data("authenticated".utf8) }
            catch { diagnose("client error after \(Int(Date().timeIntervalSince(started) * 1000)) ms: \(error.localizedDescription)") }
            precondition(accepted == (args[1] == "client"), "Signing identity gate failed")
            print(accepted ? "Signed peer accepted" : "Wrong signing identity rejected")
        }
    }
}
