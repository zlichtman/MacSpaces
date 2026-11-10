import AppKit
import SwiftUI

/// Settings → Tsukumo → Voice: the voice models with Download and Remove, in a drawer, and a link
/// to Studio, where recordings come in, voices are named, approved and kept, the agent's voice is
/// chosen and dictation lives. On a Mac that can't run the models the drawer is one line saying
/// why. Nothing downloads and no permission is asked until Download is pressed.
struct RecordedVoicesSettings: View {
    let agent: String
    @ObservedObject private var voices = RecordedVoices.shared
    @AppStorage(WidgetOptions.Keys.voicesEngine) private var engineID = ""
    /// A drawer, closed to save space; it opens by itself while a download runs.
    @AppStorage(WidgetOptions.Keys.recordedVoicesDrawer) private var drawerOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            studio
            SettingsDisclosure("Voice models", detail: downloadedNote,
                               isOpen: Binding(get: { drawerOpen || isDownloading }, set: { drawerOpen = $0 })) {
                if voices.isAvailable {
                    models
                    if let problem = voices.problem { SettingsCaption(problem, colour: .red) }
                } else {
                    SettingsCaption(RecordedVoiceSupport.unavailableNote)
                }
            }
        }
        .onAppear { if voices.isAvailable { voices.refreshModels() } }
    }

    private var downloadedNote: String {
        switch voices.downloaded.count {
        case 0: ""
        case 1: "1 downloaded"
        case let count: "\(count) downloaded"
        }
    }

    private var isDownloading: Bool { if case .download = voices.job?.kind { true } else { false } }

    // MARK: Models

    private var models: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(VoiceModel.catalogue) { model in modelRow(model) }
            SettingsCaption("Models download from Hugging Face. Without one, the Mac's voices keep working.",
                            help: "Models download from Hugging Face and stay in Application Support. Without one, the Mac's voices keep working.")
        }
    }

    private func modelRow(_ model: VoiceModel) -> some View {
        let state = voices.state(model)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(model.title).font(.system(size: 13))
                    Text(model.modelName + " · " + Self.size(state, model)).font(.caption).foregroundStyle(.secondary)
                }
                Text(model.goodAt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .help("\(model.goodAt) \(model.licence). Uses up to about \(String(format: "%.0f", model.peakGB.rounded(.up))) GB of memory while it runs, in its own process.")
            Spacer(minLength: 8)
            if voices.job?.kind == .download(model.id), let job = voices.job {
                Text("\(job.stage) \(Int((job.fraction * 100).rounded()))%").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button("Stop") { voices.cancel() }.buttonStyle(.settings(.secondary))
            } else if state.isDownloaded {
                if model.speaks {
                    if voices.engine == model {
                        Text("In use").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Use") { voices.useEngine(model); engineID = model.id }
                            .buttonStyle(.settings(.secondary))
                            .help("Voices from recordings speak with \(model.title)")
                    }
                }
                if voices.lacksExtras(model) {
                    Button("Update") { voices.download(model) }
                        .buttonStyle(.settings(.secondary))
                        .disabled(voices.isBusy)
                        .help("Adds noise reduction for the clips it cuts (DeepFilterNet, 26 MB)")
                }
                SettingsRemoveButton(label: "Remove the download") { voices.remove(model) }
                    .disabled(voices.isBusy)
            } else {
                Button(Self.isPartial(state) ? "Resume" : "Download") { voices.download(model) }
                    .buttonStyle(.settings(model == .sorting ? .primary : .secondary))
                    .disabled(voices.isBusy)
            }
        }
    }

    private static func isPartial(_ state: VoiceModelStore.State) -> Bool { if case .partial = state { true } else { false } }

    private static func size(_ state: VoiceModelStore.State, _ model: VoiceModel) -> String {
        let format = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        switch state {
        case .downloaded(let bytes): return format(bytes) + " on this Mac"
        case .partial(let bytes): return format(bytes) + " of " + format(model.downloadBytes)
        case .notDownloaded: return format(model.downloadBytes)
        }
    }

    // MARK: Studio

    /// Recordings, voices and the agent's voice are in Studio's Voices; this card keeps only the
    /// models.
    private var studio: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.and.mic").font(.system(size: 16)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Voices and \(agent)'s voice are in Studio").font(.system(size: 13))
                Text(Self.studioLine(voices: voices.ready.count, waiting: voices.waiting))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Open Studio") { StudioModel.shared.section = .voices; NookCommands.open(.prompter) }
                .buttonStyle(.settings(.secondary))
                .help("Opens the Nook on Studio's Voices: recordings, voices and \(agent)'s voice")
        }
    }

    private static func studioLine(voices: Int, waiting: Int) -> String {
        var parts = [voices == 0 ? "No voices from recordings yet" : voices == 1 ? "1 voice" : "\(voices) voices"]
        if waiting > 0 { parts.append(waiting == 1 ? "1 to approve" : "\(waiting) to approve") }
        return parts.joined(separator: " · ")
    }
}
