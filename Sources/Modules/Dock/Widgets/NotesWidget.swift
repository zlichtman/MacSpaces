import SwiftUI

/// Quick scratchpad. The tile shows a preview; click to edit in a popover.
/// Content persists in UserDefaults.
struct NotesWidget: View {
    @AppStorage("quickNote") private var note = ""
    @State private var editing = false

    var body: some View {
        Button {
            editing.toggle()
        } label: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $editing, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Note")
                    .font(.headline)
                TextEditor(text: $note)
                    .font(.system(size: 12))
                    .frame(width: 280, height: 160)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var content: some View {
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text("Jot something down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.system(size: 9))
                    Text("NOTE")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.secondary)

                Text(note)
                    .font(.system(size: 10))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
        }
    }
}
