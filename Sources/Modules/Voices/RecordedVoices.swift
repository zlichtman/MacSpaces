import AppKit
import AVFoundation
import Foundation
import Speech

/// A voice made from recordings: its name, whose it is, and its clips (`VoiceSamples.Sample`), each
/// cut from a recording, with what it says and the person's fingerprint (to recognise them in
/// later recordings). Saved in Voices/People/<id>/ as voice.json beside the clips. A voice found
/// in a recording waits to be approved (whose voice it is) before it can read.
struct RecordedVoice: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    /// The first clip's words, length and the voice's fingerprint, as voices saved before 4.02 keep them.
    var transcript: String
    var fingerprint: [Float]?
    var seconds: Double
    let created: Date
    /// Whose voice it is, as answered when it was approved: "mine" or "permission" (someone else's,
    /// who said yes). Nil for voices saved before the question was asked, and while waiting.
    var consent: String? = nil
    /// Voices saved before 4.02: Siren's other deliveries, each a clip beside clip.wav (<delivery>.wav).
    var deliveries: [VoiceDelivery.Clip]? = nil
    /// Its clips, in order; nil for a voice saved before 4.02 (clip.wav and its deliveries).
    var samples: [VoiceSamples.Sample]? = nil
    /// False while it waits to be approved; nil (voices saved before 4.02) and true are approved.
    var approved: Bool? = nil

    /// How `wisp.voice` names it, beside the system voices' identifiers.
    var voiceID: String { RecordedVoice.prefix + id.uuidString }
    static let prefix = "recorded:"

    var isApproved: Bool { approved != false }

    /// Its clips: the saved list, or for a voice from before 4.02, clip.wav and its deliveries.
    var clips: [VoiceSamples.Sample] {
        if let samples { return samples }
        return [VoiceSamples.Sample(file: "clip.wav", transcript: transcript, seconds: seconds, delivery: .natural, included: true,
                                    fingerprint: fingerprint)]
            + (deliveries ?? []).map { kept in
                VoiceSamples.Sample(file: kept.delivery.rawValue + ".wav", transcript: kept.transcript, seconds: kept.seconds,
                                    delivery: kept.delivery, included: true, fingerprint: nil)
            }
    }

    func folder(in root: URL = VoicePaths.root) -> URL {
        VoicePaths.people(in: root).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func file(_ sample: VoiceSamples.Sample, in root: URL = VoicePaths.root) -> URL {
        folder(in: root).appendingPathComponent(sample.file)
    }

    /// The clip Natural reads: what Play plays.
    func clip(in root: URL = VoicePaths.root) -> URL {
        let clips = clips
        guard let index = VoiceSamples.reference(clips, for: .natural) else { return folder(in: root).appendingPathComponent("clip.wav") }
        return file(clips[index], in: root)
    }

    /// The deliveries it can read: Natural, then those it has an included clip for.
    var availableDeliveries: [VoiceDelivery] { VoiceSamples.deliveries(clips) }

    /// The clip and its words a delivery copies (`VoiceSamples.reference`, one clip picked Siren's way).
    func reference(for delivery: VoiceDelivery?, in root: URL = VoicePaths.root) -> (clip: URL, transcript: String)? {
        let clips = clips
        return VoiceSamples.reference(clips, for: delivery ?? .natural).map { (file(clips[$0], in: root), clips[$0].transcript) }
    }

    /// The recordings its clips came from (earlier ones counted as one).
    var recordingCount: Int { Set(clips.map { $0.recording?.uuidString ?? "" }).count }
}

/// A recording brought into Studio's Voices, waiting to be sorted, sorted, or not usable. Only its
/// path is kept; the file is read, never changed or copied.
struct VoiceRecording: Codable, Identifiable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case waiting, sorting, sorted, failed }
    let id: UUID
    let name: String
    let path: String
    let added: Date
    var state: State
    /// Why it couldn't be used, or what sorting left out.
    var note: String?
    /// People found in it.
    var people: Int = 0
}

/// Voices from recordings: the voice models with their downloads, the recordings brought in (each
/// sorted in turn into the people heard), and the voices, which join across recordings when the
/// same person is heard again. All model work happens in the voice helper (`VoiceHelperClient`);
/// this keeps only files and lists, so the notch app stays light. Nothing downloads, and no
/// permission is asked, until the user presses Download or brings recordings in.
@MainActor
final class RecordedVoices: ObservableObject {
    static let shared = RecordedVoices()

    struct Job: Equatable {
        /// `prepare` is Record My Voice's take being made into a voice.
        enum Kind: Equatable { case download(String), sort, speak, prepare }
        let kind: Kind
        var stage: String
        var fraction: Double
    }

    @Published private(set) var states: [String: VoiceModelStore.State] = [:]
    @Published private(set) var lackingExtras: Set<String> = []
    @Published private(set) var job: Job?
    @Published private(set) var recordings: [VoiceRecording] = []
    /// Every voice: approved ones and those waiting to be approved.
    @Published private(set) var voices: [RecordedVoice] = []
    @Published private(set) var playing: URL?
    /// The Voices folder's size on disk (models included), once measured.
    @Published private(set) var folderBytes: Int64?
    /// Sorting waits after Stop until Sort is pressed again.
    @Published private(set) var paused = false
    @Published var problem: String?

