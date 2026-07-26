import Foundation
import Darwin

private final class ShortcutOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
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
    func startIfNeeded() {
        guard !started else { return }
        started = true
        refresh()
    }

    func refresh() {
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

    func run(_ name: String) {
        runningName = name
        Self.execute(arguments: ["run", name]) { [weak self] status, _ in
            guard let self else { return }
            self.runningName = nil
            self.errorText = status == 0 ? nil : "Couldn’t run \(name)"
        }
    }

    private nonisolated static func execute(
        arguments: [String],
        completion: @escaping @MainActor @Sendable (Int32, String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            let readHandle = pipe.fileHandleForReading
            let output = ShortcutOutputBuffer()
            let outputEnded = DispatchSemaphore(value: 0)
            let processEnded = DispatchSemaphore(value: 0)

            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
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
                try process.run()
                // Close only the parent's writer; the child keeps its inherited
                // descriptors until it exits.
                try? pipe.fileHandleForWriting.close()

                if processEnded.wait(timeout: .now() + 20) == .timedOut {
                    process.terminate()
                    if processEnded.wait(timeout: .now() + 2) == .timedOut {
                        Darwin.kill(process.processIdentifier, SIGKILL)
                        _ = processEnded.wait(timeout: .now() + 2)
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
