import SwiftUI
import AppKit

/// Spotlight-style file search. The tile opens a popover with a query field;
/// results come from a live `NSMetadataQuery` against the user's home folder.
struct SearchWidget: View {
    @State private var showingSearch = false

    var body: some View {
        Button {
            showingSearch.toggle()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                Text("Search")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingSearch, arrowEdge: .top) {
            SearchPopover()
        }
    }
}

private struct SearchPopover: View {
    @StateObject private var model = FileSearchModel()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search files…", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)

            if !model.results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.results, id: \.self) { url in
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                        Text(url.deletingLastPathComponent().path)
                                            .font(.system(size: 8))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)
            } else if !model.query.isEmpty {
                Text(model.isSearching ? "Searching…" : "No results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { fieldFocused = true }
    }
}

@MainActor
private final class FileSearchModel: ObservableObject {
    @Published var query = "" {
        didSet { restartSearch() }
    }
    @Published private(set) var results: [URL] = []
    @Published private(set) var isSearching = false

    private var metadataQuery: NSMetadataQuery?
    private var debounceWorkItem: DispatchWorkItem?
    private var observer: NSObjectProtocol?

    private func restartSearch() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.startQuery() }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func startQuery() {
        stopQuery()

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }

        let metadata = NSMetadataQuery()
        metadata.predicate = NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@", trimmed)
        metadata.searchScopes = [NSMetadataQueryUserHomeScope]
        metadata.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]

        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: metadata,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.collectResults()
            }
        }

        isSearching = true
        metadataQuery = metadata
        metadata.start()
    }

    private func collectResults() {
        guard let metadata = metadataQuery else { return }
        metadata.disableUpdates()

        results = (0..<min(metadata.resultCount, 30)).compactMap { index in
            guard let item = metadata.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            return URL(fileURLWithPath: path)
        }
        isSearching = false
    }

    private func stopQuery() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        metadataQuery?.stop()
        metadataQuery = nil
        isSearching = false
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
