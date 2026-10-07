import AppKit
import AVFoundation
import ApplicationServices
import Speech
import SwiftUI

@MainActor
final class DictationModel: ObservableObject {
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
    func start() {
        guard !listening, !starting else { return }
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
        DictationWindow.shared.hide()
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

@MainActor
final class DictationWindow: NSObject, NSWindowDelegate {
    static let shared = DictationWindow()
    let model = DictationModel()
    private var panel: VoicePanel?
    func show(target: NSRunningApplication? = nil) {
        model.target = target ?? NSWorkspace.shared.frontmostApplication
        if panel == nil {
            let panel = VoicePanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "MacSpaces Dictation"; panel.isReleasedWhenClosed = false; panel.delegate = self
            panel.contentView = NSHostingView(rootView: DictationView(model: model)); panel.center(); self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
    }
    func hide() { model.stop(); panel?.orderOut(nil) }
    func windowWillClose(_ notification: Notification) { model.stop() }
    private final class VoicePanel: NSPanel { override var canBecomeKey: Bool { true } }
}

struct DictationView: View {
    @ObservedObject var model: DictationModel
    @ObservedObject private var theme = ThemeStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.listening ? "Listening on this Mac" : model.starting ? "Waiting for access…" : "On-device dictation", systemImage: model.listening ? "waveform" : "mic")
                    .font(.headline)
                Spacer()
                if model.listening || model.starting { Button("Stop") { model.stop() } }
                else { Button("Start") { model.start() }.buttonStyle(.borderedProminent) }
            }
            Text("No audio is saved or uploaded. Start explicitly; stop, edit, then copy or paste into your original app.").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $model.text).font(.body).disabled(model.listening || model.starting)
                .scrollContentBackground(.hidden).padding(6).background(theme.notch.control, in: RoundedRectangle(cornerRadius: 10))
            if let problem = model.problem { Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Clear") { model.text = "" }.disabled(model.listening || model.starting)
                Spacer()
                Button("Copy") { model.copy() }.disabled(model.text.isEmpty)
                Button("Paste" + (model.target?.localizedName.map { " into " + $0 } ?? "")) { model.paste() }.disabled(model.text.isEmpty)
            }
        }.padding(18).background(theme.notch.surface).foregroundStyle(theme.nookForeground).tint(theme.notch.accent).preferredColorScheme(theme.notch.colorScheme)
    }
}
