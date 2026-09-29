import SwiftUI
import UniformTypeIdentifiers

struct WidgetEditorItem: Identifiable, Equatable {
    let id: String
    let kind: String
    let title: String
    let symbol: String
}

/// Visual Nook selection, removal and drag reordering.
struct NookWidgetEditor: View {
    let items: [WidgetEditorItem]
    let choices: [WidgetEditorItem]
    let toggle: (String) -> Void
    let remove: (String) -> Void
    let reorder: ([String]) -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @State private var selectedID: String?
    @State private var draggedID: String?
    @State private var showingLibrary = false
    @State private var search = ""

    private var tokens: ThemeTokens { theme.notch }
    private var selected: WidgetEditorItem? { items.first { $0.id == selectedID } }
    private var filteredChoices: [WidgetEditorItem] {
        choices.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        SettingsCard("Your widgets", systemImage: "square.grid.2x2") {
            VStack(spacing: 0) {
                Group {
                    HStack {
                        Label("Nook", systemImage: "rectangle.grid.1x2.fill")
                        Spacer()
                        Button { showingLibrary = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("Add widget")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tokens.accent)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            Button { selectedID = item.id } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: item.symbol).foregroundStyle(tokens.accent)
                                        Spacer(minLength: 4)
                                        if selectedID == item.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(tokens.accent) }
                                    }
                                    Spacer(minLength: 0)
                                    Text(item.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                                }
                                .padding(12)
                                .frame(width: 112, height: 90, alignment: .leading)
                                .background(tokens.tile.opacity(0.55), in: RoundedRectangle(cornerRadius: 13))
                                .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(selectedID == item.id ? tokens.accent : tokens.border.opacity(0.4), lineWidth: 1) }
                                .contentShape(RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select \(item.title)")
                            .onDrag { draggedID = item.id; return NSItemProvider(object: item.id as NSString) }
                            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                                guard !providers.isEmpty, let source = draggedID,
                                      source != item.id, let from = items.firstIndex(where: { $0.id == source }),
                                      let to = items.firstIndex(where: { $0.id == item.id }) else { return false }
                                var ids = items.map(\.id)
                                ids.insert(ids.remove(at: from), at: to)
                                reorder(ids)
                                draggedID = nil
                                return true
                            }
                            .contextMenu {
                                Button("Move Earlier") { move(item.id, by: -1) }.disabled(items.first?.id == item.id)
                                Button("Move Later") { move(item.id, by: 1) }.disabled(items.last?.id == item.id)
                                Divider()
                                Button("Remove \(item.title)", role: .destructive) { remove(item.id) }
                            }
                        }
                        Button { showingLibrary = true } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "plus").font(.system(size: 19, weight: .light))
                                Text(items.isEmpty ? "Add your first widget" : "Add widget").font(.system(size: 10, weight: .medium))
                            }
                            .frame(width: items.isEmpty ? 210 : 112, height: 90)
                            .foregroundStyle(tokens.accent)
                            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(tokens.border, style: StrokeStyle(lineWidth: 1, dash: [4])) }
                        }.buttonStyle(.plain)
                    }
                    .padding(12)
                }
            }
            .background(tokens.surface, in: RoundedRectangle(cornerRadius: 22))
            .environment(\.colorScheme, tokens.colorScheme)
            .foregroundStyle(tokens.colorScheme == .dark ? Color.white : Color.black)

            HStack {
                if let selected {
                    Text(selected.title).font(.caption.weight(.medium))
                    Spacer()
                    Button { move(selected.id, by: -1) } label: { Image(systemName: "arrow.left") }
                        .disabled(items.first?.id == selected.id).help("Move Earlier")
                    Button { move(selected.id, by: 1) } label: { Image(systemName: "arrow.right") }
                        .disabled(items.last?.id == selected.id).help("Move Later")
                    Button("Remove", role: .destructive) { remove(selected.id); selectedID = nil }
                } else {
                    Text("Select a widget to edit. Drag to reorder.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                Button("Add widgets") { showingLibrary = true }
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 26)
        }
        .sheet(isPresented: $showingLibrary) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Add widgets").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Done") { showingLibrary = false }.keyboardShortcut(.defaultAction)
                }
                TextField("Search widgets", text: $search).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 8) {
                        ForEach(filteredChoices) { choice in
                            let included = items.contains { $0.kind == choice.kind }
                            Button { toggle(choice.kind) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: choice.symbol).frame(width: 20)
                                    Text(choice.title).font(.system(size: 12)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: included ? "checkmark.circle.fill" : "plus.circle")
                                }.padding(12).frame(maxWidth: .infinity)
                                    .background(included ? tokens.accent.opacity(0.16) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).accessibilityLabel("\(included ? "Remove" : "Add") \(choice.title)")
                        }
                    }
                }
                Text("Changes appear immediately in your active profile.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width: 540, height: 410)
        }
    }

    private func move(_ id: String, by offset: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }), items.indices.contains(from + offset) else { return }
        var ids = items.map(\.id)
        ids.swapAt(from, from + offset)
        reorder(ids)
    }
}
