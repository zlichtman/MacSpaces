import AppKit
import AVFoundation
import Combine
import Speech

/// Studio's scripts, and the teleprompter that reads them from just under the camera.
/// Scripts are kept on this Mac (Application Support/MacSpaces/scripts.json).
/// The prompter scrolls at a set speed, or follows your voice using on-device
/// speech recognition (microphone and speech access are asked for only when
/// you choose that), and is hidden from screen sharing and recordings.
@MainActor
final class ScriptPrompter: ObservableObject {
    static let shared = ScriptPrompter()

    struct Script: Identifiable, Codable, Equatable {
        var id = UUID()
        var title: String
        var text: String
        var edited = Date()
    }

    enum Mode: String, CaseIterable, Identifiable {
        case scroll, voice
        var id: String { rawValue }
        var title: String { self == .scroll ? "Scroll" : "Follow my voice" }
        var shortTitle: String { self == .scroll ? "Scroll" : "Voice" }
    }

    enum TextSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var points: CGFloat { switch self { case .small: return 20; case .medium: return 26; case .large: return 34 } }
        var title: String { rawValue.capitalized }
    }

    @Published var scripts: [Script] = [] { didSet { save() } }
    @Published var selectedID: UUID?
    @Published var mode: Mode { didSet { defaults.set(mode.rawValue, forKey: "prompter.mode") } }
    /// Words per minute while scrolling.
    @Published var speed: Double { didSet { defaults.set(speed, forKey: "prompter.speed") } }
    @Published var textSize: TextSize { didSet { defaults.set(textSize.rawValue, forKey: "prompter.size"); wrapLines() } }
    @Published var countdown: Bool { didSet { defaults.set(countdown, forKey: "prompter.countdown") } }

    // Playback
    @Published private(set) var isShowing = false
    @Published private(set) var isRunning = false
    /// Position in the script, in words (fractional while scrolling).
    @Published private(set) var position: Double = 0
    @Published private(set) var countdownValue: Int?
    @Published private(set) var listening = false
    @Published private(set) var voiceProblem: String?
    /// Voice mode was refused (no on-device recognition), so this run scrolls.
    @Published private(set) var scrollingInstead = false
    /// Set when scripts.json exists but couldn't be read: it is left untouched and
    /// nothing is saved over it until `startNewLibrary()`.
    @Published private(set) var libraryProblem: String?
    private(set) var words: [String] = []
    /// `words` wrapped to the panel, measured only when they or the text size change.
    @Published private(set) var lines: [PrompterView.Line] = []
    private var normalised: [String] = []

    private let defaults: UserDefaults
    private var tick: Timer?
    private var lastTick = Date()
    private var countdownID = UUID()
    private let speech = VoiceFollower()
    private var store = ProtectedFile(url: ScriptPrompter.storeURL)

    var selected: Script? { scripts.first { $0.id == selectedID } ?? scripts.first }

    /// Where scripts.json lives, and Studio's Takes folder beside it. Debug harnesses (any other
    /// bundle identifier) use a temporary fixtures folder instead.
    static var directory: URL {
        let isolated = Bundle.main.bundleIdentifier != "dev.opensource.MacSpaces"
        return isolated ? FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesFixtures")
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacSpaces")
    }

    private static var storeURL: URL { directory.appendingPathComponent("scripts.json") }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = Mode(rawValue: defaults.string(forKey: "prompter.mode") ?? "") ?? .scroll
        speed = defaults.object(forKey: "prompter.speed") as? Double ?? 140
        textSize = TextSize(rawValue: defaults.string(forKey: "prompter.size") ?? "") ?? .medium
        countdown = defaults.object(forKey: "prompter.countdown") as? Bool ?? true
        switch store.load({ try JSONDecoder().decode([Script].self, from: SecureStorage.open($0)) }) {
        case .loaded(let saved): scripts = saved
        case .missing: break
        case .unreadable(let reason):
            libraryProblem = "Your saved scripts couldn't be opened (\(reason)), so they were left as they are. Changes here aren't saved until you start a new library."
        }
        if scripts.isEmpty, libraryProblem == nil {
            scripts = [Script(title: "Welcome", text: "This is Studio. Write or paste a script here. Select some words and press Read to hear them in a voice: each reading is a take you can play, star and save. Press Prompt to read it yourself, just under your camera, hidden from screen sharing and recordings.")]
        }
        selectedID = scripts.first?.id
        speech.onHeard = { [weak self] heard in self?.follow(heard) }
        speech.onProblem = { [weak self] problem in self?.voiceProblem = problem; self?.listening = false }
        speech.onListening = { [weak self] value in self?.listening = value }
    }

    /// Never writes over a library that failed to load (see `libraryProblem`). A save
    /// that fails says so on the page rather than losing the changes quietly.
    private func save() {
        guard store.isWritable else { return }
        do {
            try store.write(SecureStorage.seal(JSONEncoder().encode(scripts)))
            libraryProblem = nil
        } catch {
            libraryProblem = "Scripts can't be saved: \(error.localizedDescription)"
        }
    }

    /// The owner's explicit reset after a failed load: the unreadable file is kept
    /// beside the original (renamed, never deleted) and the scripts here are saved.
    func startNewLibrary() {
        do {
            try store.setAside()
            libraryProblem = nil
            save()
        } catch {
            libraryProblem = "The unreadable scripts file couldn't be set aside: \(error.localizedDescription)"
        }
    }

