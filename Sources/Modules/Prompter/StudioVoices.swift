import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Studio's Voices, left column: the recordings brought in (drop them, or +), each waiting,
/// being sorted, sorted (how many people) or not usable, with Sort and Remove; the models that
/// needs download in Settings → Tsukumo → Voice. On a Mac that can't run them it's one line
/// saying why.
struct StudioRecordingsColumn: View {
    @ObservedObject private var voices = RecordedVoices.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var targeted = false

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !voices.isAvailable {
                Text(RecordedVoiceSupport.unavailableNote).font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 6) {
                    Text("Recordings").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if voices.paused, voices.waitingRecordings > 0, !voices.isBusy {
                        Button("Sort") { voices.sortAll() }.buttonStyle(WidgetChipStyle(prominent: true, height: 20))
                            .help("Sorts the recordings waiting")
                    }
                    Button { choose() } label: { Image(systemName: "plus") }
                        .buttonStyle(WidgetChipStyle(height: 20)).disabled(!voices.canSort)
                        .help("Choose recordings: audio, or video with sound")
                }
                dropZone
                engineLine
            }
        }
    }

    private var dropZone: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Group {
            if !voices.canSort {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.badge.plus").font(.system(size: 18)).foregroundStyle(.secondary)
                    Text("Download Finding voices to sort recordings").font(.system(size: 10)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Button("Open Settings") { SettingsWindowController.shared.show(.tsukumo) }
                        .buttonStyle(WidgetChipStyle(height: 22))
                }
                .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if voices.recordings.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.badge.plus").font(.system(size: 18)).foregroundStyle(.secondary)
                    Text("Drop recordings").font(.system(size: 11, weight: .semibold))
                    Text("Several at once is fine. The same person heard in two becomes one voice.")
                        .font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Choose Files") { choose() }.buttonStyle(WidgetChipStyle(height: 22))
                }
                .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(voices.recordings) { recording in row(recording) }
                    }
                    .padding(3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Color.primary.opacity(targeted ? 0.10 : 0.04), in: shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(targeted ? 0.35 : 0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard voices.canSort else { return false }
            Task { voices.add(await Self.urls(from: providers)) }
            return true
        }
        .help("Recordings are read on this Mac and never changed or copied; only each person's clearest stretches are kept.")
    }

    private func row(_ recording: VoiceRecording) -> some View {
        let sorting = recording.state == .sorting
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: Self.symbol(recording.state)).font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(recording.state == .failed ? Color.orange : sorting ? theme.notch.accent : Color.secondary)
                    .frame(width: 12)
                VStack(alignment: .leading, spacing: 0) {
                    Text(recording.name).font(.system(size: 10, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(status(recording)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if sorting {
                    iconButton("stop.fill", help: "Stop sorting") { voices.cancel() }
                } else if recording.state != .sorted {
                    iconButton("play.fill", help: "Sort it now") { voices.sort(recording) }.disabled(voices.isBusy)
                }
                iconButton("xmark", help: recording.state == .sorted
                           ? "Remove from the list. Voices already approved keep their clips."
                           : "Remove from the list") { voices.removeRecording(recording) }
            }
            if sorting { StudioProgressBar(fraction: voices.job?.fraction) }
        }
        .padding(.horizontal, 5).padding(.vertical, 4)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(recording.note.map { recording.name + "\n" + $0 } ?? recording.name)
        .contextMenu {
            if recording.state != .sorting, recording.state != .sorted { Button("Sort Now") { voices.sort(recording) }.disabled(voices.isBusy) }
            Button("Remove", role: .destructive) { voices.removeRecording(recording) }
        }
    }

    private func status(_ recording: VoiceRecording) -> String {
        switch recording.state {
        case .waiting: return voices.paused ? "Waiting · press Sort" : "Waiting"
        case .sorting: return voices.job?.kind == .sort ? (voices.job?.stage ?? "Sorting") : "Sorting"
        case .sorted: return recording.people == 1 ? "1 person" : "\(recording.people) people"
        case .failed: return recording.note ?? "Couldn't be used"
        }
    }

    private static func symbol(_ state: VoiceRecording.State) -> String {
        switch state {
        case .waiting: "clock"
        case .sorting: "waveform"
        case .sorted: "checkmark"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                .frame(width: 16, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var engineLine: some View {
        Button { SettingsWindowController.shared.show(.tsukumo) } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu").font(.system(size: 9))
                Text(voices.engine?.modelName ?? "No voice model yet").lineLimit(1)
            }
            .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Voice models download and are chosen in Settings, Tsukumo, Voice")
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie]
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        voices.add(panel.urls)
    }

    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
            if let url { urls.append(url) }
        }
        return urls
    }
}

