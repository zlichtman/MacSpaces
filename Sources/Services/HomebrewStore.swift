import Foundation

/// The Homebrew tab's model: the installed packages (read only while the tab shows,
/// off the main thread, never online) and the one command a button started. Nothing
/// runs on its own: Update and Upgrade run only from their buttons.
@MainActor
final class HomebrewStore: ObservableObject {
    static let shared = HomebrewStore()

    enum Status: Equatable {
        case idle, loading, ready
        /// No `brew` in the usual places.
        case missing
        case failed(String)
    }

    /// A command a button started, its output so far and how it ended.
    struct Job: Equatable {
        let command: HomebrewCatalog.Command
        var log = ""
        var running = true
        var exitCode: Int32?
        var needsPassword: Bool { HomebrewCatalog.needsPassword(log) }
        var succeeded: Bool { exitCode == 0 }
    }

    @Published private(set) var packages: [HomebrewPackage] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var job: Job?
    /// When `brew update` last fetched the lists (from Homebrew's cache), if known.
    @Published private(set) var listsUpdated: Date?

    /// Outdated packages once a read has run (the rail's badge), else nil.
    var outdatedCount: Int? { status == .ready ? packages.filter(\.outdated).count : nil }

    private var loadedAt: Date?
    private var generation = 0
    private var process: Process?
    private var isPreview = false

    /// `brew`'s path, if Homebrew is installed.
    nonisolated static var brew: String? {
        HomebrewCatalog.candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Reads the installed packages, unless a read is under five minutes old.
    func load(force: Bool = false) {
        guard !isPreview, status != .loading else { return }
        if !force, status == .ready, let loadedAt, Date().timeIntervalSince(loadedAt) < 300 { return }
        guard let brew = Self.brew else { status = .missing; return }
        generation += 1
        let current = generation
        status = .loading
        Task.detached(priority: .utility) { [brew, current] in
            let result = Self.read(brew: brew)
            await MainActor.run { [result, current] in
                let store = HomebrewStore.shared
                guard store.generation == current, !store.isPreview else { return }
                switch result {
                case .success(let packages):
                    store.packages = packages
                    store.status = .ready
                    store.loadedAt = Date()
                case .failure(let error):
                    store.status = .failed(error.message)
                }
                store.listsUpdated = Self.listsDate()
            }
        }
    }

    /// Starts a button's command, unless one is already running.
    func run(_ command: HomebrewCatalog.Command) {
        guard !isPreview, job?.running != true, let brew = Self.brew,
              let arguments = HomebrewCatalog.arguments(command) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = arguments
        process.environment = Self.environment(brew: brew)
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [text] in HomebrewStore.shared.append(text) }
        }
        process.terminationHandler = { finished in
            let code = finished.terminationStatus
            Task { @MainActor [code] in HomebrewStore.shared.finish(code) }
        }
        job = Job(command: command)
        do {
            try process.run()
            self.process = process
        } catch {
            job?.running = false
            job?.exitCode = -1
            job?.log = error.localizedDescription
        }
    }

    /// Stops the running command (Homebrew cleans up after itself on SIGTERM).
    func stop() {
        process?.terminate()
    }

    /// Clears a finished command's strip.
    func dismissJob() {
        guard job?.running != true else { return }
        job = nil
    }

    private func append(_ text: String) {
        guard job != nil else { return }
        job?.log = HomebrewCatalog.trimmed((job?.log ?? "") + text)
    }

    private func finish(_ code: Int32) {
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process = nil
        job?.running = false
        job?.exitCode = code
        load(force: true)
    }

    private struct ReadError: Error { let message: String }

    nonisolated private static func environment(brew: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let folder = (brew as NSString).deletingLastPathComponent
        environment["PATH"] = "\(folder):/usr/bin:/bin:/usr/sbin:/sbin"
        environment.merge(HomebrewCatalog.environment) { _, ours in ours }
        return environment
    }

    nonisolated private static func read(brew: String) -> Result<[HomebrewPackage], ReadError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = HomebrewCatalog.listArguments
        process.environment = environment(brew: brew)
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(ReadError(message: error.localizedDescription)) }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let problem = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let packages = HomebrewCatalog.parse(data) else {
            let message = HomebrewCatalog.lastLine(String(decoding: problem, as: UTF8.self)) ?? "brew info didn't answer."
            return .failure(ReadError(message: message))
        }
        // Self-updating casks by the app on disk (this runs on the detached read task).
        return .success(HomebrewCatalog.reconciled(packages, appVersion: HomebrewCatalog.appVersion(at:)))
    }

    /// `brew update` rewrites the package name lists in Homebrew's cache.
    nonisolated private static func listsDate() -> Date? {
        let cache = ProcessInfo.processInfo.environment["HOMEBREW_CACHE"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/Homebrew").path
        let names = URL(fileURLWithPath: cache).appendingPathComponent("api/formula_names.txt")
        return (try? names.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

#if DEBUG
    /// Captures: synthetic packages and a job (Homebrew is never run or read).
    func setPreview(packages: [HomebrewPackage], status: Status = .ready, job: Job? = nil, listsUpdated: Date? = nil) {
        isPreview = true
        generation += 1
        self.packages = packages
        self.status = status
        self.job = job
        self.listsUpdated = listsUpdated
    }
#endif
}
