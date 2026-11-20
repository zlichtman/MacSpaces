import AVFoundation
import SwiftUI

/// Which part of Studio shows: the scripts with their takes and the teleprompter, the voices,
/// or Dictate (speak, edit, copy or paste: what the Dictation page did).
enum StudioSection: String, CaseIterable, Identifiable {
    case scripts, voices, dictate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .scripts: "Scripts"
        case .voices: "Voices"
        case .dictate: "Dictate"
        }
    }
}

/// The Studio page (`NotchTab.prompter`): your scripts on the left; the selected one to edit,
/// with Read (the selected words, else the whole script, in the chosen voice) and Prompt (the
/// teleprompter under the camera); and its takes on the right. Voices shows the recordings
/// brought in and the voices made from them. Dictate is on-device dictation. Studio lives only in
/// the Nook.
struct StudioPage: View {
    @ObservedObject var prompter: ScriptPrompter
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var studio = StudioModel.shared
    @ObservedObject private var recorded = RecordedVoices.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var voiceStudio = VoiceStudio.shared
    @State var selection: NSRange?
    @State private var macVoices: [AVSpeechSynthesisVoice] = []
    @FocusState private var titleFocused: Bool
    @State private var typing = false
    @State private var dictating = false

    init(prompter: ScriptPrompter, selection: NSRange? = nil,
         onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.prompter = prompter
        self.onEditingChanged = onEditingChanged
        _selection = State(initialValue: selection)
    }

    private var section: StudioSection { studio.section }

