import SwiftUI
import AppKit

/// The most recent items in ~/Downloads. Click to open, drag out to move,
/// right-click for Finder actions. macOS shows a one-time folder-access prompt.
struct DownloadsWidget: View {
    @StateObject private var model = DownloadsModel()

    var body: some View {
        Group {
            if model.items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 16))
                    Text("Downloads folder is empty")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.items, id: \.self) { url in
                            VStack(spacing: 2) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 30, height: 30)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 8))
                                    .lineLimit(1)
                                    .frame(width: 52)
                            }
                            .onDrag { NSItemProvider(object: url as NSURL) }
                            .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                            .contextMenu {
                                Button("Open") { NSWorkspace.shared.open(url) }
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

@MainActor
private final class DownloadsModel: ObservableObject {
    @Published private(set) var items: [URL] = []

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var scanTask: Task<[URL], Never>?
    private var refreshGeneration = 0

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func stop() {
        refreshGeneration += 1
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        scanTask?.cancel()
        refreshTask = nil
        scanTask = nil
    }

    deinit {
        timer?.invalidate()
        refreshTask?.cancel()
        scanTask?.cancel()
    }

    private func refresh() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        scanTask?.cancel()
        let scanTask = Task.detached(priority: .utility) {
            Self.scan(downloads: downloads)
        }
        self.scanTask = scanTask
        refreshTask = Task { [weak self] in
            let snapshot = await scanTask.value
            guard !Task.isCancelled,
                  let self,
                  self.refreshGeneration == generation else { return }
            if items != snapshot {
                items = snapshot
            }
            refreshTask = nil
            self.scanTask = nil
        }
    }

    nonisolated private static func scan(downloads: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: downloads,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var dated: [(URL, Date)] = []
        dated.reserveCapacity(contents.count)
        for url in contents {
            guard withUnsafeCurrentTask(body: { !($0?.isCancelled ?? false) }) else {
                return []
            }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            dated.append((url, date))
        }
        guard withUnsafeCurrentTask(body: { !($0?.isCancelled ?? false) }) else { return [] }
        return dated
            .sorted { $0.1 > $1.1 }
            .prefix(12)
            .map(\.0)
    }
}
