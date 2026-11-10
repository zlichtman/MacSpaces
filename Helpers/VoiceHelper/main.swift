import Foundation
import MLXAudioCore

// MacSpacesVoiceHelper: the XPC service that sorts speakers and speaks in tagged voices for
// MacSpaces, so the notch app never loads MLX or a model. It starts when MacSpaces sends it a
// job, runs one job at a time, and quits after two idle minutes, taking the model's memory with it.

/// One job at a time; quits once idle.
final class VoiceHelperService: NSObject, VoiceHelperProtocol, @unchecked Sendable {
    static let idleSeconds: TimeInterval = 120

    private let lock = NSLock()
    private var running: Task<Void, Never>?
    private var idleTimer: DispatchSourceTimer?
    private let engine = VoiceEngine()
    private weak var connection: NSXPCConnection?

    func attach(_ connection: NSXPCConnection) {
        self.connection = connection
        armIdle()
    }

    private func report(_ stage: String, _ fraction: Double) {
        (connection?.remoteObjectProxy as? VoiceHelperClientProtocol)?.progress(stage, fraction: fraction)
    }

    /// Runs `job` unless another is running; the reply comes from `job`. A job replies a moment
    /// before it's marked finished, so a request sent as soon as a reply arrives waits up to 2 s for
    /// the slot rather than being told the helper is busy.
    private func run(_ busy: @escaping () -> Void, _ job: @escaping @Sendable () async -> Void, waited: Int = 0) {
        lock.lock()
        guard running == nil else {
            lock.unlock()
            guard waited < 20 else { busy(); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.run(busy, job, waited: waited + 1)
            }
            return
        }
        idleTimer?.cancel(); idleTimer = nil
        running = Task { [weak self] in
            await job()
            self?.finished()
        }
        lock.unlock()
    }

    private func finished() {
        lock.lock(); running = nil; lock.unlock()
        armIdle()
    }