#if DEBUG
    /// QA captures: the selected script laid out as if read up to `word`.
    func previewPlayback(at word: Double) {
        words = (selected?.text ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        wrapLines()
        position = word
        isRunning = true
    }
#endif

    // MARK: Library

    func newScript() {
        let script = Script(title: "Untitled script", text: "")
        scripts.insert(script, at: 0)
        selectedID = script.id
    }

    /// Its takes go with it.
    func delete(_ script: Script) {
        scripts.removeAll { $0.id == script.id }
        StudioModel.shared.removeTakes(of: script.id)
        if selectedID == script.id { selectedID = scripts.first?.id }
    }

    func update(_ script: Script) {
        guard let index = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        var edited = script
        edited.edited = Date()
        scripts[index] = edited
    }

    /// Plain text, Markdown, RTF or Word files become scripts.
    func importFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text, .rtf, .rtfd, .init(filenameExtension: "md")!,
                                     .init(filenameExtension: "docx")!].compactMap { $0 }
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil).string)
                ?? (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            guard !text.isEmpty else { continue }
            let script = Script(title: url.deletingPathExtension().lastPathComponent, text: text)
            scripts.insert(script, at: 0)
            selectedID = script.id
        }
    }

    // MARK: Playback

    func start() {
        guard let script = selected, !script.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        words = script.text.split(whereSeparator: \.isWhitespace).map(String.init)
        wrapLines()
        normalised = words.map { ScriptAligner.words($0).joined() }
        position = 0
        voiceProblem = nil
        scrollingInstead = false
        isShowing = true
        PrompterPanel.shared.show()
        countdownID = UUID()
        if countdown {
            runCountdown(3, id: countdownID)
        } else {
            begin()
        }
    }

    private func wrapLines() {
        lines = PrompterView.wrap(words, width: PrompterPanel.size.width - 48, size: textSize.points)
    }

    /// `id` ends a count left over from an earlier Start.
    private func runCountdown(_ value: Int, id: UUID) {
        guard isShowing, id == countdownID else { return }
        guard value > 0 else { countdownValue = nil; begin(); return }
        countdownValue = value
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.runCountdown(value - 1, id: id) }
    }

    private func begin() {
        isRunning = true
        guard mode == .voice, !scrollingInstead else { startTicking(); return }
        WispModel.shared.voice.stopListening(deliver: false)
        // Audio stays on this Mac: without on-device recognition, scroll instead.
        if case .refuse(let reason) = speech.decision {
            voiceProblem = reason
            scrollingInstead = true
            startTicking()
            return
        }
        speech.start()
    }

    func togglePause() {
        guard isShowing, countdownValue == nil else { return }
        if isRunning {
            isRunning = false
            tick?.invalidate(); tick = nil
            speech.stop()
        } else {
            begin()
        }
    }

    func close() {
        isRunning = false
        isShowing = false
        countdownValue = nil
        countdownID = UUID()
        tick?.invalidate(); tick = nil
        speech.stop()
        PrompterPanel.shared.hide()
    }

    /// Back (or forward) by about one line.
    func skip(_ wordsToMove: Double) {
        position = min(max(0, position + wordsToMove), Double(words.count))
        speech.resetHeard()
    }

    func changeSpeed(by delta: Double) { speed = min(260, max(60, speed + delta)) }

    private func startTicking() {
        tick?.invalidate()
        lastTick = Date()
        tick = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                let now = Date()
                self.position = min(Double(self.words.count), self.position + now.timeIntervalSince(self.lastTick) * self.speed / 60)
                self.lastTick = now
                if self.position >= Double(self.words.count) { self.togglePause() }
            }
        }
    }

    private func follow(_ heard: [String]) {
        guard isRunning, mode == .voice,
              let next = ScriptAligner.position(script: normalised, heard: heard, from: Int(position)) else { return }
        position = Double(next)
    }
}

