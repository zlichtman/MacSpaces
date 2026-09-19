import SwiftUI
import AVFoundation
import AppKit

/// One-tap voice recorder. Memos are saved as .m4a files in
/// ~/Documents/MacSpaces Voice Memos; the folder opens after each recording.
struct VoiceMemoWidget: View {
    @StateObject private var model = VoiceMemoModel()

    var body: some View {
        Button {
            model.toggleRecording()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(model.isRecording ? Color.red.opacity(0.25) : Color.primary.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(model.isRecording ? .red : .primary)
                }
                Text(model.isRecording ? model.elapsedText : "Record")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.isRecording ? .red : .secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDisappear { model.teardown() }
        .contextMenu {
            Button("Show Memos in Finder") { model.revealFolder() }
        }
    }
}

@MainActor
private final class VoiceMemoModel: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var desiredRecording = false
    private var generation = 0

    var elapsedText: String {
        String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
    }

    private var memosFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("MacSpaces Voice Memos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func toggleRecording() {
        isRecording ? stop(reveal: true) : requestAndStart()
    }

    private func requestAndStart() {
        desiredRecording = true
        generation += 1
        let requestGeneration = generation
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                guard self.desiredRecording,
                      self.generation == requestGeneration else { return }
                guard granted else {
                    self.desiredRecording = false
                    NSSound(named: "Basso")?.play()
                    return
                }
                self.start()
            }
        }
    }

    private func start() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = memosFolder.appendingPathComponent("Memo \(formatter.string(from: Date())).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else {
            desiredRecording = false
            NSSound(named: "Basso")?.play()
            return
        }
        self.recorder = recorder
        guard recorder.record() else {
            desiredRecording = false
            self.recorder = nil
            try? FileManager.default.removeItem(at: url)
            NSSound(named: "Basso")?.play()
            return
        }

        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsed += 1
            }
        }
    }

    private func stop(reveal: Bool) {
        desiredRecording = false
        generation += 1
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        if reveal {
            NSSound(named: "Pop")?.play()
            revealFolder()
        }
    }

    func teardown() {
        stop(reveal: false)
    }

    deinit {
        recorder?.stop()
        timer?.invalidate()
    }

    func revealFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([memosFolder])
    }
}
