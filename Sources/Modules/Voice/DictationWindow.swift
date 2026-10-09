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

struct DictationView: View {
    @ObservedObject var model: DictationModel
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @FocusState private var editing: Bool
    private var active: Bool { model.listening || model.starting }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: model.listening ? "waveform" : "mic.fill")
                    .font(.system(size: 22)).foregroundStyle(theme.notch.accent)
                    .frame(width: 42, height: 42)
                    .background(theme.notch.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dictation").font(.system(size: 17, weight: .semibold))
                    Text(model.listening ? "Listening on this Mac" : model.starting ? "Waiting for access…" : "Speak, edit, then paste.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if active { model.stop() } else { editing = false; model.start() }
                } label: {
                    Label(active ? "Stop" : "Start dictation", systemImage: active ? "stop.fill" : "mic")
                }.buttonStyle(WidgetChipStyle(height: 32))
            }
            ZStack(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text(model.listening ? "Your words appear here…" : "Your transcript appears here. You can also type or edit it.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .padding(.horizontal, 13).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.text).font(.system(size: 13))
                    .scrollContentBackground(.hidden).padding(8)
                    .focused($editing).disabled(active)
                    .accessibilityLabel("Dictation transcript")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.notch.control, in: RoundedRectangle(cornerRadius: 16))
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text("On-device · Audio isn't saved").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.text = "" }.disabled(active || model.text.isEmpty)
                Button { model.copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(model.text.isEmpty)
                Button { model.paste() } label: { Label("Paste", systemImage: "arrow.up.forward.app") }
                    .disabled(model.text.isEmpty)
                    .help(model.target?.localizedName.map { "Paste into " + $0 } ?? "Copy and paste into your app")
            }.buttonStyle(WidgetChipStyle(height: 28))
        }
        .padding(.horizontal, 4).padding(.vertical, 8)
        .foregroundStyle(theme.nookForeground).tint(theme.notch.accent)
        .preferredColorScheme(theme.notch.colorScheme)
        .onChange(of: editing) { _, value in onEditingChanged(value || active) }
        .onChange(of: active) { _, value in onEditingChanged(value || editing) }
        .onDisappear { model.stop(); onEditingChanged(false) }
    }
}
