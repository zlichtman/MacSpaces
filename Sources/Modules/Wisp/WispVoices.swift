import AVFoundation
import os

/// The agent's speaking voice (Settings → Tsukumo → Voice): Automatic (the best installed voice
/// for your language), one of this Mac's voices, your own Personal Voice (macOS 14+, once
/// you allow it), or a voice made from recordings (`RecordedVoices`, Apple silicon and macOS 15+).
/// Everything is spoken on this Mac.
enum WispVoices {
    static var chosenID: String? { UserDefaults.standard.string(forKey: WidgetOptions.Keys.wispVoice) }

    /// The chosen voice made from recordings, while it and a model to speak it are there.
    @MainActor static var chosenRecorded: RecordedVoice? {
        let voices = RecordedVoices.shared
        guard voices.isAvailable, voices.engine != nil else { return nil }
        return voices.voice(id: chosenID)
    }

    /// The chosen system voice if it's still installed, else Automatic (also what a voice made
    /// from recordings falls back to when it can't speak).
    static func current() -> AVSpeechSynthesisVoice? {
        chosenID.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? automatic()
    }

    static func automatic() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let matching = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return matching.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
    }

    static func isPersonal(_ voice: AVSpeechSynthesisVoice) -> Bool {
        if #available(macOS 14, *) { return voice.voiceTraits.contains(.isPersonalVoice) }
        return false
    }

    /// What the voice menus offer: Personal Voices, then just the two best Mac voices for your
    /// language (Premium or Enhanced only: the compact standard ones sound poor), a man's and a
    /// woman's where both exist, plus any voice already chosen for the agent or Studio so a saved
    /// pick keeps working. Novelty voices are left out.
    static func choices() -> [AVSpeechSynthesisVoice] {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let prefix = String(language.prefix(2))
        let all = AVSpeechSynthesisVoice.speechVoices()
        let personal = all.filter(isPersonal)
        let good = all.filter { voice in
            guard !isPersonal(voice), voice.language.hasPrefix(prefix), voice.quality != .default else { return false }
            if #available(macOS 14, *), voice.voiceTraits.contains(.isNoveltyVoice) { return false }
            return true
        }
        .sorted { a, b in
            if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
            let aLocal = a.language == language, bLocal = b.language == language
            if aLocal != bLocal { return aLocal }
            return a.name < b.name
        }
        var best: [AVSpeechSynthesisVoice] = []
        if let first = good.first {
            best.append(first)
            let other = good.first { $0.gender != first.gender && $0.gender != .unspecified } ?? good.dropFirst().first
            if let other { best.append(other) }
        }
        let saved = [UserDefaults.standard.string(forKey: WidgetOptions.Keys.wispVoice),
                     UserDefaults.standard.string(forKey: WidgetOptions.Keys.studioVoice)]
        let kept = all.filter { voice in saved.contains(voice.identifier) && !best.contains(voice) && !personal.contains(voice) }
        return personal + best + kept
    }

    /// Whether this Mac has any Premium or Enhanced voice for your language, for the menus' hint.
    static var hasGoodVoice: Bool {
        let prefix = String(AVSpeechSynthesisVoice.currentLanguageCode().prefix(2))
        return AVSpeechSynthesisVoice.speechVoices().contains { $0.language.hasPrefix(prefix) && $0.quality != .default && !isPersonal($0) }
    }

    static func label(_ voice: RecordedVoice) -> String { voice.name + " (from recordings)" }

    static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        if isPersonal(voice) { return voice.name + " (Personal Voice)" }
        let quality: String
        switch voice.quality {
        case .premium: quality = "Premium"
        case .enhanced: quality = "Enhanced"
        default: quality = ""
        }
        let region = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
        return [voice.name, quality.isEmpty ? region : quality + ", " + region].joined(separator: " · ")
    }
}

