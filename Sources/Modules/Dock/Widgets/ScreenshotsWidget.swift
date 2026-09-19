import SwiftUI
import AppKit
import ImageIO

/// Capture buttons plus a strip of recent screenshots from the user's
/// configured screenshot folder (defaults to the Desktop).
struct ScreenshotsWidget: View {
    @StateObject private var model = ScreenshotsModel()

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                captureButton("rectangle.dashed", "Capture selection", ["-i"])
                captureButton("macwindow", "Capture window", ["-i", "-w"])
                captureButton("rectangle.inset.filled", "Capture full screen", [])
            }

            Divider()
                .padding(.vertical, 14)

            if model.recent.isEmpty {
                Text("Recent screenshots appear here")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.recent, id: \.self) { url in
                            ScreenshotThumbnail(url: url)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private func captureButton(_ symbol: String, _ help: String, _ arguments: [String]) -> some View {
        Button {
            // A destination path is required: the buttons previously passed -c,
            // which routes the capture to the clipboard only, so nothing ever
            // reached the folder this widget's own thumbnail strip reads.
            let destination = ScreenshotsModel.captureDestination()
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = arguments + [destination.path]
            task.terminationHandler = { _ in
                Task { @MainActor in model.refresh() }
            }
            try? task.run()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 24, height: 18)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ScreenshotThumbnail: View {
    let url: URL
    @StateObject private var model: ScreenshotThumbnailModel

    init(url: URL) {
        self.url = url
        _model = StateObject(wrappedValue: ScreenshotThumbnailModel(url: url))
    }

    var body: some View {
        Group {
            if let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear { model.load() }
        .onDisappear { model.cancel() }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}

@MainActor
private final class ScreenshotThumbnailModel: ObservableObject {
    @Published private(set) var image: NSImage?

    private let url: URL
    private var loadTask: Task<Void, Never>?
    private var decodeTask: Task<Data?, Never>?
    private var loadGeneration = 0

    init(url: URL) {
        self.url = url
    }

    func load() {
        guard image == nil, loadTask == nil else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let url = url
        let decodeTask = Task.detached(priority: .utility) {
            Self.thumbnailData(for: url)
        }
        self.decodeTask = decodeTask
        loadTask = Task { [weak self] in
            let thumbnailData = await decodeTask.value
            guard !Task.isCancelled,
                  let self,
                  self.loadGeneration == generation else { return }
            if let thumbnailData {
                image = NSImage(data: thumbnailData)
            }
            loadTask = nil
            self.decodeTask = nil
        }
    }

    func cancel() {
        loadGeneration += 1
        loadTask?.cancel()
        decodeTask?.cancel()
        loadTask = nil
        decodeTask = nil
    }

    deinit {
        loadTask?.cancel()
        decodeTask?.cancel()
    }

    nonisolated private static func thumbnailData(for url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 160,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
              ) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

@MainActor
private final class ScreenshotsModel: ObservableObject {
    @Published private(set) var recent: [URL] = []

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var scanTask: Task<[URL], Never>?
    private var refreshGeneration = 0

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
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

    /// The folder screenshots are saved to: the user's custom
    /// `com.apple.screencapture location` if set, otherwise the Desktop.
    static var screenshotFolder: URL {
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let expanded = (custom as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return URL(fileURLWithPath: expanded)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// A free path in the screenshot folder, named after the system convention.
    static func captureDestination() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Screenshot \(formatter.string(from: Date()))"
        let folder = screenshotFolder

        var candidate = folder.appendingPathComponent("\(base).png")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(suffix)).png")
            suffix += 1
        }
        return candidate
    }

    fileprivate func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        scanTask?.cancel()
        let folder = Self.screenshotFolder
        let scanTask = Task.detached(priority: .utility) {
            Self.scan(folder: folder)
        }
        self.scanTask = scanTask
        refreshTask = Task { [weak self] in
            let snapshot = await scanTask.value
            guard !Task.isCancelled,
                  let self,
                  self.refreshGeneration == generation else { return }
            if recent != snapshot {
                recent = snapshot
            }
            refreshTask = nil
            self.scanTask = nil
        }
    }

    nonisolated private static func scan(folder: URL) -> [URL] {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var dated: [(URL, Date)] = []
        dated.reserveCapacity(contents.count)
        for url in contents {
            guard withUnsafeCurrentTask(body: { !($0?.isCancelled ?? false) }) else {
                return []
            }
            guard imageExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?
                .creationDate ?? .distantPast
            dated.append((url, date))
        }
        guard withUnsafeCurrentTask(body: { !($0?.isCancelled ?? false) }) else { return [] }
        return dated
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map(\.0)
    }
}
