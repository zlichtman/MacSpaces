import SwiftUI

/// Studio's Dictate, left column: Start or Stop, what it's doing, and where Paste goes. The
/// dictation itself is `DictationModel` (explicit Start, on-device recognition only, no audio kept).
struct StudioDictationColumn: View {
    @ObservedObject var model: DictationModel
    @ObservedObject private var theme = ThemeStore.shared

    private var active: Bool { model.listening || model.starting }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { active ? model.stop() : model.start() } label: {
                VStack(spacing: 6) {
                    Image(systemName: model.listening ? "waveform" : "mic.fill").font(.system(size: 22))
                        .foregroundStyle(active ? theme.nookOnAccent : theme.notch.accent)
                    Text(active ? "Stop" : "Start").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(active ? theme.nookOnAccent : Color.primary)
                }
                .frame(maxWidth: .infinity).frame(height: 84)
                .background(active ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(theme.notch.accent.opacity(0.12)),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(active ? "Stop listening" : "Start dictation: speak, then edit and paste")
            Text(model.listening ? "Listening on this Mac" : model.starting ? "Waiting for access" : "Speak, edit, then paste.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let app = model.target?.localizedName {
                Text("Paste goes to \(app)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Text("On-device · Audio isn't saved").font(.system(size: 9)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Studio's Dictate, the transcript: type or edit it, then Clear, Save as Script, Copy or Paste
/// (into the app in front when the Nook opened).
struct StudioDictation: View {
    @ObservedObject var model: DictationModel
    @ObservedObject var prompter: ScriptPrompter
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @FocusState private var editing: Bool

    private var active: Bool { model.listening || model.starting }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text(model.listening ? "Your words appear here" : "Your transcript appears here. You can also type or edit it.")
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
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2).help(problem)
            }
            HStack(spacing: 6) {
                Button("Clear") { model.text = "" }.disabled(active || model.text.isEmpty)
                Button("Save as Script") { saveAsScript() }
                    .disabled(active || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Makes a new script from the transcript, to read or prompt")
                Spacer(minLength: 0)
                Button { model.copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(model.text.isEmpty)
                Button { model.paste() } label: { Label("Paste", systemImage: "arrow.up.forward.app") }
                    .buttonStyle(WidgetChipStyle(prominent: !model.text.isEmpty, height: 24))
                    .disabled(model.text.isEmpty)
                    .help(model.target?.localizedName.map { "Paste into " + $0 } ?? "Copy and paste into your app")
            }
            .buttonStyle(WidgetChipStyle(height: 24))
        }
        .onChange(of: editing) { value in onEditingChanged(value || active) }
        .onChange(of: active) { value in onEditingChanged(value || editing) }
        .onDisappear { model.stop(); onEditingChanged(false) }
    }

    private func saveAsScript() {
        let text = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        prompter.newScript()
        guard var script = prompter.selected else { return }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        script.title = String(firstLine.prefix(40))
        script.text = text
        prompter.update(script)
        StudioModel.shared.section = .scripts
    }
}
