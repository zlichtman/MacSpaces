import AVFoundation
import Speech

/// Wisp's ears and voice. Listening uses on-device recognition only and stops by itself
/// after a pause; replies are read with the best system voice for the user's language.
/// Microphone and Speech Recognition are asked for only from the mic button.
@MainActor
final class WispVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var isSpeaking = false
    private(set) var problem: String?

    /// The words heard (nil when listening couldn't start).
    var heard: ((String?) -> Void)?
    var finishedSpeaking: (() -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasTap = false
    private var generation = UUID()
    private var silence: DispatchWorkItem?
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func startListening() {
        guard !isListening else { return }
        problem = nil
        if DictationModel.shared.listening || (ScriptPrompter.shared.isRunning && ScriptPrompter.shared.mode == .voice) {
            fail("The microphone is busy with Dictation or the teleprompter.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            fail("On-device speech isn't available for this language on this Mac, so Wisp can't listen. Typing works.")
            return
        }
        let token = UUID()
        generation = token
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                guard status == .authorized else { self.fail("Allow Speech Recognition in System Settings → Privacy & Security."); return }
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        guard allowed else { self.fail("Allow Microphone access in System Settings → Privacy & Security."); return }
                        self.listen(recognizer, token: token)
                    }
                }
            }
        }
    }

    private func listen(_ recognizer: SFSpeechRecognizer, token: UUID) {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { fail("No usable microphone was found."); return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        hasTap = true
        do { engine.prepare(); try engine.start() }
        catch { teardown(); fail("Couldn't start the microphone: " + error.localizedDescription); return }
        transcript = ""
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let finished = result?.isFinal == true || error != nil
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.isListening else { return }
                if let text, !text.isEmpty {
                    self.transcript = text
                    self.armSilence(after: 1.5)
                }
                if finished { self.stopListening(deliver: true) }
            }
        }
        // Nothing said at all: give up after a while.
        armSilence(after: 7)
    }

    /// Stops; `deliver` hands what was heard to Wisp.
    func stopListening(deliver: Bool) {
        guard isListening else { return }
        let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        teardown()
        if deliver { heard?(words) }
    }

    private func armSilence(after seconds: Double) {
        silence?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stopListening(deliver: true) }
        silence = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func teardown() {
        silence?.cancel()
        generation = UUID()
        isListening = false
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        engine.stop()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func fail(_ message: String) {
        problem = message
        heard?(nil)
    }

    // MARK: Speaking

    private lazy var voice: AVSpeechSynthesisVoice? = {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let matching = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return matching.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
    }()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.spoke() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.spoke() }
    }

    private func spoke() {
        guard !synthesizer.isSpeaking else { return }
        isSpeaking = false
        finishedSpeaking?()
    }
}
