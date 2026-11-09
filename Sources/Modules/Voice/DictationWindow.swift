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
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { starting = false; problem = "No usable microphone was found."; return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
        self.request = request
        prefix = text.trimmingCharacters(in: .whitespacesAndNewlines)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        hasTap = true
        do { engine.prepare(); try engine.start() }
        catch { stop(); problem = "Couldn't start the microphone: " + error.localizedDescription; return }
        starting = false; listening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let finished = result?.isFinal == true || error != nil
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.listening else { return }
                if let transcript, !transcript.isEmpty { self.text = (self.prefix.isEmpty ? "" : self.prefix + "\n") + transcript }
                if finished { self.stop(); if let message { self.problem = message } }
            }
        }
    }
    func stop() {
        generation = UUID(); starting = false; listening = false
        request?.endAudio(); task?.cancel(); task = nil; request = nil
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