/// Studio's Voices, the list: every voice, those found in recordings waiting to be approved
/// (name them, Approve, which asks whose voice it is) and the approved ones (Read with it in
/// Studio, use it for the agent). Each has its clips to include or leave out, Same Person to
/// combine two, and Remove. Above them, Record My Voice (its card opens at the top of the list,
/// `StudioOwnVoiceCard`), the agent's voice and the Voices folder with its size.
struct StudioVoicesList: View {
    var onRead: (RecordedVoice) -> Void
    @ObservedObject private var voices = RecordedVoices.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var voiceStudio = VoiceStudio.shared
    @ObservedObject private var recorder = OwnVoiceRecorder.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(WidgetOptions.Keys.wispVoice) private var agentVoice = ""
    @State private var names: [UUID: String] = [:]
    @State private var macVoices: [AVSpeechSynthesisVoice] = []
    /// The voice about to be approved, waiting on whose voice it is.
    @State var asking: UUID?
    /// Voices whose clips show.
    @State var open: Set<UUID>

    init(onRead: @escaping (RecordedVoice) -> Void, asking: UUID? = nil, open: Set<UUID> = []) {
        self.onRead = onRead
        _asking = State(initialValue: asking)
        _open = State(initialValue: open)
    }

    private var agent: String { WispCharacter.current.title }

