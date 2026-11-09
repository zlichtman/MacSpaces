import Foundation
import os

/// Whether this Mac can make voices from recordings: Apple Silicon (the models run on MLX),
/// macOS 15 or later (Siren's minimum), and the voice helper in the app.
enum RecordedVoiceSupport {
    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        // Also true for an Intel copy running under Rosetta on Apple Silicon.
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    static var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices/MacSpacesVoiceHelper.xpc", isDirectory: true)
    }

    static var isAvailable: Bool {
        guard #available(macOS 15, *) else { return false }
        return isAppleSilicon && FileManager.default.fileExists(atPath: helperURL.path)
    }

    /// The one line shown in place of the feature where it can't run.
    static var unavailableNote: String {
        if !isAppleSilicon { return "Voices from recordings need a Mac with Apple Silicon." }
        if #unavailable(macOS 15) { return "Voices from recordings need macOS 15 or later." }
        return "Voices from recordings aren't part of this copy of MacSpaces."
    }
}

/// MacSpaces' end of the voice helper (`VoiceHelperProtocol`). The helper starts with the first
/// request and quits on its own when idle; a request after that starts it again.
@MainActor
final class VoiceHelperClient: NSObject {
    enum Failure: LocalizedError {
        case unavailable, stopped(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: RecordedVoiceSupport.unavailableNote
            case .stopped(let reason): reason
            }
        }
    }

    /// Stage and fraction (0 to 1) of the job running.
    var progress: ((String, Double) -> Void)?
    private var connection: NSXPCConnection?

    private func proxy(_ failed: @escaping (Error) -> Void) -> VoiceHelperProtocol? {
        guard RecordedVoiceSupport.isAvailable,
              let name = Bundle(url: RecordedVoiceSupport.helperURL)?.bundleIdentifier else { failed(Failure.unavailable); return nil }
        if connection == nil {
            let connection = NSXPCConnection(serviceName: name)
            connection.remoteObjectInterface = NSXPCInterface(with: VoiceHelperProtocol.self)
            connection.exportedInterface = NSXPCInterface(with: VoiceHelperClientProtocol.self)
            connection.exportedObject = ProgressSink { [weak self] stage, fraction in
                Task { @MainActor [weak self] in self?.progress?(stage, fraction) }
            }
            connection.invalidationHandler = { [weak self] in Task { @MainActor [weak self] in self?.connection = nil } }
            connection.resume()
            self.connection = connection
        }
        return connection?.remoteObjectProxyWithErrorHandler { failed($0) } as? VoiceHelperProtocol
    }

    /// A reply from the helper, or the connection's error if it quit or crashed first.
    private func call<T: Sendable>(_ body: @escaping (VoiceHelperProtocol, @escaping @Sendable (Result<T, Error>) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let once = Once(continuation)
            guard let helper = proxy({ error in
                once.resume(.failure(Failure.stopped(error is Failure ? error.localizedDescription
                                                     : "The voice helper stopped. Try again.")))
            }) else { return }
            body(helper) { once.resume($0) }
        }
    }

    func download(_ model: VoiceModel, hub: URL) async throws {
        let id = model.id, path = hub.path
        let error: String? = try await call { helper, done in
            helper.download(model: id, hub: path) { done(.success($0)) }
        }
        if let error { throw Failure.stopped(error) }
    }

    func sort(_ request: VoiceHelperMessage.SortRequest) async throws -> VoiceHelperMessage.SortResult {
        let data = try JSONEncoder().encode(request)
        let reply: Data = try await call { helper, done in
            helper.sort(data) { data, error in
                if let data { done(.success(data)) } else { done(.failure(Failure.stopped(error ?? "Sorting stopped."))) }
            }
        }
        return try JSONDecoder().decode(VoiceHelperMessage.SortResult.self, from: reply)
    }

    /// Record My Voice's take made into a clip.
    func prepare(_ request: VoiceHelperMessage.TakeRequest) async throws -> VoiceHelperMessage.Person {
        let data = try JSONEncoder().encode(request)
        let reply: Data = try await call { helper, done in
            helper.prepare(data) { data, error in
                if let data { done(.success(data)) } else { done(.failure(Failure.stopped(error ?? "Stopped."))) }
            }
        }
        return try JSONDecoder().decode(VoiceHelperMessage.Person.self, from: reply)
    }

    func speak(_ request: VoiceHelperMessage.SpeakRequest) async throws -> URL {
        let data = try JSONEncoder().encode(request)
        let path: String = try await call { helper, done in
            helper.speak(data) { path, error in
                if let path { done(.success(path)) } else { done(.failure(Failure.stopped(error ?? "Speaking stopped."))) }
            }
        }
        return URL(fileURLWithPath: path)
    }

    /// How alike each file sounds to `reference` (the side-by-side harness only).
    func likeness(_ request: VoiceHelperMessage.LikenessRequest) async throws -> [Double?] {
        let data = try JSONEncoder().encode(request)
        let reply: Data = try await call { helper, done in
            helper.likeness(data) { data, error in
                if let data { done(.success(data)) } else { done(.failure(Failure.stopped(error ?? "Measuring stopped."))) }
            }
        }
        return try JSONDecoder().decode(VoiceHelperMessage.LikenessResult.self, from: reply).likeness
    }

    func cancel() {
        (connection?.remoteObjectProxy as? VoiceHelperProtocol)?.cancel()
    }

    /// Resumes its continuation exactly once: a reply and a connection error can both arrive.
    private final class Once<T>: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: false)
        private let continuation: CheckedContinuation<T, Error>
        init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }
        func resume(_ result: Result<T, Error>) {
            let first = lock.withLock { done -> Bool in defer { done = true }; return !done }
            if first { continuation.resume(with: result) }
        }
    }

    private final class ProgressSink: NSObject, VoiceHelperClientProtocol {
        let handler: @Sendable (String, Double) -> Void
        init(_ handler: @escaping @Sendable (String, Double) -> Void) { self.handler = handler }
        func progress(_ stage: String, fraction: Double) { handler(stage, fraction) }
    }
}
