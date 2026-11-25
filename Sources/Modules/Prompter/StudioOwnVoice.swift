import AVFoundation
import SwiftUI

/// Record My Voice, in Studio's Voices (Siren's guided take, its `Recorder`): you read
/// `OwnVoiceTake.passage` aloud, mono 48 kHz WAV with a live level, into the Voices folder
/// (`RecordedVoices.takesFolder`); Use This makes it a voice (`RecordedVoices.makeOwnVoice`), Record
/// Again throws it away. The microphone is asked for only when Record is pressed.
@MainActor
final class OwnVoiceRecorder: ObservableObject {
    static let shared = OwnVoiceRecorder()

    enum Phase: Equatable {
        case closed, ready, recording, recorded, preparing
        /// Why the take couldn't be recorded or used, in one line.
        case failed(String)
    }

    @Published private(set) var phase: Phase = .closed
    /// The meter's level, 0 to 1.
    @Published private(set) var level: Float = 0
    @Published private(set) var seconds: Double = 0
    /// The voice the last take made, to show it in the list.
    @Published private(set) var made: UUID?
    /// The take waiting for Use This or Record Again.
    private(set) var take: URL?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var starting: Task<Void, Never>?
    private var preparing: Task<Void, Never>?
    private(set) var preview = false

    var isOpen: Bool { phase != .closed }

    /// Check renders only: this phase, level and time, with no microphone.
    func setPreview(_ phase: Phase, level: Float = 0, seconds: Double = 0) {
        preview = true
        self.phase = phase
        self.level = level
        self.seconds = seconds
    }

    func open() {
        guard phase == .closed else { return }
        preview = false
        phase = .ready
    }

    /// Closes the card: a recording stops and its take goes; a take being made carries on.
    func close() {
        if phase == .preparing {
            preparing?.cancel()
            if RecordedVoices.shared.job?.kind == .prepare { RecordedVoices.shared.cancel() }
        }
        preparing = nil
        discard()
        phase = .closed
    }

    /// Studio's Voices went out of sight: a recording stops and is thrown away.
    func leave() {
        guard !preview, phase == .recording || starting != nil else { return }
        discard()
        phase = .ready
    }

    // MARK: Recording

    /// Asks for the microphone (only now, from Record), then records.
    func record() {
        guard !preview, phase != .recording, phase != .preparing else { return }
        discard()
        phase = .ready
        starting = Task { [weak self] in
            let allowed = await Self.permitted()
            guard let self, !Task.isCancelled else { return }
            self.starting = nil
            guard self.phase == .ready else { return }
            guard allowed else {
                self.phase = .failed("MacSpaces can't use the microphone. Allow it in System Settings, Privacy & Security, Microphone.")
                return
            }
            do { try self.start() } catch {
                self.phase = .failed("Recording couldn't start. Check that a microphone is connected, then Record Again.")
            }
        }
    }

    private static func permitted() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private func start() throws {
        let folder = RecordedVoices.shared.takesFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(UUID().uuidString + ".wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            try? FileManager.default.removeItem(at: url)
            throw CocoaError(.fileWriteUnknown)
        }
        self.recorder = recorder
        take = url
        level = 0
        seconds = 0
        phase = .recording
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let recorder else { return }
        recorder.updateMeters()
        level = OwnVoiceTake.level(power: recorder.averagePower(forChannel: 0), previous: level)
        seconds = recorder.currentTime
        if seconds >= OwnVoiceTake.maximumSeconds { stop() }
    }

    func stop() {
        guard let recorder else { return }
        seconds = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        timer?.invalidate(); timer = nil
        level = 0
        phase = .recorded
    }

    /// Stops any recording and deletes the take.
    private func discard() {
        starting?.cancel(); starting = nil
        if let recorder {
            recorder.stop()
            self.recorder = nil
        }
        timer?.invalidate(); timer = nil
        if let take {
            if RecordedVoices.shared.playing == take { RecordedVoices.shared.stopPlaying() }
            try? FileManager.default.removeItem(at: take)
        }
        take = nil
        level = 0
        seconds = 0
    }

    // MARK: Using it

