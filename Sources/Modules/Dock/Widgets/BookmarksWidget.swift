import SwiftUI
import AppKit

/// Saved links. Click to open in the default browser; manage in the popover.
struct BookmarksWidget: View {
    @StateObject private var model = BookmarksModel()
    @State private var showingManager = false

    var body: some View {
        Button {
            showingManager.toggle()
        } label: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingManager, arrowEdge: .top) {
            manager
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.bookmarks.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "bookmark")
                    .font(.system(size: 16))
                Text("Save your favorite links")
                    .font(.system(size: 9))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.bookmarks.prefix(3)) { bookmark in
                    HStack(spacing: 5) {
                        Image(systemName: "link")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text(bookmark.title)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
        }
    }

    private var manager: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bookmarks")
                .font(.headline)

            if !model.bookmarks.isEmpty {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.bookmarks) { bookmark in
                            HStack {
                                Button {
                                    model.open(bookmark)
                                } label: {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(bookmark.title)
                                            .font(.system(size: 12))
                                        Text(bookmark.urlString)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    model.remove(bookmark)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            Divider()

            TextField("Title", text: $model.newTitle)
                .textFieldStyle(.roundedBorder)
            TextField("https://…", text: $model.newURL)
                .textFieldStyle(.roundedBorder)
            Button("Add Bookmark") { model.add() }
                .disabled(!model.canAdd)
        }
        .padding(14)
        .frame(width: 280)
    }
}

struct Bookmark: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var urlString: String
}

@MainActor
private final class BookmarksModel: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published var newTitle = ""
    @Published var newURL = ""

    private let defaultsKey = "bookmarks"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = decoded
        }
    }

    var canAdd: Bool {
        !newTitle.trimmingCharacters(in: .whitespaces).isEmpty && normalizedURL != nil
    }

    private var normalizedURL: URL? {
        var text = newURL.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        return URL(string: text)
    }

    func add() {
        guard let url = normalizedURL else { return }
        bookmarks.append(Bookmark(id: UUID(),
                                  title: newTitle.trimmingCharacters(in: .whitespaces),
                                  urlString: url.absoluteString))
        newTitle = ""
        newURL = ""
        persist()
    }

    func remove(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        persist()
    }

    func open(_ bookmark: Bookmark) {
        guard let url = URL(string: bookmark.urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
