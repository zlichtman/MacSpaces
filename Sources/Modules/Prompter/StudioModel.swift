import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

/// Studio's takes: a script's words read in a voice (one made from recordings, a Mac voice or a
/// Personal Voice), each reading kept as a take beside the scripts, in
/// Application Support/MacSpaces/Takes/<script id>/ (takes.json, sealed like the scripts, and
/// each take's <id>.wav). Voices from recordings are made by the voice helper with a fresh seed
/// per take, so takes of the same words differ; Mac voices read the same way every time.
@MainActor
final class StudioModel: ObservableObject {
    static let shared = StudioModel()

    /// The take being made.
    struct Making: Equatable {
        let scriptID: UUID
        let text: String
        /// The words being read, in the script, to show them highlighted while it's made.
        let range: NSRange?
        let voiceName: String
        let recorded: Bool
    }

    /// What reads: a voice from recordings, a Mac voice (Personal Voices included) or Automatic.
    enum Voice: Equatable {
        case automatic
        case mac(AVSpeechSynthesisVoice)
        case recorded(RecordedVoice)

        var name: String {
            switch self {
            case .automatic: "Automatic"
            case .mac(let voice): voice.name
            case .recorded(let voice): voice.name
            }
        }
    }

    @Published private(set) var scriptID: UUID?
    @Published private(set) var takes: [StudioTake] = []
    @Published private(set) var making: Making?
    @Published private(set) var playing: UUID?
    @Published var problem: String?
    /// Which part of the page shows. Leaving Dictate stops dictation; going to it notes the app
    /// in front, which Paste goes back to.
    @Published var section: StudioSection = .scripts {
        didSet {
            guard section != oldValue else { return }
            if oldValue == .dictate { DictationModel.shared.stop() }
            if section == .dictate { DictationModel.shared.captureTarget() }
        }
    }
    @Published var voiceID: String { didSet { defaults.set(voiceID, forKey: WidgetOptions.Keys.studioVoice) } }
    @Published var pace: Double { didSet { defaults.set(pace, forKey: WidgetOptions.Keys.studioPace) } }
    @Published var style: String { didSet { defaults.set(style, forKey: WidgetOptions.Keys.studioStyle) } }
    @Published var delivery: VoiceDelivery { didSet { defaults.set(delivery.rawValue, forKey: WidgetOptions.Keys.studioDelivery) } }
    /// Best Quality for voices from recordings: each piece made up to three times, the most alike
    /// kept, taking up to three times as long. Off is Fast.
    @Published var bestQuality: Bool { didSet { defaults.set(bestQuality, forKey: WidgetOptions.Keys.studioBestQuality) } }