    /// Makes the take a voice, off the main thread in the voice helper; a take that fails Siren's
    /// checks says why, for Record Again.
    func use() {
        guard !preview, phase == .recorded, let take else { return }
        if RecordedVoices.shared.playing == take { RecordedVoices.shared.stopPlaying() }
        // `makeOwnVoice` deletes the take whatever happens.
        self.take = nil
        phase = .preparing
        preparing = Task { [weak self] in
            let outcome = await RecordedVoices.shared.makeOwnVoice(from: take)
            guard let self, !Task.isCancelled, self.phase == .preparing else { return }
            self.preparing = nil
            switch outcome {
            case .made(let voice):
                self.made = voice.id
                self.phase = .closed
            case .failed(let reason):
                self.phase = .failed(reason)
            }
        }
    }
}

/// The Record My Voice card at the top of Studio's Voices list: the passage, Record and Stop with
/// the level and time, then Use This or Record Again; while the take is made, its progress; a take
/// that can't be used says why in one line.
struct StudioOwnVoiceCard: View {
    @ObservedObject var recorder: OwnVoiceRecorder
    @ObservedObject private var voices = RecordedVoices.shared
    @ObservedObject private var theme = ThemeStore.shared

    init(recorder: OwnVoiceRecorder = .shared) { self.recorder = recorder }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Record My Voice").font(.system(size: 11, weight: .semibold))
                Text("Read this aloud").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Button { recorder.close() } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(recorder.phase == .preparing ? "Stop and close" : "Close")
            }
            Text(OwnVoiceTake.passage)
                .font(.system(size: 11)).lineSpacing(2)
                .foregroundStyle(recorder.phase == .recording ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            controls
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.notch.accent.opacity(0.12), in: shape)
        .overlay { shape.strokeBorder(theme.notch.accent.opacity(recorder.phase == .recording ? 0.9 : 0.5), lineWidth: 1) }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 6) {
            switch recorder.phase {
            case .closed, .ready:
                Button { recorder.record() } label: { Label("Record", systemImage: "mic.fill") }
                    .buttonStyle(WidgetChipStyle(prominent: true, height: 22))
                    .help("Records you reading the passage. The microphone is asked for the first time.")
                Text("Somewhere quiet, a hand's width from the mic.").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            case .recording:
                Button { recorder.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(WidgetChipStyle(prominent: true, height: 22))
                StudioLevelMeter(level: recorder.level)
                Text(OwnVoiceTake.clock(recorder.seconds)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            case .recorded:
                // Check renders have no take; their button plays nothing.
                if let take = recorder.take ?? (recorder.preview ? URL(fileURLWithPath: "/nonexistent.wav") : nil) { playButton(take) }
                Text("Recorded \(OwnVoiceTake.clock(recorder.seconds))").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Button("Record Again") { recorder.record() }.buttonStyle(WidgetChipStyle(height: 22))
                Button("Use This") { recorder.use() }.buttonStyle(WidgetChipStyle(prominent: true, height: 22))
                    .help("Makes it a voice of yours, named My voice")
            case .preparing:
                VStack(alignment: .leading, spacing: 3) {
                    Text(voices.job?.kind == .prepare ? (voices.job?.stage ?? "Making your voice") : "Making your voice")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    StudioProgressBar(fraction: voices.job?.kind == .prepare ? voices.job?.fraction : nil)
                }
                Button("Stop") { recorder.close() }.buttonStyle(WidgetChipStyle(height: 22))
            case .failed(let reason):
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(.orange)
                Text(reason).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true).help(reason)
                Spacer(minLength: 0)
                Button("Record Again") { recorder.record() }.buttonStyle(WidgetChipStyle(prominent: true, height: 22))
            }
            if recorder.phase == .recording { Spacer(minLength: 0) }
        }
    }

    private func playButton(_ clip: URL) -> some View {
        let playing = voices.playing == clip
        return Button { playing ? voices.stopPlaying() : voices.play(clip) } label: {
            Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: 9))
                .foregroundStyle(playing ? theme.nookOnAccent : Color.primary)
                .frame(width: 22, height: 22)
                .background(playing ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(Color.primary.opacity(0.09)), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(playing ? "Stop" : "Listen to the take")
    }
}

/// The microphone's level as lit segments in the accent. Under Reduce Motion it has four coarse
/// segments, so it changes far less often.
struct StudioLevelMeter: View {
    var level: Float
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(level: Float) { self.level = level }

    var body: some View {
        let count = reduceMotion ? 4 : 16
        let lit = OwnVoiceTake.lit(level, of: count)
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index < lit ? theme.notch.accent : Color.primary.opacity(0.12))
            }
        }
        .frame(width: 96, height: 10)
        .accessibilityElement()
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
    }
}