/// On-device speech recognition feeding the words heard so far. Restarts the
/// recognition task when macOS ends it (about once a minute).
@MainActor
final class VoiceFollower {
    var onHeard: ([String]) -> Void = { _ in }
    var onProblem: (String) -> Void = { _ in }
    var onListening: (Bool) -> Void = { _ in }
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var active = false
    private var hasTap = false
    /// Only the newest recognition task's callbacks count.
    private var generation = UUID()
    /// Tasks in a row that failed just after starting.
    private var quickFailures = 0

    /// Whether voice following may run here: only with on-device recognition.
    var decision: OnDeviceSpeech.Decision {
        OnDeviceSpeech.decide(hasRecognizer: recognizer != nil, isAvailable: recognizer?.isAvailable ?? false,
                              supportsOnDevice: recognizer?.supportsOnDeviceRecognition ?? false)
    }

    func start() {
        guard !active else { return }
        guard !DictationModel.shared.listening, !DictationModel.shared.starting else {
            onProblem("Stop dictation before starting voice following.")
            return
        }
        guard decision == .listen else {
            if case .refuse(let reason) = decision { onProblem(reason) }
            return
        }
        active = true
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard self.active else { return }
                guard status == .authorized else {
                    self.active = false
                    self.onProblem("Allow Speech Recognition for MacSpaces in System Settings → Privacy & Security.")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in
                        guard self.active else { return }
                        guard granted else {
                            self.active = false
                            self.onProblem("Allow the Microphone for MacSpaces in System Settings → Privacy & Security.")
                            return
                        }
                        self.listen()
                    }
                }
            }
        }
    }

    func stop() {
        active = false
        generation = UUID()
        quickFailures = 0
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        removeTap()
        if engine.isRunning { engine.stop() }
        onListening(false)
    }

    /// The engine stops itself on a device change and leaves its tap on, so this doesn't
    /// depend on it running; a second tap on the bus would crash.
    private func removeTap() {
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
    }

    func resetHeard() {
        guard active else { return }
        quickFailures = 0
        task?.finish()
    }

    private func listen() {
        guard active, let recognizer, decision == .listen else {
            if active, case .refuse(let reason) = decision { stop(); onProblem(reason) }
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            stop()
            onProblem("No usable microphone was found.")
            return
        }
        let token = UUID()
        generation = token
        task?.cancel()
        self.request?.endAudio()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Never a server request: on-device only (checked above), always required.
        request.requiresOnDeviceRecognition = true
        self.request = request
        // Each tap feeds only its own request, so the audio thread never reads `self.request`.
        removeTap()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        hasTap = true
        if !engine.isRunning {
            do { try engine.start() } catch {
                stop()
                onProblem("The microphone couldn't start: \(error.localizedDescription)")
                return
            }
        }
        onListening(true)
        let started = Date()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let words = result.map { ScriptAligner.words($0.bestTranscription.formattedString) } ?? []
            let finished = (result?.isFinal ?? false) || error != nil
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.active, self.generation == token else { return }
                if !words.isEmpty { self.onHeard(words) }
                if finished {
                    // Recognition tasks end on their own; carry on with a fresh one. One that
                    // keeps failing as soon as it starts won't recover, so stop and say why.
                    if let failure, Date().timeIntervalSince(started) < 2 {
                        self.quickFailures += 1
                        if self.quickFailures >= 3 {
                            self.stop()
                            self.onProblem(failure)
                            return
                        }
                    } else {
                        self.quickFailures = 0
                    }
                    self.task = nil
                    self.listen()
                }
            }
        }
    }
}