    /// Waiting voices first (they need you), then the approved ones, oldest first.
    private var ordered: [RecordedVoice] { voices.voices.filter { !$0.isApproved } + voices.ready }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollViewReader { scroller in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        if recorder.isOpen, voices.isAvailable { StudioOwnVoiceCard(recorder: recorder) }
                        if let problem = voices.problem {
                            Text(problem).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true).help(problem)
                        }
                        if voices.voices.isEmpty, !recorder.isOpen {
                            Text(voices.isAvailable
                                 ? "Drop recordings of someone talking: voice memos, podcasts or videos, or Record My Voice. Each person heard is listed here to name and approve, then reads your scripts."
                                 : "Voices from recordings can't be made on this Mac. Read uses the Mac's voices and your Personal Voice.")
                                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(ordered) { voice in
                            Group {
                                if asking == voice.id { consent(voice) } else { voiceRow(voice) }
                            }
                            .id(voice.id)
                            if open.contains(voice.id) { clips(voice) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // The voice a take just made, shown where it landed.
                .onChange(of: recorder.made) { made in
                    guard let made else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { scroller.scrollTo(made, anchor: .center) }
                }
            }
        }
        .onAppear {
            macVoices = WispVoices.choices()
            voices.refreshSize()
        }
        .onDisappear { recorder.leave() }
        .onChange(of: voiceStudio.voicesChanged) { _ in macVoices = WispVoices.choices() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Voices").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if voices.waiting > 0 {
                Text("\(voices.waiting) to approve").font(.system(size: 10)).foregroundStyle(theme.notch.accent).lineLimit(1)
            }
            Spacer(minLength: 4)
            if voices.isAvailable {
                Button { recorder.isOpen ? recorder.close() : recorder.open() } label: {
                    // The words, or just the microphone when the header is full.
                    ViewThatFits(in: .horizontal) {
                        Label("Record My Voice", systemImage: "mic").lineLimit(1).fixedSize()
                        Image(systemName: "mic")
                    }
                    .accessibilityLabel("Record My Voice")
                }
                .buttonStyle(WidgetChipStyle(prominent: recorder.isOpen, height: 22))
                .disabled(!voices.canSort && !recorder.isOpen)
                .help(voices.canSort ? "Read a short passage aloud to make a voice of your own"
                                     : "Download Finding voices in Settings, Tsukumo, Voice first")
            }
            NookMenu { agentMenu } label: {
                HStack(spacing: 3) {
                    Text("\(agent): \(StudioPage.short(agentVoiceName, 12))").lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                }
                .fixedSize()
            }
            .buttonStyle(WidgetChipStyle(height: 22))
            .help("The voice \(agent) answers in, in voice mode")
            Button { voices.showInFinder() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "folder")
                    if let bytes = voices.folderBytes { Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
                }
            }
            .buttonStyle(WidgetChipStyle(height: 22))
            .help("Show the Voices folder in the Finder: the voices' clips and the voice models")
        }
    }

    private var agentVoiceName: String {
        if agentVoice.isEmpty { return "Automatic" }
        if let voice = voices.voice(id: agentVoice) { return voice.name }
        return AVSpeechSynthesisVoice(identifier: agentVoice)?.name ?? "Automatic"
    }

    @ViewBuilder
    private var agentMenu: some View {
        NookMenuHeading("\(agent)'s voice")
        NookMenuRow("Automatic", selected: agentVoice.isEmpty) { agentVoice = "" }
        if voices.isAvailable, !voices.ready.isEmpty {
            NookMenuDivider()
            NookMenuHeading("From recordings")
            ForEach(voices.ready) { voice in
                NookMenuRow(voice.name, systemImage: "waveform", selected: agentVoice == voice.voiceID) { agentVoice = voice.voiceID }
                    .disabled(voices.engine == nil)
            }
        }
        NookMenuDivider()
        NookMenuHeading("This Mac")
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(macVoices, id: \.identifier) { voice in
                    NookMenuRow(WispVoices.label(voice), selected: agentVoice == voice.identifier) { agentVoice = voice.identifier }
                }
            }
        }
        .frame(width: 250, height: min(CGFloat(macVoices.count) * 28, 196))
        if voiceStudio.personalVoiceStatus == .notAsked {
            NookMenuRow("Use My Personal Voice", systemImage: "person.crop.circle") { voiceStudio.requestPersonalVoice() }
        }
    }

    // MARK: A voice

    private func name(for voice: RecordedVoice) -> Binding<String> {
        Binding(get: { names[voice.id] ?? voice.name }, set: { names[voice.id] = $0 })
    }

    private func voiceRow(_ voice: RecordedVoice) -> some View {
        let isAgent = agentVoice == voice.voiceID
        let alike = voice.isApproved ? nil : voices.soundsLike(voice)
        return row(highlighted: !voice.isApproved) {
            playButton(voice.clip(in: voices.root))
            VStack(alignment: .leading, spacing: 2) {
                NookTextField("Name", text: name(for: voice), height: 22)
                    .onSubmit { commitRename(voice) }
                    .help("Rename: type and press Return")
                HStack(spacing: 4) {
                    Text(line(voice, isAgent: isAgent)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                        .help("“\(voice.transcript)”")
                    if let alike {
                        Button("Same person as \(StudioPage.short(alike.name, 14))?") { voices.combine(voice, with: alike) }
                            .buttonStyle(.plain).font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.notch.accent)
                            .lineLimit(1)
                            .help("They sound alike. Combines them into one voice.")
                    }
                }
            }
            Button { toggleOpen(voice) } label: {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(open.contains(voice.id) ? 90 : 0))
                    .frame(width: 18, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help(open.contains(voice.id) ? "Hide its clips" : "Its clips: choose which it copies")
            if voice.isApproved {
                Button("Read") { commitRename(voice); onRead(voice) }
                    .buttonStyle(WidgetChipStyle(prominent: true, height: 22))
                    .disabled(voices.engine == nil)
                    .help(voices.engine == nil ? "Download a voice model in Settings, Tsukumo, Voice first" : "Read your scripts in \(voice.name)'s voice")
            } else {
                Button("Approve") { asking = voice.id }
                    .buttonStyle(WidgetChipStyle(prominent: true, height: 22))
                    .help("Says whose voice it is, so it can read")
            }
            NookMenu { voiceMenu(voice, isAgent: isAgent) } label: { Image(systemName: "ellipsis") }
                .buttonStyle(WidgetChipStyle(height: 22))
        }
    }

    private func line(_ voice: RecordedVoice, isAgent: Bool) -> String {
        let clips = voice.clips
        var parts = [clips.count == 1 ? "1 clip" : "\(clips.count) clips"]
        if voice.recordingCount > 1 { parts.append("\(voice.recordingCount) recordings") }
        if voice.isApproved {
            switch voice.consent {
            case "mine": parts.append("Yours")
            case "permission": parts.append("With their yes")
            default: parts.append("Saved")
            }
            let extra = voice.availableDeliveries.filter { $0 != .natural }.map(\.title)
            if !extra.isEmpty { parts.append(extra.joined(separator: ", ")) }
            if isAgent { parts.append("\(agent)'s voice") }
        } else {
            parts.insert("To approve", at: 0)
            if let name = clips.first?.recordingName { parts.append(name) }
        }
        return parts.joined(separator: " · ")
    }

    private func toggleOpen(_ voice: RecordedVoice) {
        if open.contains(voice.id) { open.remove(voice.id) } else { open.insert(voice.id) }
    }

    @ViewBuilder
    private func voiceMenu(_ voice: RecordedVoice, isAgent: Bool) -> some View {
        if voice.isApproved {
            if isAgent {
                NookMenuRow("Stop Using for \(agent)", systemImage: "person.wave.2") { agentVoice = "" }
            } else {
                NookMenuRow("Use for \(agent)", systemImage: "person.wave.2") { agentVoice = voice.voiceID }
                    .disabled(voices.engine == nil)
            }
            NookMenuDivider()
        }
        let others = voices.voices.filter { $0.id != voice.id }
        if !others.isEmpty {
            NookMenuHeading("Same person as")
            ForEach(others) { other in
                NookMenuRow(other.name, systemImage: "person.2") { voices.combine(voice, with: other) }
            }
            NookMenuDivider()
        }
        NookMenuRow("Remove Voice", systemImage: "trash", destructive: true) { voices.delete(voice) }
    }

    private func commitRename(_ voice: RecordedVoice) {
        guard let name = names[voice.id] else { return }
        voices.rename(voice, to: name)
        names[voice.id] = nil
    }

    /// Siren's question before a voice can read, in the row itself.
    private func consent(_ voice: RecordedVoice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Whose voice is \(name(for: voice).wrappedValue)?").font(.system(size: 11, weight: .semibold))
            Text("Make a voice only from your own, or from someone who has said you may.")
                .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Button("Mine") { approve(voice, consent: "mine") }.buttonStyle(WidgetChipStyle(prominent: true, height: 22))
                Button("Someone Else's, Who Said Yes") { approve(voice, consent: "permission") }
                    .buttonStyle(WidgetChipStyle(height: 22))
                Button("Cancel") { asking = nil }.buttonStyle(WidgetChipStyle(height: 22))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.notch.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.notch.accent.opacity(0.5), lineWidth: 1) }
    }

    private func approve(_ voice: RecordedVoice, consent: String) {
        voices.approve(voice, name: name(for: voice).wrappedValue, consent: consent)
        names[voice.id] = nil
        asking = nil
    }

    // MARK: Its clips

    /// The voice's clips: each delivery reads one included clip, Use First's or the one picked.
    private func clips(_ voice: RecordedVoice) -> some View {
        let clips = voice.clips
        let used = Set(VoiceDelivery.allCases.compactMap { VoiceSamples.reference(clips, for: $0) })
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(clips.enumerated()), id: \.element.id) { index, sample in
                HStack(spacing: 6) {
                    Button { voices.setIncluded(sample, in: voice, !sample.included) } label: {
                        Image(systemName: sample.included ? "checkmark.square.fill" : "square").font(.system(size: 12))
                            .foregroundStyle(sample.included ? theme.notch.accent : Color.secondary)
                            .frame(width: 18, height: 20).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(sample.included && !VoiceSamples.canExclude(clips, at: index))
                    .help(sample.included ? "Leave this clip out" : "Include this clip")
                    playButton(voice.file(sample, in: voices.root))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(clipLine(sample, used: used.contains(index))).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                        Text(sample.transcript).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .help("“\(sample.transcript)”")
                    Spacer(minLength: 0)
                    NookMenu { clipMenu(sample, index: index, in: voice) } label: {
                        Image(systemName: "ellipsis").font(.system(size: 10, weight: .semibold))
                            .frame(width: 14, height: 20).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .opacity(sample.included ? 1 : 0.6)
            }
            Text("Each delivery reads its clearest checked clip, or the one you Use First.")
                .font(.system(size: 9)).foregroundStyle(.secondary).padding(.horizontal, 6)
        }
        .padding(.leading, 22).padding(.vertical, 2)
    }

    private func clipLine(_ sample: VoiceSamples.Sample, used: Bool) -> String {
        var parts = [sample.delivery.title, "\(Int(sample.seconds.rounded())) s", sample.recordingName ?? "Earlier recording"]
        if used { parts.append("In use") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func clipMenu(_ sample: VoiceSamples.Sample, index: Int, in voice: RecordedVoice) -> some View {
        if sample.pinned == true {
            NookMenuRow("Choose Automatically", systemImage: "wand.and.stars") { voices.chooseAutomatically(sample, in: voice) }
        } else {
            NookMenuRow("Use First", systemImage: "arrow.up.to.line") { voices.useFirst(sample, in: voice) }
        }
        NookMenuRow("Not the Same Person", systemImage: "person.badge.minus") { voices.separate(sample, from: voice) }
            .disabled(voice.clips.count < 2)
        NookMenuDivider()
        NookMenuRow("Delete Clip", systemImage: "trash", destructive: true) { voices.deleteClip(sample, from: voice) }
            .disabled(voice.clips.count < 2)
    }

    // MARK: Pieces

    private func row<Content: View>(highlighted: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) { content() }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(highlighted ? theme.notch.accent.opacity(0.10) : Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .help(playing ? "Stop" : "Play the clip")
    }
}

/// A thin bar in the accent: how far a voice job is, or, with no fraction yet, a short piece
/// sliding along it (still under Reduce Motion).
struct StudioProgressBar: View {
    var fraction: Double?
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(fraction: Double?) { self.fraction = fraction }

    var body: some View {
        GeometryReader { box in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                if let fraction, fraction > 0 {
                    Capsule().fill(theme.notch.accent).frame(width: max(4, box.size.width * min(1, fraction)))
                } else if reduceMotion {
                    Capsule().fill(theme.notch.accent.opacity(0.6)).frame(width: box.size.width * 0.3)
                } else {
                    TimelineView(.periodic(from: .now, by: 1.0 / 30)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        Capsule().fill(theme.notch.accent).frame(width: box.size.width * 0.3)
                            .offset(x: (box.size.width * 1.3) * phase - box.size.width * 0.3)
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(fraction.map { "\(Int(($0 * 100).rounded())) percent" } ?? "Working")
    }
}