    private let defaults: UserDefaults
    private var store: ProtectedFile?
    private var player: AVAudioPlayer?
    private var playerDelegate: Finished?
    private var writer: AVSpeechSynthesizer?
    private var task: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        voiceID = defaults.string(forKey: WidgetOptions.Keys.studioVoice) ?? ""
        pace = StudioTakes.clampedPace(defaults.object(forKey: WidgetOptions.Keys.studioPace) as? Double ?? 1)
        style = defaults.string(forKey: WidgetOptions.Keys.studioStyle) ?? ""
        delivery = defaults.string(forKey: WidgetOptions.Keys.studioDelivery).flatMap(VoiceDelivery.init(rawValue:)) ?? .natural
        bestQuality = defaults.object(forKey: WidgetOptions.Keys.studioBestQuality) as? Bool ?? false
    }

    /// Opens the Nook on Studio's Dictate, where dictation lives (what opening the Dictation page
    /// did): `target` is the app Paste goes to, else the app in front.
    static func openDictation(target: NSRunningApplication? = nil) {
        shared.section = .dictate
        DictationModel.shared.captureTarget(target)
        NookCommands.open(.prompter)
    }

    /// Opens the Nook on Studio's scripts, where the teleprompter's Prompt is.
    static func openTeleprompter() {
        shared.section = .scripts
        NookCommands.open(.prompter)
    }

    static var root: URL { ScriptPrompter.directory.appendingPathComponent("Takes", isDirectory: true) }
    static func folder(for scriptID: UUID) -> URL { root.appendingPathComponent(scriptID.uuidString, isDirectory: true) }
    func file(for take: StudioTake) -> URL? { scriptID.map { Self.folder(for: $0).appendingPathComponent(take.fileName) } }

    /// Check renders only: these takes and this take being made, with no audio.
    func setPreview(scriptID: UUID, takes: [StudioTake], making: Making?) {
        store = nil
        self.scriptID = scriptID
        self.takes = takes
        self.making = making
        problem = nil
    }

    // MARK: The voice

    /// The chosen voice if it's still here, else Automatic. A voice from recordings counts only
    /// while this Mac can speak it (a model downloaded).
    var voice: Voice {
        let recorded = RecordedVoices.shared
        if recorded.isAvailable, recorded.engine != nil, let voice = recorded.voice(id: voiceID) { return .recorded(voice) }
        if !voiceID.hasPrefix(RecordedVoice.prefix), let voice = AVSpeechSynthesisVoice(identifier: voiceID) { return .mac(voice) }
        return .automatic
    }

    /// The deliveries the chosen voice can read (Natural alone for a Mac voice).
    var deliveries: [VoiceDelivery] {
        if case .recorded(let voice) = voice { return voice.availableDeliveries }
        return [.natural]
    }

    /// The delivery a reading now uses: the chosen one if the voice has it, else Natural.
    var readingDelivery: VoiceDelivery { deliveries.contains(delivery) ? delivery : .natural }

    /// Whether a reading now would follow `style` (CosyVoice 3, with a voice from recordings).
    var followsStyle: Bool {
        if case .recorded = voice { return RecordedVoices.shared.followsStyle }
        return false
    }

    // MARK: Takes of a script

    /// Shows this script's takes (read from its folder; takes whose audio is gone are dropped).
    func show(scriptID: UUID?) {
        guard scriptID != self.scriptID else { return }
        stopPlaying()
        self.scriptID = scriptID
        problem = nil
        guard let scriptID else { takes = []; store = nil; return }
        let folder = Self.folder(for: scriptID)
        var file = ProtectedFile(url: folder.appendingPathComponent("takes.json"))
        switch file.load({ try JSONDecoder().decode([StudioTake].self, from: SecureStorage.open($0)) }) {
        case .loaded(let saved):
            takes = StudioTakes.present(saved) { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        case .missing:
            takes = []
        case .unreadable(let reason):
            takes = []
            problem = "This script's takes couldn't be opened (\(reason)), so they're left as they are."
        }
        store = file
    }

    private func save() {
        guard let scriptID, let store, store.isWritable else { return }
        do {
            try FileManager.default.createDirectory(at: Self.folder(for: scriptID), withIntermediateDirectories: true)
            if takes.isEmpty {
                try? store.remove()
            } else {
                try store.write(SecureStorage.seal(JSONEncoder().encode(takes)))
            }
        } catch {
            problem = "Takes can't be saved: \(error.localizedDescription)"
        }
    }

    /// When its script is deleted.
    func removeTakes(of scriptID: UUID) {
        if self.scriptID == scriptID {
            stop()
            takes = []
            store = nil
            self.scriptID = nil
        }
        try? FileManager.default.removeItem(at: Self.folder(for: scriptID))
    }

    // MARK: Reading

    var isMaking: Bool { making != nil }

    /// Reads `text` (from `range` of the script, when a selection) in the chosen voice as a new take.
    func read(_ text: String, range: NSRange?, scriptID: UUID) {
        make(text, range: range, scriptID: scriptID, voice: voice, delivery: readingDelivery, style: StudioTakes.cleanStyle(style), pace: pace,
             bestQuality: bestQuality)
    }

    /// Another take of the same words, voice, style, pace and quality, with a new seed.
    func again(_ take: StudioTake) {
        guard let scriptID else { return }
        let voice: Voice
        if let recorded = RecordedVoices.shared.voice(id: take.voice), RecordedVoices.shared.engine != nil {
            voice = .recorded(recorded)
        } else if !take.voice.isEmpty, let mac = AVSpeechSynthesisVoice(identifier: take.voice) {
            voice = .mac(mac)
        } else if take.voice.isEmpty {
            voice = .automatic
        } else {
            problem = "\(take.voiceName) can't read here any more."
            return
        }
        make(take.text, range: nil, scriptID: scriptID, voice: voice,
             delivery: take.delivery.flatMap(VoiceDelivery.init(rawValue:)) ?? .natural, style: take.style, pace: take.pace,
             bestQuality: take.bestQuality ?? false)
    }

    private func make(_ text: String, range: NSRange?, scriptID: UUID, voice: Voice, delivery: VoiceDelivery, style: String?,
                      pace: Double, bestQuality: Bool) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, making == nil else { return }
        if case .recorded = voice, RecordedVoices.shared.isBusy {
            problem = "Another voice job is running. Try again when it's done."
            return
        }
        show(scriptID: scriptID)
        stopPlaying()
        problem = nil
        let recorded: Bool
        if case .recorded = voice { recorded = true } else { recorded = false }
        making = Making(scriptID: scriptID, text: text, range: range, voiceName: voice.name, recorded: recorded)
        task = Task { [weak self] in
            guard let self else { return }
            await self.render(text, scriptID: scriptID, voice: voice, delivery: delivery, style: style, pace: pace,
                              bestQuality: bestQuality)
            self.making = nil
            self.task = nil
        }
    }

    private func render(_ text: String, scriptID: UUID, voice: Voice, delivery: VoiceDelivery, style: String?, pace: Double,
                        bestQuality: Bool) async {
        var delivery = delivery
        var bestQuality = bestQuality
        let seed: UInt64?
        let engine: String?
        let raw: URL
        switch voice {
        case .recorded(let recorded):
            let chosen = UInt64.random(in: 1...UInt64(UInt32.max))
            if !recorded.availableDeliveries.contains(delivery) { delivery = .natural }
            guard let file = await RecordedVoices.shared.take(text, in: recorded, delivery: delivery, seed: chosen, style: style,
                                                             bestQuality: bestQuality) else {
                if !Task.isCancelled { problem = RecordedVoices.shared.problem ?? "The take couldn't be made." }
                return
            }
            seed = chosen
            engine = RecordedVoices.shared.engine?.modelName
            raw = file
        case .mac, .automatic:
            let mac: AVSpeechSynthesisVoice?
            if case .mac(let chosen) = voice { mac = chosen } else { mac = WispVoices.automatic() }
            guard let file = await spoken(text, voice: mac) else {
                if !Task.isCancelled { problem = "This voice couldn't read it. Try another." }
                return
            }
            seed = nil
            engine = nil
            delivery = .natural
            // A Mac voice reads the same way every time: there's nothing to choose between.
            bestQuality = false
            raw = file
        }
        guard !Task.isCancelled else { try? FileManager.default.removeItem(at: raw); return }
        let take = StudioTake(id: UUID(), text: text, voice: voiceKey(voice), voiceName: voice.name, engine: engine, seed: seed,
                              style: engine == nil ? nil : (RecordedVoices.shared.followsStyle ? style : nil),
                              pace: pace, seconds: 0, created: Date(), delivery: delivery == .natural ? nil : delivery.rawValue,
                              bestQuality: bestQuality ? true : nil)
        let destination = Self.folder(for: scriptID).appendingPathComponent(take.fileName)
        let paced = pace
        let result: Result<Double, Error> = await Task.detached(priority: .userInitiated) {
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if abs(paced - 1) < 0.001 {
                    try FileManager.default.moveItem(at: raw, to: destination)
                } else {
                    defer { try? FileManager.default.removeItem(at: raw) }
                    try StudioAudio.paced(raw, rate: paced, to: destination)
                }
                return .success(StudioAudio.seconds(of: destination))
            } catch {
                try? FileManager.default.removeItem(at: raw)
                return .failure(error)
            }
        }.value
        switch result {
        case .failure(let error):
            problem = "The take couldn't be saved: \(error.localizedDescription)"
        case .success(let seconds):
            let finished = StudioTake(id: take.id, text: take.text, voice: take.voice, voiceName: take.voiceName, engine: take.engine,
                                      seed: take.seed, style: take.style, pace: take.pace, seconds: seconds, created: take.created,
                                      delivery: take.delivery, bestQuality: take.bestQuality)
            // The page may have moved to another script while it was made.
            if self.scriptID == scriptID {
                takes = StudioTakes.adding(finished, to: takes)
                save()
                play(finished)
            } else {
                append(finished, toScript: scriptID)
            }
        }
    }

    private func voiceKey(_ voice: Voice) -> String {
        switch voice {
        case .automatic: ""
        case .mac(let mac): mac.identifier
        case .recorded(let recorded): recorded.voiceID
        }
    }

    /// A take finished after its script was left: added to that script's own list.
    private func append(_ take: StudioTake, toScript scriptID: UUID) {
        var file = ProtectedFile(url: Self.folder(for: scriptID).appendingPathComponent("takes.json"))
        var list: [StudioTake] = []
        switch file.load({ try JSONDecoder().decode([StudioTake].self, from: SecureStorage.open($0)) }) {
        case .loaded(let saved): list = saved
        case .missing: break
        case .unreadable: return
        }
        try? file.write(SecureStorage.seal(JSONEncoder().encode(StudioTakes.adding(take, to: list))))
    }

    /// A Mac voice's reading, written by the synthesizer into a WAV in the temporary folder.
    private func spoken(_ text: String, voice: AVSpeechSynthesisVoice?) async -> URL? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("MacSpaces-take-\(UUID().uuidString).wav")
        let output = SpokenFile(url: file)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        let writer = AVSpeechSynthesizer()
        self.writer = writer
        writer.write(utterance) { buffer in output.append(buffer) }
        let finished = await output.finished()
        self.writer = nil
        guard finished, !Task.isCancelled else { try? FileManager.default.removeItem(at: file); return nil }
        return file
    }

    /// Stops the take being made.
    func stop() {
        guard let making else { return }
        task?.cancel()
        task = nil
        if making.recorded { RecordedVoices.shared.cancel() }
        writer?.stopSpeaking(at: .immediate)
        writer = nil
        self.making = nil
    }

    // MARK: Listening

    func play(_ take: StudioTake) {
        stopPlaying()
        guard let url = file(for: take), let player = try? AVAudioPlayer(contentsOf: url) else { return }
        let delegate = Finished { [weak self] in self?.playing = nil; self?.player = nil }
        player.delegate = delegate
        self.player = player
        playerDelegate = delegate
        playing = take.id
        player.play()
    }

    func stopPlaying() {
        player?.stop()
        player = nil
        playing = nil
    }

    // MARK: Keeping the best

    func toggleStar(_ take: StudioTake) {
        takes = StudioTakes.toggledStar(take.id, in: takes)
        save()
    }

    func delete(_ take: StudioTake) {
        if playing == take.id { stopPlaying() }
        if let url = file(for: take) { try? FileManager.default.removeItem(at: url) }
        takes.removeAll { $0.id == take.id }
        save()
    }

    /// Keeps the starred takes and deletes the rest.
    func keepStarred() {
        let (kept, removed) = StudioTakes.keepingStarred(takes)
        guard !removed.isEmpty else { return }
        for take in removed { delete(take) }
        takes = kept
        save()
    }

    func deleteAll() {
        for take in takes { delete(take) }
    }

    /// The take as an audio file in the Tray, to drag into any app.
    func saveToTray(_ take: StudioTake) {
        guard let url = file(for: take) else { return }
        let name = String(StudioTakes.fileName(for: take).dropLast(4))
        Task {
            let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
            guard let data else { problem = "The take's audio couldn't be read."; return }
            ShelfStore.shared.stageFile(data, name: name, ext: "wav")
        }
    }

    /// The take saved as a WAV file where you choose.
    func saveAs(_ take: StudioTake) {
        guard let url = file(for: take) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = StudioTakes.fileName(for: take)
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            problem = "The take couldn't be saved there: \(error.localizedDescription)"
        }
    }

    private final class Finished: NSObject, AVAudioPlayerDelegate {
        let done: @MainActor () -> Void
        init(_ done: @escaping @MainActor () -> Void) { self.done = done }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            Task { @MainActor in self.done() }
        }
    }
}
