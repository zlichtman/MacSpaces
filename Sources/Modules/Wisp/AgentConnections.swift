import Foundation
import os

/// The command-line tools Claude and Codex come in through: the owner's own Claude Code and Codex,
/// signed in as they already are. MacSpaces never reads their credentials; it only runs them.
enum AgentCLI: String, CaseIterable, Identifiable {
    case claude, codex

    var id: String { rawValue }
    /// The tool's own name, as Settings shows it.
    var title: String { self == .claude ? "Claude Code" : "Codex" }
    var executable: String { rawValue }
    /// How to sign in, for Settings and the chat.
    var signInHint: String { self == .claude ? "run claude in Terminal and sign in" : "run codex login in Terminal" }

    /// Where installers put it. A GUI app has no shell PATH, so these are checked in order.
    static var searchDirectories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [".local/bin", ".claude/local", ".npm-global/bin", ".bun/bin", ".volta/bin", ".cargo/bin"].map { "\(home)/\($0)" }
            + ["/opt/homebrew/bin", "/usr/local/bin"]
    }

    /// The installed tool's path, or nil.
    var path: String? {
        Self.searchDirectories.map { "\($0)/\(executable)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// Whether a command-line tool can answer.
enum AgentCLIStatus: Equatable {
    case unknown, notInstalled, signedOut, ready
}

/// Claude Code's and Codex's state for Settings and the chat picker: installed, signed in, and
/// Codex's model list. Checked off the main thread, at most every 30 seconds unless forced.
@MainActor
final class AgentConnections: ObservableObject {
    static let shared = AgentConnections()

    @Published private(set) var status: [AgentCLI: AgentCLIStatus] = [:]
    /// Codex's own model list (`codex debug models`), its listed slugs in its order.
    @Published private(set) var codexModels: [String] = []
    private var checked: Date?
    private var checking = false

    func status(of cli: AgentCLI) -> AgentCLIStatus { status[cli] ?? .unknown }

    func refresh(force: Bool = false) {
        guard !checking else { return }
        if !force, let checked, Date().timeIntervalSince(checked) < 30 { return }
        checking = true
        Task { [weak self] in
            let found = await Task.detached { () -> ([AgentCLI: AgentCLIStatus], [String]) in
                var found: [AgentCLI: AgentCLIStatus] = [:]
                var models: [String] = []
                for cli in AgentCLI.allCases {
                    found[cli] = await AgentConnections.check(cli)
                }
                if found[.codex] != .notInstalled, let path = AgentCLI.codex.path {
                    models = await AgentConnections.codexCatalogue(path)
                }
                return (found, models)
            }.value
            guard let self else { return }
            self.status = found.0
            if !found.1.isEmpty { self.codexModels = found.1 }
            self.checked = Date()
            self.checking = false
        }
    }

    /// `claude auth status --json` says `loggedIn`; `codex login status` exits 0 when signed in.
    /// A tool too old to say counts as unknown, so the chat still tries it.
    nonisolated static func check(_ cli: AgentCLI) async -> AgentCLIStatus {
        guard let path = cli.path else { return .notInstalled }
        switch cli {
        case .claude:
            guard let result = try? await AgentProcess.run(path, ["auth", "status", "--json"], timeout: 10),
                  let json = (try? JSONSerialization.jsonObject(with: Data(result.output.utf8))) as? [String: Any],
                  let loggedIn = json["loggedIn"] as? Bool else { return .unknown }
            return loggedIn ? .ready : .signedOut
        case .codex:
            guard let result = try? await AgentProcess.run(path, ["login", "status"], timeout: 10) else { return .unknown }
            return result.status == 0 ? .ready : .signedOut
        }
    }

    nonisolated static func codexCatalogue(_ path: String) async -> [String] {
        guard let result = try? await AgentProcess.run(path, ["debug", "models"], timeout: 10), result.status == 0,
              let json = (try? JSONSerialization.jsonObject(with: Data(result.output.utf8))) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.filter { ($0["visibility"] as? String) == "list" }.compactMap { $0["slug"] as? String }.prefix(12).map { $0 }
    }
}

/// Runs a command-line agent with no shell, in an empty folder, and gives back what it printed.
/// The child disclaims MacSpaces' privacy grants (`responsibility_spawnattrs_setdisclaim`, when
/// macOS has it), so Claude Code or Codex can't read the calendar, reminders or anything else
/// MacSpaces was allowed: macOS would ask for the tool itself, and it never is. Personal data
/// reaches them only as the on-device agent's answers.
enum AgentProcess {
    struct Output { let status: Int32; let output: String; let error: String }

    /// The empty folder agents run in, outside iCloud and the owner's projects.
    static var workingDirectory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MacSpaces-agents", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private typealias Disclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    private static let disclaim: Disclaim? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim")
        .map { unsafeBitCast($0, to: Disclaim.self) }

    /// The child's process group while it runs, so a cancel or timeout stops it and its helpers.
    private final class Running: @unchecked Sendable {
        let pid = OSAllocatedUnfairLock<pid_t>(initialState: 0)
        func stop() { pid.withLock { if $0 > 0 { kill(-$0, SIGKILL) } } }
    }

    static func run(_ executable: String, _ arguments: [String], input: String? = nil, timeout: TimeInterval) async throws -> Output {
        let running = Running()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
                DispatchQueue.global(qos: .userInitiated).async { [running] in
                    continuation.resume(with: Result { try runBlocking(executable, arguments, input: input, timeout: timeout, running: running) })
                }
            }
        } onCancel: { [running] in
            running.stop()
        }
    }

    private static func runBlocking(_ executable: String, _ arguments: [String], input: String?, timeout: TimeInterval,
                                    running: Running) throws -> Output {
        var inPipe: [Int32] = [-1, -1], outPipe: [Int32] = [-1, -1], errPipe: [Int32] = [-1, -1]
        guard pipe(&inPipe) == 0, pipe(&outPipe) == 0, pipe(&errPipe) == 0 else { throw WispCloudError(message: "Couldn't start \(executable).") }
        // A child that quits before reading its input must not take MacSpaces down with SIGPIPE.
        _ = fcntl(inPipe[1], F_SETNOSIGPIPE, 1)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, inPipe[0], 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
        posix_spawn_file_actions_addchdir_np(&actions, workingDirectory.path)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Only the three pipes are inherited, and the child leads its own process group.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)
        _ = disclaim?(&attributes, 1)

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (AgentCLI.searchDirectories + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
        environment["NO_COLOR"] = "1"
        let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        close(inPipe[0]); close(outPipe[1]); close(errPipe[1])
        guard spawned == 0 else {
            close(inPipe[1]); close(outPipe[0]); close(errPipe[0])
            throw WispCloudError(message: "Couldn't start \(executable).")
        }
        running.pid.withLock { $0 = pid }

        let group = DispatchGroup()
        let output = Collected(), error = Collected()
        let outHandle = FileHandle(fileDescriptor: outPipe[0], closeOnDealloc: true)
        let errHandle = FileHandle(fileDescriptor: errPipe[0], closeOnDealloc: true)
        DispatchQueue.global().async(group: group) { output.data = outHandle.readDataToEndOfFile() }
        DispatchQueue.global().async(group: group) { error.data = errHandle.readDataToEndOfFile() }
        let inHandle = FileHandle(fileDescriptor: inPipe[1], closeOnDealloc: true)
        DispatchQueue.global().async {
            if let input { try? inHandle.write(contentsOf: Data(input.utf8)) }
            try? inHandle.close()
        }
        let timer = DispatchWorkItem { running.stop() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        timer.cancel()
        running.pid.withLock { $0 = 0 }
        group.wait()
        // Exited normally: the exit code; killed by a signal: 128 plus the signal.
        let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        return Output(status: code, output: String(decoding: output.data, as: UTF8.self), error: String(decoding: error.data, as: UTF8.self))
    }

    /// One pipe's bytes, written by its reader before `group.wait()` returns.
    private final class Collected: @unchecked Sendable { var data = Data() }
}
