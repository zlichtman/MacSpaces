import SwiftUI
import UniformTypeIdentifiers

/// The Folio page's details column for the selection, like Folio's: the picture, its name,
/// kind and size, then the tags (yours first, tinted, then what Folio read; clicking one
/// searches for it) with an "Add a tag" field, your note, and the text in it. Several selected
/// share the tags they all have and a note they agree on; what you add goes on every one.
struct FolioDetails: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var request: FolioFieldRequest
    let searchTag: (String) -> Void
    @ObservedObject private var library = FolioIndex.shared
    @ObservedObject private var theme = ThemeStore.shared
    @FocusState private var focus: FolioFieldRequest.Field?
    @State private var newTag = ""

    var body: some View {
        let selected = store.selectedItems
        if let item = store.selectedItem ?? selected.first {
            let info = store.info[item.id]
            let record = library.record(for: item.url)
            let urls = (selected.isEmpty ? [item] : selected).map(\.url)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    picture(item, count: selected.count)
                    if selected.count > 1 {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(selected.count) items").font(.system(size: 12, weight: .semibold))
                            Spacer(minLength: 2)
                            heart(urls)
                        }
                        Text(TrayFiles.summary(count: selected.count, bytes: selected.reduce(0) { $0 + (store.info[$1.id]?.bytes ?? 0) }))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        tags(own: sharedTags(urls), automatic: [], urls: urls)
                        note(urls)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(item.displayName)
                                .font(.system(size: 12, weight: .semibold)).lineLimit(2).truncationMode(.middle)
                                .fixedSize(horizontal: false, vertical: true)
                                .help(item.name)
                            Spacer(minLength: 2)
                            heart(urls)
                        }
                        Text(store.offlineIDs.contains(item.id) ? "On a disconnected drive" : info?.details ?? "")
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                        if store.isTrash {
                            FolioTrashNote(url: item.url)
                        }
                        let own = library.mark(for: item.url)?.tags ?? []
                        tags(own: own, automatic: FolioTags.automatic(record?.tags ?? [], without: own), urls: urls)
                        note(urls)
                        if let record {
                            let text = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !text.isEmpty {
                                section(info?.isImage == true ? "Text in image" : "Text")
                                Text(String(text.prefix(600)))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                    .lineLimit(9)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        } else if info?.isDirectory == false {
                            Text("Reading this file…").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
            }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.92),
                                         .init(color: .black.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom))
            .onChange(of: request.count) { _ in focus = request.field }
            .onChange(of: store.selectedIDs) { _ in newTag = "" }
        }
    }

    /// Your tags (tinted, removable), then the automatic ones, then the field that adds tags.
    @ViewBuilder
    private func tags(own: [String], automatic: [String], urls: [URL]) -> some View {
        section("Tags")
        if !own.isEmpty || !automatic.isEmpty {
            FolioFlow(spacing: 4) {
                ForEach(own, id: \.self) { tag in
                    FolioOwnTag(tag: tag, search: { searchTag(tag) }, remove: { library.removeTag(tag, from: urls) })
                }
                ForEach(automatic, id: \.self) { tag in
                    Button(tag) { searchTag(tag) }
                        .buttonStyle(FolioTagStyle())
                        .help("Search for \u{201C}\(tag)\u{201D} (a tag Folio found)")
                }
            }
        }
        FolioInlineField(symbol: "plus", placeholder: urls.count > 1 ? "Tag all \(urls.count)" : "Add a tag", text: $newTag,
                         focus: $focus, field: .tag) {
            library.addTags(FolioTags.parse(newTag), to: urls)
            newTag = ""
            focus = .tag
        }
        .help("Type a tag and press Return; commas add several (T)")
    }

    /// Like, or unlike when every selected file is liked (L).
    private func heart(_ urls: [URL]) -> some View {
        let liked = urls.allSatisfy(library.isLiked)
        return Button { library.toggleLike(urls) } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(liked ? AnyShapeStyle(Color.pink) : AnyShapeStyle(.secondary))
                .frame(width: 20, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(liked ? "Unlike (L)" : urls.count > 1 ? "Like all \(urls.count) (L)" : "Like (L)")
        .accessibilityLabel(liked ? "Unlike" : "Like")
    }

    /// Your note, saved as you type. Several selected show the note they share; typing gives
    /// them all the new one.
    @ViewBuilder
    private func note(_ urls: [URL]) -> some View {
        let notes = urls.map { library.mark(for: $0)?.note ?? "" }
        let shared = notes.allSatisfy { $0 == notes.first } ? notes.first ?? "" : ""
        let placeholder = urls.count == 1 ? "Add a note" : shared.isEmpty && notes.contains { !$0.isEmpty } ? "Mixed notes: type to replace" : "Note for all \(urls.count)"
        section("Note")
        FolioInlineField(symbol: "square.and.pencil", placeholder: placeholder,
                         text: Binding(get: { shared }, set: { library.setNote($0, for: urls) }),
                         focus: $focus, field: .note, multiline: true)
            .help("A note of your own; search finds its words (N)")
    }

    /// The tags every selected file has of your own.
    private func sharedTags(_ urls: [URL]) -> [String] {
        guard let first = urls.first else { return [] }
        let rest = urls.dropFirst().map { library.mark(for: $0)?.tags ?? [] }
        return (library.mark(for: first)?.tags ?? []).filter { tag in rest.allSatisfy { FolioTags.contains($0, tag) } }
    }

    /// The picture at its own shape (several selected: the focused one over a second card).
    @ViewBuilder
    private func picture(_ item: ShelfItem, count: Int) -> some View {
        let corner = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Group {
            if let preview = store.previews[item.id], preview.isContent {
                Image(nsImage: preview.image).resizable().interpolation(.high).scaledToFit()
                    .clipShape(corner)
                    .overlay { corner.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5) }
            } else {
                ZStack {
                    corner.fill(Color.primary.opacity(0.07))
                    if let preview = store.previews[item.id] {
                        Image(nsImage: preview.image).resizable().scaledToFit().frame(width: 40, height: 40)
                    } else {
                        Image(systemName: "doc").font(.system(size: 24, weight: .light)).foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 70)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 92)
        .background(alignment: .center) {
            if count > 1 {
                corner.fill(Color.primary.opacity(0.1)).padding(.horizontal, 10).offset(y: 4)
            }
        }
        .padding(.top, 2)
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.4).foregroundStyle(.tertiary)
            .padding(.top, 4)
    }
}

