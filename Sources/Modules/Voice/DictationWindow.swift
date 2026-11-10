import AppKit
import AVFoundation
import ApplicationServices
import Speech
import SwiftUI

@MainActor
final class DictationModel: ObservableObject {
    static let shared = DictationModel()
    @Published var text = ""
    @Published private(set) var listening = false
    @Published private(set) var starting = false
    @Published var problem: String?
    var target: NSRunningApplication?
    private let engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var generation = UUID()
    private var hasTap = false
    private var prefix = ""
    /// Between the earlier text and what's heard now: a new line for a new Start, a space when
    /// a recognition task that macOS ended is carried on.
    private var separator = "\n"
    private var recognizer: SFSpeechRecognizer?
    /// Only the newest recognition task's callbacks count.
    private var recognition = UUID()
    /// Tasks in a row that ended just after starting.
    private var quickEnds = 0
    func captureTarget(_ app: NSRunningApplication? = nil) {
        if let app = app ?? NSWorkspace.shared.frontmostApplication, app != .current, !app.isTerminated { target = app }
    }
    func start() {
        guard !listening, !starting else { return }
        WispModel.shared.voice.stopListening(deliver: false)
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            problem = "On-device dictation isn't available for this language on this Mac. No audio will be sent to a server."
            return
        }
        if ScriptPrompter.shared.isRunning, ScriptPrompter.shared.mode == .voice {
            problem = "Pause the voice-following teleprompter before starting dictation."
            return
        }
        generation = UUID(); let token = generation
        starting = true; problem = nil
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.starting else { return }
                guard status == .authorized else { self.starting = false; self.problem = "Allow Speech Recognition in System Settings → Privacy & Security."; return }
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token, self.starting else { return }
                        guard allowed else { self.starting = false; self.problem = "Allow Microphone access in System Settings → Privacy & Security."; return }
                        self.listen(recognizer, token: token)
                    }
                }
            }
        }
    }
    private func listen(_ recognizer: SFSpeechRecognizer, token: UUID) {
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { starting = false; problem = "No usable microphone was found."; return }
        self.recognizer = recognizer
        prefix = text.trimmingCharacters(in: .whitespacesAndNewlines)
        separator = "\n"; quickEnds = 0
        recognize(token: token)
        do { engine.prepare(); try engine.start() }
        catch { stop(); problem = "Couldn't start the microphone: " + error.localizedDescription; return }
        starting = false; listening = true
    }
    /// One recognition task. macOS ends each about once a minute, so a final result without an
    /// error starts a fresh one that carries on from the text so far. Permission was granted
    /// when the user pressed Start, so nothing is asked again; Stop changes `generation`, so
    /// nothing restarts after it.
    private func recognize(token: UUID) {
        guard let recognizer else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        task?.cancel(); self.request?.endAudio()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
        self.request = request
        // Each tap feeds only its own request, so the audio thread never reads `self.request`.
        if hasTap { input.removeTap(onBus: 0) }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        hasTap = true
        let pass = UUID(); recognition = pass
        let started = Date()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let finished = result?.isFinal == true || error != nil
            let message = error?.localizedDescription
            Task { @MainActor [weak self, token, pass, started, transcript, finished, message] in
                guard let self, self.generation == token, self.recognition == pass, self.listening else { return }
                if let transcript, !transcript.isEmpty { self.text = (self.prefix.isEmpty ? "" : self.prefix + self.separator) + transcript }
                guard finished else { return }
                if let message { self.stop(); self.problem = message; return }
                // A task that keeps ending as soon as it starts won't recover: stop rather than spin.
                if Date().timeIntervalSince(started) < 2 {
                    self.quickEnds += 1
                    if self.quickEnds >= 3 { self.stop(); return }
                } else {
                    self.quickEnds = 0
                }
                self.task = nil
                self.prefix = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.separator = " "
                self.recognize(token: token)
            }
        }
    }
    func stop() {
        generation = UUID(); starting = false; listening = false
        request?.endAudio(); task?.cancel(); task = nil; request = nil; recognizer = nil
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
    }
    func copy() { guard !text.isEmpty else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func paste() {
        stop(); copy()
        guard let target, !target.isTerminated, target != .current else { problem = "Copied. Switch to your destination app and paste."; return }
        guard AXIsProcessTrusted() else {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            problem = "Copied. Allow Accessibility to paste directly, or paste manually in your app."
            return
        }
        NotchManager.active?.closeDictation()
        target.activate()
        let expected = target.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expected else {
                self?.problem = "Copied. The destination couldn't become active; paste manually."
                return
            }
            let source = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
                event?.flags = .maskCommand; event?.post(tap: .cghidEventTap)
            }
        }
    }
}
