import Foundation
import Darwin

private final class ShortcutOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        // Runs may last indefinitely; retain only a bounded diagnostic tail.
        if data.count > 65_536 { data.removeFirst(data.count - 65_536) }
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private final class ShortcutRun: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func launch(_ child: Process) throws {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { throw CancellationError() }
        process = child
        try child.run()
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        if let process, process.isRunning { process.terminate() }
    }
}

/// Reads and runs the user's Apple Shortcuts through the system-provided
/// `shortcuts` command. Names stay local and no scripting bridge is required.
@MainActor
final class ShortcutsService: ObservableObject {
    @Published private(set) var names: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var runningName: String?
    @Published private(set) var errorText: String?

    private var started = false
    private var activeRun: (id: UUID, control: ShortcutRun)?
    private var queued: [(String, [URL], URL?)] = []
    func startIfNeeded() {
        guard !started else { return }
        started = true
        refresh()
    }

#if DEBUG
    /// Website captures: synthetic Shortcut names; the real list is never read.
    private var previewNames: [String]?
    func setPreview(_ names: [String]) { previewNames = names; self.names = names; started = true }
#endif

#if DEBUG
    /// Executes only a caller-provided QA fixture; never invokes the user's Shortcuts.
    static func checkProcess(arguments: [String], cancelAfter: TimeInterval? = nil) async -> (Int32, String) {
        let control = ShortcutRun()
        if let cancelAfter { Task { try? await Task.sleep(for: .seconds(cancelAfter)); control.cancel() } }
        return await withCheckedContinuation { continuation in
            execute(arguments: arguments, timeout: nil, control: control, executable: "/bin/sh") {
                continuation.resume(returning: ($0, $1))
            }
        }
    }
#endif

    func refresh() {
#if DEBUG
        if let previewNames { names = previewNames; return }
#endif
        isLoading = true
        Self.execute(arguments: ["list"]) { [weak self] status, output in
            guard let self else { return }
            self.isLoading = false
            if status == 0 {
                self.names = output
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .filter { !$0.isEmpty }
                self.errorText = nil
            } else {
                self.errorText = "Shortcuts unavailable"
            }
        }
    }

    func run(_ name: String, inputs: [URL] = [], output: URL? = nil, enqueue: Bool = false) {
        guard activeRun == nil else {
            if enqueue { queued.append((name, inputs, output)) }
            else { errorText = "A shortcut is already running. Cancel it or wait for it to finish." }
            return
        }
        let id = UUID(), control = ShortcutRun()
        activeRun = (id, control)
        runningName = name
        errorText = nil
        var arguments = ["run", name]
        for url in inputs { arguments += ["--input-path", url.path] }
        if let output { arguments += ["--output-path", output.path] }
        Self.execute(arguments: arguments, timeout: nil, control: control) { [weak self] status, output in
            guard let self, self.activeRun?.id == id else { return }
            self.activeRun = nil
            self.runningName = nil
            self.errorText = control.cancelled ? "Cancelled \(name). Work already performed by the shortcut may remain."
                : status == 0 ? nil : "Couldn’t run \(name): " + (output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Shortcuts returned \(status)." : String(output.suffix(1000)))
            if !self.queued.isEmpty {
                let next = self.queued.removeFirst()
                self.run(next.0, inputs: next.1, output: next.2)
            }
        }
    }

    func cancel() { activeRun?.control.cancel() }

    private nonisolated static func execute(
        arguments: [String], timeout: TimeInterval? = 20, control: ShortcutRun = ShortcutRun(), executable: String = "/usr/bin/shortcuts",
        completion: @escaping @MainActor @Sendable (Int32, String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            let readHandle = pipe.fileHandleForReading
            let output = ShortcutOutputBuffer()
            let outputEnded = DispatchSemaphore(value: 0)
            let processEnded = DispatchSemaphore(value: 0)

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { _ in
                processEnded.signal()
            }

            // Drain while the child is alive. A blocking read-after-wait can
            // deadlock on a full pipe, while an inherited writer in a runaway
            // descendant can prevent EOF forever.
            readHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    outputEnded.signal()
                } else {
                    output.append(chunk)
                }
            }

            do {
                try control.launch(process)
                // Close only the parent's writer; the child keeps its inherited
                // descriptors until it exits.
                try? pipe.fileHandleForWriting.close()

                let deadline = timeout.map { Date().addingTimeInterval($0) }
                while processEnded.wait(timeout: .now() + 0.2) == .timedOut {
                    if control.cancelled || deadline.map({ Date() >= $0 }) == true {
                        if process.isRunning { process.terminate() }
                        if processEnded.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                            Darwin.kill(process.processIdentifier, SIGKILL)
                            _ = processEnded.wait(timeout: .now() + 2)
                        }
                        break
                    }
                }

                // Give the normal EOF callback a brief chance to append the
                // final chunk, then close our reader even if a descendant kept
                // a duplicate writer open.
                _ = outputEnded.wait(timeout: .now() + 0.2)
                readHandle.readabilityHandler = nil
                try? readHandle.close()

                let status: Int32 = process.isRunning ? -9 : process.terminationStatus
                let text = output.string
                Task { @MainActor in completion(status, text) }
            } catch {
                readHandle.readabilityHandler = nil
                try? readHandle.close()
                try? pipe.fileHandleForWriting.close()
                Task { @MainActor in completion(-1, "") }
            }
        }
    }
}
