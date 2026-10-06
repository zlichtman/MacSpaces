import SwiftUI

/// The Teleprompter page: your scripts on the left, the selected one to edit on
/// the right, and how it plays (scroll speed or following your voice) below.
struct PrompterPage: View {
    @ObservedObject var prompter: ScriptPrompter
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @FocusState private var editing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            library.frame(width: 150)
            editor.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: editing) { _, value in onEditingChanged(value) }
        .onDisappear { onEditingChanged(false) }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Scripts").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { prompter.importFiles() } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(WidgetChipStyle(height: 22)).help("Import text, Markdown, RTF or Word files")
                Button { prompter.newScript() } label: { Image(systemName: "plus") }
                    .buttonStyle(WidgetChipStyle(height: 22)).help("New script")
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(prompter.scripts) { script in
                        let selected = script.id == prompter.selected?.id
                        Button { prompter.selectedID = script.id } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(script.title.isEmpty ? "Untitled script" : script.title)
                                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(minutes(script.text)).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(selected ? theme.notch.accent.opacity(0.18) : Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Delete Script", role: .destructive) { prompter.delete(script) } }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let script = prompter.selected {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Title", text: Binding(get: { script.title }, set: { var s = script; s.title = $0; prompter.update(s) }))
                    .textFieldStyle(.plain).font(.system(size: 15, weight: .bold))
                    .focused($editing)
                TextEditor(text: Binding(get: { script.text }, set: { var s = script; s.text = $0; prompter.update(s) }))
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .focused($editing)
                HStack(spacing: 8) {
                    Picker("", selection: $prompter.mode) {
                        ForEach(ScriptPrompter.Mode.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Picker("", selection: $prompter.textSize) {
                        ForEach(ScriptPrompter.TextSize.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    Toggle("3-2-1", isOn: $prompter.countdown).toggleStyle(.checkbox).font(.system(size: 11))
                }
                HStack(spacing: 8) {
                    if prompter.mode == .scroll {
                        Slider(value: $prompter.speed, in: 60...260, step: 10).frame(maxWidth: 160)
                        Text("\(Int(prompter.speed)) wpm").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(prompter.isShowing ? "Stop" : "Start") {
                        prompter.isShowing ? prompter.close() : prompter.start()
                    }
                    .buttonStyle(WidgetChipStyle(prominent: true, height: 26))
                    .disabled(script.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text(prompter.mode == .voice
                     ? "Follows your voice with on-device speech recognition; MacSpaces asks for the microphone the first time. Hidden from screen sharing and recordings."
                     : "Space pauses, ← → move a line, ↑ ↓ change speed, Esc closes. Hidden from screen sharing and recordings.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func minutes(_ text: String) -> String {
        let count = text.split(whereSeparator: \.isWhitespace).count
        let minutes = Double(count) / max(prompter.speed, 1)
        return count == 0 ? "Empty" : "\(count) words · \(minutes < 1 ? "under a minute" : "\(Int(minutes.rounded())) min")"
    }
}