    let root: URL
    private let store: VoiceModelStore
    private let helper = VoiceHelperClient()
    private var player: AVAudioPlayer?
    private var playerDelegate: PlayerDelegate?
    private var agentTask: Task<Void, Never>?
    private var agentFinished: ((Bool) -> Void)?
    private var agentFile: URL?
    private var stopping = false
    private var preview = false

    init(root: URL = VoicePaths.root) {
        self.root = root
        store = VoiceModelStore(hub: VoicePaths.models(in: root))
        helper.progress = { [weak self] stage, fraction in
            guard let self, var job = self.job else { return }
            job.stage = stage; job.fraction = min(1, max(0, fraction))
            self.job = job
        }
        loadVoices()
        loadRecordings()
        // Recordings left waiting are sorted when Sort is pressed, never on their own at launch.
        paused = recordings.contains { $0.state == .waiting }
        carryOverFound()
        // A take left by quitting while recording or making it.
        try? FileManager.default.removeItem(at: takesFolder)
        if isAvailable { refreshModels() }
    }

    /// Check renders only: shows these models, recordings and voices without the helper or disk.
    func setPreview(states: [String: VoiceModelStore.State], recordings: [VoiceRecording] = [], voices: [RecordedVoice],
                    job: Job? = nil, folderBytes: Int64? = nil) {
        preview = true
        self.states = states; self.recordings = recordings; self.voices = voices; problem = nil; self.job = job
        self.folderBytes = folderBytes
    }

    var isAvailable: Bool { RecordedVoiceSupport.isAvailable }
    var isBusy: Bool { job != nil }

    /// The voices that can read: approved ones.
    var ready: [RecordedVoice] { voices.filter(\.isApproved) }
    /// Voices found in recordings that wait to be approved.
    var waiting: Int { voices.filter { !$0.isApproved }.count }

    // MARK: Models

    /// Reads which models are on disk, off the main thread (it walks a few folders).
    func refreshModels() {
        let store = store
        Task.detached(priority: .utility) {
            let states = Dictionary(uniqueKeysWithValues: VoiceModel.catalogue.map { ($0.id, store.state(of: $0)) })
            let lacking = Set(VoiceModel.catalogue.filter { store.lacksExtras($0) }.map(\.id))
            await MainActor.run { [weak self] in
                self?.states = states
                self?.lackingExtras = lacking
                self?.sortNext()
            }
        }
    }

    func state(_ model: VoiceModel) -> VoiceModelStore.State { states[model.id] ?? .notDownloaded }

    /// Downloaded before its extras were added (Finding voices without noise reduction): Update fetches them.
    func lacksExtras(_ model: VoiceModel) -> Bool { lackingExtras.contains(model.id) }

    var downloaded: Set<String> { Set(states.filter { $0.value.isDownloaded }.map(\.key)) }
    var canSort: Bool { state(.sorting).isDownloaded }

    /// The engine replies are spoken with (`voices.engine`, else the best downloaded for this Mac).
    var engine: VoiceModel? {
        VoiceModel.speakingEngine(chosen: UserDefaults.standard.string(forKey: WidgetOptions.Keys.voicesEngine), downloaded: downloaded)
    }

    func useEngine(_ model: VoiceModel) {
        UserDefaults.standard.set(model.id, forKey: WidgetOptions.Keys.voicesEngine)
        objectWillChange.send()
    }

    /// Asked only from the model's Download button. Hugging Face is the only service contacted.
    func download(_ model: VoiceModel) {
        guard isAvailable, job == nil else { return }
        problem = nil
        job = Job(kind: .download(model.id), stage: "Downloading", fraction: 0)
        let hub = store.hub
        Task {
            do {
                try FileManager.default.createDirectory(at: hub, withIntermediateDirectories: true)
                try await helper.download(model, hub: hub)
            } catch {
                problem = error.localizedDescription
            }
            job = nil
            refreshModels()
            refreshSize()
            sortNext()
        }
    }

    /// Frees the model's space; a part another downloaded model uses stays.
    func remove(_ model: VoiceModel) {
        guard job == nil else { return }
        let store = store
        Task.detached(priority: .utility) {
            let failure: String?
            do { try store.remove(model); failure = nil } catch { failure = error.localizedDescription }
            await MainActor.run { [weak self] in
                if let failure { self?.problem = "It couldn't be removed: " + failure }
                self?.refreshModels()
                self?.refreshSize()
            }
        }
    }

    /// Stops the running job; a recording being sorted goes back to waiting, and sorting waits
    /// until Sort is pressed.
    func cancel() {
        if job?.kind == .sort { stopping = true; paused = true }
        helper.cancel()
    }

    // MARK: Recordings

    /// The dropped files that are audio or video with sound; anything else is left out.
    nonisolated static func recordings(in urls: [URL]) -> [URL] {
        urls.filter { url in
            guard url.isFileURL, !url.hasDirectoryPath else { return false }
            return (try? AVAudioFile(forReading: url)) != nil
        }
    }

