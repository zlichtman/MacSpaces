import Foundation
import Combine

/// Polls a folder off the main thread and publishes its most recent files.
/// Shared by the Downloads and Screenshots widgets.
@MainActor
final class FolderScannerModel: ObservableObject {
    enum SortKey {
        case creationDate
        case contentModificationDate

        fileprivate var resourceKey: URLResourceKey {
            switch self {
            case .creationDate: return .creationDateKey
            case .contentModificationDate: return .contentModificationDateKey
            }
        }
    }

    @Published private(set) var items: [URL] = []

    /// Resolved on every refresh so folder changes (e.g. a new screenshot
    /// location) are picked up without restarting the scanner.
    private let folderProvider: () -> URL
    private let interval: TimeInterval
    private let limit: Int
    private let sortKey: SortKey
    /// Lowercased path extensions to keep; nil keeps everything.
    private let allowedExtensions: Set<String>?

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var scanTask: Task<[URL], Never>?
    private var refreshGeneration = 0

    init(
        folder: @escaping () -> URL,
        interval: TimeInterval,
        limit: Int,
        sortedBy sortKey: SortKey,
        allowedExtensions: Set<String>? = nil
    ) {
        self.folderProvider = folder
        self.interval = interval
        self.limit = limit
        self.sortKey = sortKey
        self.allowedExtensions = allowedExtensions
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
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
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        scanTask?.cancel()
        let folder = folderProvider()
        let limit = limit
        let sortKey = sortKey
        let allowedExtensions = allowedExtensions
        let scanTask = Task.detached(priority: .utility) {
            Self.scan(
                folder: folder,
                limit: limit,
                sortKey: sortKey,
                allowedExtensions: allowedExtensions
            )
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

    nonisolated private static func scan(
        folder: URL,
        limit: Int,
        sortKey: SortKey,
        allowedExtensions: Set<String>?
    ) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [sortKey.resourceKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var dated: [(URL, Date)] = []
        dated.reserveCapacity(contents.count)
        for url in contents {
            guard withUnsafeCurrentTask(body: { !($0?.isCancelled ?? false) }) else {
                return []
            }
            if let allowedExtensions,
               !allowedExtensions.contains(url.pathExtension.lowercased()) {
                continue
            }
            let values = try? url.resourceValues(forKeys: [sortKey.resourceKey])
            let date: Date
            switch sortKey {
            case .creationDate:
                date = values?.creationDate ?? .distantPast
            case .contentModificationDate:
                date = values?.contentModificationDate ?? .distantPast
            }
            dated.append((url, date))
        }
        guard withUnsafeCurrentTask(body: { !($0?.isCancelled ?? false) }) else { return [] }
        return dated
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