/// A reference in the Trash: where Put Back returns it and how long it waits.
private struct FolioTrashNote: View {
    let url: URL
    @ObservedObject private var trash = FolioTrash.shared

    var body: some View {
        let days = trash.daysLeft(url)
        VStack(alignment: .leading, spacing: 5) {
            Label("From \(trash.originName(url))", systemImage: "arrow.uturn.backward")
            Label(days == 1 ? "Let go in 1 day" : "Let go in \(days) days", systemImage: "clock")
            Button { trash.putBack(FolioTrash.shared.store.items.filter { $0.url == url }) } label: {
                Label("Put Back", systemImage: "arrow.uturn.backward.circle")
            }
            .buttonStyle(WidgetChipStyle(height: 22))
            .help("Return it to \(trash.originName(url))")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .help("The file itself stays where it is; only its reference waits here.")
    }
}

/// Which details field a key asks for: T the tag field, N the note.
@MainActor
final class FolioFieldRequest: ObservableObject {
    enum Field: Hashable { case tag, note }
    @Published private(set) var field: Field?
    /// Bumped on every request, so asking twice for one field still focuses it.
    @Published private(set) var count = 0

    func ask(_ field: Field) { self.field = field; count += 1 }
}

/// One of your tags: tinted in the accent, so it reads apart from the automatic ones. Click
/// searches; the × (on hover) or the right-click menu removes it.
private struct FolioOwnTag: View {
    let tag: String
    let search: () -> Void
    let remove: () -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 3) {
            Button(action: search) {
                HStack(spacing: 3) {
                    Image(systemName: "tag.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(theme.notch.accent)
                    Text(tag).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            if hovering {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 10, height: 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove this tag")
            }
        }
        .padding(.leading, 6).padding(.trailing, hovering ? 5 : 7)
        .frame(height: 19)
        .background(theme.notch.accent.opacity(0.24), in: Capsule())
        .overlay { Capsule().strokeBorder(theme.notch.accent.opacity(0.55), lineWidth: 0.75) }
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .help("Your tag. Click to search for \u{201C}\(tag)\u{201D}")
        .contextMenu {
            Button("Search for \u{201C}\(tag)\u{201D}", action: search)
            Button("Remove Tag", role: .destructive, action: remove)
        }
    }
}

/// A small field in the details column: a symbol, the text and a focus ring in the accent.
/// Return calls `submit`; Escape leaves the field.
struct FolioInlineField: View {
    let symbol: String
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<FolioFieldRequest.Field?>.Binding
    let field: FolioFieldRequest.Field
    var multiline = false
    var submit: () -> Void = {}
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        HStack(alignment: multiline ? .top : .center, spacing: 4) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                .padding(.top, multiline ? 3 : 0)
            Group {
                if multiline {
                    TextField(placeholder, text: $text, axis: .vertical).lineLimit(1...6)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 10))
            .focused(focus, equals: field)
            .onSubmit(submit)
            .onExitCommand { focus.wrappedValue = nil }
        }
        .padding(.horizontal, 6).padding(.vertical, multiline ? 4 : 0)
        .frame(minHeight: 20)
        .background(Color.primary.opacity(0.07), in: shape)
        .overlay { shape.strokeBorder(theme.notch.accent, lineWidth: 1.25).opacity(focus.wrappedValue == field ? 1 : 0) }
        .contentShape(shape)
        .onTapGesture { focus.wrappedValue = field }
    }
}

/// An automatic tag: a small capsule, like Folio's.
private struct FolioTagStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.09), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Lays its views out left to right, wrapping onto new rows.
struct FolioFlow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let itemWidth = min(size.width, width)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + itemWidth > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + itemWidth
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
