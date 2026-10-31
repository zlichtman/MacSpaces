import Foundation
import os

/// Whether Codex will run MacSpaces' hooks. Codex runs a hook only after it has been
/// reviewed in Codex's `/hooks`, and a hook that changes needs reviewing again, so
/// installed hooks can sit unused without any sign. This asks Codex's own app server
/// (`hooks/list`, which only reads) how many of MacSpaces' hooks still need review.
@MainActor
final class CodexHookReview: ObservableObject {
    static let shared = CodexHookReview()

    /// MacSpaces hooks Codex won't run yet; 0 when all are approved or Codex isn't installed.
    @Published private(set) var needsReview = 0

    private var checking = false
    private var lastCheck: Date?

    /// Checks at most once a minute unless `force`; the Agents tab and Settings call this as they appear.
    func check(force: Bool = false) {
        guard !checking, force || lastCheck.map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return }
        checking = true
        lastCheck = Date()
        Task.detached(priority: .utility) {
            let count = Self.untrustedCount()
            await MainActor.run { [count] in
                let review = CodexHookReview.shared
                review.checking = false
                if let count, count != review.needsReview { review.needsReview = count }
            }
        }
    }

    /// Codex's command-line tool, wherever it's installed (Homebrew, npm or inside ChatGPT).
    nonisolated static var codexBinary: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex",
                "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                "/Applications/Codex.app/Contents/Resources/codex"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// The number of MacSpaces hooks Codex lists as not trusted, or nil when it couldn't tell.
    nonisolated static func untrustedCount() -> Int? {
        guard let binary = codexBinary else { return nil }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["app-server"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let buffer = OSAllocatedUnfairLock(initialState: Data())
        let answered = DispatchSemaphore(value: 0)
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; answered.signal(); return }
            let hasList = buffer.withLock { data -> Bool in
                data.append(chunk)
                return String(decoding: data, as: UTF8.self).contains(#""id":2"#)
            }
            if hasList { answered.signal() }
        }
        do { try process.run() } catch { return nil }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }
        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"MacSpaces","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","method":"initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"hooks/list","params":{}}"#,
        ]
        input.fileHandleForWriting.write(Data((requests.joined(separator: "\n") + "\n").utf8))
        guard answered.wait(timeout: .now() + 10) == .success else { return nil }
        let text = buffer.withLock { String(decoding: $0, as: UTF8.self) }
        guard let line = text.split(separator: "\n").first(where: { $0.contains(#""id":2"#) }),
              let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let result = message["result"] as? [String: Any],
              let lists = result["data"] as? [[String: Any]] else { return nil }
        let ours = lists.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .filter { ($0["command"] as? String)?.contains(AgentActivityMonitor.marker) == true }
        var seen = Set<String>()
        return ours.filter { hook in
            seen.insert(hook["key"] as? String ?? UUID().uuidString).inserted && (hook["trustStatus"] as? String) != "trusted"
        }.count
    }
}
