import SwiftUI

/// Multiple local notes. The legacy scratchpad is migrated once without deleting its saved value.
struct NotesWidget: View {
    var compact = false
    @ObservedObject private var service = AppServices.shared.notes
    @State private var editing = false
    @State private var selected: UUID?
    @State private var draft = ""
    @State private var baseRevision: UUID?
    @State private var showDeleted = false

    var body: some View {
        tileContent
        .popover(isPresented: $editing, arrowEdge: .top) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Notes").font(.headline)
                        Spacer()
                        Button { if saveDraft(), let id = service.create() { selected = id; draft = ""; baseRevision = service.notes.first { $0.id == id }?.current.id } } label: { Image(systemName: "plus") }.help("New note")
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(service.notes.filter { $0.current.deleted == showDeleted }) { note in
                                Button {
                                    if saveDraft() { selected = note.id; draft = note.current.text; baseRevision = note.current.id }
                                } label: {
                                    Text(note.title.isEmpty ? "Untitled note" : note.title).lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                                        .background(selected == note.id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Button(showDeleted ? "Show notes" : "Recently deleted") {
                        if saveDraft() { selected = nil; draft = ""; showDeleted.toggle() }
                    }.font(.caption)
                }.frame(width: 135)
                VStack(alignment: .leading, spacing: 8) {
                    if selected != nil {
                        TextEditor(text: $draft).font(.system(size: 12)).frame(width: 280, height: 170)
                            .disabled(showDeleted)
                        HStack {
                            Button(showDeleted ? "Restore" : "Save") {
                                if showDeleted, let selected { _ = service.save(selected, text: draft); showDeleted = false; loadDraft() } else { _ = saveDraft() }
                            }
                            if !showDeleted {
                                Button("Delete", role: .destructive) {
                                    if let selected, service.save(selected, text: draft, deleted: true, base: baseRevision) { self.selected = nil; draft = "" }
                                }
                            }
                        }
                    } else { Text("Choose a note or create one.").frame(width: 280, height: 170) }
                    if let note = service.notes.first(where: { $0.id == selected }), !note.conflicts.isEmpty {
                        Menu("Other versions (\(note.conflicts.count))") {
                            ForEach(note.conflicts) { revision in
                                Button((revision.deleted ? "Deleted: " : "") + String(revision.text.prefix(55))) {
                                    service.restoreVersion(note: note.id, revision: revision.id)
                                    showDeleted = service.notes.first { $0.id == note.id }?.current.deleted ?? false
                                    loadDraft()
                                }
                            }
                        }
                    }
                    if let error = service.error { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }.padding(12)
            .onDisappear { _ = saveDraft() }
        }
    }
    /// Recent notes as tappable cards, plus a one-click new note.
    @ViewBuilder
    private var tileContent: some View {
        let notes = service.active.filter { !$0.current.text.isEmpty }
        VStack(alignment: .leading, spacing: 5) {
            if notes.isEmpty {
                Button { newNote() } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "square.and.pencil").font(.system(size: 16))
                        Text("Write a note").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ForEach(notes.prefix(compact ? 1 : 2)) { note in
                    Button { openEditor(note.id) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            if !compact {
                                Text(preview(of: note)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                HStack {
                    if !compact {
                        Text("\(notes.count) note\(notes.count == 1 ? "" : "s")").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { newNote() } label: { Label("New", systemImage: "plus") }
                        .buttonStyle(WidgetChipStyle(height: 20)).help("New note")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, compact ? 6 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func preview(of note: StoredNote) -> String {
        note.current.text.split(separator: "\n").dropFirst().joined(separator: " ")
    }

    private func newNote() {
        guard let id = service.create() else { return }
        selected = id
        showDeleted = false
        loadDraft()
        editing = true
    }

    private func openEditor(_ id: UUID? = nil) {
        if let id { selected = id }
        if selected == nil { selected = service.active.first?.id ?? service.create() }
        showDeleted = false
        loadDraft()
        editing = true
    }
    private func loadDraft() {
        let note = service.notes.first { $0.id == selected }
        draft = note?.current.text ?? ""; baseRevision = note?.current.id
    }
    private func saveDraft() -> Bool {
        guard let selected, !showDeleted else { return true }
        let saved = service.save(selected, text: draft, base: baseRevision)
        if saved { loadDraft() }
        return saved
    }
}