    /// Lists the recordings and sorts them, one after another, into people. They're read, never
    /// changed. Before macOS 26, whose transcriber needs no permission, this is when Speech
    /// Recognition is asked for: the clips need their words written down. A recording already
    /// sorted is left as it is; one that failed or waits is sorted again.
    func add(_ urls: [URL]) {
        guard isAvailable else { return }
        problem = nil
        Task {
            let files = await Task.detached(priority: .userInitiated) { Self.recordings(in: urls) }.value
            guard !files.isEmpty else { problem = "Drop audio files, or videos with sound."; return }
            if #unavailable(macOS 26) {
                guard await Self.speechAllowed() else {
                    problem = "Turn on Speech Recognition for MacSpaces in System Settings, Privacy & Security, so it can write down what each person says."
                    return
                }
            }
            var already = 0
            for file in files {
                if let index = recordings.firstIndex(where: { $0.path == file.path }) {
                    switch recordings[index].state {
                    case .sorted, .sorting: already += 1
                    case .waiting, .failed: recordings[index].state = .waiting; recordings[index].note = nil
                    }
                } else {
                    recordings.append(VoiceRecording(id: UUID(), name: file.lastPathComponent, path: file.path, added: Date(), state: .waiting))
                }
            }
            if already > 0 { problem = already == 1 ? "That recording is already sorted." : "\(already) of those recordings are already sorted." }
            saveRecordings()
            paused = false
            sortNext()
        }
    }

    /// Sorts this recording next (and the rest after it).
    func sort(_ recording: VoiceRecording) {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }), recordings[index].state != .sorting else { return }
        var item = recordings.remove(at: index)
        item.state = .waiting
        item.note = nil
        let first = recordings.firstIndex { $0.state == .waiting } ?? recordings.count
        recordings.insert(item, at: first)
        saveRecordings()
        paused = false
        sortNext()
    }

    /// Sorts every recording waiting.
    func sortAll() {
        paused = false
        sortNext()
    }

    var waitingRecordings: Int { recordings.filter { $0.state == .waiting }.count }

    /// Takes the recording off the list (the file is never touched). Voices still waiting to be
    /// approved lose their clips from it, and go when nothing is left; approved voices keep theirs.
    func removeRecording(_ recording: VoiceRecording) {
        if recordings.first(where: { $0.id == recording.id })?.state == .sorting {
            stopping = true
            helper.cancel()
        }
        recordings.removeAll { $0.id == recording.id }
        saveRecordings()
        for voice in voices where !voice.isApproved && voice.clips.contains(where: { $0.recording == recording.id }) {
            let kept = voice.clips.filter { $0.recording != recording.id }
            if kept.isEmpty {
                delete(voice)
            } else {
                for sample in voice.clips where sample.recording == recording.id { try? FileManager.default.removeItem(at: voice.file(sample, in: root)) }
                update(voice) { $0.samples = kept }
            }
        }
        try? FileManager.default.removeItem(at: VoicePaths.sorting(in: root).appendingPathComponent(recording.id.uuidString))
    }

    /// The next recording waiting, through the helper, unless a job runs or sorting waits.
    private func sortNext() {
        guard !preview, isAvailable, canSort, job == nil, !paused,
              let index = recordings.firstIndex(where: { $0.state == .waiting }) else { return }
        let recording = recordings[index]
        recordings[index].state = .sorting
        stopping = false
        job = Job(kind: .sort, stage: "Reading", fraction: 0)
        let output = VoicePaths.sorting(in: root).appendingPathComponent(recording.id.uuidString, isDirectory: true)
        let hub = store.hub
        Task {
            var state = VoiceRecording.State.sorted, note: String?, people = 0
            do {
                let result = try await helper.sort(.init(files: [recording.path], output: output.path, hub: hub.path))
                people = integrate(result.people, from: recording)
                note = result.skipped.first
                if people == 0 {
                    state = .failed
                    note = note ?? "No one could be heard talking on their own."
                }
            } catch {
                state = stopping ? .waiting : .failed
                note = stopping ? nil : error.localizedDescription
            }
            stopping = false
            try? FileManager.default.removeItem(at: output)
            if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
                recordings[index].state = state
                recordings[index].note = note
                recordings[index].people = people
                saveRecordings()
            }
            job = nil
            refreshSize()
            sortNext()
        }
    }

    /// The people found in one recording become clips of voices: of the voice they already are
    /// (`VoiceSamples.joining`), else of a new voice waiting to be approved. Returns how many.
    private func integrate(_ people: [VoiceHelperMessage.Person], from recording: VoiceRecording?, joiningAs id: UUID? = nil) -> Int {
        let source = recording?.id ?? id ?? UUID()
        var count = 0
        for person in people where !person.transcript.isEmpty {
            let candidates = voices.map { voice in
                VoiceSamples.Candidate(id: voice.id.uuidString, samples: voice.clips.map { ($0.recording, $0.fingerprint) })
            }
            let target = VoiceSamples.joining(person.fingerprint, recording: source, among: candidates)
                .flatMap { id in voices.first { $0.id.uuidString == id } }
            let voice = target ?? RecordedVoice(id: UUID(), name: person.label, transcript: person.transcript, fingerprint: person.fingerprint,
                                                seconds: person.seconds, created: Date(), samples: [], approved: false)
            let folder = voice.folder(in: root)
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch { continue }
            func moved(_ path: String, delivery: VoiceDelivery, transcript: String, seconds: Double,
                       evidence: VoiceSamples.Evidence?) -> VoiceSamples.Sample? {
                let name = "clip-\(UUID().uuidString.prefix(8)).wav"
                guard (try? FileManager.default.moveItem(at: URL(fileURLWithPath: path), to: folder.appendingPathComponent(name))) != nil else { return nil }
                return VoiceSamples.Sample(file: name, transcript: transcript, seconds: seconds, delivery: delivery, included: true,
                                           fingerprint: person.fingerprint, recording: source, recordingName: recording?.name,
                                           evidence: evidence)
            }
            let clipSeconds = Self.seconds(of: URL(fileURLWithPath: person.clip)) ?? min(person.seconds, VoiceSamples.referenceSeconds)
            guard let main = moved(person.clip, delivery: .natural, transcript: person.transcript, seconds: clipSeconds,
                                   evidence: person.evidence) else { continue }
            let extra = (person.deliveries ?? []).compactMap {
                moved($0.file, delivery: $0.delivery, transcript: $0.transcript, seconds: $0.seconds, evidence: $0.evidence)
            }
            if target == nil {
                var made = voice
                made.samples = [main] + extra
                made.seconds = clipSeconds
                voices.append(made)
                save(made)
            } else {
                update(voice) { edited in
                    edited.samples = VoiceSamples.combined(edited.clips, with: [main] + extra, keepReading: edited.isApproved)
                    edited.fingerprint = VoiceSamples.fingerprint(edited.clips) ?? edited.fingerprint
                }
            }
            count += 1
        }
        return count
    }

    private nonisolated static func seconds(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private static func speechAllowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    // MARK: Record My Voice

    /// Where Record My Voice's take is recorded (Voices/Sorting/Takes/<id>.wav) and made into a clip
    /// (beside it, <id>/); emptied when MacSpaces starts.
    var takesFolder: URL { VoicePaths.sorting(in: root).appendingPathComponent("Takes", isDirectory: true) }

    enum OwnVoiceOutcome: Equatable {
        case made(RecordedVoice)
        /// Why the take can't make a voice, in one line.
        case failed(String)
    }

    /// Record My Voice: the take made into a clip by the helper as sorting makes one
    /// (`VoiceHelperClient.prepare`), judged by Siren's sample checks (`OwnVoiceTake.problem`), and,
    /// when it passes, a new voice named My voice, yours and approved (you said so by recording it).
    /// The take, and everything made from it but the clip, is deleted either way. Before macOS 26
    /// this is when Speech Recognition is asked for, as when recordings are brought in.
    func makeOwnVoice(from take: URL) async -> OwnVoiceOutcome {
        defer { try? FileManager.default.removeItem(at: take) }
        guard isAvailable, canSort else { return .failed("Download Finding voices in Settings, Tsukumo, Voice first.") }
        let busy = OwnVoiceOutcome.failed("Another voice job is running. Try again when it's done.")
        guard job == nil else { return busy }
        if #unavailable(macOS 26) {
            guard await Self.speechAllowed() else {
                return .failed("Turn on Speech Recognition for MacSpaces in System Settings, Privacy & Security, so it can write down what you said.")
            }
        }
        guard !Task.isCancelled else { return .failed("Stopped.") }
        guard job == nil else { return busy }
        problem = nil
        job = Job(kind: .prepare, stage: "Reading", fraction: 0)
        let output = take.deletingPathExtension()
        defer {
            try? FileManager.default.removeItem(at: output)
            job = nil
            refreshSize()
            sortNext()
        }
        let person: VoiceHelperMessage.Person
        do {
            person = try await helper.prepare(.init(file: take.path, script: OwnVoiceTake.passage, output: output.path, hub: store.hub.path))
        } catch {
            return .failed(error.localizedDescription)
        }
        // Closed while it was made: nothing is kept (the clip goes with `output`).
        guard !Task.isCancelled else { return .failed("Stopped.") }
        let clip = URL(fileURLWithPath: person.clip)
        let seconds = await Task.detached(priority: .userInitiated) { Self.seconds(of: clip) ?? 0 }.value
        if let problem = OwnVoiceTake.problem(seconds: seconds, evidence: person.evidence) { return .failed(problem.message) }
        guard !person.transcript.isEmpty else {
            return .failed("The words couldn't be made out. Read the passage clearly, close to the mic, then Use This.")
        }
        var voice = RecordedVoice(id: UUID(), name: OwnVoiceTake.name, transcript: person.transcript, fingerprint: person.fingerprint,
                                  seconds: seconds, created: Date(), consent: "mine", samples: [], approved: true)
        let file = "clip-\(UUID().uuidString.prefix(8)).wav"
        do {
            try FileManager.default.createDirectory(at: voice.folder(in: root), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: clip, to: voice.folder(in: root).appendingPathComponent(file))
        } catch {
            try? FileManager.default.removeItem(at: voice.folder(in: root))
            return .failed("Your voice couldn't be saved: \(error.localizedDescription)")
        }
        voice.samples = [VoiceSamples.Sample(file: file, transcript: person.transcript, seconds: seconds, delivery: .natural, included: true,
                                             fingerprint: person.fingerprint, recordingName: "Recorded in Studio",
                                             evidence: person.evidence)]
        voices.append(voice)
        save(voice)
        return .made(voice)
    }

    // MARK: Voices

    /// The other voice this one sounds like, when it may be the same person (Same Person combines them).
    func soundsLike(_ voice: RecordedVoice) -> RecordedVoice? {
        let others = voices.filter { $0.id != voice.id }.map { (id: $0.id.uuidString, fingerprint: VoiceSamples.fingerprint($0.clips) ?? $0.fingerprint) }
        guard let id = VoiceSamples.soundsLike(VoiceSamples.fingerprint(voice.clips) ?? voice.fingerprint, among: others) else { return nil }
        return voices.first { $0.id.uuidString == id }
    }

    /// Says whose voice it is, so it can read: "mine", or "permission" (someone else's, who said yes).
    func approve(_ voice: RecordedVoice, name: String, consent: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        update(voice) { edited in
            if !name.isEmpty { edited.name = name }
            edited.consent = consent
            edited.approved = true
        }
    }

    func rename(_ voice: RecordedVoice, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        update(voice) { $0.name = name }
    }

    /// The same person: `other`'s clips join `voice` and `other` goes. An approved voice is always
    /// the one kept (it keeps its name and how it reads; the clips it gains start left out), and
    /// the agent and Studio follow it.
    func combine(_ voice: RecordedVoice, with other: RecordedVoice) {
        guard voice.id != other.id else { return }
        let (kept, gone) = !voice.isApproved && other.isApproved ? (other, voice) : (voice, other)
        let folder = kept.folder(in: root)
        var incoming: [VoiceSamples.Sample] = []
        for sample in gone.clips {
            let name = "clip-\(UUID().uuidString.prefix(8)).wav"
            guard (try? FileManager.default.moveItem(at: gone.file(sample, in: root), to: folder.appendingPathComponent(name))) != nil else { continue }
            let moved = VoiceSamples.Sample(file: name, transcript: sample.transcript, seconds: sample.seconds, delivery: sample.delivery,
                                            included: sample.included, fingerprint: sample.fingerprint ?? (sample.file == "clip.wav" ? gone.fingerprint : nil),
                                            recording: sample.recording, recordingName: sample.recordingName, evidence: sample.evidence)
            incoming.append(moved)
        }
        update(kept) { edited in
            edited.samples = VoiceSamples.combined(edited.clips, with: incoming, keepReading: edited.isApproved)
            edited.fingerprint = VoiceSamples.fingerprint(edited.clips) ?? edited.fingerprint
        }
        if remove(gone) { follow(gone, to: kept.isApproved ? kept : nil) }
    }

    /// Not the same person: the clip becomes a voice of its own, waiting to be approved.
    func separate(_ sample: VoiceSamples.Sample, from voice: RecordedVoice) {
        guard voice.clips.count > 1, voice.clips.contains(sample) else { return }
        var made = RecordedVoice(id: UUID(), name: voice.name + " (2)", transcript: sample.transcript, fingerprint: sample.fingerprint,
                                 seconds: sample.seconds, created: Date(), samples: [], approved: false)
        do {
            try FileManager.default.createDirectory(at: made.folder(in: root), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: voice.file(sample, in: root), to: made.file(sample, in: root))
        } catch {
            problem = "The clip couldn't be moved: " + error.localizedDescription
            return
        }
        var alone = sample
        alone.included = true
        alone.delivery = .natural
        alone.pinned = nil
        made.samples = [alone]
        update(voice) { edited in
            edited.samples = Self.keepingNatural(edited.clips.filter { $0 != sample })
            edited.fingerprint = VoiceSamples.fingerprint(edited.clips) ?? edited.fingerprint
        }
        voices.append(made)
        save(made)
    }

    /// Includes or leaves out a clip (never the last included Natural one).
    func setIncluded(_ sample: VoiceSamples.Sample, in voice: RecordedVoice, _ included: Bool) {
        guard let index = voice.clips.firstIndex(of: sample) else { return }
        if !included, !VoiceSamples.canExclude(voice.clips, at: index) { return }
        update(voice) { edited in
            var clips = edited.clips
            clips[index].included = included
            edited.samples = clips
        }
    }

    /// Use First: the clip's delivery always reads this clip (it's included and moves to the top).
    func useFirst(_ sample: VoiceSamples.Sample, in voice: RecordedVoice) {
        guard let index = voice.clips.firstIndex(of: sample) else { return }
        update(voice) { edited in edited.samples = VoiceSamples.pinnedFirst(edited.clips, at: index) }
    }

    /// Choose Automatically: the clip's delivery goes back to reading the clip picked for it.
    func chooseAutomatically(_ sample: VoiceSamples.Sample, in voice: RecordedVoice) {
        guard let index = voice.clips.firstIndex(of: sample) else { return }
        update(voice) { edited in edited.samples = VoiceSamples.unpinned(edited.clips, at: index) }
    }

    /// Deletes one clip's file; the last clip goes with the voice (Remove Voice).
    func deleteClip(_ sample: VoiceSamples.Sample, from voice: RecordedVoice) {
        guard voice.clips.count > 1, voice.clips.contains(sample) else { return }
        do { try FileManager.default.removeItem(at: voice.file(sample, in: root)) } catch {
            problem = "The clip couldn't be deleted: " + error.localizedDescription
            return
        }
        update(voice) { edited in
            edited.samples = Self.keepingNatural(edited.clips.filter { $0 != sample })
            edited.fingerprint = VoiceSamples.fingerprint(edited.clips) ?? edited.fingerprint
        }
        refreshSize()
    }

    /// A list that still reads: if no included Natural clip is left, the first clip becomes one.
    private static func keepingNatural(_ clips: [VoiceSamples.Sample]) -> [VoiceSamples.Sample] {
        guard !clips.isEmpty, !clips.contains(where: { $0.included && $0.delivery == .natural }) else { return clips }
        var clips = clips
        if let index = clips.firstIndex(where: { $0.delivery == .natural }) ?? clips.indices.first {
            clips[index].included = true
            clips[index].delivery = .natural
        }
        return clips
    }

    /// Deletes a voice's folder (its clips and voice.json); the recordings it came from were never
    /// copied. If the agent or Studio read in it, they go back to Automatic.
    func delete(_ voice: RecordedVoice) {
        if remove(voice) { follow(voice, to: nil) }
        refreshSize()
    }

    /// Deletes the folder, then takes the voice off the list; false (with `problem`) if it couldn't.
    @discardableResult
    private func remove(_ voice: RecordedVoice) -> Bool {
        let folder = voice.folder(in: root)
        if !preview, FileManager.default.fileExists(atPath: folder.path) {
            do { try FileManager.default.removeItem(at: folder) } catch {
                problem = "\(voice.name)'s files couldn't be deleted: \(error.localizedDescription)"
                return false
            }
        }
        voices.removeAll { $0.id == voice.id }
        return true
    }

    /// The agent's and Studio's choice of `voice` moves to `next` (or Automatic).
    private func follow(_ voice: RecordedVoice, to next: RecordedVoice?) {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: WidgetOptions.Keys.wispVoice) == voice.voiceID {
            if let next { defaults.set(next.voiceID, forKey: WidgetOptions.Keys.wispVoice) } else { defaults.removeObject(forKey: WidgetOptions.Keys.wispVoice) }
        }
        if StudioModel.shared.voiceID == voice.voiceID { StudioModel.shared.voiceID = next?.voiceID ?? "" }
    }

    /// An approved voice by `wisp.voice` or `studio.voice`'s id.
    func voice(id: String?) -> RecordedVoice? {
        guard let id, id.hasPrefix(RecordedVoice.prefix) else { return nil }
        return voices.first { $0.voiceID == id && $0.isApproved }
    }

    // MARK: The Voices folder

    /// Shows Application Support/MacSpaces/Voices in the Finder (made first if it isn't there yet).
    func showInFinder() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    /// Measures the Voices folder off the main thread.
    func refreshSize() {
        guard !preview else { return }
        let root = root
        Task.detached(priority: .utility) {
            let bytes = VoiceModelStore.size(of: root)
            await MainActor.run { [weak self] in self?.folderBytes = bytes }
        }
    }

    // MARK: Listening

    func play(_ clip: URL) {
        stopPlaying()
        guard let player = try? AVAudioPlayer(contentsOf: clip) else { return }
        let delegate = PlayerDelegate { [weak self] in self?.playing = nil; self?.player = nil }
        player.delegate = delegate
        self.player = player
        playerDelegate = delegate
        playing = clip
        player.play()
    }

    func stopPlaying() {
        player?.stop()
        player = nil
        playing = nil
    }

    // MARK: Speaking

    /// A line spoken in a voice, written to a WAV file in the temporary folder. `delivery`, `seed`
    /// and `style` are Studio's: a delivery copies its own clip, each take samples with its own
    /// seed, and an engine that follows a style (CosyVoice 3) reads it that way. The delivery reads
    /// one clip, picked Siren's way (`VoiceSamples.reference`), once its clips from earlier versions
    /// are measured (`measureClips`). `bestQuality` (Studio's Best Quality) makes up to three
    /// attempts at each piece and keeps the one most like the voice (`TakeChoice`).
    func speech(_ text: String, in voice: RecordedVoice, delivery: VoiceDelivery? = nil, seed: UInt64? = nil,
                style: String? = nil, bestQuality: Bool = false) async throws -> URL {
        guard let engine else { throw VoiceHelperClient.Failure.stopped("Download a voice model in Settings, Tsukumo, Voice first.") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("MacSpaces-voice-\(UUID().uuidString).wav")
        let voice = await measureClips(voice)
        try Task.checkCancellation()
        guard let reference = voice.reference(for: delivery, in: root) else {
            throw VoiceHelperClient.Failure.stopped("This voice has no clips left.")
        }
        return try await helper.speak(.init(text: text, clip: reference.clip.path, transcript: reference.transcript,
                                            engine: engine.id, hub: store.hub.path, output: output.path, seed: seed,
                                            style: engine.runtime == .cosyVoice ? style : nil,
                                            takes: bestQuality ? TakeChoice.attempts : nil))
    }

    /// One Studio take: the words in the voice as a WAV in the temporary folder, shown as the
    /// running job (Stop cancels it). Nil with `problem` set when it couldn't be made.
    func take(_ text: String, in voice: RecordedVoice, delivery: VoiceDelivery?, seed: UInt64, style: String?,
              bestQuality: Bool = false) async -> URL? {
        guard job == nil else { problem = "Another voice job is running. Try again when it's done."; return nil }
        problem = nil
        job = Job(kind: .speak, stage: "Loading the voice", fraction: 0)
        defer { job = nil; sortNext() }
        do {
            return try await speech(text, in: voice, delivery: delivery, seed: seed, style: style, bestQuality: bestQuality)
        } catch {
            problem = error.localizedDescription
            return nil
        }
    }

    /// Whether the engine in use follows a style (CosyVoice 3, Expressive).
    var followsStyle: Bool { engine?.runtime == .cosyVoice }

    /// Plays a line in a voice: the helper makes it, then it plays here.
    func say(_ text: String, in voice: RecordedVoice) async -> Bool {
        guard job == nil else { return false }
        job = Job(kind: .speak, stage: "Loading the voice", fraction: 0)
        defer { job = nil; sortNext() }
        do {
            let file = try await speech(text, in: voice)
            play(file)
            // The file is only needed while it plays.
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { try? FileManager.default.removeItem(at: file) }
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    /// The agent's reply in its voice from recordings, when the agent's voice is one. Returns false
    /// (and calls nothing) when it isn't, so the system voice speaks instead. `finished` gets true
    /// once the reply has played or was stopped, false if it couldn't be made, so the caller can
    /// fall back to the system voice.
    func speakAsAgent(_ text: String, finished: @escaping (Bool) -> Void) -> Bool {
        guard isAvailable, engine != nil,
              let voice = voice(id: UserDefaults.standard.string(forKey: WidgetOptions.Keys.wispVoice)) else { return false }
        stopAgent()
        agentFinished = finished
        agentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let file = try await self.speech(text, in: voice)
                guard !Task.isCancelled else { try? FileManager.default.removeItem(at: file); return }
                self.agentFile = file
                self.play(file)
                self.playerDelegate?.extra = { [weak self] in self?.finishAgent(true) }
            } catch {
                guard !Task.isCancelled else { return }
                self.finishAgent(false)
            }
        }
        return true
    }

    func stopAgent() {
        guard agentTask != nil || agentFinished != nil else { return }
        agentTask?.cancel()
        agentTask = nil
        helper.cancel()
        stopPlaying()
        finishAgent(true)
    }

    private func finishAgent(_ spoke: Bool) {
        if let file = agentFile { try? FileManager.default.removeItem(at: file) }
        agentFile = nil
        let done = agentFinished
        agentFinished = nil
        agentTask = nil
        done?(spoke)
    }

    // MARK: Measuring clips from earlier versions

    /// Voices measured (or tried) this session, so a failed measurement isn't retried on every line.
    private var measuredVoices: Set<UUID> = []

    /// A voice whose clips came from an earlier version (nothing measured), measured once before it
    /// first reads, so its clip is picked Siren's way: background gap, longest quiet and joins from
    /// each clip's audio, off the main thread, and each clip's likeness to the voice by the helper's
    /// fingerprint model when Finding voices is downloaded. A Use First made back then is kept
    /// (`VoiceSamples.inferredPin`). Voices saved before 4.02 (one clip per delivery, nothing to
    /// choose) and voices with one included clip are left as they are.
    private func measureClips(_ voice: RecordedVoice) async -> RecordedVoice {
        guard !preview, voice.samples != nil, !measuredVoices.contains(voice.id),
              voice.clips.filter(\.included).count > 1, voice.clips.contains(where: { $0.evidence == nil }) else { return voice }
        measuredVoices.insert(voice.id)
        let clips = voice.clips
        let files = clips.map { voice.file($0, in: root) }
        let pin = VoiceSamples.inferredPin(clips, added: Dictionary(recordings.map { ($0.id, $0.added) }, uniquingKeysWith: { a, _ in a }))
        let heard: [VoiceSamples.Evidence?] = await Task.detached(priority: .userInitiated) {
            files.map { file -> VoiceSamples.Evidence? in
                guard let read = Self.monoSamples(of: file) else { return nil }
                let gap = VoiceSamples.backgroundGapDB(read.samples, rate: read.rate)
                return VoiceSamples.Evidence(backgroundDB: gap > 0 ? gap : nil,
                                             longestPause: VoiceSamples.longestQuiet(read.samples, rate: read.rate),
                                             joined: VoiceSamples.looksJoined(read.samples, rate: read.rate))
            }
        }.value
        var likeness: [Double?] = clips.map { _ in nil }
        let unmeasured = clips.indices.filter { clips[$0].evidence == nil && heard[$0] != nil }
        if canSort, let print = VoiceSamples.fingerprint(clips) ?? voice.fingerprint, !unmeasured.isEmpty {
            if let scores = try? await helper.likeness(.init(reference: "", files: unmeasured.map { files[$0].path },
                                                             hub: store.hub.path, fingerprint: print)) {
                for (index, score) in zip(unmeasured, scores) { likeness[index] = score }
            }
        }
        update(voice) { edited in
            var samples = edited.clips
            guard samples.map(\.file) == clips.map(\.file) else { return }
            for index in unmeasured {
                var evidence = heard[index]
                evidence?.likeness = likeness[index]
                samples[index].evidence = evidence
            }
            if let pin { samples[pin].pinned = true }
            edited.samples = samples
        }
        return voices.first { $0.id == voice.id } ?? voice
    }

    /// A clip's first channel and its sample rate; nil if it can't be read.
    private nonisolated static func monoSamples(of url: URL) -> (samples: [Float], rate: Int)? {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
              file.processingFormat.sampleRate > 0, file.length > 0, file.length < 10_000_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let data = buffer.floatChannelData else { return nil }
        return (Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))), Int(file.processingFormat.sampleRate))
    }

    // MARK: Files

    /// Edits a voice and rewrites its voice.json (a voice from before 4.02 gets its clip list then).
    private func update(_ voice: RecordedVoice, _ change: (inout RecordedVoice) -> Void) {
        guard let index = voices.firstIndex(where: { $0.id == voice.id }) else { return }
        var edited = voices[index]
        if edited.samples == nil { edited.samples = edited.clips; edited.deliveries = nil }
        change(&edited)
        if let first = edited.clips.first(where: { $0.included && $0.delivery == .natural }) ?? edited.clips.first {
            edited.transcript = first.transcript
            edited.seconds = first.seconds
        }
        voices[index] = edited
        save(edited)
    }

    private func save(_ voice: RecordedVoice) {
        guard !preview else { return }
        do {
            try JSONEncoder().encode(voice).write(to: voice.folder(in: root).appendingPathComponent("voice.json"), options: .atomic)
        } catch {
            problem = "\(voice.name) couldn't be saved: " + error.localizedDescription
        }
    }

    private func loadVoices() {
        let folder = VoicePaths.people(in: root)
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        voices = entries.compactMap { entry in
            (try? Data(contentsOf: entry.appendingPathComponent("voice.json")))
                .flatMap { try? JSONDecoder().decode(RecordedVoice.self, from: $0) }
        }
        .filter { voice in voice.clips.contains { FileManager.default.fileExists(atPath: voice.file($0, in: root).path) } }
        .sorted { $0.created < $1.created }
    }

    private var recordingsFile: URL { root.appendingPathComponent("recordings.json") }

    private func saveRecordings() {
        guard !preview else { return }
        if recordings.isEmpty { try? FileManager.default.removeItem(at: recordingsFile); return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? JSONEncoder().encode(recordings).write(to: recordingsFile, options: .atomic)
    }

    /// The list as it was; one being sorted when MacSpaces quit waits again.
    private func loadRecordings() {
        recordings = ((try? Data(contentsOf: recordingsFile)).flatMap { try? JSONDecoder().decode([VoiceRecording].self, from: $0) } ?? [])
            .map { recording in
                var recording = recording
                if recording.state == .sorting { recording.state = .waiting }
                return recording
            }
    }

    /// People found under 4.00 and 4.01 and not yet named (Voices/Sorting/found.json) become voices
    /// waiting to be approved, their clips moved into Voices/People; then the old list goes.
    private func carryOverFound() {
        let sorting = VoicePaths.sorting(in: root)
        let file = sorting.appendingPathComponent("found.json")
        guard let data = try? Data(contentsOf: file),
              let found = try? JSONDecoder().decode([VoiceHelperMessage.Person].self, from: data) else { return }
        let present = found.filter { FileManager.default.fileExists(atPath: $0.clip) }
        // One earlier sort: its people were told apart already, so they never join each other.
        _ = integrate(present, from: nil, joiningAs: UUID())
        // Anyone whose clip couldn't be moved stays listed for the next launch.
        let left = present.filter { !$0.transcript.isEmpty && FileManager.default.fileExists(atPath: $0.clip) }
        guard left.isEmpty else {
            try? JSONEncoder().encode(left).write(to: file, options: .atomic)
            return
        }
        try? FileManager.default.removeItem(at: file)
        for person in found {
            try? FileManager.default.removeItem(atPath: person.clip)
            for delivery in person.deliveries ?? [] { try? FileManager.default.removeItem(atPath: delivery.file) }
        }
    }

    private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
        let done: @MainActor () -> Void
        /// Also run when playback ends (the agent's reply cleaning up).
        var extra: (@MainActor () -> Void)?
        init(_ done: @escaping @MainActor () -> Void) { self.done = done }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            Task { @MainActor in self.done(); self.extra?() }
        }
    }
}