    private func armIdle() {
        lock.lock(); defer { lock.unlock() }
        idleTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + Self.idleSeconds)
        timer.setEventHandler { [weak self] in
            guard let self else { exit(0) }
            self.lock.lock(); let idle = self.running == nil; self.lock.unlock()
            if idle { exit(0) }
        }
        idleTimer = timer
        timer.resume()
    }

    private static let busy = "MacSpaces is still working on the last voice job. Try again when it's done."

    private static func message(_ error: Error) -> String {
        if error is CancellationError { return "Stopped." }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func download(model: String, hub: String, reply: @escaping (String?) -> Void) {
        guard let model = VoiceModel.named(model) else { reply("That model isn't one MacSpaces knows."); return }
        let store = VoiceModelStore(hub: URL(fileURLWithPath: hub, isDirectory: true))
        run({ reply(Self.busy) }) { [weak self] in
            do {
                try FileManager.default.createDirectory(at: store.hub, withIntermediateDirectories: true)
                try await store.download(model) { self?.report("Downloading", $0) }
                reply(nil)
            } catch {
                reply("The download stopped: " + Self.message(error))
            }
        }
    }

    func sort(_ request: Data, reply: @escaping (Data?, String?) -> Void) {
        guard let request = try? JSONDecoder().decode(VoiceHelperMessage.SortRequest.self, from: request) else {
            reply(nil, "That request couldn't be read."); return
        }
        let store = VoiceModelStore(hub: URL(fileURLWithPath: request.hub, isDirectory: true))
        run({ reply(nil, Self.busy) }) { [weak self] in
            // Sorting and speaking never share memory: let the voice model go first.
            await self?.engine.unload()
            do {
                let result = try await VoiceSorter(store: store).sort(request) { self?.report($0, $1) }
                reply(try JSONEncoder().encode(result), nil)
            } catch {
                reply(nil, Self.message(error))
            }
        }
    }

    func speak(_ request: Data, reply: @escaping (String?, String?) -> Void) {
        guard let request = try? JSONDecoder().decode(VoiceHelperMessage.SpeakRequest.self, from: request),
              let model = VoiceModel.named(request.engine), model.speaks else {
            reply(nil, "That request couldn't be read."); return
        }
        let store = VoiceModelStore(hub: URL(fileURLWithPath: request.hub, isDirectory: true))
        let engine = engine
        run({ reply(nil, Self.busy) }) { [weak self] in
            do {
                self?.report("Loading the voice", 0)
                MemoryTrace.begin(output: URL(fileURLWithPath: request.output))
                try await engine.load(model, store: store)
                MemoryTrace.mark("loaded")
                let reference = URL(fileURLWithPath: request.clip)
                let attempts = max(1, min(TakeChoice.attempts, request.takes ?? 1))
                // Best Quality: up to three attempts of each piece, the one most like the voice kept.
                let judge = attempts > 1 ? TakeJudge(store: store, reference: reference, transcript: request.transcript) : nil
                let stage = judge == nil ? "Speaking" : "Making the best take"
                self?.report(stage, 0.2)
                let samples = try await engine.render(request.text, reference: reference,
                                                      transcript: request.transcript, seed: request.seed,
                                                      style: request.style, judge: judge, attempts: attempts) { [weak self, stage] fraction in
                    self?.report(stage, 0.2 + 0.8 * fraction)
                }
                MemoryTrace.mark("made")
                let output = URL(fileURLWithPath: request.output)
                try AudioUtils.writeWavFile(samples: samples, sampleRate: await engine.sampleRate, fileURL: output)
                reply(output.path, nil)
            } catch {
                reply(nil, Self.message(error))
            }
        }
    }

    func prepare(_ request: Data, reply: @escaping (Data?, String?) -> Void) {
        guard let request = try? JSONDecoder().decode(VoiceHelperMessage.TakeRequest.self, from: request) else {
            reply(nil, "That request couldn't be read."); return
        }
        let store = VoiceModelStore(hub: URL(fileURLWithPath: request.hub, isDirectory: true))
        run({ reply(nil, Self.busy) }) { [weak self] in
            // Like sorting, it uses the fingerprint and noise models: the voice model goes first.
            await self?.engine.unload()
            do {
                let person = try await VoiceSorter(store: store).prepareTake(request) { self?.report($0, $1) }
                reply(try JSONEncoder().encode(person), nil)
            } catch let failure as ReferenceBuilder.Failure where failure == .transcriptNeedsReview || failure == .noSpeech {
                reply(nil, "The words couldn't be made out. Read the passage clearly, close to the mic, then Use This.")
            } catch {
                reply(nil, Self.message(error))
            }
        }
    }

    func likeness(_ request: Data, reply: @escaping (Data?, String?) -> Void) {
        guard let request = try? JSONDecoder().decode(VoiceHelperMessage.LikenessRequest.self, from: request) else {
            reply(nil, "That request couldn't be read."); return
        }
        let store = VoiceModelStore(hub: URL(fileURLWithPath: request.hub, isDirectory: true))
        run({ reply(nil, Self.busy) }) { [weak self] in
            // One model at a time: the voice model goes before the fingerprint model loads.
            await self?.engine.unload()
            do {
                self?.report("Measuring likeness", 0)
                let files = request.files.map { URL(fileURLWithPath: $0) }
                let judge = TakeJudge(store: store)
                let scores: [Double?]
                if let fingerprint = request.fingerprint {
                    scores = try await judge.likeness(of: files, to: fingerprint)
                } else {
                    scores = try await judge.likeness(of: files, to: URL(fileURLWithPath: request.reference))
                }
                reply(try JSONEncoder().encode(VoiceHelperMessage.LikenessResult(likeness: scores)), nil)
            } catch {
                reply(nil, Self.message(error))
            }
        }
    }

    func cancel() {
        lock.lock(); let job = running; lock.unlock()
        job?.cancel()
    }
}

final class VoiceHelperListener: NSObject, NSXPCListenerDelegate {
    let service = VoiceHelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: VoiceHelperProtocol.self)
        connection.remoteObjectInterface = NSXPCInterface(with: VoiceHelperClientProtocol.self)
        connection.exportedObject = service
        // MacSpaces quit or let go: stop whatever it asked for.
        connection.invalidationHandler = { [service] in service.cancel() }
        connection.resume()
        service.attach(connection)
        return true
    }
}

let delegate = VoiceHelperListener()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