    private var takesWidth: CGFloat { 176 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                sectionSwitch
                switch section {
                case .scripts: library
                case .voices: StudioRecordingsColumn()
                case .dictate: StudioDictationColumn(model: .shared)
                }
            }
            .frame(width: 136)
            switch section {
            case .scripts:
                scriptArea
            case .voices:
                StudioVoicesList(onRead: { voice in
                    studio.voiceID = voice.voiceID
                    studio.section = .scripts
                })
            case .dictate:
                StudioDictation(model: .shared, prompter: prompter, onEditingChanged: { dictating = $0 })
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            studio.show(scriptID: prompter.selected?.id)
            macVoices = WispVoices.choices()
        }
        .onChange(of: prompter.selected?.id) { id in
            studio.show(scriptID: id)
            selection = nil
        }
        .onChange(of: voiceStudio.voicesChanged) { _ in macVoices = WispVoices.choices() }
        .onChange(of: titleFocused) { _ in onEditingChanged(titleFocused || typing || dictating) }
        .onChange(of: typing) { _ in onEditingChanged(titleFocused || typing || dictating) }
        .onChange(of: dictating) { _ in onEditingChanged(titleFocused || typing || dictating) }
        .onDisappear { onEditingChanged(false) }
    }

    private var sectionSwitch: some View {
        HStack(spacing: 3) {
            ForEach(StudioSection.allCases) { item in
                Button { studio.section = item } label: {
                    // Shrinks a little rather than truncating ("Voice…" when bold in the 136 pt column);
                    // voices waiting to be approved show as a dot, not a number that wouldn't fit.
                    Text(item.title)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WidgetChipStyle(prominent: section == item, height: 22))
                .overlay(alignment: .topTrailing) {
                    if item == .voices, recorded.waiting > 0 {
                        Circle().fill(Color.orange).frame(width: 6, height: 6).offset(x: -2, y: 2)
                            .accessibilityLabel("\(recorded.waiting) waiting")
                    }
                }
                .help(item == .voices && recorded.waiting > 0 ? "\(recorded.waiting) voices waiting to be approved" : item.title)
            }
        }
    }

    // MARK: Scripts

    private var library: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(prompter.scripts.count == 1 ? "1 script" : "\(prompter.scripts.count) scripts")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button { prompter.importFiles() } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(WidgetChipStyle(height: 22)).help("Import text, Markdown, RTF or Word files")
                Button { prompter.newScript() } label: { Image(systemName: "plus") }
                    .buttonStyle(WidgetChipStyle(height: 22)).help("New script")
            }
            if let problem = prompter.libraryProblem {
                VStack(alignment: .leading, spacing: 6) {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Button("Start New Library") { prompter.startNewLibrary() }
                        .buttonStyle(WidgetChipStyle(height: 22))
                        .help("Keeps the unreadable file beside it, renamed, and saves scripts from now on")
                }
                .padding(8).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(prompter.scripts) { script in
                        let selected = script.id == prompter.selected?.id
                        Button { prompter.selectedID = script.id } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(script.title.isEmpty ? "Untitled script" : script.title)
                                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(minutes(script.text)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(selected ? theme.notch.accent.opacity(0.18) : Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Delete Script and Its Takes", role: .destructive) { prompter.delete(script) } }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var scriptArea: some View {
        if let script = prompter.selected {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    titleRow(script)
                    StudioTextEditor(text: Binding(get: { script.text }, set: { var s = script; s.text = $0; prompter.update(s) }),
                                     selection: $selection, highlight: highlight(script), accent: theme.notch.accent,
                                     ink: theme.nookForeground, fontSize: 13,
                                     onEditingChanged: { typing = $0 })
                        .padding(4)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    readBar(script)
                }
                .frame(maxWidth: .infinity)
                takesColumn(script).frame(width: takesWidth)
            }
        } else {
            Text("Press + to write a script.").font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The words being read, while their take is made.
    private func highlight(_ script: ScriptPrompter.Script) -> NSRange? {
        guard let making = studio.making, making.scriptID == script.id else { return nil }
        return making.range
    }

    private func titleRow(_ script: ScriptPrompter.Script) -> some View {
        HStack(spacing: 6) {
            TextField("Title", text: Binding(get: { script.title }, set: { var s = script; s.title = $0; prompter.update(s) }))
                .textFieldStyle(.plain).font(.system(size: 15, weight: .bold))
                .focused($titleFocused)
            Spacer(minLength: 4)
            NookMenu { prompterOptions } label: { Image(systemName: "text.alignleft") }
                .buttonStyle(WidgetChipStyle(height: 22))
                .help("Teleprompter: how it scrolls, its text size and the countdown")
            Button(prompter.isShowing ? "Stop" : "Prompt") {
                prompter.isShowing ? prompter.close() : prompter.start()
            }
            .buttonStyle(WidgetChipStyle(prominent: prompter.isShowing, height: 22))
            .disabled(script.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Read it yourself, just under the camera. Hidden from screen sharing and recordings.")
        }
    }

    @ViewBuilder
    private var prompterOptions: some View {
        NookMenuHeading("Teleprompter")
        ForEach(ScriptPrompter.Mode.allCases) { mode in
            NookMenuRow(mode.title, selected: prompter.mode == mode) { prompter.mode = mode }
        }
        NookMenuDivider()
        NookMenuHeading("Text size")
        ForEach(ScriptPrompter.TextSize.allCases) { size in
            NookMenuRow(size.title, selected: prompter.textSize == size) { prompter.textSize = size }
        }
        NookMenuDivider()
        NookMenuToggle("Count down 3-2-1", isOn: $prompter.countdown)
        if prompter.mode == .scroll {
            NookMenuHeading("Scroll speed")
            HStack(spacing: 6) {
                Slider(value: $prompter.speed, in: 60...260, step: 10)
                Text("\(Int(prompter.speed)) wpm").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).frame(width: 220)
        }
        Text(prompter.mode == .voice
             ? "Follows your voice with on-device speech recognition; the microphone is asked for the first time."
             : "Space pauses, ← → move a line, ↑ ↓ change speed, Esc closes.")
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .frame(width: 220, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func readBar(_ script: ScriptPrompter.Script) -> some View {
        let readsSelection = StudioTakes.readsSelection(script.text, selection: selection)
        let makingHere = studio.making?.scriptID == script.id
        return HStack(spacing: 6) {
            NookMenu(arrowEdge: .top) { voiceMenu } label: {
                HStack(spacing: 4) {
                    Image(systemName: voiceSymbol).font(.system(size: 10, weight: .semibold))
                    Text(Self.short(studio.voice.name, 12)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                }
                .fixedSize()
            }
            .buttonStyle(WidgetChipStyle(height: 24))
            .help("The voice Read uses")
            NookMenu(arrowEdge: .top) { readOptions } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(WidgetChipStyle(height: 24))
            .help("Delivery, quality, pace, and a style for the Expressive engine")
            Spacer(minLength: 0)
            if makingHere {
                Button("Stop") { studio.stop() }.buttonStyle(WidgetChipStyle(height: 24))
            } else {
                // Never truncated: the voice chip gives way first ("Read S…" was clipped at the Nook's width).
                Button(readsSelection ? "Read Selection" : "Read") {
                    studio.read(StudioTakes.reading(script.text, selection: selection),
                                range: readsSelection ? selection : nil, scriptID: script.id)
                }
                .buttonStyle(WidgetChipStyle(prominent: true, height: 24))
                .fixedSize()
                .layoutPriority(1)
                .disabled(script.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || studio.isMaking)
                .help("Reads the selected words, or the whole script, in \(studio.voice.name). Each reading is a take.")
            }
        }
    }

    static func short(_ name: String, _ limit: Int) -> String {
        name.count > limit ? String(name.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…" : name
    }

    private var isRecorded: Bool {
        if case .recorded = studio.voice { return true }
        return false
    }

    private var voiceSymbol: String {
        if case .recorded = studio.voice { return "waveform" }
        return "person.wave.2"
    }

    @ViewBuilder
    private var voiceMenu: some View {
        if recorded.isAvailable {
            NookMenuHeading("From recordings")
            if recorded.ready.isEmpty {
                NookMenuRow("Add a Voice", systemImage: "plus") { studio.section = .voices }
            } else {
                ForEach(recorded.ready) { voice in
                    NookMenuRow(voice.name, systemImage: "waveform", selected: studio.voiceID == voice.voiceID) {
                        studio.voiceID = voice.voiceID
                    }
                    .disabled(recorded.engine == nil)
                }
                if recorded.engine == nil {
                    NookMenuRow("Download a Voice Model", systemImage: "arrow.down.circle") {
                        SettingsWindowController.shared.show(.tsukumo)
                    }
                }
            }
            NookMenuDivider()
        }
        NookMenuHeading("This Mac")
        NookMenuRow("Automatic", selected: studio.voiceID.isEmpty) { studio.voiceID = "" }
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(macVoices, id: \.identifier) { voice in
                    NookMenuRow(WispVoices.label(voice), selected: studio.voiceID == voice.identifier) {
                        studio.voiceID = voice.identifier
                    }
                }
            }
        }
        .frame(width: 250, height: min(CGFloat(macVoices.count) * 28, 196))
        if voiceStudio.personalVoiceStatus == .notAsked {
            NookMenuRow("Use My Personal Voice", systemImage: "person.crop.circle") { voiceStudio.requestPersonalVoice() }
        }
    }

    @ViewBuilder
    private var readOptions: some View {
        NookMenuHeading("Delivery")
        if studio.deliveries.count > 1 {
            ForEach(studio.deliveries) { delivery in
                NookMenuRow(delivery.title, selected: studio.readingDelivery == delivery) { studio.delivery = delivery }
            }
        } else {
            Text(isRecorded
                 ? "This voice has one clip. Recordings with more of them talking can add Slow and Soft and Upbeat."
                 : "Voices from recordings can read Natural, Slow and Soft or Upbeat, from different clips of them.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 230, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8).padding(.bottom, 4)
        }
        NookMenuDivider()
        NookMenuHeading("Quality")
        if isRecorded {
            NookMenuRow("Fast", selected: !studio.bestQuality) { studio.bestQuality = false }
            NookMenuRow("Best Quality", selected: studio.bestQuality) { studio.bestQuality = true }
                .help("Makes up to three takes of each sentence and keeps the one most like the voice. Takes up to three times as long.")
        } else {
            Text("Best Quality needs a voice from recordings.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 230, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8).padding(.bottom, 4)
        }
        NookMenuDivider()
        NookMenuHeading("Pace")
        HStack(spacing: 6) {
            Slider(value: $studio.pace, in: StudioTakes.paces, step: StudioTakes.paceStep)
            Text(String(format: "%.2f×", studio.pace)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).frame(width: 230)
        NookMenuDivider()
        NookMenuHeading("Style")
        if studio.followsStyle {
            ForEach(StudioTakes.styles, id: \.self) { chip in
                NookMenuRow(chip, selected: studio.style.lowercased() == chip.lowercased()) {
                    studio.style = StudioTakes.toggled(studio.style, chip: chip)
                }
            }
            NookTextField("Or your own direction", text: $studio.style, height: 24).frame(width: 230).padding(.horizontal, 4)
        } else {
            Text("Styles need a voice from recordings and the Expressive engine (CosyVoice 3), in Settings, Tsukumo, Voice.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 230, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8).padding(.bottom, 4)
        }
    }

    /// Check renders: the menus' contents as they show in their popovers.
    var menuPanels: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) { voiceMenu }.padding(6).fixedSize()
            VStack(alignment: .leading, spacing: 2) { readOptions }.padding(6).fixedSize()
            VStack(alignment: .leading, spacing: 2) { prompterOptions }.padding(6).fixedSize()
        }
    }

    // MARK: Takes

    private func takesColumn(_ script: ScriptPrompter.Script) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Takes").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                if !studio.takes.isEmpty {
                    Text("\(studio.takes.count)").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer()
                NookMenu { takesMenu } label: { Image(systemName: "ellipsis") }
                    .buttonStyle(WidgetChipStyle(height: 22))
                    .disabled(studio.takes.isEmpty)
            }
            if let problem = studio.problem {
                Text(problem).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true).help(problem)
            }
            if let making = studio.making, making.scriptID == script.id { makingRow(making) }
            if studio.takes.isEmpty, studio.making?.scriptID != script.id {
                Text("Select words, or none for the whole script, and press Read. Each reading is a take: read again for another, star the best.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(studio.takes) { take in takeRow(take) }
                }
            }
        }
    }

    @ViewBuilder
    private var takesMenu: some View {
        NookMenuRow("Keep Starred, Delete the Rest", systemImage: "star") { studio.keepStarred() }
            .disabled(!studio.takes.contains(where: \.starred) || studio.takes.allSatisfy(\.starred))
        NookMenuDivider()
        NookMenuRow("Delete All Takes", systemImage: "trash", destructive: true) { studio.deleteAll() }
    }

    private func makingRow(_ making: StudioModel.Making) -> some View {
        let job = making.recorded ? recorded.job : nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.notch.accent)
                Text("Reading in \(making.voiceName)").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Button { studio.stop() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Stop")
            }
            StudioProgressBar(fraction: job.map(\.fraction))
            Text(job?.stage ?? "Speaking").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(7)
        .background(theme.notch.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func takeRow(_ take: StudioTake) -> some View {
        let playing = studio.playing == take.id
        let number = StudioTakes.number(of: take, in: studio.takes)
        let words = take.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? take.text
        return HStack(spacing: 6) {
            Button { playing ? studio.stopPlaying() : studio.play(take) } label: {
                Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: 9))
                    .foregroundStyle(playing ? theme.nookOnAccent : Color.primary)
                    .frame(width: 22, height: 22)
                    .background(playing ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(Color.primary.opacity(0.09)), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(playing ? "Stop" : "Play")
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("Take \(number)").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(take.voiceName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(Self.rowLine(take, words: words))
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { studio.toggleStar(take) } label: {
                Image(systemName: take.starred ? "star.fill" : "star").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(take.starred ? theme.notch.accent : Color.secondary)
                    .frame(width: 16, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(take.starred ? "Unstar" : "Star the best take")
            NookMenu { takeMenu(take) } label: {
                Image(systemName: "ellipsis").font(.system(size: 10, weight: .semibold))
                    .frame(width: 14, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(take.starred ? theme.notch.accent.opacity(0.14) : Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(details(take))
        .contextMenu {
            Button("Another Take") { studio.again(take) }.disabled(studio.isMaking)
            Button("Save to Tray") { studio.saveToTray(take) }
            Button("Save as File") { studio.saveAs(take) }
            Divider()
            Button("Delete Take", role: .destructive) { studio.delete(take) }
        }
    }

    @ViewBuilder
    private func takeMenu(_ take: StudioTake) -> some View {
        NookMenuRow("Another Take", systemImage: "arrow.clockwise") { studio.again(take) }.disabled(studio.isMaking)
        NookMenuRow("Save to Tray", systemImage: "tray.and.arrow.down") { studio.saveToTray(take) }
        NookMenuRow("Save as File", systemImage: "square.and.arrow.down") { studio.saveAs(take) }
        NookMenuDivider()
        NookMenuRow("Delete Take", systemImage: "trash", destructive: true) { studio.delete(take) }
    }

    /// A take's second line: its length, its delivery when not Natural, Best Quality, and its first words.
    static func rowLine(_ take: StudioTake, words: String) -> String {
        var parts = [StudioTakes.duration(take.seconds)]
        if let delivery = take.delivery.flatMap(VoiceDelivery.init(rawValue:)) { parts.append(delivery.title) }
        if take.bestQuality == true { parts.append("Best Quality") }
        parts.append(words)
        return parts.joined(separator: " · ")
    }

    private func details(_ take: StudioTake) -> String {
        let engine = take.engine.map { ", " + $0 } ?? ""
        var parts = ["“\(take.text)”", take.voiceName + engine]
        if let delivery = take.delivery.flatMap(VoiceDelivery.init(rawValue:)) { parts.append(delivery.title) }
        if take.bestQuality == true { parts.append("Best Quality") }
        if let style = take.style { parts.append("Style: \(style)") }
        if abs(take.pace - 1) > 0.001 { parts.append(String(format: "Pace %.2f×", take.pace)) }
        if let seed = take.seed { parts.append("Seed \(seed)") }
        return parts.joined(separator: "\n")
    }

    private func minutes(_ text: String) -> String {
        let count = text.split(whereSeparator: \.isWhitespace).count
        let minutes = Double(count) / max(prompter.speed, 1)
        return count == 0 ? "Empty" : "\(count) words · \(minutes < 1 ? "under a minute" : "\(Int(minutes.rounded())) min")"
    }
}
