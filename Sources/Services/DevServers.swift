import AppKit
import Darwin

/// Local development servers: your own processes listening on a TCP port, such
/// as `npm run dev`, a Python or Rails server, or a Go binary. Apps from
/// /Applications and macOS's own services are left out. Read with `lsof`
/// (no permission needed) every few seconds while the widget shows.
@MainActor
final class DevServers: ObservableObject {
    struct Server: Identifiable, Equatable {
        let pid: Int32
        let port: Int
        let command: String
        let folder: String
        var processIdentity: UInt64? = nil
        var id: String { "\(pid):\(port)" }
        var project: String { folder.isEmpty ? command : (folder as NSString).lastPathComponent }
        var url: URL { URL(string: "http://localhost:\(port)")! }
    }

    @Published private(set) var servers: [Server] = []
    @Published private(set) var scanned = false
    @Published private(set) var errorText: String?
    private var timer: Timer?
    private var scanning = false

    func start() {
        guard timer == nil else { return }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func scan() {
        guard !scanning else { return }
        scanning = true
        Task.detached(priority: .utility) {
            let found = Self.listening()
            await MainActor.run {
                self.scanning = false
                self.scanned = true
                if found != self.servers { self.servers = found }
            }
        }
    }

    func open(_ server: Server) { NSWorkspace.shared.open(server.url) }

    /// Asks the server to quit (SIGTERM), as Ctrl-C in its terminal would.
    func stop(_ server: Server) {
        guard let identity = server.processIdentity, Self.identity(server.pid) == identity else {
            errorText = "This process changed or exited. Refresh before stopping it."
            scan()
            return
        }
        guard kill(server.pid, SIGTERM) == 0 else {
            errorText = "Couldn't stop \(server.command): " + String(cString: strerror(errno))
            scan()
            return
        }
        errorText = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.scan() }
    }

    /// PID plus process start time; revalidate a stale scan before signalling it.
    nonisolated static func identity(_ pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let count = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(count)) == count,
              info.pbi_uid == getuid() else { return nil }
        return info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec
    }

    nonisolated static func listening() -> [Server] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-u", String(getuid()), "-Fpcn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self)).filter { isDevelopment($0.pid) }
            .map { Server(pid: $0.pid, port: $0.port, command: $0.command, folder: workingDirectory($0.pid), processIdentity: identity($0.pid)) }
            .sorted { $0.port < $1.port }
    }

    /// `lsof -F pcn` output: "p<pid>", "c<command>", then "n<address:port>" lines.
    nonisolated static func parse(_ output: String) -> [(pid: Int32, port: Int, command: String)] {
        var results: [(pid: Int32, port: Int, command: String)] = []
        var seen = Set<String>()
        var pid: Int32 = 0, command = ""
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "n":
                guard let portText = value.split(separator: ":").last, let port = Int(portText),
                      seen.insert("\(pid):\(port)").inserted else { continue }
                results.append((pid, port, command))
            default: break
            }
        }
        return results
    }

    /// Your own tools, not apps or macOS services: macOS's own folders are left
    /// out, and so is anything inside an app bundle (Spotify, Docker, AirPlay
    /// receivers) except the developer tools Xcode ships (python3, node in a toolchain).
    nonisolated static func isDevelopment(_ pid: Int32) -> Bool {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return isDevelopment(path: String(cString: buffer))
    }

    nonisolated static func isDevelopment(path: String) -> Bool {
        let system = ["/System/", "/usr/libexec/", "/usr/sbin/", "/Library/Apple/", "/sbin/"]
        if system.contains(where: { path.hasPrefix($0) }) { return false }
        if path.contains(".app/Contents/") {
            return path.contains("/Contents/Developer/")
        }
        return true
    }

    nonisolated static func workingDirectory(_ pid: Int32) -> String {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return "" }
        return withUnsafePointer(to: info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }
}