/// Settings' Voice card: plays a line in the chosen voice, and saves it as an audio file in the
/// Tray (Folio), to drag into any app.
@MainActor
final class VoiceStudio: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceStudio()
    @Published private(set) var isSpeaking = false
    @Published private(set) var isSaving = false
    @Published private(set) var status: String?
    /// Bumped when the list of voices may have changed (a Personal Voice allowed).
    @Published private(set) var voicesChanged = 0
    private let synthesizer = AVSpeechSynthesizer()
    private var writer: AVSpeechSynthesizer?
    private var recorded: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    private func utterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = WispVoices.current()
        return utterance
    }

    func play(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = true; status = nil
        if let voice = WispVoices.chosenRecorded {
            // Made by the voice helper, then played here; the first line also loads the model.
            status = "Making the line in \(voice.name)'s voice"
            recorded = Task { [weak self] in
                let played = await RecordedVoices.shared.say(text, in: voice)
                guard let self, !Task.isCancelled else { return }
                self.status = played ? nil : RecordedVoices.shared.problem
                self.isSpeaking = false
            }
            return
        }
        synthesizer.speak(utterance(text))
    }

    func stop() {
        recorded?.cancel(); recorded = nil
        if WispVoices.chosenRecorded != nil {
            RecordedVoices.shared.cancel()
            RecordedVoices.shared.stopPlaying()
            isSpeaking = false; status = nil
        }
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }

    /// Speaks the line into a WAV file off the main thread and adds it to the Tray.
    func saveToTray(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSaving else { return }
        isSaving = true; status = nil
        if let voice = WispVoices.chosenRecorded {
            Task { [weak self] in
                do {
                    let file = try await RecordedVoices.shared.speech(text, in: voice)
                    let data = try Data(contentsOf: file)
                    try? FileManager.default.removeItem(at: file)
                    ShelfStore.shared.stageFile(data, name: TrayFiles.stagedName(for: .text("Spoken " + text)), ext: "wav")
                    self?.status = "Saved to the Tray"
                } catch {
                    self?.status = error.localizedDescription
                }
                self?.isSaving = false
            }
            return
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("MacSpaces-voice-\(UUID().uuidString).wav")
        let output = SpokenFile(url: file)
        let writer = AVSpeechSynthesizer()
        self.writer = writer
        writer.write(utterance(text)) { buffer in
            output.append(buffer)
        }
        // `write` reports nothing when it's done but an empty buffer, so the file says when.
        Task { [weak self] in
            let finished = await output.finished()
            guard let self else { return }
            self.writer = nil; self.isSaving = false
            guard finished, let data = try? Data(contentsOf: file) else {
                self.status = "This voice couldn't be saved. Try another."
                try? FileManager.default.removeItem(at: file)
                return
            }
            try? FileManager.default.removeItem(at: file)
            ShelfStore.shared.stageFile(data, name: TrayFiles.stagedName(for: .text("Spoken " + text)), ext: "wav")
            self.status = "Saved to the Tray"
        }
    }

    /// macOS 14+: whether MacSpaces may speak in your Personal Voice.
    var personalVoiceStatus: PersonalVoiceAccess {
        guard #available(macOS 14, *) else { return .unavailable }
        switch AVSpeechSynthesizer.personalVoiceAuthorizationStatus {
        case .authorized: return .allowed
        case .denied: return .denied
        case .unsupported: return .unavailable
        default: return .notAsked
        }
    }

    enum PersonalVoiceAccess { case unavailable, notAsked, denied, allowed }

    /// Asked only from the Use My Personal Voice button.
    func requestPersonalVoice() {
        guard #available(macOS 14, *) else { return }
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
            Task { @MainActor in
                let voices = AVSpeechSynthesisVoice.speechVoices().filter(WispVoices.isPersonal)
                if status == .authorized, voices.isEmpty {
                    VoiceStudio.shared.status = "Make a Personal Voice in System Settings, Accessibility, then choose it here."
                }
                VoiceStudio.shared.voicesChanged += 1
            }
        }
    }
}

/// The WAV file a spoken line is written into, from the synthesizer's own thread.
final class SpokenFile: @unchecked Sendable {
    private struct State { var file: AVAudioFile?; var frames: AVAudioFrameCount = 0; var done = false; var failed = false }
    private let url: URL
    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    init(url: URL) { self.url = url }

    func append(_ buffer: AVAudioBuffer) {
        state.withLockUnchecked { state in
            guard !state.done else { return }
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { state.done = true; return }
            do {
                if state.file == nil {
                    state.file = try AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                                 commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
                }
                try state.file?.write(from: pcm)
                state.frames += pcm.frameLength
            } catch { state.failed = true; state.done = true }
        }
    }

    /// Waits (up to two minutes) for the last buffer; true when audio was written.
    func finished() async -> Bool {
        for _ in 0..<1200 {
            let (done, ok) = state.withLockUnchecked { state -> (Bool, Bool) in
                if state.done { state.file = nil }
                return (state.done, !state.failed && state.frames > 0)
            }
            if done { return ok }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }
}
